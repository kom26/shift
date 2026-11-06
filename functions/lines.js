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

/** 1 日 1 件にそろえる。同じ日が複数枚に重なって出たときは、あとのものを使う */
export function normalizeLines(raw) {
  const byDate = new Map();
  for (const item of Array.isArray(raw) ? raw : []) {
    if (!item || !validDate(item.date)) continue;
    const off = item.off === true;
    const start = off ? null : normalizeTime(item.start);
    const end = off ? null : normalizeTime(item.end);
    // 時間が片方しか読めなかった行は、読み違いなので捨てる(時間なしの行は、終日として残す)
    if (!off && (start === null) !== (end === null)) continue;
    byDate.set(item.date, { date: item.date, start, end, off });
  }
  return [...byDate.values()].sort((a, b) => (a.date < b.date ? -1 : 1));
}
