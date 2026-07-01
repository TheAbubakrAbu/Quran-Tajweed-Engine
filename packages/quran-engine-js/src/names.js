// @ts-check
/**
 * The 99 Names of Allah (Asmā’ ul-Ḥusnā). Thin accessor over data/names-of-allah.json.
 *
 * @typedef {Object} NameOfAllah
 * @property {string} name             Arabic
 * @property {string} transliteration
 * @property {number} number           1..99
 * @property {string} found            ayah references where it appears (e.g. "(1:3) (17:110)")
 * @property {string} meaning
 * @property {string} desc
 * @property {string[]} otherNames
 */

export class NamesOfAllah {
  /** @param {NameOfAllah[]} [list] parsed data/names-of-allah.json */
  constructor(list = []) {
    /** @type {NameOfAllah[]} */
    this.list = [...list].sort((a, b) => a.number - b.number);
    /** @type {Map<number, NameOfAllah>} */
    this._byNumber = new Map(this.list.map((n) => [n.number, n]));
  }

  /** All 99 names, ordered by number. */
  all() {
    return this.list;
  }

  /** @param {number} number 1..99 @returns {NameOfAllah|undefined} */
  byNumber(number) {
    return this._byNumber.get(number);
  }
}
