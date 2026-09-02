// @ts-check
/**
 * How far apart two readings actually are, measured word by word.
 *
 * The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which
 * says what differs but never how much. This measures it: align the two readings' words and sort
 * every pair into one of three buckets.
 *
 *  * **identical** - the same word, written the same way, marks and all.
 *  * **sameSkeleton** - the same consonantal skeleton (rasm), different vowels or spelling. This is
 *    the overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm
 *    was designed to allow: one written form, several sound readings.
 *  * **different** - a different skeleton, i.e. a genuinely different word form.
 *
 * WHY ALIGNMENT IS NOT INDEXING. Readings merge and split ayahs (Warsh's al-Baqarah has 285 ayahs
 * to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n of the
 * other. The comparison therefore walks the whole SURAH's word stream on both sides with a
 * two-pointer alignment and bounded lookahead - the same technique the word-by-word pack is built
 * with - rather than pairing by index. Words that cannot be resynced are reported as `added` or
 * `dropped` rather than silently dropped from the count.
 *
 * WHAT IT CANNOT TELL YOU. This measures the two printed TEXTS, which is not the same as measuring
 * the two recitations: a difference that lives only in how a letter is sounded (imalah, taqlil,
 * ishmam) shows up here only where the print marks it. Read the numbers as "how far apart the
 * printed mushafs are", which is what they are.
 *
 * Only the riwayat whose text this engine publishes can be compared - the eight verified ones. See
 * `../../docs/15-qiraat-comparison.md`.
 */

import { removingArabicDiacriticsAndSigns } from "./text.js";

/** Letters folded together before comparing skeletons: the same consonant, written differently. */
const SKELETON_FOLD = {
  "ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا", "ى": "ا", "ٰ": "ا",
  "ؤ": "و", "ئ": "ي", "ة": "ه",
  "ء": "", "ـ": "",
};

/** How far ahead to look for a resync before declaring a word added or dropped. */
const LOOKAHEAD = 3;

/**
 * @typedef {Object} WordDifference
 * @property {number} position   1-based word position in the BASE reading's surah
 * @property {string} base       the base reading's word ("" when the other reading adds one)
 * @property {string} other      the compared reading's word ("" when it drops one)
 * @property {"sameSkeleton"|"different"|"added"|"dropped"} kind
 */

/**
 * @typedef {Object} ComparisonTotals
 * @property {number} words         words compared, in the base reading
 * @property {number} identical
 * @property {number} sameSkeleton
 * @property {number} different
 * @property {number} added         words the compared reading has and the base does not
 * @property {number} dropped       words the base has and the compared reading does not
 * @property {number} identicalPercent  identical / words, 0...100
 */

export class QiraatComparison {
  /**
   * @param {import('./quran.js').Quran} quran a Quran with qiraat text loaded
   */
  constructor(quran) {
    this._quran = quran;
  }

  /**
   * The riwayat whose text is loaded and so can be compared, in slug order. "hafs" is always one of
   * them: it is `quran.json` itself.
   */
  available() {
    return [...new Set(["hafs", ...this._quran.loadedRiwayat()])].sort();
  }

  /**
   * Compare one surah, word by word.
   * @param {number} surahId
   * @param {string} riwayah          the reading to measure
   * @param {Object} [opts]
   * @param {string} [opts.against="hafs"]
   * @returns {ComparisonTotals}
   */
  compareSurah(surahId, riwayah, { against = "hafs" } = {}) {
    return totals(this._align(surahId, against, riwayah));
  }

  /**
   * Compare the whole Quran. This walks every word of both readings - about 155,000 comparisons -
   * so cache the result rather than calling it per render.
   * @param {string} riwayah
   * @param {Object} [opts]
   * @param {string} [opts.against="hafs"]
   * @returns {ComparisonTotals}
   */
  compare(riwayah, { against = "hafs" } = {}) {
    /** @type {ComparisonTotals} */
    const sum = { words: 0, identical: 0, sameSkeleton: 0, different: 0, added: 0, dropped: 0, identicalPercent: 0 };
    for (const surah of this._quran.all()) {
      const part = this.compareSurah(surah.id, riwayah, { against });
      sum.words += part.words;
      sum.identical += part.identical;
      sum.sameSkeleton += part.sameSkeleton;
      sum.different += part.different;
      sum.added += part.added;
      sum.dropped += part.dropped;
    }
    sum.identicalPercent = sum.words ? (100 * sum.identical) / sum.words : 0;
    return sum;
  }

  /**
   * The words that are not identical, in reading order - the rows behind a comparison view.
   * @param {number} surahId
   * @param {string} riwayah
   * @param {Object} [opts]
   * @param {string} [opts.against="hafs"]
   * @param {number} [opts.limit=0] 0 for all
   * @returns {WordDifference[]}
   */
  differences(surahId, riwayah, { against = "hafs", limit = 0 } = {}) {
    const out = this._align(surahId, against, riwayah).filter((row) => row.kind !== "identical");
    const rows = out.map((row) => ({
      position: row.position,
      base: row.base,
      other: row.other,
      kind: /** @type {WordDifference["kind"]} */ (row.kind),
    }));
    return limit > 0 ? rows.slice(0, limit) : rows;
  }

