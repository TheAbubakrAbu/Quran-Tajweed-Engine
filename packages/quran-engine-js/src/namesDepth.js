// @ts-check
/**
 * The 99 Names of Allah in depth: the layer under `namesOfAllah`.
 *
 * `names-of-allah.json` carries each name, its meaning and a one-line description. This carries
 * what sits beneath that: the triliteral root the name is built on, one of nine themes, a
 * paragraph on what the name means, one line on living by it, and the ayahs where the name
 * itself appears with the token it sits at.
 *
 * Roots print SPACED ("ر ح م") the way a grammar book sets them, while `morphology.json` stores
 * them closed up ("رحم"). `rootKey()` closes the spaces, so matching a name to its morphology
 * entries is one call rather than a trap.
 *
 * The written material (roots, themes, explanations, living lines) is Tilawa's, by Jamil
 * Hammoudeh, used with permission. The occurrences point into this engine's own Ḥafṣ text.
 *
 * @typedef {Object} NameTheme
 * @property {string} id
 * @property {string} label
 *
 * @typedef {Object} NameOccurrence
 * @property {number} surah
 * @property {number} ayah
 * @property {number|null} token  0-based whitespace-token index into the ayah's raw text, or
 *   null where the corpus could not place the name in the ayah (ten occurrences across four
 *   names). The ayah is still right: show the verse whole and highlight nothing.
 * @property {number} tokens  how many tokens the name spans (0 for an unplaced occurrence)
 *
 * @typedef {Object} NameDepth
 * @property {number} number       1..99, matching `namesOfAllah.byNumber`
 * @property {string} root         spaced, e.g. "ر ح م"
 * @property {string} theme        a `NameTheme` id
 * @property {string} explanation
 * @property {string} living
 * @property {NameOccurrence[]} occurrences
 */

/** A spaced root as morphology stores it: "ر ح م" -> "رحم". */
export function rootKey(root) {
  return String(root ?? "").replace(/\s+/gu, "");
}

export class NamesDepth {
  /**
   * @param {Object} [data] parsed data/names-depth.json
   * @param {NameTheme[]} [data.themes]
   * @param {NameDepth[]} [data.names]
   */
  constructor(data = {}) {
    /** @type {NameDepth[]} */
    this._names = data.names ?? [];
    /** @type {NameTheme[]} */
    this._themes = data.themes ?? [];
    /** @type {Map<number, NameDepth>} */
    this._byNumber = new Map(this._names.map((n) => [n.number, n]));
  }

  get isLoaded() {
    return this._names.length > 0;
  }

  /** All 99, ordered by number. @returns {NameDepth[]} */
  all() {
    return this._names;
  }

  /** @param {number} number 1..99 @returns {NameDepth|null} */
  byNumber(number) {
    return this._byNumber.get(number) ?? null;
  }

  /** The nine themes, in the corpus's own order. @returns {NameTheme[]} */
  themes() {
    return this._themes;
  }

  /** @param {string} id a theme id @returns {NameTheme|null} */
  theme(id) {
    return this._themes.find((t) => t.id === id) ?? null;
  }

  /** Every name under one theme, by number. @param {string} id @returns {NameDepth[]} */
  byTheme(id) {
    return this._names.filter((n) => n.theme === id);
  }

  /**
   * Every name built on one root. Accepts either spelling, spaced or closed up.
   * @param {string} root @returns {NameDepth[]}
   */
  byRoot(root) {
    const key = rootKey(root);
    if (!key) return [];
    return this._names.filter((n) => rootKey(n.root) === key);
  }

  /**
   * Every name that appears in an ayah, with the occurrence that put it there.
   * @param {number} surahId @param {number} ayahId
   * @returns {{name: NameDepth, occurrence: NameOccurrence}[]}
   */
  inAyah(surahId, ayahId) {
    /** @type {{name: NameDepth, occurrence: NameOccurrence}[]} */
    const hits = [];
    for (const name of this._names) {
      for (const occurrence of name.occurrences) {
        if (occurrence.surah === surahId && occurrence.ayah === ayahId) hits.push({ name, occurrence });
      }
    }
    // Unplaced occurrences (null token) sort last, so a highlighted list stays in reading order.
    const at = (o) => (o.token ?? Number.MAX_SAFE_INTEGER);
    return hits.sort((a, b) => at(a.occurrence) - at(b.occurrence));
  }

  /**
   * Names whose root, explanation or living line matches a query. The Arabic root is compared as
   * written (spaces closed on both sides); the prose case-insensitively.
   * @param {string} query @param {number} [limit] @returns {NameDepth[]}
   */
  search(query, limit = 25) {
    const q = String(query ?? "").trim();
    if (!q) return [];
    const lower = q.toLowerCase();
    const key = rootKey(q);
    return this._names
      .filter((n) => (key && rootKey(n.root).includes(key))
        || n.explanation.toLowerCase().includes(lower)
        || n.living.toLowerCase().includes(lower))
      .slice(0, limit);
  }

  count() {
    return {
      names: this._names.length,
      themes: this._themes.length,
      occurrences: this._names.reduce((n, x) => n + x.occurrences.length, 0),
    };
  }
}
