// シフト表のスクリーンショットから、日付と時間だけを読み取る(Claude の API を、アプリの代わりに呼ぶ)。
// API キーはここ(サーバー)だけに置き、アプリには入れない。ログインしている人だけが、1 日に決まった回数まで使える

import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { cleanKind, cleanNameHint, cleanYearMonth, extractJson, normalizeLines, normalizeTasks } from "./lines.js";

initializeApp();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

/** 読み取りに使うモデル(試験で 14/14 日が合ったもの) */
const MODEL = "claude-haiku-5-5";
/** 1 人が 1 日に使える回数(使いすぎと、料金の暴走を防ぐ) */
const DAILY_LIMIT = 5;
/** 回数の制限を受けない管理者の UID(Apple でサインインしていて、メールアドレスが伏せられるので、UID で決める) */
const ADMIN_UIDS = ["FiO92cEsHBRYp1vFZtjghs6to2M2"];
function isAdmin(auth) {
  return !!auth && ADMIN_UIDS.includes(auth.uid);
}
const MAX_IMAGES = 5;
/** 画像 1 枚の上限(base64 の文字数。アプリ側で縮小してから送る) */
const MAX_IMAGE_CHARS = 3_000_000;

const PROMPT = `これは勤務シフト表のスクリーンショットです(複数枚のときは、同じ表の続きです。画面の端が重なって、同じ日が 2 枚に写ることがあるので、同じ日は 1 回だけにして、日付順に並べてください)。日付と時間だけを読み取って、JSON の配列だけを返してください(説明やコードブロックは付けない)。

読み取りのルール:
- 画面の表は、1 行に「日付のマス + 時間のマス」の組が 2 組、横に並んでいます(左の組と右の組)。左の組から先に、上から下へ読み、次に右の組を上から下へ読んでも、日付順に並べ直してください。
- 年と月は、画面上の期間の表示(例: 2026/11/08(日)〜11/21(土))から決めてください。月をまたぐときは、日付が小さくなったところで翌月にしてください。
- 時間のマスは、同じ行で、すぐ左にある日付のマスの時間です。上や下の行の日付とずらさないでください。日付の入っていない灰色のマス(表の空き)は読み飛ばしてください。
- 時間のマスが 2 段(上が開始、下が終了)のときは、start と end にしてください。
- 夜勤の表では、24 時を過ぎる時刻(24:00、24:30、25:00、30:00、31:00 など)がよく出ます。0:30 や 7:00 に直さず、書かれているとおりに "24:30" "31:00" と書いてください。開始も終了も、1 文字ずつ数字を確かめてください(例: 22:00〜31:00 と 24:30〜31:00 と 22:00〜30:00 を取り違えない)。
- 「休」を含むマス(「休」「公休」「希望休」「有休」など)は off を true にして、start と end は null にしてください。マスの隅の「欠」などの小さな印は無視してください。
- 時間の欄が空のときは、start と end を null、off を false にしてください。
- 表にある日付は、読みにくくても 1 日も飛ばさずに、すべて出してください。

出力の形(1 日 1 要素。同じ日に別の時間の予定があれば、別の要素にしてください):
[{"date": "YYYY-MM-DD", "start": "HH:MM" または null, "end": "HH:MM" または null, "off": true/false}]`;

/** 課題の一覧・予定表・メールの画面などから、タイトルと開始・締切を読み取る */
const TASK_PROMPT = `これは課題の一覧、予定表、メール、チャットなどのスクリーンショットです(複数枚のときは、同じ内容の続きです。同じ項目が 2 枚に写っていても、1 回だけにしてください)。やること・課題・提出物・予定の「タイトル」と、「開始」「締切」の日付と時刻を読み取って、JSON の配列だけを返してください(説明やコードブロックは付けない)。

読み取りのルール:
- 1 つのやること・課題につき 1 要素にしてください。
- 「いつまで」「期限」「提出」「〆」「due」などは締切(dueDate / dueTime)、「いつから」「開始」「公開」「start」などは開始(startDate / startTime)にしてください。
- 日付や時刻が、画像に書かれていないときは、その項目は null にしてください。推測で埋めないでください。
- 開始も締切も書かれていないやること(日付のないタスク)も、タイトルだけで 1 要素にしてください。
- 年が書かれていない日付は、今日(日本時間で __TODAY__)に近い年にしてください。
- 時刻は "HH:MM"(24 時間表記)にしてください。「24:00」は、そのまま "24:00" と書いてください。時刻が無いときは null にしてください。
- 「午前 9 時」「17 時まで」のような書き方も、"09:00" "17:00" にしてください。
- タイトルは、画像に書かれている言葉を、そのまま短く使ってください(長い説明文は入れないでください)。
- そのやることを見分けるのに役立つ補足(授業名、章や回の見出し、場所、科目名など)が画像にあれば、note に短く書いてください。なければ空文字にしてください。

出力の形:
[{"title": "…", "note": "…", "startDate": "YYYY-MM-DD" または null, "startTime": "HH:MM" または null, "dueDate": "YYYY-MM-DD" または null, "dueTime": "HH:MM" または null}]`;

