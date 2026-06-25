#!/usr/bin/env node
// Regenerates the derived data files from data/quran.json:
//   • data/surahs/NNN.json + data/surahs/index.json   (per-surah split + lightweight index)
//   • data/tajweed/NNN.json + data/tajweed-annotations.json  (pre-computed tajweed layer)
//
// Run from the repo root:  node scripts/build-data.mjs
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { detectPaintOps } from "../packages/quran-engine-js/src/tajweed.js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const data = (p) => join(ROOT, "data", p);
const pad3 = (n) => String(n).padStart(3, "0");

const quran = JSON.parse(await readFile(data("quran.json"), "utf-8"));

// ---- per-surah split -----------------------------------------------------------
await mkdir(data("surahs"), { recursive: true });
const index = [];
for (const s of quran) {
  await writeFile(data(`surahs/${pad3(s.id)}.json`), JSON.stringify(s, null, 2), "utf-8");
  const { ayahs, ...meta } = s;
  index.push(meta);
}
await writeFile(data("surahs/index.json"), JSON.stringify(index, null, 2), "utf-8");
console.log(`surahs/: ${quran.length} files + index.json`);

// ---- tajweed annotation corpus -------------------------------------------------
await mkdir(data("tajweed"), { recursive: true });
const combined = [];
let total = 0;
for (const surah of quran) {
  const entries = [];
  for (const ayah of surah.ayahs) {
    const ops = detectPaintOps(ayah.textArabic, { surahId: surah.id, ayahId: ayah.id });
    const len = ayah.textArabic.length;
    const cat = new Array(len).fill(null);
    const pri = new Array(len).fill(-1);
    for (const op of [...ops].sort((a, b) => a.priority - b.priority))
      for (let i = op.start; i < op.end && i < len; i++)
        if (op.priority >= pri[i]) { pri[i] = op.priority; cat[i] = op.category; }
    const annotations = [];
    let i = 0;
    while (i < len) {
      if (cat[i] == null) { i++; continue; }
      let j = i + 1;
      while (j < len && cat[j] === cat[i]) j++;
      annotations.push({ start: i, end: j, rule: cat[i] });
      i = j;
    }
    const entry = { surah: surah.id, ayah: ayah.id, annotations };
    entries.push(entry);
    combined.push(entry);
    total += annotations.length;
  }
  await writeFile(data(`tajweed/${pad3(surah.id)}.json`), JSON.stringify(entries, null, 1), "utf-8");
}
await writeFile(data("tajweed-annotations.json"), JSON.stringify(combined), "utf-8");
console.log(`tajweed/: ${quran.length} files + tajweed-annotations.json (${total} annotations)`);
