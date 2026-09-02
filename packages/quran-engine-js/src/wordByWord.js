// @ts-check
/**
 * Word by word: what each word of an ayah means, and how it is said.
 *
 * Two layers, aligned to the SAME tokens: the English gloss and a Latin transliteration. Index n
 * is the same word in both, and the tokens are the ayah's own whitespace-separated words in
 * `quran.json` - so a consumer splits the ayah on whitespace and indexes straight in. No matching,
 * no normalizing, no drift. That alignment is done once, at build time, against a corpus that
 * tokenizes ~200 ayahs differently; doing it at render time is the classic silent-wrong-gloss bug.
 *
 * A token with no word of its own - the rub-el-hizb ornament ۞, the tail of a word the corpus
 * writes as two - carries "" in both layers. Show nothing for it rather than a neighbour's meaning.
 */

const WHITESPACE = /\s+/;

/**
 * @typedef {Object} Word
 * @property {number} position         1-based index of the word in the ayah
 * @property {string} arabic           the ayah's own token
 * @property {string} english          the gloss, "" when the token has none
 * @property {string} transliteration
 */

export class WordByWord {
  /**
   * @param {Object} [data]
   * @param {Record<string, string[][]>} [data.english]         data/word-by-word.json .english
   * @param {Record<string, string[][]>} [data.transliteration] data/word-by-word.json .transliteration
   * @param {import('./quran.js').Quran} [quran] used for the Arabic side; optional
   */
  constructor({ english = {}, transliteration = {} } = /** @type any */ ({}), quran) {
    this._english = english;
    this._transliteration = transliteration;
    this._quran = quran ?? null;
  }

  /** Whether a pack is loaded at all - cheap enough to gate UI on. */
  get isLoaded() {
    return Object.keys(this._english).length > 0;
  }

  /**
   * Every word of an ayah, in reading order.
   * @param {number} surahId
   * @param {number} ayahId
   * @returns {Word[]}
   */
  words(surahId, ayahId) {
    const english = this.glosses(surahId, ayahId);
    if (!english) return [];
    const latin = this.transliterations(surahId, ayahId) ?? [];
    const tokens = this._tokens(surahId, ayahId);
    return english.map((gloss, i) => ({
      position: i + 1,
      arabic: tokens[i] ?? "",
      english: gloss,
      transliteration: latin[i] ?? "",
    }));
  }

  /**
   * One word, by its 1-based position.
   * @param {number} surahId @param {number} ayahId @param {number} position
   */
  word(surahId, ayahId, position) {
    return this.words(surahId, ayahId)[position - 1] ?? null;
  }

  /** @param {number} surahId @param {number} ayahId */
  glosses(surahId, ayahId) {
    return this._row(this._english, surahId, ayahId);
  }

  /** @param {number} surahId @param {number} ayahId */
  transliterations(surahId, ayahId) {
    return this._row(this._transliteration, surahId, ayahId);
  }

  /**
   * Ayahs containing a word whose gloss carries `term` - a word-level English search, which finds
   * ayahs a translation search misses because no translator used that phrasing.
   * @param {string} term
   * @param {Object} [opts]
   * @param {number} [opts.limit=50]
   * @returns {{surah:number, ayah:number, position:number, english:string, transliteration:string}[]}
   */
  find(term, { limit = 50 } = {}) {
    const needle = term.trim().toLowerCase();
    if (!needle) return [];
    /** @type {{surah:number, ayah:number, position:number, english:string, transliteration:string}[]} */
    const out = [];
    for (const surahKey of Object.keys(this._english).map(Number).sort((a, b) => a - b)) {
      const rows = this._english[String(surahKey)];
      for (let ayahIndex = 0; ayahIndex < rows.length; ayahIndex++) {
        const glosses = rows[ayahIndex];
        for (let i = 0; i < glosses.length; i++) {
          if (!glosses[i].toLowerCase().includes(needle)) continue;
          const latin = this._transliteration[String(surahKey)]?.[ayahIndex]?.[i] ?? "";
          out.push({
            surah: surahKey,
            ayah: ayahIndex + 1,
            position: i + 1,
            english: glosses[i],
            transliteration: latin,
          });
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  /**
   * @param {Record<string, string[][]>} layer
   * @param {number} surahId @param {number} ayahId
   */
  _row(layer, surahId, ayahId) {
    const rows = layer[String(surahId)];
    if (!rows || ayahId < 1 || ayahId > rows.length) return null;
    return rows[ayahId - 1];
  }

  /** @param {number} surahId @param {number} ayahId */
  _tokens(surahId, ayahId) {
    const text = this._quran?.ayah(surahId, ayahId)?.textArabic;
    return text ? text.trim().split(WHITESPACE) : [];
  }
}
