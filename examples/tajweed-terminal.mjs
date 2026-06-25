// tajweed-terminal.mjs
//
// Render any ayah to the TERMINAL with 24-bit (true color) ANSI, coloring each
// tajweed span with its canonical rule color. Runs with zero install:
//
//     node examples/tajweed-terminal.mjs            # defaults to 1:1
//     node examples/tajweed-terminal.mjs 2 255      # Ayat al-Kursi
//     node examples/tajweed-terminal.mjs 112        # whole surah (al-Ikhlas)
//
// Usage:
//   <surah>          → print every ayah of that surah, colored
//   <surah> <ayah>   → print just that one ayah
//
// Note: your terminal must support 24-bit color (most modern ones do:
// iTerm2, Apple Terminal, the VS Code terminal, GNOME Terminal, Windows Terminal).

import { loadFromDisk } from "../packages/quran-engine-js/src/node.js";

// "#RRGGBB" → ANSI 24-bit foreground escape sequence.
const RESET = "\x1b[0m";
function ansiFg(hex) {
  if (!hex) return "";
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
  if (!m) return "";
  const [r, g, b] = [m[1], m[2], m[3]].map((h) => parseInt(h, 16));
  return `\x1b[38;2;${r};${g};${b}m`;
}

// Turn an ayah's Arabic text into a colored string. The engine returns
// non-overlapping spans in order; text outside any span is printed uncolored.
function colorize(text, spans) {
  let out = "";
  let cursor = 0;
  for (const s of spans) {
    if (s.start > cursor) out += text.slice(cursor, s.start); // uncolored gap
    out += ansiFg(s.color) + text.slice(s.start, s.end) + RESET;
    cursor = s.end;
  }
  out += text.slice(cursor);
  return out;
}

// ---- args ------------------------------------------------------------------
const surahId = Number(process.argv[2] ?? 1);
const ayahArg = process.argv[3] != null ? Number(process.argv[3]) : null;

const engine = await loadFromDisk();
const surah = engine.quran.surah(surahId);
if (!surah) {
  console.error(`No surah ${surahId}. Use a number 1..114.`);
  process.exit(1);
}

// Build a legend of the rule categories so the colors are interpretable.
const legend = engine.tajweedRules.categories
  .map((c) => `${ansiFg(c.colorHex)}${c.englishTitle}${RESET}`)
  .join("  ·  ");

console.log(`\n${surah.id}. ${surah.nameEnglish}  (${surah.nameArabic})\n`);
console.log(`Legend: ${legend}\n`);

// Pick the ayahs to render.
const ayahs = ayahArg != null
  ? [engine.quran.ayah(surahId, ayahArg)].filter(Boolean)
  : surah.ayahs;

if (!ayahs.length) {
  console.error(`No ayah ${surahId}:${ayahArg}.`);
  process.exit(1);
}

// Terminals render RTL Arabic right-aligned poorly when mixed with the ref label,
// so we print the colored Arabic on its own line.
for (const ayah of ayahs) {
  const spans = engine.tajweed(ayah.textArabic);
  console.log(`  [${surahId}:${ayah.id}]`);
  console.log(`  ${colorize(ayah.textArabic, spans)}\n`);
}
