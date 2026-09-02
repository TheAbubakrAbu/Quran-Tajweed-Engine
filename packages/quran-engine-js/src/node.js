// @ts-check
/**
 * Node-only convenience loader. Reads the canonical JSON from the repository `data/` directory
 * and builds a ready-to-use engine. In browsers/bundlers, import the JSON yourself and use
 * `createEngine` from the main entry point instead.
 */

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createEngine } from "./index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
// packages/quran-engine-js/src -> repo root /data
const DATA_DIR = join(__dirname, "..", "..", "..", "data");

const RIWAYAT = ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"];
/** The eight riwayat whose text this engine publishes - the ones with line tables. */
const RIWAYAT_WITH_TEXT = ["hafs", ...RIWAYAT];

/** @param {string} rel */
async function readJson(rel) {
  return JSON.parse(await readFile(join(DATA_DIR, rel), "utf-8"));
}

/**
 * Load all canonical data from disk and build the engine.
 * @param {Object} [opts]
 * @param {string} [opts.dataDir]   override the data directory
 * @param {boolean} [opts.loadQiraat=false]  also load the 7 qiraat text files (~11 MB); needed by
 *        `engine.qiraatComparison`, which has nothing to compare without them
 * @param {boolean} [opts.loadSurahInfo=false]  also load surah-info.json (~1.8 MB)
 * @param {boolean} [opts.loadMushaf=false]  also load the mushaf index, page and line tables (~2 MB)
 * @param {boolean} [opts.loadQiraatTajweed=false]  also load the 7 riwayah tajweed packs (~0.9 MB)
 * @param {boolean} [opts.loadWordByWord=false]  also load word-by-word.json (~1.8 MB)
 * @param {boolean} [opts.loadSimilarAyahs=false]  also load similar-ayahs.json (~3.5 MB)
 * @param {string} [opts.riwayah]   default display riwayah for search indexing
 */
export async function loadFromDisk(opts = {}) {
  const dir = opts.dataDir ?? DATA_DIR;
  const read = async (rel) => JSON.parse(await readFile(join(dir, rel), "utf-8"));

  const [quran, juz, reciters, tajweedRules, surahInfo, namesOfAllah, muqattaat, qiraatCounts] = await Promise.all([
    read("quran.json"),
    read("juz.json"),
    read("reciters.json"),
    read("tajweed-rules.json"),
    read("surah-info.json"),
    read("names-of-allah.json"),
    read("muqattaat.json"),
    read("qiraat-counts.json"),
  ]);

  // Themes and lessons load by default: together they are ~250 KB, and a topic list is exactly the
  // kind of thing a consumer wants without having to know it needed a flag.
  // Sections (80 KB) and the alphabet (18 KB) join them: small, and both answer questions a
  // consumer should not have to opt into.
  const [themes, tajweedLessons, surahSections, arabicAlphabet] = await Promise.all([
    read("themes.json"),
    read("tajweed-lessons.json"),
    read("surah-sections.json"),
    read("arabic-alphabet.json"),
  ]);

  /** @type {any} */
  const data = { quran, juz, reciters, tajweedRules, surahInfo, namesOfAllah, muqattaat, qiraatCounts,
                 themes, tajweedLessons, surahSections, arabicAlphabet };

  if (opts.loadQiraat) {
    /** @type {Record<string, any>} */
    const qiraat = {};
    await Promise.all(RIWAYAT.map(async (r) => { qiraat[r] = await read(`qiraat/qiraah-${r}.json`); }));
    data.qiraat = qiraat;
  }

  if (opts.loadMushaf) {
    data.mushafIndex = await read("mushaf/index.json");
    /** @type {Record<string, any>} */
    const pages = {};
    /** @type {Record<string, any>} */
    const lines = {};
    await Promise.all(data.mushafIndex.riwayat.map(async (/** @type any */ entry) => {
      pages[entry.riwayah] = await read(`mushaf/${entry.pages}`);
      if (entry.lines) lines[entry.riwayah] = await read(`mushaf/${entry.lines}`);
    }));
    data.mushafPages = pages;
    data.mushafLines = lines;
  }

  if (opts.loadQiraatTajweed) {
    data.qiraatTajweedRules = await read("tajweed-qiraat/rules.json");
    /** @type {Record<string, any>} */
    const packs = {};
    await Promise.all(RIWAYAT.map(async (r) => { packs[r] = await read(`tajweed-qiraat/${r}.json`); }));
    data.qiraatTajweed = packs;
  }

  if (opts.loadWordByWord) data.wordByWord = await read("word-by-word.json");
  if (opts.loadSimilarAyahs) data.similarAyahs = await read("similar-ayahs.json");

  return createEngine(data, { riwayah: opts.riwayah });
}

export { readJson, DATA_DIR, RIWAYAT, RIWAYAT_WITH_TEXT };
