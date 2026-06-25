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
import { tajweedSpans, detectPaintOps, resolveSpans } from "./tajweed.js";

export * from "./text.js";
export * from "./quran.js";
export * from "./tajweed.js";
export * from "./juzPage.js";
export * from "./sorting.js";
export * from "./audio.js";
export * from "./search.js";
export * from "./cache.js";

/**
 * Build the full engine facade from parsed JSON.
 * @param {Object} data
 * @param {import('./quran.js').Surah[]} data.quran                 data/quran.json
 * @param {import('./juzPage.js').JuzEntry[]} data.juz              data/juz.json
 * @param {import('./audio.js').Reciter[]} data.reciters            data/reciters.json
 * @param {any} [data.tajweedRules]                                 data/tajweed-rules.json
 * @param {Array<{id:number,sources:Array<{name:string,contents:string}>}>} [data.surahInfo] data/surah-info.json
 * @param {Record<string, Record<string, {id:number,text:string}[]>>} [data.qiraat]  riwayah -> qiraah JSON
 * @param {{ riwayah?: string }} [opts]
 */
export function createEngine(data, opts = {}) {
  const quran = new Quran({ surahs: data.quran, surahInfo: data.surahInfo, qiraat: data.qiraat });
  const juzPage = new JuzPage(quran, data.juz);
  const reciters = new Reciters(data.reciters);
  const search = new Search(quran, opts);
  const tajweedRules = data.tajweedRules ?? null;

  return {
    quran,
    juzPage,
    reciters,
    search,
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
