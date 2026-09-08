// @ts-check
/**
 * A curated word of Quranic vocabulary, with every ayah the same written form appears in.
 *
 * 149 words, ordered so that consecutive days feel varied (the themes are interleaved in the
 * corpus itself), which is why the day mapping below is a walk and not a hash: hashing would
 * scatter the curation's own ordering, and the ordering is the point.
 *
 * The occurrence list is derived from the Hafs text by matching the exact written form, so the
 * count on a card and the list behind it are one derivation and cannot disagree. A form can
 * repeat inside a single ayah, so an occurrence carries token indices, plural.
 *
 * Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission.
 */

/**
 * @typedef {Object} WordOccurrence
 * @property {number} surah
 * @property {number} ayah
 * @property {number[]} tokens  0-based whitespace-token indices into the ayah's raw text
 */

/**
 * @typedef {Object} WordEntry
 * @property {string} id
 * @property {string} arabic          the form as it stands at its first appearance
 * @property {string} transliteration
 * @property {string} meaning
 * @property {number} surah          the anchor: where the form first appears
 * @property {number} ayah
 * @property {number} token
 * @property {number} count          hits across the whole Quran
 * @property {WordOccurrence[]} occurrences  in mushaf order
 */

/** Days since the Unix epoch in the runtime's local time zone. */
function localDayIndex(date) {
  const d = date instanceof Date ? date : new Date(date);
  return Math.floor((d.getTime() - d.getTimezoneOffset() * 60_000) / 86_400_000);
}

export class WordOfDay {
  /** @param {Object} [data] data/word-of-day.json @param {WordEntry[]} [data.words] */
  constructor(data = {}) {
    this._words = data.words ?? [];
    /** @type {Map<string, WordEntry>} */
    this._byId = new Map(this._words.map((w) => [w.id, w]));
  }

  get isLoaded() {
    return this._words.length > 0;
  }

  /** The whole corpus, in curation order. @returns {WordEntry[]} */
  all() {
    return this._words;
  }

  /** @param {string} id @returns {WordEntry|null} */
  word(id) {
    return this._byId.get(id) ?? null;
  }

  /**
   * The word for a given day index: the corpus walked in order, one entry per day, wrapping.
   * Take this rather than `forDate` if your app has its own idea of when a day turns over (the
   * upstream app rolls at Fajr, not midnight); hand it your own day number and the mapping is
   * identical.
   * @param {number} dayIndex @returns {WordEntry|null}
   */
  forDayIndex(dayIndex) {
    if (!this._words.length) return null;
    const n = this._words.length;
    return this._words[((Math.trunc(dayIndex) % n) + n) % n];
  }

  /**
   * Today's word, by local midnight.
   * @param {Date|number|string} [date] @returns {WordEntry|null}
   */
  forDate(date = new Date()) {
    return this.forDayIndex(localDayIndex(date));
  }

  /**
   * Words whose form, transliteration or meaning matches a query. Arabic is compared as written,
   * since the corpus stores the exact form and that is what a reader is looking at.
   * @param {string} query @param {number} [limit] @returns {WordEntry[]}
   */
  search(query, limit = 25) {
    const q = String(query ?? "").trim();
    if (!q) return [];
    const lower = q.toLowerCase();
    return this._words
      .filter((w) => w.arabic.includes(q)
        || w.transliteration.toLowerCase().includes(lower)
        || w.meaning.toLowerCase().includes(lower))
      .slice(0, limit);
  }

  /** Every curated word appearing in an ayah, if any. @returns {WordEntry[]} */
  wordsIn(surahId, ayahId) {
    return this._words.filter((w) => w.occurrences.some((o) => o.surah === surahId && o.ayah === ayahId));
  }

  count() {
    return { words: this._words.length, occurrences: this._words.reduce((n, w) => n + w.count, 0) };
  }
}
