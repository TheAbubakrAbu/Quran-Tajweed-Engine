// @ts-check
/**
 * Arabic text utilities shared across the engine.
 *
 * Faithfully ported from Al-Islam's QuranStructs.swift / Settings.swift / Globals.swift.
 * Everything here operates on Unicode scalar values so the behaviour is identical across
 * languages and never depends on a particular font or glyph shaping.
 */

/** Combining marks that count as Arabic "tashkeel" (diacritics) for the search normalizer. */
const TASHKEEL_RANGES = [
  [0x0610, 0x061a],
  [0x064b, 0x065f],
  [0x0670, 0x0670],
  [0x06d6, 0x06ed],
];

/** @param {number} cp */
function inTashkeel(cp) {
  return TASHKEEL_RANGES.some(([lo, hi]) => cp >= lo && cp <= hi);
}

/**
 * Canonical Arabic fold map applied before stripping marks during search normalization.
 * Mirrors Settings.canonicalArabicSearchMap.
 * @type {Record<string,string>}
 */
const CANONICAL_ARABIC_MAP = {
  "ٰ": "ا", // dagger alif
  "ٱ": "ا",
  "أ": "ا", "إ": "ا", "آ": "ا", "ٲ": "ا", "ٳ": "ا", "ٵ": "ا",
  "ؤ": "و", "ئ": "ي", "ء": "", "ٴ": "", "ٶ": "و", "ٷ": "و", "ٸ": "ي",
  "ۥ": "و", // small waw
  "ۦ": "ي", // small yeh
  "ى": "ا", // alif maqsura -> alif
  "ة": "ه", // teh marbuta -> heh
};

/** Boolean-search operators that must survive the unwanted-character strip. */
const KEPT_OPERATORS = new Set(["&", "|", "!", "#"]);

/**
 * Remove Quranic recitation marks / diacritics (the "clean Arabic" used for display + search).
 * Mirrors Globals.removingArabicDiacriticsAndSigns.
 * @param {string} text
 * @returns {string}
 */
export function removingArabicDiacriticsAndSigns(text) {
  let out = "";
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp === 0x0671) { out += "ا"; continue; } // hamzat wasl -> alif
    if (
      (cp >= 0x064b && cp <= 0x065f) ||
      (cp >= 0x06d6 && cp <= 0x06ed) ||
      cp === 0x0670 || cp === 0x0657 || cp === 0x0674 || cp === 0x0656
    ) continue;
    out += ch;
  }
  return out;
}

/**
 * Remove the marks the surah-name search treats as noise. Mirrors String.removingArabicMarks().
 * @param {string} text
 */
export function removingArabicMarks(text) {
  let out = "";
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (
      cp === 0x0640 ||
      (cp >= 0x0610 && cp <= 0x061a) ||
      (cp >= 0x064b && cp <= 0x065f) ||
      (cp >= 0x06d6 && cp <= 0x06ed)
    ) continue;
    out += ch;
  }
  return out;
}

/** Convert Arabic-Indic and Eastern-Arabic digits to Western. Mirrors String.arabicDigitsToWestern(). */
export function arabicDigitsToWestern(text) {
  /** @type {Record<string,string>} */
  const map = {
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
    "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
    "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
  };
  return [...text].map((c) => map[c] ?? c).join("");
}

/** Collapse runs of whitespace into single spaces. */
export function collapsingWhitespace(text) {
  return text.split(/\s+/u).filter(Boolean).join(" ");
}

/**
 * The core search normalizer. Mirrors Settings.cleanSearch():
 *   fold Arabic carriers -> strip punctuation/symbols/combining-marks (except & | ! #)
 *   -> lowercase -> collapse whitespace.
 * @param {string} text
 * @param {{ whitespace?: boolean }} [opts]
 */
