#!/usr/bin/env node
/**
 * Sync the canonical /data JSON into each language package that bundles data as a build resource
 * (so the package is self-contained and consumable WITHOUT the repo /data dir present — e.g. the
 * Swift package added to an iOS app via SwiftPM).
 *
 * SINGLE SOURCE OF TRUTH stays /data. These bundled copies are GENERATED — never hand-edit them;
 * re-run `node scripts/sync-package-resources.mjs` after changing /data (or running build-data.mjs).
 *
 * Currently targets the Swift package (the one Al-Islam will consume). Other ports discover the
 * repo /data on disk in dev; add them here when they need bundled resources too.
 */
import { readFile, writeFile, mkdir, copyFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const p = (...a) => join(ROOT, ...a);

// The JSON the engine decodes. Nested paths are kept nested — SwiftPM's `.copy("Resources")`
// preserves the directory structure, and the Swift loader looks a file up under its own
// subdirectory. Excluded on purpose: the per-surah splits (surahs/, tajweed/ — redundant with the
// combined files), fonts/ (TTFs the app bundles itself), qiraat/ (11 MB of riwayah text: the Swift
// loader reads it when `loadQiraat` is passed a `dataDirectory`, but bundling it would triple the
// package for a feature most consumers do not use), and mushaf/pdfs/ (23 MB of facsimiles the engine
// never loads itself: `mushaf.pdfPath(_:)` hands the consumer a path, and the consumer ships it).
const FILES = [
  "quran.json",
  "juz.json",
  "reciters.json",
  "tajweed-rules.json",
  "tajweed-annotations.json",
  "surah-info.json",
  "names-of-allah.json",
  "arabic-alphabet.json",
  "muqattaat.json",
  "qiraat-counts.json",
  "themes.json",
  "tajweed-lessons.json",
  "surah-sections.json",
  "surah-stats.json",
  "word-by-word.json",
  "similar-ayahs.json",
  // Batch 5. The three that load by default are small; morphology, the topic indexes and the
  // variant trio are opt-in but bundled anyway, because an app added via SwiftPM has no repo
  // /data to fall back on and a flag it cannot satisfy is worse than 2 MB it may not read.
  "quran-metadata.json",
  "ayah-themes.json",
  "word-of-day.json",
  "morphology.json",
  "mutashabihat.json",
  "quran-topics.json",
  "qiraat-variants.json",
  "qiraat-places.json",
  "qiraat-variant-audio.json",
  "mushaf/index.json",
  "tajweed-qiraat/rules.json",
  ...["hafs", "shubah", "warsh", "qaloon", "buzzi", "qunbul", "duri", "susi",
      "hisham", "ibn-dhakwan", "khalaf", "khallad", "abu-harith", "duri-kisai",
      "ibn-wardan", "ibn-jammaz", "ruways", "rawh", "ishaq", "idris"]
    .map((slug) => `mushaf/pages/${slug}.json`),
  ...["hafs", "shubah", "warsh", "qaloon", "buzzi", "qunbul", "duri", "susi"]
    .flatMap((slug) => [`mushaf/lines/${slug}.json`, ...(slug === "hafs" ? [] : [`tajweed-qiraat/${slug}.json`])]),
];

const targets = [
  p("packages", "quran-engine-swift", "Sources", "QuranEngine", "Resources"),
];

const BANNER = {
  _generated: "Files in this directory are COPIED from /data by scripts/sync-package-resources.mjs.",
  _doNotEdit: "Do not hand-edit. The single source of truth is the repo-root /data directory.",
};

for (const dir of targets) {
  await mkdir(dir, { recursive: true });
  let bytes = 0;
  for (const f of FILES) {
    const target = join(dir, f);
    await mkdir(dirname(target), { recursive: true });
    await copyFile(p("data", f), target);
    bytes += (await readFile(p("data", f))).length;
  }
  await writeFile(join(dir, "GENERATED.json"), JSON.stringify(BANNER, null, 2));
  console.log(`synced ${FILES.length} files (${(bytes / 1e6).toFixed(1)} MB) -> ${dir.replace(ROOT + "/", "")}`);
}
