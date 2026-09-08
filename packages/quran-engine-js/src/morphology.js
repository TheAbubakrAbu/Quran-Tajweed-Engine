// @ts-check
/**
 * Root and lemma of every word of the Quran: the Quranic Arabic Corpus morphology (Kais Dukes),
 * as redistributed by the Quranic Universal Library.
 *
 * Two questions this answers that nothing else in the engine can. Given a word, what is its root
 * and its dictionary form, and where else does that root appear. Given a typed root (رحم, or
 * `rHm` in Buckwalter), which ayahs carry it. That second one is why a search box can answer a
 * bare root at all: matching text would find only the surface forms that happen to be spelled
 * that way.
 *
 * **The invariant, the same one `word-by-word.json` keeps**: one id per whitespace token of the
 * ayah's raw Hafs text, in the text's own token order. The alignment against Quran.com's word
 * positions happened at build time, so nothing here matches or normalizes text. Index `n` is the
 * `n`th token; id `0` means the token has neither a root nor a lemma, which is the honest answer
 * for particles and for the sajdah mark. Ids are 1-based into `roots` and `lemmas`.
 *
 * The occurrence indexes are built on first use and then kept: walking 77,629 tokens is fast, but
 * a caller asking for every occurrence of ten different roots should not pay for it ten times.
 */

import { cleanSearch, removingArabicDiacriticsAndSigns } from "./text.js";

/**
 * @typedef {Object} Root
 * @property {string} letters      the letters spaced the way a lexicon prints them, "ر ب ب"
 * @property {string} buckwalter   the same letters in Buckwalter transliteration, "rbb"
 * @property {string} joined       the letters with the spaces closed up, "ربب"
 */

/**
 * @typedef {Object} Lemma
 * @property {string} text   the dictionary form with its marks, "رَبّ"
 * @property {string} clean  the same form unmarked, "رب"
 */

/**
 * @typedef {Object} WordLocation
 * @property {number} surah
 * @property {number} ayah
 * @property {number} token  0-based index into the ayah's whitespace tokens
 */

/**
 * The fold a typed query and the tables are both compared under: marks and spaces gone.
 *
 * Every space is removed, not merely trimmed, because a root is printed spaced ("ر ب ب") and
 * typed closed up ("ربب"), and the two have to meet. Note that `cleanSearch`'s own `whitespace`
 * option only trims the ends, so the closing-up is done here.
 */
export function foldForMorphology(text) {
  return cleanSearch(removingArabicDiacriticsAndSigns(text ?? ""), { whitespace: true })
    .replace(/\s+/g, "");
}

export class Morphology {
  /**
   * @param {Object} [data] data/morphology.json
   * @param {Array<[string, string]>} [data.roots]
   * @param {Array<[string, string]>} [data.lemmas]
   * @param {Record<string, number[][]>} [data.rootIds]
   * @param {Record<string, number[][]>} [data.lemmaIds]
   */
  constructor(data = {}) {
    this._roots = data.roots ?? [];
    this._lemmas = data.lemmas ?? [];
    this._rootIds = data.rootIds ?? {};
    this._lemmaIds = data.lemmaIds ?? {};
    /** @type {Map<number, WordLocation[]>|null} */
    this._byRoot = null;
    /** @type {Map<number, WordLocation[]>|null} */
    this._byLemma = null;
  }

  /** Whether a corpus was supplied at all. */
  get isLoaded() {
    return this._roots.length > 0;
  }

  /** @param {number} id @returns {Root|null} */
  root(id) {
    const row = id >= 1 ? this._roots[id - 1] : undefined;
    if (!row) return null;
    return { letters: row[0], buckwalter: row[1], joined: row[0].replace(/ /g, "") };
  }

  /** @param {number} id @returns {Lemma|null} */
  lemma(id) {
    const row = id >= 1 ? this._lemmas[id - 1] : undefined;
    return row ? { text: row[0], clean: row[1] } : null;
  }

  /**
   * The root and lemma id of every token of the ayah, or null when the ayah is not covered.
   * @param {number} surahId @param {number} ayahId
   * @returns {{roots: number[], lemmas: number[]}|null}
   */
  ids(surahId, ayahId) {
    const roots = this._rootIds[String(surahId)];
    const lemmas = this._lemmaIds[String(surahId)];
    if (!roots || !lemmas || ayahId < 1 || ayahId > roots.length || ayahId > lemmas.length) return null;
    return { roots: roots[ayahId - 1], lemmas: lemmas[ayahId - 1] };
  }