export function cleanSearch(text, opts = {}) {
  // 1. canonical Arabic fold
  let folded = text;
  for (const [k, v] of Object.entries(CANONICAL_ARABIC_MAP)) {
    folded = folded.split(k).join(v);
  }
  // 2. strip "unwanted" chars: punctuation, symbols, and all combining marks (Unicode M*),
  //    keeping the four boolean operators.
  let cleaned = "";
  for (const ch of folded) {
    if (KEPT_OPERATORS.has(ch)) { cleaned += ch; continue; }
    if (/\p{P}|\p{S}|\p{M}/u.test(ch)) continue;
    cleaned += ch;
  }
  cleaned = collapsingWhitespace(cleaned.toLowerCase());
  if (opts.whitespace) cleaned = cleaned.trim();
  return cleaned;
}

/** Keep ONLY tashkeel scalars (inverse of cleanSearch). Mirrors arabicTashkeelBlob(). */
export function arabicTashkeelBlob(text) {
  let out = "";
  for (const ch of text) {
    if (inTashkeel(ch.codePointAt(0) ?? 0)) out += ch;
  }
  return out;
}

/** Lowercase + whitespace-collapse without stripping marks. Mirrors exactPhraseBlob(). */
export function exactPhraseBlob(text) {
  return collapsingWhitespace(text.toLowerCase());
}

/** Tokenize a cleaned blob on spaces. Mirrors searchTokens(). */
export function searchTokens(cleanedText) {
  return cleanedText.split(" ").filter(Boolean);
}

const ARABIC_LETTER_RANGES = [
  [0x0600, 0x06ff], [0x0750, 0x077f], [0x08a0, 0x08ff],
  [0xfb50, 0xfdff], [0xfe70, 0xfeff], [0x1ee00, 0x1eeff],
];

/** True if the string contains any Arabic-script letter. Mirrors containsArabicLetters. */
export function containsArabicLetters(text) {
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (ARABIC_LETTER_RANGES.some(([lo, hi]) => cp >= lo && cp <= hi)) return true;
  }
  return false;
}

/**
 * Drop "silent" Arabic letters for the lenient Arabic search variant.
 * Mirrors Globals.removingSilentArabicLettersForSearch (grapheme-cluster walk).
 * @param {string} text
 */
export function removingSilentArabicLettersForSearch(text) {
  const VOWELS = new Set([0x064e, 0x064f, 0x0650, 0x064b, 0x064c, 0x064d, 0x0656, 0x0657, 0x065a]);
  const clusters = splitGraphemeClusters(text);
  let out = "";
  for (const cluster of clusters) {
    const scalars = [...cluster].map((c) => c.codePointAt(0) ?? 0);
    const base = scalars[0];
    const has = (cp) => scalars.includes(cp);
    const hasStdSukoon = has(0x0652) && !has(0x06e1);
    // hamzatul wasl is always silent
    if (base === 0x0671) continue;
    // alif/waw/ya/alif-maqsura with a plain sukoon
    if ([0x0627, 0x0648, 0x064a, 0x0649].includes(base) && hasStdSukoon) continue;
    // lam with a plain sukoon
    if (base === 0x0644 && hasStdSukoon) continue;
    // waw carrying a dagger alif with no vowel/shadda/sukoon
    if (base === 0x0648 && has(0x0670) &&
        !scalars.some((s) => VOWELS.has(s) || s === 0x0651 || s === 0x0652)) continue;
    out += cluster;
  }
  return out;
}

/**
 * Split a string into Unicode extended grapheme clusters (base letter + trailing combining marks),
 * matching Swift's `Character` iteration. Uses Intl.Segmenter when available, else a combining-mark
 * fallback that is sufficient for Arabic Quranic text.
 * @param {string} text
 * @returns {string[]}
 */
export function splitGraphemeClusters(text) {
  if (typeof Intl !== "undefined" && /** @type {any} */ (Intl).Segmenter) {
    const seg = new Intl.Segmenter("ar", { granularity: "grapheme" });
    return [...seg.segment(text)].map((s) => s.segment);
  }
  /** @type {string[]} */
  const out = [];
  for (const ch of text) {
    if (out.length && /\p{M}/u.test(ch)) out[out.length - 1] += ch;
    else out.push(ch);
  }
  return out;
}
