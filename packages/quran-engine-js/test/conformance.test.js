// @ts-check
/**
 * Conformance test — runs the language-agnostic vectors in /conformance/vectors.json against the
 * engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a behavior is specified ONCE in
 * that JSON, and every language port runs the same file (see docs/PORTING.md → "Conformance vectors").
 * This is the reference consumer; other ports mirror this harness.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadFromDisk } from "../src/node.js";
import { filterByCounts } from "../src/sorting.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const vectors = JSON.parse(await readFile(join(HERE, "../../../conformance/vectors.json"), "utf-8"));
const engine = await loadFromDisk();

test("conformance: searchVerses", () => {
  for (const v of vectors.searchVerses) {
    const ids = engine.search.searchVerses(v.query).map((h) => h.id);
    if (v.empty) assert.equal(ids.length, 0, `"${v.query}" should be empty`);
    for (const id of v.contains ?? []) assert.ok(ids.includes(id), `"${v.query}" should contain ${id}`);
    for (const id of v.excludes ?? []) assert.ok(!ids.includes(id), `"${v.query}" should exclude ${id}`);
  }
});

test("conformance: juzFromEnd", () => {
  for (const v of vectors.juzFromEnd) {
    assert.equal(engine.juzPage.juzFromEnd(v.n)?.id ?? null, v.id, `juzFromEnd(${v.n})`);
  }
});

test("conformance: juzStats", () => {
  for (const v of vectors.juzStats) {
    const s = engine.juzPage.juzStats(v.juz);
    if (v.isNull) { assert.equal(s, undefined, `juzStats(${v.juz}) should be null`); continue; }
    for (const k of ["surahCount", "ayahCount", "wordCount", "letterCount", "pageCount"]) {
      assert.equal(s[k], v[k], `juzStats(${v.juz}).${k}`);
    }
  }
  let sum = 0;
  for (let i = 1; i <= 30; i++) sum += engine.juzPage.juzStats(i).ayahCount;
  assert.equal(sum, vectors.juzStatsInvariant.sumAyahCountAllJuz);
});

test("conformance: surahFromEnd", () => {
  for (const v of vectors.surahFromEnd) {
    assert.equal(engine.quran.surahFromEnd(v.n)?.id ?? null, v.id, `surahFromEnd(${v.n})`);
  }
});

test("conformance: sajdah", () => {
  const sj = vectors.sajdah;
  const ids = engine.quran.sajdahAyahs().map((r) => `${r.surah.id}:${r.ayah.id}`);
  assert.equal(ids.length, sj.count);
  for (const id of sj.contains ?? []) {
    assert.ok(ids.includes(id), `sajdah should contain ${id}`);
    const [s, a] = id.split(":").map(Number);
    assert.ok(engine.quran.isSajdahAyah(s, a), `isSajdahAyah(${id})`);
  }
  for (const id of sj.excludes ?? []) {
    const [s, a] = id.split(":").map(Number);
    assert.ok(!engine.quran.isSajdahAyah(s, a), `isSajdahAyah(${id}) should be false`);
  }
});

test("conformance: surahInfo", () => {
  for (const v of vectors.surahInfo) {
    const sources = engine.quran.info(v.surah);
    assert.ok(sources.length >= (v.minSources ?? 1), `info(${v.surah}) sources`);
    if (v.hasSourceName) assert.ok(sources.some((s) => s.name === v.hasSourceName), `info(${v.surah}) has ${v.hasSourceName}`);
  }
});

test("conformance: namesOfAllah", () => {
  assert.equal(engine.namesOfAllah.all().length, vectors.namesOfAllah.count);
  for (const v of vectors.namesOfAllah.byNumber) {
    assert.equal(engine.namesOfAllah.byNumber(v.number)?.transliteration, v.transliteration);
  }
});

test("conformance: filterByCounts", () => {
  for (const v of vectors.filterByCounts) {
    const ids = filterByCounts(engine.quran.all(), { ayahs: v.ayahs, pages: v.pages }).map((s) => s.id).sort((a, b) => a - b);
    assert.deepEqual(ids, [...v.ids].sort((a, b) => a - b));
  }
});

test("conformance: surahFlags", () => {
  for (const v of vectors.surahFlags) {
    assert.equal(engine.quran.pageChangesWithinSurah(v.surah), v.pageChanges, `pageChanges(${v.surah})`);
    assert.equal(engine.quran.juzChangesWithinSurah(v.surah), v.juzChanges, `juzChanges(${v.surah})`);
    assert.equal(engine.quran.pageOrJuzChangesWithinSurah(v.surah), v.pageOrJuz, `pageOrJuz(${v.surah})`);
  }
});

test("conformance: existsInQiraah + numberOfAyahsInQiraah", () => {
  for (const v of vectors.existsInQiraah) {
    assert.equal(engine.quran.existsInQiraah(v.surah, v.ayah, v.riwayah), v.exists, `existsInQiraah(${v.surah},${v.ayah},${v.riwayah})`);
  }
  for (const v of vectors.numberOfAyahsInQiraah) {
    assert.equal(engine.quran.numberOfAyahsInQiraah(v.surah, v.riwayah), v.count, `numberOfAyahsInQiraah(${v.surah},${v.riwayah})`);
  }
});

test("conformance: muqattaat", () => {
  const m = vectors.muqattaat;
  assert.equal(engine.muqattaat.all().length, m.count);
  for (const p of m.pronunciations) {
    const got = engine.muqattaat.pronunciation(p.surah, p.ayah);
    assert.ok(got, `muqattaat ${p.surah}:${p.ayah} present`);
    assert.equal(got.transliteration, p.transliteration);
    if (p.spelledContainsMaddah) assert.ok(got.spelledOutArabic.includes("ٓ"), `muqattaat ${p.surah}:${p.ayah} keeps madd-lāzim maddah`);
  }
  for (const a of m.absent ?? []) {
    assert.equal(engine.muqattaat.pronunciation(a.surah, a.ayah), undefined, `muqattaat ${a.surah}:${a.ayah} absent`);
  }
});

test("conformance: tajweed", () => {
  for (const v of vectors.tajweed) {
    const spans = engine.tajweed(engine.quran.ayah(v.surah, v.ayah).textArabic);
    const rules = spans.map((s) => s.category); // JS spans expose the rule id as `category`
    if (v.excludesRule) assert.ok(!rules.includes(v.excludesRule), `${v.surah}:${v.ayah} should NOT have ${v.excludesRule}`);
    if (v.lastSpanRule) {
      const last = [...spans].sort((a, b) => a.start - b.start).at(-1);
      assert.equal(last?.category, v.lastSpanRule, `${v.surah}:${v.ayah} last span rule`);
    }
  }
});
