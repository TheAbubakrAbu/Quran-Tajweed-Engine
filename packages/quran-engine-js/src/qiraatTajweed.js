// @ts-check
/**
 * Riwayah tajweed: where a reading differs from Hafs, and why.
 *
 * This is a different layer from `tajweed.js`. That one detects the universal recitation rules
 * (madd, ghunnah, qalqalah...) from the text itself, for any riwayah. This one carries what is
 * SPECIFIC to a transmission: the letters Warsh reads with taqlil, the words al-Bazzi doubles the
 * ta of, the places Hafs and Qalun part company. Those cannot be detected from the text, because
 * they ARE the text's difference; they come from each printed mushaf's own colored marks and its
 * own legend box, extracted once at build time.
 *
 * Two consequences worth knowing:
 *
 *  * **The meaning of a colour is per edition.** Each mushaf prints its own legend, so the same
 *    colour letter is a different rule in a different riwayah. Always read `legend(riwayah)`;
 *    never assume a fixed palette. The `rule` key IS stable across riwayat, which is why
 *    `describe(rule)` can explain it once for all of them.
 *  * **Extents are letter indices, not character offsets.** A rule colours base letters
 *    (`firstLetter`..`lastLetter`, inclusive, in reading order, diacritics not counted), or the
 *    whole word when `wholeWord` is true. Map them onto your own rendering of the word.
 *
 * Only the seven verified non-Hafs riwayat carry a pack. The twelve whose text is not published
 * have no pack here either: their rules index into that text.
 */

/**
 * @typedef {Object} LegendEntry
 * @property {string} code     the single letter this riwayah's data uses for the rule
 * @property {string} rule     stable rule key, e.g. "idgham" - the same across riwayat
 * @property {string} arabic   the rule's name as this mushaf prints it
 * @property {string} english
 * @property {string} [short]  one-line explanation, from the shared catalogue
 * @property {string} [long]
 */

/**
 * @typedef {Object} WordRule
 * @property {number} word         1-based word index within the ayah
 * @property {string} rule         stable rule key
 * @property {string} code
 * @property {string} arabic
 * @property {string} english
 * @property {number} firstLetter  inclusive base-letter index, or -1 for the whole word
 * @property {number} lastLetter
 * @property {boolean} wholeWord
 */

export class QiraatTajweed {
  /**
   * @param {Object} [data]
   * @param {Record<string, {short:string, long:string}>} [data.rules] data/tajweed-qiraat/rules.json
   * @param {Record<string, {riwayah:string,version:number,legend:LegendEntry[],rules:Record<string,Record<string,Record<string,[string,number,number][]>>>,khilafMarkers:Record<string,number[]>}>} [data.riwayat]
   *        slug -> data/tajweed-qiraat/<slug>.json
   */
  constructor({ rules = {}, riwayat = {} } = /** @type any */ ({})) {
    this._descriptions = rules;
    this._riwayat = riwayat;
    /** @type {Map<string, Map<string, LegendEntry>>} */
    this._legendByCode = new Map();
  }

  /** The riwayat that have a pack loaded, in slug order. */
  available() {
    return Object.keys(this._riwayat).sort();
  }

  /**
   * This riwayah's printed legend, each entry carrying the shared explanation of its rule.
   * @param {string} riwayah
   * @returns {LegendEntry[]}
   */
  legend(riwayah) {
    const pack = this._riwayat[riwayah];
    if (!pack) return [];
    return pack.legend.map((entry) => ({ ...entry, ...(this._descriptions[entry.rule] ?? {}) }));
  }

  /**
   * What this riwayah colours in one ayah, word by word.
   * @param {number} surahId
   * @param {number} ayahId
   * @param {string} riwayah
   * @returns {WordRule[]}
   */
  wordRules(surahId, ayahId, riwayah) {
    const pack = this._riwayat[riwayah];
    const words = pack?.rules?.[String(surahId)]?.[String(ayahId)];
    if (!words) return [];
    const byCode = this._codes(riwayah);
    /** @type {WordRule[]} */
    const out = [];
    for (const key of Object.keys(words).map(Number).sort((a, b) => a - b)) {
      for (const [code, lo, hi] of words[String(key)]) {
        const entry = byCode.get(code);
        out.push({
          word: key,
          rule: entry?.rule ?? code,
          code,
          arabic: entry?.arabic ?? "",
          english: entry?.english ?? "",
          firstLetter: lo,
          lastLetter: hi,
          wholeWord: lo < 0,
        });
      }
    }
    return out;
  }

  /**
   * The ayahs of a surah this riwayah reads differently from Hafs somewhere - the index behind a
   * "show me where these two readings part" list, without walking every ayah's rules.
   * @param {number} surahId
   * @param {string} riwayah
   */
  khilafAyahs(surahId, riwayah) {
    return this._riwayat[riwayah]?.khilafMarkers?.[String(surahId)] ?? [];
  }

  /** @param {number} surahId @param {number} ayahId @param {string} riwayah */
  hasKhilaf(surahId, ayahId, riwayah) {
    return this.khilafAyahs(surahId, riwayah).includes(ayahId);
  }

  /**
   * What a rule key means, in one line and in a paragraph. Shared across every riwayah that uses
   * the rule, so an app writes the explanation once.
   * @param {string} rule
   */
  describe(rule) {
    return this._descriptions[rule] ?? null;
  }

  /** Every rule key the catalogue explains. */
  ruleKeys() {
    return Object.keys(this._descriptions).sort();
  }

  /** @param {string} riwayah */
  _codes(riwayah) {
    const cached = this._legendByCode.get(riwayah);
    if (cached) return cached;
    const map = new Map(this.legend(riwayah).map((e) => [e.code, e]));
    this._legendByCode.set(riwayah, map);
    return map;
  }
}
