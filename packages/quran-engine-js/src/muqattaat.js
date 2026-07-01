// @ts-check
/**
 * Muqaṭṭaʿāt — the disconnected opening letters of 29 surahs (e.g. الٓمٓ). The mushaf prints them joined
 * with maddah marks but they are recited letter by letter ("Alif Lām Mīm"), so this exposes, per opening
 * ayah, the individual letters, a transliteration, and the fully-vocalized Arabic spelling (whose long
 * vowels carry the madd-lāzim maddah U+0653, so a tajweed pass colours them like the real ayah).
 *
 * Data: data/muqattaat.json (mirrors Muqattaat.swift). Ash-Shūra (42) is the one surah whose muqattaʿāt
 * span two ayahs (1: Ḥā Mīm, 2: ʿAyn Sīn Qāf).
 *
 * @typedef {Object} MuqattaatPronunciation
 * @property {number} surah
 * @property {number} ayah
 * @property {string[]} letters            bare letters, e.g. ["ا","ل","م"]
 * @property {string} transliteration      "Alif Lām Mīm"
 * @property {string} spelledOutArabic     fully vocalized, e.g. "أَلِفۡ لَآم مِيٓمۡ"
 */

export class Muqattaat {
  /** @param {{letterNames?: Record<string,string>, ayahs?: MuqattaatPronunciation[]}} [data] parsed data/muqattaat.json */
  constructor(data = {}) {
    /** @type {Record<string,string>} */
    this.letterNames = data.letterNames ?? {};
    /** @type {MuqattaatPronunciation[]} */
    this.ayahs = data.ayahs ?? [];
    /** @type {Map<string, MuqattaatPronunciation>} */
    this._byKey = new Map(this.ayahs.map((e) => [`${e.surah}:${e.ayah}`, e]));
  }

  /** Every muqattaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd ayah). */
  all() {
    return this.ayahs;
  }

  /** Pronunciation for a muqattaʿāt ayah, or undefined if that ayah doesn't open with them. */
  pronunciation(surahId, ayahId) {
    return this._byKey.get(`${surahId}:${ayahId}`);
  }

  /** Transliteration of a single muqattaʿāt letter, e.g. "ا" → "Alif". */
  letterName(letter) {
    return this.letterNames[letter];
  }
}
