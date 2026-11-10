// シフト表のスクリーンショットを読み取った結果(AI の返事)を、アプリに返す形に整える。
// 日付と時間の形がおかしいものは捨てる(アプリ側でも、もう一度確かめる)

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^\d{1,2}:\d{2}$/;

/** AI の返事の文字列から、JSON の配列を取り出す(前後の説明やコードブロックが付いていても読む) */
export function extractJson(text) {
  const start = text.indexOf("[");
  const end = text.lastIndexOf("]");
  if (start < 0 || end < start) throw new Error("JSON の配列が見つかりません");
  return JSON.parse(text.slice(start, end + 1));
}

function validDate(s) {
  if (typeof s !== "string" || !DATE.test(s)) return false;
  const [y, m, d] = s.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

function normalizeTime(s) {
  if (typeof s !== "string" || !TIME.test(s.trim())) return null;
  const [h, m] = s.trim().split(":").map(Number);
  if (m > 59 || h > 30) return null; // 25:00 などの営業日の表記は、30 時まで受ける
  return String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
}

/** 名前(表に書かれた名前)。空や長すぎるものは、無いことにする */
function normalizeName(s) {
  if (typeof s !== "string") return null;
  const t = s.trim();
  return t.length > 0 && t.length <= 40 ? t : null;
}

/**
 * 同じ日・同じ時間・同じ名前は 1 件にそろえる(同じ日が複数枚に重なって出たとき)。
 * 同じ日でも、時間や名前が違うものは、どちらも残す。日付、開始、名前の順に並べる
 */
export function normalizeLines(raw) {
  const byKey = new Map();
  for (const item of Array.isArray(raw) ? raw : []) {
    if (!item || !validDate(item.date)) continue;
    const off = item.off === true;
    const start = off ? null : normalizeTime(item.start);
    const end = off ? null : normalizeTime(item.end);
    // 時間が片方しか読めなかった行は、読み違いなので捨てる(時間なしの行は、終日として残す)
    if (!off && (start === null) !== (end === null)) continue;
    const name = normalizeName(item.name);
    const line = { date: item.date, start, end, off };
    if (name !== null) line.name = name;
    byKey.set([item.date, start, end, off, name].join("|"), line);
  }
  const key = (l) => [l.date, l.start ?? "", l.name ?? ""].join("|");
  return [...byKey.values()].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
}

/** アプリから受け取る名前の指定。改行や引用符は取り除く(AI への文章に入れるため) */
export function cleanNameHint(s) {
  if (typeof s !== "string") return null;
  const t = s.replace(/[\r\n"「」\\]/g, " ").replace(/\s+/g, " ").trim().slice(0, 40);
  return t.length > 0 ? t : null;
}

/** アプリから受け取る年月の指定("YYYY-MM")。形が正しくなければ、無いことにする */
export function cleanYearMonth(s) {
  if (typeof s !== "string" || !/^\d{4}-\d{2}$/.test(s)) return null;
  const m = Number(s.slice(5));
  return m >= 1 && m <= 12 ? s : null;
}

/** 時刻("HH:MM")。開始・締切は、その日のうちの時刻なので、24:00 まで受ける */
function normalizeTaskTime(s) {
  const t = normalizeTime(s);
  if (t === null) return null;
  const [h, m] = t.split(":").map(Number);
  return h < 24 || (h === 24 && m === 0) ? t : null;
}

/** タイトル(空や長すぎるものは、無いことにする) */
function normalizeTitle(s) {
  if (typeof s !== "string") return null;
  const t = s.replace(/\s+/g, " ").trim();
  return t.length > 0 && t.length <= 100 ? t : null;
}

/**
 * 画像から読み取った、開始・締切・タスクを整える。
 * タイトルの無いものは捨てる。日付の形がおかしければ、その日付は無いことにする(時刻は、日付があるときだけ残す)。
 * 締切が開始より前なら、読み違いなので、開始は無いことにする。同じ内容は 1 件にして、日付順(日付のないタスクは最後)に並べる
 */
export function normalizeTasks(raw) {
  const byKey = new Map();
  for (const item of Array.isArray(raw) ? raw : []) {
    const title = item && normalizeTitle(item.title);
    if (!title) continue;
    let startDate = validDate(item.startDate) ? item.startDate : null;
    let dueDate = validDate(item.dueDate) ? item.dueDate : null;
    if (startDate && dueDate && dueDate < startDate) startDate = null;
    const startTime = startDate ? normalizeTaskTime(item.startTime) : null;
    const dueTime = dueDate ? normalizeTaskTime(item.dueTime) : null;
    const note = typeof item.note === "string" ? item.note.replace(/\s+/g, " ").trim().slice(0, 200) : "";
    byKey.set([title, startDate, startTime, dueDate, dueTime].join("|"), { title, startDate, startTime, dueDate, dueTime, note });
  }
  const key = (t) => [t.dueDate ?? t.startDate ?? "9999-99-99", t.dueTime ?? t.startTime ?? "", t.title].join("|");
  return [...byKey.values()].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
}

/** アプリから受け取る読み取りの種類。"tasks" 以外は、シフト(予定) */
export function cleanKind(s) {
  return s === "tasks" ? "tasks" : "events";
}
