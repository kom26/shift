import test from "node:test";
import assert from "node:assert/strict";
import { cleanKind, cleanNameHint, cleanYearMonth, extractJson, normalizeLines, normalizeTasks } from "./lines.js";

test("説明やコードブロックが付いていても、配列を取り出す", () => {
  const text = '読み取りました:\n```json\n[{"date":"2026-11-08","start":"17:00","end":"21:00","off":false}]\n```';
  assert.equal(extractJson(text).length, 1);
  assert.throws(() => extractJson("読み取れませんでした"));
});

test("日付順に並べ、同じ日の同じ時間は 1 件にし、24:00 はそのまま残す", () => {
  const lines = normalizeLines([
    { date: "2026-11-11", start: "16:00", end: "24:00", off: false },
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false },
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false },
  ]);
  assert.deepEqual(lines.map((l) => l.date), ["2026-11-08", "2026-11-11"]);
  assert.equal(lines[0].start, "17:00");
  assert.equal(lines[1].end, "24:00");
});

test("同じ日でも、時間が違う予定は、どちらも残す(開始の順)", () => {
  const lines = normalizeLines([
    { date: "2026-11-08", start: "18:00", end: "22:00", off: false },
    { date: "2026-11-08", start: "09:00", end: "12:00", off: false },
  ]);
  assert.deepEqual(lines.map((l) => l.start), ["09:00", "18:00"]);
});

test("名前が違う人の同じ日・同じ時間は、どちらも残し、名前を付ける", () => {
  const lines = normalizeLines([
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false, name: "山田花子" },
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false, name: "山田太郎" },
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false, name: "山田太郎" },
  ]);
  assert.deepEqual(lines.map((l) => l.name), ["山田太郎", "山田花子"]);
});

test("名前の指定は、改行や引用符を取り除き、年月の指定は形を確かめる", () => {
  assert.equal(cleanNameHint('  山田\n"太郎" '), "山田 太郎");
  assert.equal(cleanNameHint("   "), null);
  assert.equal(cleanNameHint(5), null);
  assert.equal(cleanYearMonth("2026-11"), "2026-11");
  assert.equal(cleanYearMonth("2026-13"), null);
  assert.equal(cleanYearMonth("2026/11"), null);
});

test("休みは時間を捨て、形のおかしい行は捨てる", () => {
  const lines = normalizeLines([
    { date: "2026-11-10", start: "09:00", end: "10:00", off: true },
    { date: "2026-02-30", start: "09:00", end: "10:00", off: false },
    { date: "2026-11-12", start: "9:00", end: null, off: false },
    { date: "2026-11-13", start: "abc", end: "21:00", off: false },
    { date: "2026-11-14", start: null, end: null, off: false },
    null,
  ]);
  assert.deepEqual(lines, [
    { date: "2026-11-10", start: null, end: null, off: true },
    { date: "2026-11-14", start: null, end: null, off: false },
  ]);
});

test("配列でない返事は、空にする", () => {
  assert.deepEqual(normalizeLines({}), []);
  assert.deepEqual(normalizeLines(undefined), []);
});

test("開始・締切の読み取り: タイトルの無いものは捨て、日付のないタスクも残す", () => {
  const tasks = normalizeTasks([
    { title: "発表資料", startDate: "2026-12-08", startTime: "14:00", dueDate: "2026-12-11", dueTime: "17:00" },
    { title: "", dueDate: "2026-12-12" },
    { title: "本を返す", startDate: null, dueDate: null },
    { title: "レポート", dueDate: "2026-12-05", dueTime: "18:00" },
  ]);
  assert.deepEqual(tasks.map((t) => t.title), ["レポート", "発表資料", "本を返す"]);
  assert.equal(tasks[1].startTime, "14:00");
  assert.equal(tasks[2].dueDate, null);
});

test("開始・締切の読み取り: 形のおかしい日付は無いことにし、日付のない時刻は捨てる", () => {
  const [t] = normalizeTasks([{ title: "A", startDate: "2026-13-40", startTime: "09:00", dueDate: "2026-12-11", dueTime: "25:00" }]);
  assert.equal(t.startDate, null);
  assert.equal(t.startTime, null);
  assert.equal(t.dueDate, "2026-12-11");
  assert.equal(t.dueTime, null);
});

test("開始・締切の読み取り: 締切が開始より前なら開始を捨て、同じ内容は 1 件にする", () => {
  const tasks = normalizeTasks([
    { title: "B", startDate: "2026-12-20", dueDate: "2026-12-10" },
    { title: "C", dueDate: "2026-12-11", dueTime: "24:00" },
    { title: "C", dueDate: "2026-12-11", dueTime: "24:00" },
  ]);
  assert.equal(tasks.length, 2);
  assert.equal(tasks[0].startDate, null);
  assert.equal(tasks[1].dueTime, "24:00");
});

test("読み取りの種類: tasks 以外は、シフト", () => {
  assert.equal(cleanKind("tasks"), "tasks");
  assert.equal(cleanKind(undefined), "events");
  assert.equal(cleanKind("x"), "events");
});