/** アプリからの指定(年月・名前)を、AI への文章に足す。kind が tasks のときは、開始・締切を読み取る文章 */
function buildPrompt({ yearMonth, name, kind }) {
  if (kind === "tasks") {
    let prompt = TASK_PROMPT.replace("__TODAY__", today());
    if (yearMonth) {
      const y = Number(yearMonth.split("-")[0]);
      prompt += `

年の指定: 年が書かれていない日付は、${y}年としてください(上の「今日に近い年にしてください」より、こちらを優先してください)。`;
    }
    return prompt;
  }
  let prompt = PROMPT;
  if (yearMonth) {
    const [y, m] = yearMonth.split("-").map(Number);
    prompt += `

年月の指定: この表には年月の表示がありません。表の最初の日は ${y}年${m}月 としてください。月をまたぐときは、日付が小さくなったところで翌月にしてください(上の「年と月は、画面上の期間の表示から決めてください」より、こちらを優先してください)。`;
  }
  if (name) {
    prompt += `

読み取る人の指定: この表には複数の人の名前があります。「${name}」の行だけを読み取ってください。
- 名前は部分一致で探してください(例: 「山田」なら「山田太郎」も「山田花子」も当てはまります)。
- 表の中に、指定の名前と完全に一致する人がいるときは、その人だけを読み取ってください。
- 完全に一致する人がいなくて、部分一致する人が複数いるときは、全員分を読み取ってください。
- 読み取った要素には、表に書かれている名前を "name" に入れてください。
- ほかの人の行は、読み取らないでください。`;
  }
  return prompt;
}

function today() {
  // 日本時間の日付(1 日の回数は、日本時間の日付で数える)
  return new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10);
}

/** 1 日の回数を数える。上限を超えていたら、止める */
async function countUse(uid) {
  const db = getFirestore();
  const ref = db.collection("ocrUsage").doc(`${uid}_${today()}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = snap.exists ? snap.data().count || 0 : 0;
    if (used >= DAILY_LIMIT) {
      throw new HttpsError("resource-exhausted", `画像の読み取りは、1 日 ${DAILY_LIMIT} 回までです。あしたまた使えます。`);
    }
    tx.set(ref, { uid, count: used + 1, day: today() }, { merge: true });
  });
}

export const readShiftScreenshots = onCall(
  { region: "asia-northeast1", secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120, memory: "512MiB", maxInstances: 5 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "画像から追加するには、ログインが必要です。");
    }
    const images = request.data?.images;
    if (!Array.isArray(images) || images.length < 1 || images.length > MAX_IMAGES) {
      throw new HttpsError("invalid-argument", `画像は 1〜${MAX_IMAGES} 枚にしてください。`);
    }
    if (images.some((s) => typeof s !== "string" || s.length === 0 || s.length > MAX_IMAGE_CHARS)) {
      throw new HttpsError("invalid-argument", "画像が大きすぎるか、形が正しくありません。");
    }

    if (!isAdmin(request.auth)) await countUse(request.auth.uid);

    const content = [];
    images.forEach((data, i) => {
      if (images.length > 1) content.push({ type: "text", text: `画像${i + 1}:` });
      content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data } });
    });
    const kind = cleanKind(request.data?.kind);
    const prompt = buildPrompt({ yearMonth: cleanYearMonth(request.data?.yearMonth), name: cleanNameHint(request.data?.name), kind });
    content.push({ type: "text", text: prompt });

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
    let response;
    try {
      response = await client.messages.create({
        model: MODEL,
        max_tokens: 8000,
        output_config: { effort: "low" },
        messages: [{ role: "user", content }],
      });
    } catch (error) {
      console.error("読み取りの呼び出しに失敗", error?.status, error?.message);
      throw new HttpsError("internal", "読み取りに失敗しました。少し待って、もう一度試してください。");
    }

    const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
    let lines;
    try {
      lines = kind === "tasks" ? normalizeTasks(extractJson(text)) : normalizeLines(extractJson(text));
    } catch (error) {
      console.error("読み取り結果の形が正しくない", error?.message);
      throw new HttpsError("internal", "読み取り結果を読めませんでした。画像を変えて、もう一度試してください。");
    }
    console.log("読み取り", { uid: request.auth.uid, kind, images: images.length, lines: lines.length, usage: response.usage });
    // 開始・締切の読み取りは tasks、シフトの読み取りは lines(古いアプリは、lines だけを読む)
    return kind === "tasks" ? { tasks: lines } : { lines };
  },
);
