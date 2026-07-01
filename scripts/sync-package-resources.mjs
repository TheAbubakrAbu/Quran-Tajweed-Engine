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

// The core JSON the engine actually decodes today, plus the data needed for near-term parity
// (surah info, names of Allah, arabic alphabet). Excluded on purpose: the per-surah splits
// (surahs/, tajweed/ — redundant with the combined files), fonts/ (TTFs the app bundles itself),
// and qiraat/ (not yet wired into the Swift Quran loader — add when it is).
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
    await copyFile(p("data", f), join(dir, f));
    bytes += (await readFile(p("data", f))).length;
  }
  await writeFile(join(dir, "GENERATED.json"), JSON.stringify(BANNER, null, 2));
  console.log(`synced ${FILES.length} files (${(bytes / 1e6).toFixed(1)} MB) -> ${dir.replace(ROOT + "/", "")}`);
}
