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

/** @param {string} rel */
async function readJson(rel) {
  return JSON.parse(await readFile(join(DATA_DIR, rel), "utf-8"));
}

/**
 * Load all canonical data from disk and build the engine.
 * @param {Object} [opts]
 * @param {string} [opts.dataDir]   override the data directory
 * @param {boolean} [opts.loadQiraat=false]  also load the 7 qiraat text files (~11 MB)
 * @param {boolean} [opts.loadSurahInfo=false]  also load surah-info.json (~1.8 MB)
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

  /** @type {any} */
  const data = { quran, juz, reciters, tajweedRules, surahInfo, namesOfAllah, muqattaat, qiraatCounts };

  if (opts.loadQiraat) {
    /** @type {Record<string, any>} */
    const qiraat = {};
    await Promise.all(RIWAYAT.map(async (r) => { qiraat[r] = await read(`qiraat/qiraah-${r}.json`); }));
    data.qiraat = qiraat;
  }

  return createEngine(data, { riwayah: opts.riwayah });
}

export { readJson, DATA_DIR, RIWAYAT };
