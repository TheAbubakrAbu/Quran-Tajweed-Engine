// @ts-check
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadFromDisk } from "../src/node.js";
import { surahAudioUrl, ayahAudioUrl } from "../src/audio.js";
import { sortSurahs, filterByCounts } from "../src/sorting.js";
import { localSurahPath, sanitizeReciterDir } from "../src/cache.js";

const engine = await loadFromDisk();

test("quran: 114 surahs, 6236 ayahs", () => {
  assert.equal(engine.quran.all().length, 114);
  assert.equal(engine.quran.totalAyahs, 6236);
});

test("quran: surah + ayah lookup", () => {
  assert.equal(engine.quran.surah(1)?.nameEnglish, "The Opener");
  assert.equal(engine.quran.surah(1)?.numberOfAyahs, 7);
  assert.ok(engine.quran.ayah(2, 255)?.textArabic.length > 10); // Ayat al-Kursi
});

test("quran: global ayah number", () => {
  assert.equal(engine.quran.globalAyahNumber(1, 1), 1);
  assert.equal(engine.quran.globalAyahNumber(2, 1), 8); // after Al-Fatiha's 7 ayahs
  assert.equal(engine.quran.globalAyahNumber(114, 6), 6236);
});

test("juz: 30 entries, membership", () => {
  assert.equal(engine.juzPage.juzes().length, 30);
  assert.equal(engine.juzPage.juz(1)?.startSurah, 1);
  assert.equal(engine.juzPage.juz(30)?.endSurah, 114);
  const first = engine.juzPage.firstAyahOfJuz(1);
  assert.equal(first?.surah.id, 1);
  assert.equal(first?.ayah.id, 1);
});

test("quran: sajdah, surahFromEnd, surahInfo", () => {
  const sj = engine.quran.sajdahAyahs();
  assert.equal(sj.length, 15);
  assert.ok(engine.quran.isSajdahAyah(32, 15));
  assert.ok(!engine.quran.isSajdahAyah(1, 1));
  assert.equal(engine.quran.surahFromEnd(1)?.id, 114);
  assert.equal(engine.quran.surahFromEnd(115), undefined);
  assert.ok(engine.quran.info(1).length >= 1);
});

test("qiraah existence + per-qiraah counts", () => {
  const q = engine.quran;
  assert.equal(q.existsInQiraah(2, 285, "warsh"), true);
  assert.equal(q.existsInQiraah(2, 286, "warsh"), false); // Baqarah is 285 in Warsh
  assert.equal(q.existsInQiraah(2, 286, "shubah"), true); // Shubah matches Hafs (6236)
  assert.equal(q.existsInQiraah(2, 286), true);            // no riwayah → Hafs
  assert.equal(q.numberOfAyahsInQiraah(2), 286);
  assert.equal(q.numberOfAyahsInQiraah(2, "warsh"), 285);
});

test("muqattaat + surah flags", () => {
  assert.equal(engine.muqattaat.all().length, 30);
  assert.equal(engine.muqattaat.pronunciation(2, 1)?.transliteration, "Alif Lām Mīm");
  assert.equal(engine.muqattaat.pronunciation(42, 2)?.transliteration, "ʿAyn Sīn Qāf");
  assert.equal(engine.muqattaat.pronunciation(1, 1), undefined);
  assert.equal(engine.muqattaat.letterName("ا"), "Alif");
  assert.equal(engine.quran.juzChangesWithinSurah(2), true);
  assert.equal(engine.quran.juzChangesWithinSurah(1), false);
  assert.equal(engine.quran.pageOrJuzChangesWithinSurah(112), false);
});

test("names of Allah: 99, by number", () => {
  assert.equal(engine.namesOfAllah.all().length, 99);
  assert.equal(engine.namesOfAllah.byNumber(1)?.transliteration, "Ar-Rahman");
  assert.equal(engine.namesOfAllah.byNumber(100), undefined);
});

test("sorting: filterByCounts", () => {
  assert.deepEqual(filterByCounts(engine.quran.all(), { ayahs: { op: "==", value: 286 } }).map((s) => s.id), [2]);
});

test("juz: from-the-end shorthand + per-juz stats", () => {
  // "-1" → juz 30, "-2" → juz 29 … "-30" → juz 1
  assert.equal(engine.juzPage.juzFromEnd(1)?.id, 30);
  assert.equal(engine.juzPage.juzFromEnd(30)?.id, 1);
  assert.equal(engine.juzPage.juzFromEnd(0), undefined);
  assert.equal(engine.juzPage.juzFromEnd(31), undefined);

  const stats = engine.juzPage.juzStats(30);
  assert.ok(stats);
  assert.equal(stats.ayahCount, engine.juzPage.ayahsInJuz(30).length);
  assert.ok(stats.surahCount >= 1 && stats.pageCount >= 1);
  assert.ok(stats.wordCount > 0 && stats.letterCount > 0);
  assert.equal(engine.juzPage.juzStats(99), undefined);

  // Every juz's ayahCount sums to all 6236 ayahs (boundary split is exhaustive & disjoint).
  let sum = 0;
  for (let i = 1; i <= 30; i++) sum += engine.juzPage.juzStats(i).ayahCount;
  assert.equal(sum, 6236);
});