  /**
   * The root of one token, or null when the token has none (a particle) or is out of range.
   * @param {number} surahId @param {number} ayahId @param {number} token
   * @returns {{id: number, root: Root}|null}
   */
  rootOf(surahId, ayahId, token) {
    const ids = this.ids(surahId, ayahId);
    if (!ids || token < 0 || token >= ids.roots.length) return null;
    const id = ids.roots[token];
    const root = this.root(id);
    return root ? { id, root } : null;
  }

  /**
   * The dictionary form of one token.
   * @param {number} surahId @param {number} ayahId @param {number} token
   * @returns {{id: number, lemma: Lemma}|null}
   */
  lemmaOf(surahId, ayahId, token) {
    const ids = this.ids(surahId, ayahId);
    if (!ids || token < 0 || token >= ids.lemmas.length) return null;
    const id = ids.lemmas[token];
    const lemma = this.lemma(id);
    return lemma ? { id, lemma } : null;
  }

  /** Every word carrying this root, in mushaf order. @param {number} id @returns {WordLocation[]} */
  occurrencesOfRoot(id) {
    this._index();
    return this._byRoot?.get(id) ?? [];
  }

  /** Every word carrying this lemma, in mushaf order. @param {number} id @returns {WordLocation[]} */
  occurrencesOfLemma(id) {
    this._index();
    return this._byLemma?.get(id) ?? [];
  }

  /**
   * Roots matching a typed query, by prefix of either spelling. Arabic is folded, so a query
   * with or without marks and with or without spaces finds the same root.
   * @param {string} query @param {number} [limit]
   * @returns {Array<{id: number, root: Root}>}
   */
  findRoots(query, limit = 50) {
    return this._find(this._roots, query, limit, (row) => ({
      letters: row[0], buckwalter: row[1], joined: row[0].replace(/ /g, ""),
    }));
  }

  /**
   * Lemmas matching a typed query, by prefix of the marked or unmarked form.
   * @param {string} query @param {number} [limit]
   * @returns {Array<{id: number, lemma: Lemma}>}
   */
  findLemmas(query, limit = 50) {
    const hits = this._find(this._lemmas, query, limit, (row) => ({ text: row[0], clean: row[1] }));
    return hits.map(({ id, root }) => ({ id, lemma: /** @type any */ (root) }));
  }

  /** Corpus size: roots, lemmas, and the tokens they cover. */
  count() {
    let tokens = 0;
    for (const ayahs of Object.values(this._rootIds)) for (const row of ayahs) tokens += row.length;
    return { roots: this._roots.length, lemmas: this._lemmas.length, tokens };
  }

  /** @private */
  _find(table, query, limit, shape) {
    const folded = foldForMorphology(query);
    const latin = (query ?? "").trim().toLowerCase();
    if (!folded && !latin) return [];
    const out = [];
    for (let i = 0; i < table.length && out.length < limit; i++) {
      const row = table[i];
      const arabic = foldForMorphology(row[0]);
      const roman = String(row[1] ?? "").toLowerCase();
      if ((folded && arabic.startsWith(folded)) || (latin && roman.startsWith(latin))) {
        out.push({ id: i + 1, root: shape(row) });
      }
    }
    return out;
  }

  /** @private Build the reverse indexes once, in mushaf order. */
  _index() {
    if (this._byRoot) return;
    /** @type {Map<number, WordLocation[]>} */
    const byRoot = new Map();
    /** @type {Map<number, WordLocation[]>} */
    const byLemma = new Map();
    const surahs = Object.keys(this._rootIds).map(Number).sort((a, b) => a - b);
    for (const surah of surahs) {
      const roots = this._rootIds[String(surah)] ?? [];
      const lemmas = this._lemmaIds[String(surah)] ?? [];
      for (let a = 0; a < roots.length; a++) {
        const rootRow = roots[a];
        const lemmaRow = lemmas[a] ?? [];
        for (let t = 0; t < rootRow.length; t++) {
          const location = { surah, ayah: a + 1, token: t };
          const rootId = rootRow[t];
          if (rootId) {
            const bucket = byRoot.get(rootId);
            if (bucket) bucket.push(location); else byRoot.set(rootId, [location]);
          }
          const lemmaId = lemmaRow[t];
          if (lemmaId) {
            const bucket = byLemma.get(lemmaId);
            if (bucket) bucket.push(location); else byLemma.set(lemmaId, [location]);
          }
        }
      }
    }
    this._byRoot = byRoot;
    this._byLemma = byLemma;
  }
}
