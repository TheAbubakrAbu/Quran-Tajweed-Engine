// @ts-check
/**
 * @quran-tajweed-engine/core — framework-agnostic Quran engine.
 *
 * Pure ESM, zero runtime dependencies. Works in browsers, Node 18+, Deno, Bun, React Native
 * (via Hermes/Intl.Segmenter polyfill). The engine is data-driven: feed it the JSON from `/data`.
 *
 * Quick start (Node):
 *   import { loadFromDisk } from "@quran-tajweed-engine/core/node";
 *   const engine = await loadFromDisk();
 *   engine.quran.surah(1).nameEnglish;            // "The Opener"
 *   engine.tajweed("بِسۡمِ ٱللَّهِ");               // colored spans
 *
 * Quick start (browser/bundler): import the JSON yourself and pass it in:
 *   import { createEngine } from "@quran-tajweed-engine/core";
 *   import quran from "../data/quran.json";  // etc.
 *   const engine = createEngine({ quran, juz, reciters, tajweedRules, surahInfo, qiraat });
 */

import { Quran } from "./quran.js";
import { JuzPage } from "./juzPage.js";
import { Reciters } from "./audio.js";
import { Search } from "./search.js";
import { NamesOfAllah } from "./names.js";
import { Muqattaat } from "./muqattaat.js";
import { Mushaf } from "./mushaf.js";
import { QiraatTajweed } from "./qiraatTajweed.js";
import { WordByWord } from "./wordByWord.js";
import { SimilarAyahs } from "./similar.js";
import { Themes } from "./themes.js";
import { TajweedLessons } from "./lessons.js";
import { AskAI } from "./askAI.js";
import { SurahSections } from "./sections.js";
import { ArabicAlphabet } from "./alphabet.js";
import { QiraatComparison } from "./qiraatComparison.js";
import { tajweedSpans, detectPaintOps, resolveSpans } from "./tajweed.js";

export * from "./text.js";
export * from "./quran.js";
export * from "./tajweed.js";
export * from "./juzPage.js";
export * from "./sorting.js";
export * from "./audio.js";
export * from "./search.js";
export * from "./names.js";
export * from "./muqattaat.js";
export * from "./mushaf.js";
export * from "./qiraatTajweed.js";
export * from "./wordByWord.js";
export * from "./similar.js";
export * from "./themes.js";
export * from "./lessons.js";
export * from "./semantic.js";
export * from "./askAI.js";
export * from "./sections.js";
export * from "./alphabet.js";
export * from "./qiraatComparison.js";
export * from "./cache.js";

/**
 * Build the full engine facade from parsed JSON.
 * @param {Object} data
 * @param {import('./quran.js').Surah[]} data.quran                 data/quran.json
 * @param {import('./juzPage.js').JuzEntry[]} data.juz              data/juz.json
 * @param {import('./audio.js').Reciter[]} data.reciters            data/reciters.json
 * @param {any} [data.tajweedRules]                                 data/tajweed-rules.json
 * @param {Array<{id:number,sources:Array<{name:string,contents:string}>}>} [data.surahInfo] data/surah-info.json
 * @param {import('./names.js').NameOfAllah[]} [data.namesOfAllah]    data/names-of-allah.json
 * @param {Record<string, Record<string, {id:number,text:string}[]>>} [data.qiraat]  riwayah -> qiraah JSON
 * @param {any} [data.mushafIndex]                                  data/mushaf/index.json
 * @param {Record<string, any>} [data.mushafPages]                  slug -> data/mushaf/pages/<slug>.json
 * @param {Record<string, any>} [data.mushafLines]                  slug -> data/mushaf/lines/<slug>.json
 * @param {Record<string, {short:string,long:string}>} [data.qiraatTajweedRules] data/tajweed-qiraat/rules.json
 * @param {Record<string, any>} [data.qiraatTajweed]                slug -> data/tajweed-qiraat/<slug>.json
 * @param {{english:Record<string,string[][]>, transliteration:Record<string,string[][]>}} [data.wordByWord] data/word-by-word.json
 * @param {Record<string, any>} [data.similarAyahs]                 data/similar-ayahs.json
 * @param {{topics:any[]}} [data.themes]                            data/themes.json
 * @param {{chapters:any[]}} [data.tajweedLessons]                  data/tajweed-lessons.json
 * @param {Record<string, any>} [data.surahSections]                data/surah-sections.json
 * @param {any} [data.arabicAlphabet]                               data/arabic-alphabet.json
 * @param {{ riwayah?: string }} [opts]
 */
export function createEngine(data, opts = {}) {
  const quran = new Quran({ surahs: data.quran, surahInfo: data.surahInfo, qiraat: data.qiraat, qiraatCounts: data.qiraatCounts });
  const juzPage = new JuzPage(quran, data.juz);
  const reciters = new Reciters(data.reciters);
  const search = new Search(quran, opts);
  const namesOfAllah = new NamesOfAllah(data.namesOfAllah);
  const muqattaat = new Muqattaat(data.muqattaat);
  const mushaf = new Mushaf({ index: data.mushafIndex, pages: data.mushafPages, lines: data.mushafLines });
  const qiraatTajweed = new QiraatTajweed({ rules: data.qiraatTajweedRules, riwayat: data.qiraatTajweed });
  const wordByWord = new WordByWord(data.wordByWord ?? {}, quran);
  const similarAyahs = new SimilarAyahs(data.similarAyahs);
  const themes = new Themes(data.themes);
  const tajweedLessons = new TajweedLessons(data.tajweedLessons);
  const askAI = new AskAI({ quran, search, themes });
  const surahSections = new SurahSections(data.surahSections);
  const alphabet = new ArabicAlphabet(data.arabicAlphabet);
  // Needs `qiraat` loaded to say anything; with none it reports "hafs" alone and compares nothing.
  const qiraatComparison = new QiraatComparison(quran);
  const tajweedRules = data.tajweedRules ?? null;

  return {
    quran,
    juzPage,
    reciters,
    search,
    namesOfAllah,
    muqattaat,
    mushaf,
    qiraatTajweed,
    wordByWord,
    similarAyahs,
    themes,
    tajweedLessons,
    askAI,
    surahSections,
    alphabet,
    qiraatComparison,
    tajweedRules,
    /**
     * Detect tajweed spans for any Arabic ayah text.
     * @param {string} arabicText
     * @param {Object} [o]
     */
    tajweed(arabicText, o) {
      const spans = tajweedSpans(arabicText, o);
      if (!tajweedRules) return spans;
      const byId = new Map(tajweedRules.categories.map((/** @type any */ c) => [c.id, c]));
      return spans.map((s) => ({ ...s, color: byId.get(s.category)?.colorHex ?? null }));
    },
    detectPaintOps,
    resolveSpans,
  };
}