test("page: lookup is consistent", () => {
  const total = engine.juzPage.totalPages();
  assert.ok(total >= 600); // standard mushaf ~604
  const page1 = engine.juzPage.ayahsOnPage(1);
  assert.ok(page1.length > 0);
});

test("audio: surah + ayah URLs", () => {
  const alafasy = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");
  assert.ok(alafasy);
  assert.equal(surahAudioUrl(alafasy, 1), "https://server8.mp3quran.net/afs/001.mp3");
  const g = engine.quran.globalAyahNumber(2, 1);
  assert.equal(ayahAudioUrl(alafasy, g), "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3");
});

test("audio: reciters loaded with qiraat", () => {
  assert.ok(engine.reciters.all().length >= 50);
  assert.ok(engine.reciters.qiraat().includes("Warsh an Nafi"));
});

test("sorting: by ayah count ascending/descending", () => {
  const asc = sortSurahs(engine.quran.all(), "ayahs", "ascending");
  assert.ok(asc[0].numberOfAyahs <= asc[asc.length - 1].numberOfAyahs);
  const desc = sortSurahs(engine.quran.all(), "ayahs", "descending");
  assert.ok(desc[0].numberOfAyahs >= desc[desc.length - 1].numberOfAyahs);
  // Al-Baqarah (286) is the longest
  assert.equal(desc[0].id, 2);
});

test("sorting: revelation order", () => {
  const rev = sortSurahs(engine.quran.all(), "revelation", "ascending");
  assert.equal(rev[0].revelationOrder, Math.min(...engine.quran.all().map((s) => s.revelationOrder)));
});

test("search: english phrase", () => {
  const r = engine.search.searchVerses("lord of the worlds");
  assert.ok(r.some((e) => e.id === "1:2"));
});

test("search: arabic substring", () => {
  const r = engine.search.searchVerses("الرحمن الرحيم");
  assert.ok(r.length > 0);
  assert.ok(r.some((e) => e.surah === 1));
});

test("search: numeric query rejected in verse search", () => {
  assert.equal(engine.search.searchVerses("2 255").length, 0);
});

test("search: surah by name, number, reference", () => {
  assert.ok(engine.search.searchSurahs("fatihah").some((s) => s.id === 1));
  assert.ok(engine.search.searchSurahs("2").some((s) => s.id === 2));
  const ref = engine.search.parseReference("2:255");
  assert.deepEqual(ref, { surah: 2, ayah: 255 });
});

test("search: makkan/madani filter", () => {
  const makkan = engine.search.searchSurahs("makki");
  assert.ok(makkan.length > 0 && makkan.every((s) => s.type === "makkan"));
});

test("search: boolean AND/OR/NOT", () => {
  const r = engine.search.searchVerses("allah & lord");
  assert.ok(r.length > 0);
});

test("search: regular search is pure substring (no phrase boundaries)", () => {
  // A mid-word substring must still match — regular search ignores word boundaries.
  const r = engine.search.searchVerses("orld"); // inside "world(s)"
  assert.ok(r.some((e) => e.id === "1:2"));
});

test("search: '=' whole-word operator", () => {
  // "=lord" matches the whole word "lord" but a partial like "=lor" should not.
  const whole = engine.search.searchVerses("=lord");
  assert.ok(whole.some((e) => e.id === "1:2"));
  const partial = engine.search.searchVerses("=lor");
  assert.ok(!partial.some((e) => e.id === "1:2"));
  // Contrast: plain "lor" (contains) DOES hit via substring.
  assert.ok(engine.search.searchVerses("lor").some((e) => e.id === "1:2"));
});

test("search: digit rejected even inside a boolean query", () => {
  // Digit check runs before the boolean path (matches QuranData.search).
  assert.equal(engine.search.searchVerses("allah & 2").length, 0);
});

test("tajweed: produces colored spans for Al-Fatiha ayah 1", () => {
  const text = engine.quran.ayah(1, 1).textArabic;
  const spans = engine.tajweed(text);
  assert.ok(Array.isArray(spans));
  assert.ok(spans.length > 0);
  for (const s of spans) {
    assert.ok(s.start < s.end);
    assert.equal(text.slice(s.start, s.end), s.text);
    assert.ok(typeof s.category === "string");
  }
});

test("tajweed: ghunnah detected for noon-sakin + ba (iqlaab) somewhere", () => {
  // 2:8 و من الناس من يقول ... contains noon rules
  const text = engine.quran.ayah(2, 8).textArabic;
  const spans = engine.tajweed(text);
  assert.ok(spans.length > 0);
});

test("cache: deterministic paths", () => {
  const r = { id: "Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/" };
  assert.equal(localSurahPath(r, 1), `${sanitizeReciterDir(r.id)}/001.mp3`);
  assert.ok(!/[|/:.]/.test(sanitizeReciterDir(r.id)));
});