  /**
   * Every word of a surah in one reading, in order. Exposed because it is the unit everything here
   * counts in, and a consumer rendering the comparison needs the same tokens.
   * @param {number} surahId @param {string} riwayah
   * @returns {string[]}
   */
  words(surahId, riwayah) {
    const surah = this._quran.surah(surahId);
    if (!surah) return [];
    // The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking Hafs'
    // ayah ids and asking for each would compare different verses (and silently fall back to Hafs
    // for the ids the reading does not have).
    const verses = riwayah.toLowerCase() === "hafs"
      ? surah.ayahs.map((ayah) => ayah.textArabic)
      : this._quran.qiraahVerses(surahId, riwayah).map((verse) => verse.text);
    /** @type {string[]} */
    const out = [];
    for (const text of verses) {
      for (const token of text.split(/\s+/u)) if (token) out.push(token);
    }
    return out;
  }

  /**
   * Two-pointer alignment with bounded lookahead. Returns one row per aligned pair, plus rows for
   * words only one side has.
   * @param {number} surahId @param {string} base @param {string} other
   * @returns {{position:number, base:string, other:string, kind:string}[]}
   */
  _align(surahId, base, other) {
    const left = this.words(surahId, base);
    const right = this.words(surahId, other);
    /** @type {{position:number, base:string, other:string, kind:string}[]} */
    const rows = [];

    let i = 0;
    let j = 0;
    while (i < left.length && j < right.length) {
      if (left[i] === right[j]) {
        rows.push({ position: i + 1, base: left[i], other: right[j], kind: "identical" });
        i++; j++;
        continue;
      }
      if (skeleton(left[i]) === skeleton(right[j])) {
        rows.push({ position: i + 1, base: left[i], other: right[j], kind: "sameSkeleton" });
        i++; j++;
        continue;
      }
      // Not a match. Before calling it a different word, see whether one side simply has an extra
      // word here - a merge or a split - by looking for the next place the two streams agree.
      const resync = findResync(left, right, i, j);
      if (resync) {
        for (let k = i; k < resync.i; k++) {
          rows.push({ position: k + 1, base: left[k], other: "", kind: "dropped" });
        }
        for (let k = j; k < resync.j; k++) {
          rows.push({ position: i + 1, base: "", other: right[k], kind: "added" });
        }
        i = resync.i;
        j = resync.j;
        continue;
      }
      rows.push({ position: i + 1, base: left[i], other: right[j], kind: "different" });
      i++; j++;
    }
    for (; i < left.length; i++) rows.push({ position: i + 1, base: left[i], other: "", kind: "dropped" });
    for (; j < right.length; j++) rows.push({ position: left.length, base: "", other: right[j], kind: "added" });
    return rows;
  }
}

/**
 * The nearest offset within the lookahead window at which the two streams agree again by skipping
 * words on ONE side only - an insertion or a deletion.
 *
 * Skipping on both sides at once is deliberately not a resync: that is a substitution, one word
 * standing where another does, which is the `different` bucket. Allowing it here collapsed every
 * genuine word difference into a dropped+added pair and left `different` permanently at zero.
 *
 * @param {string[]} left @param {string[]} right @param {number} i @param {number} j
 */
function findResync(left, right, i, j) {
  for (let skip = 1; skip <= LOOKAHEAD; skip++) {
    // The base has words the other reading does not.
    if (i + skip < left.length && skeleton(left[i + skip]) === skeleton(right[j])) {
      return { i: i + skip, j };
    }
    // The other reading has words the base does not.
    if (j + skip < right.length && skeleton(left[i]) === skeleton(right[j + skip])) {
      return { i, j: j + skip };
    }
  }
  return null;
}

/** @param {{position:number, base:string, other:string, kind:string}[]} rows */
function totals(rows) {
  /** @type {ComparisonTotals} */
  const out = { words: 0, identical: 0, sameSkeleton: 0, different: 0, added: 0, dropped: 0, identicalPercent: 0 };
  for (const row of rows) {
    if (row.kind === "added") { out.added++; continue; }
    out.words++;
    if (row.kind === "identical") out.identical++;
    else if (row.kind === "sameSkeleton") out.sameSkeleton++;
    else if (row.kind === "dropped") out.dropped++;
    else out.different++;
  }
  out.identicalPercent = out.words ? (100 * out.identical) / out.words : 0;
  return out;
}

/**
 * The consonantal skeleton of a word: diacritics and recitation signs gone, the letters that are
 * written differently for the same consonant folded together.
 * @param {string} word
 */
export function skeleton(word) {
  let out = "";
  for (const ch of removingArabicDiacriticsAndSigns(word)) {
    const folded = /** @type {Record<string,string>} */ (SKELETON_FOLD)[ch];
    out += folded === undefined ? ch : folded;
  }
  return out;
}
