import test from "node:test";
import assert from "node:assert/strict";
import { extractJson, normalizeLines } from "./lines.js";

test("説明やコードブロックが付いていても、配列を取り出す", () => {
  const text = '読み取りました:\n```json\n[{"date":"2026-11-08","start":"17:00","end":"21:00","off":false}]\n```';
  assert.equal(extractJson(text).length, 1);
  assert.throws(() => extractJson("読み取れませんでした"));
});

test("日付順に並べ、同じ日は 1 件にし、24:00 はそのまま残す", () => {
  const lines = normalizeLines([
    { date: "2026-11-11", start: "16:00", end: "24:00", off: false },
    { date: "2026-11-08", start: "17:00", end: "21:00", off: false },
    { date: "2026-11-08", start: "18:00", end: "22:00", off: false },
  ]);
  assert.deepEqual(lines.map((l) => l.date), ["2026-11-08", "2026-11-11"]);
  assert.equal(lines[0].start, "18:00");
  assert.equal(lines[1].end, "24:00");
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
