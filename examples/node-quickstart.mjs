// node-quickstart.mjs
//
// A thorough tour of the Quran Tajweed Engine, runnable with zero install:
//
//     node examples/node-quickstart.mjs
//
// It imports `loadFromDisk` straight from the package source, so there is no
// build step and no `npm install` required — Node 18+ reads the canonical JSON
// out of the repo's `data/` directory and hands you a ready-to-use engine.
//
// Everything below is a real call against the public API. Each section prints
// readable output so you can see exactly what the engine returns.

import { loadFromDisk } from "../packages/quran-engine-js/src/node.js";
import { sortSurahs, surahAudioUrl, ayahAudioUrl } from "../packages/quran-engine-js/src/index.js";

// Tiny output helpers so the console stays readable.
const hr = () => console.log("─".repeat(72));
const heading = (t) => { hr(); console.log(t); hr(); };

// ---------------------------------------------------------------------------
// 1. Load the engine
// ---------------------------------------------------------------------------
// `loadFromDisk()` parses quran.json, juz.json, reciters.json and
// tajweed-rules.json and returns the engine facade: { quran, juzPage,
// reciters, search, tajweedRules, tajweed() }.
const engine = await loadFromDisk();
console.log(`Loaded engine: ${engine.quran.all().length} surahs, ${engine.quran.totalAyahs} ayahs total.\n`);

// ---------------------------------------------------------------------------
// 2. Surah 1 metadata + ayah 1 (Arabic, transliteration, both translations)
// ---------------------------------------------------------------------------
heading("2. Surah 1 — metadata + ayah 1");
const fatiha = engine.quran.surah(1);
console.log(`#${fatiha.id}  ${fatiha.nameEnglish}  (${fatiha.nameTransliteration} / ${fatiha.nameArabic})`);
console.log(`Type: ${fatiha.type} · Ayahs: ${fatiha.numberOfAyahs} · Pages: ${fatiha.numberOfPages} · Revelation order: ${fatiha.revelationOrder}`);

const a1 = engine.quran.ayah(1, 1);
console.log(`\nAyah 1:1`);
console.log(`  Arabic         : ${a1.textArabic}`);
console.log(`  Transliteration: ${a1.textTransliteration}`);
console.log(`  Saheeh Intl.   : ${a1.textEnglishSaheeh}`);
console.log(`  Khattab (Clear): ${a1.textEnglishMustafa}`);

// ---------------------------------------------------------------------------
// 3. Tajweed spans for Ayat al-Kursi (2:255)
// ---------------------------------------------------------------------------
// `engine.tajweed(text)` returns non-overlapping, in-order spans. Because the
// engine was built with tajweed-rules.json, every span also carries `color`
// (the canonical #RRGGBB for its rule category).
heading("3. Tajweed spans for 2:255 (Ayat al-Kursi)");
const kursi = engine.quran.ayah(2, 255);
const spans = engine.tajweed(kursi.textArabic);
console.log(`Detected ${spans.length} colored spans. First 8:\n`);
console.log("  category               color     text");
console.log("  ─────────────────────  ────────  ────");
for (const s of spans.slice(0, 8)) {
  console.log(`  ${s.category.padEnd(21)}  ${(s.color ?? "—").padEnd(8)}  ${s.text}`);
}

// ---------------------------------------------------------------------------
// 4. Global ayah number + juz / page lookups
// ---------------------------------------------------------------------------
heading("4. Global ayah number, juz & page navigation");
console.log(`Global ayah number of 2:255 = ${engine.quran.globalAyahNumber(2, 255)} (out of ${engine.quran.totalAyahs})`);

const firstOfJuz30 = engine.juzPage.firstAyahOfJuz(30);
console.log(`First ayah of Juz 30 = ${firstOfJuz30.surah.id}:${firstOfJuz30.ayah.id} (${firstOfJuz30.surah.nameEnglish})`);

const page1 = engine.juzPage.ayahsOnPage(1);
console.log(`Ayahs on mushaf page 1 = ${page1.length}`);
console.log(`Juz of 2:255 = ${engine.juzPage.juzForAyah(2, 255)} · Page of 2:255 = ${engine.juzPage.pageForAyah(2, 255)}`);

// ---------------------------------------------------------------------------
// 5. Recitation audio URLs (Mishary Alafasy)
// ---------------------------------------------------------------------------
heading("5. Audio URLs — Mishary Alafasy");
const alafasy = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");
const surahUrl = surahAudioUrl(alafasy, 1);                                  // full surah al-Fatiha
const ayahUrl = ayahAudioUrl(alafasy, engine.quran.globalAyahNumber(2, 255)); // single ayah 2:255
console.log(`Full surah (al-Fatiha): ${surahUrl}`);
console.log(`Single ayah (2:255)   : ${ayahUrl}`);

// ---------------------------------------------------------------------------
// 6. Search — verses and surahs
// ---------------------------------------------------------------------------
heading("6. Search");
const mercyHits = engine.search.searchVerses("mercy", { limit: 5 });
console.log(`Verse search "mercy" → ${mercyHits.length} (showing first 5):`);
for (const v of mercyHits) console.log(`  ${v.id}`);

const ref = engine.search.parseReference("2:255");
console.log(`\nparseReference("2:255") →`, ref);
const surahHits = engine.search.searchSurahs("2:255");
console.log(`searchSurahs("2:255") → ${surahHits.map((s) => `${s.id} ${s.nameEnglish}`).join(", ")}`);

// ---------------------------------------------------------------------------
// 7. Sort surahs by ayah count (longest first)
// ---------------------------------------------------------------------------
heading("7. Surahs sorted by ayah count (descending) — top 3");
const longest = sortSurahs(engine.quran.all(), "ayahs", "descending").slice(0, 3);
for (const s of longest) {
  console.log(`  #${s.id} ${s.nameEnglish.padEnd(18)} ${s.numberOfAyahs} ayahs`);
}

hr();
console.log("Done.");
