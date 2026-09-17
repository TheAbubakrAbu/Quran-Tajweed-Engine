// @ts-check
/**
 * Similar ayahs (mutashabihat): the other places the Quran says something close to this.
 *
 * Three sources, already merged and ranked at build time so nothing here scores or sorts:
 *
 *  * **verified** - the classical mutashabihat corpus, listed first.
 *  * **generated** - phrase-overlap matches, each carrying the `labels` that explain why it
 *    matched ("Reckoning", "Root rbb"). These are a reading aid, not a scholarly claim.
 *
 * `verified` is the flag to gate on if you show only one kind.
 *
 * The Quranic Universal Library's table is the third source, and it adds `score`, its own 0-100
 * similarity; `score` is null for rows that came from the other two sources, which rank but do
 * not score.
 *
 * The shared wording is `spans`: 0-based inclusive token ranges into the MATCHED ayah's raw text.
 * QUL's own placement where it lists the pair, else the wording the corpus recorded, located in
 * the ayah when the data was built. The data carries no text of its own (version 2): read the
 * words out of `engine.quran` by those spans, so what you show is the Quran text you already
 * have and not a second copy of it.
 */

/**
 * @typedef {Object} SimilarMatch
 * @property {number} surah
 * @property {number} ayah
 * @property {boolean} verified
 * @property {string[]} labels  why a generated row matched; empty for verified rows
 * @property {Array<[number, number]>} spans  0-based inclusive token ranges of the shared words
 *           in the MATCHED ayah's raw text; empty when no source records shared wording
 * @property {number|null} score  QUL's 0-100 similarity, null for rows from the other sources
 */

/**
 * @typedef {Object} SimilarAyahsData
 * @property {number} v  the data version; this module reads version 2
 * @property {Record<string, Array<[number, number, number, Array<[number,number]>, string[], number|null]>>} ayahs
 *           keyed "surah:ayah", each row [surah, ayah, verifiedFlag, spans, labels, score]
 */

export class SimilarAyahs {
  /** @param {SimilarAyahsData|Object} [data] data/similar-ayahs.json (version 2) */
  constructor(data = {}) {
    // A version-1 file (rows keyed at the top level, the phrase as text) is not read: it would
    // put the shared wording where a span is expected. Treated as no data rather than half a one.
    this._data = data && data.v === 2 && data.ayahs ? data.ayahs : {};
  }

  /**
   * Matches for an ayah, in display order. Empty for most short ayahs.
   * @param {number} surahId @param {number} ayahId
   * @returns {SimilarMatch[]}
   */
  matches(surahId, ayahId) {
    const rows = this._data[`${surahId}:${ayahId}`];
    if (!rows) return [];
    return rows.map(([surah, ayah, verified, spans, labels, score]) => ({
      surah,
      ayah,
      verified: verified === 1,
      labels: labels ?? [],
      spans: spans ?? [],
      score: score ?? null,
    }));
  }

  /**
   * Whether the ayah has any - a dictionary hit, so it is cheap enough to gate a button on.
   * @param {number} surahId @param {number} ayahId
   */
  has(surahId, ayahId) {
    return (this._data[`${surahId}:${ayahId}`]?.length ?? 0) > 0;
  }

  /** How many ayahs have at least one match. */
  count() {
    return Object.keys(this._data).length;
  }
}
