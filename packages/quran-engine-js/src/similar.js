// @ts-check
/**
 * Similar ayahs (mutashabihat): the other places the Quran says something close to this.
 *
 * Two kinds of row, already merged and ranked at build time so nothing here scores or sorts:
 *
 *  * **verified** - the classical mutashabihat corpus, listed first. `phrase` is the shared
 *    wording when the corpus records it.
 *  * **generated** - phrase-overlap matches, each carrying the `labels` that explain why it
 *    matched ("Reckoning", "Root rbb"). These are a reading aid, not a scholarly claim.
 *
 * `verified` is the flag to gate on if you show only one kind.
 */

/**
 * @typedef {Object} SimilarMatch
 * @property {number} surah
 * @property {number} ayah
 * @property {string} phrase    the shared wording, "" when none is recorded
 * @property {boolean} verified
 * @property {string[]} labels  why a generated row matched; empty for verified rows
 */

export class SimilarAyahs {
  /** @param {Record<string, Array<[number, number, string, number, string[]?]>>} [data] data/similar-ayahs.json */
  constructor(data = {}) {
    this._data = data;
  }

  /**
   * Matches for an ayah, in display order. Empty for most short ayahs.
   * @param {number} surahId @param {number} ayahId
   * @returns {SimilarMatch[]}
   */
  matches(surahId, ayahId) {
    const rows = this._data[`${surahId}:${ayahId}`];
    if (!rows) return [];
    return rows.map(([surah, ayah, phrase, verified, labels]) => ({
      surah,
      ayah,
      phrase: phrase ?? "",
      verified: verified === 1,
      labels: labels ?? [],
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
