// @ts-check
/**
 * Quran browsing module: surahs, ayahs, translations, qiraat (riwayat) text, and "About this surah".
 *
 * The engine is data-driven. Pass the parsed JSON from `/data` into `createQuran(...)`.
 * In Node you can use `loadFromDisk()` from `./node.js`.
 */

import { removingArabicDiacriticsAndSigns } from "./text.js";

/**
 * @typedef {Object} Ayah
 * @property {number} id
 * @property {string} textArabic           Hafs Uthmani text (full diacritics)
 * @property {string} textTransliteration
 * @property {string} textEnglishSaheeh    Saheeh International translation
 * @property {string} textEnglishMustafa   Mustafa Khattab (The Clear Quran) translation
 * @property {number} [juz]
 * @property {number} [page]
 * @property {number} [wordCount]
 * @property {number} [letterCount]
 */

/**
 * @typedef {Object} Surah
 * @property {number} id
 * @property {string} type                 "makkan" | "madinan"
 * @property {string} nameArabic
 * @property {string} nameTransliteration
 * @property {string} nameEnglish
 * @property {number} numberOfAyahs
 * @property {number} [pageStart]
 * @property {number} [pageEnd]
 * @property {number} [numberOfPages]
 * @property {number} [firstJuz]
 * @property {number} [lastJuz]
 * @property {number[]} [juzs]
 * @property {number} [revelationOrder]
 * @property {string[]} [similarNames]
 * @property {Ayah[]} ayahs
 */

/** A qiraah file maps "<surahId>" -> [{ id, text }]. */

export class Quran {
  /**
   * @param {Object} opts
   * @param {Surah[]} opts.surahs                 parsed data/quran.json
   * @param {Array<{id:number,sources:Array<{name:string,contents:string}>}>} [opts.surahInfo] data/surah-info.json
   * @param {Record<string, Record<string, {id:number,text:string}[]>>} [opts.qiraat]
   *        map of riwayah key -> qiraah JSON (e.g. { warsh: <data/qiraat/qiraah-warsh.json> })
   */
  constructor({ surahs, surahInfo, qiraat } = /** @type any */ ({})) {
    if (!Array.isArray(surahs)) throw new Error("Quran: `surahs` (data/quran.json) is required");
    /** @type {Surah[]} */
    this.surahs = surahs;
    /** @type {Map<number,Surah>} */
    this._byId = new Map(surahs.map((s) => [s.id, s]));
    /** @type {Map<number,{name:string,contents:string}[]>} */
    this._info = new Map((surahInfo ?? []).map((e) => [e.id, e.sources]));
    /** @type {Record<string, Record<string, {id:number,text:string}[]>>} */
    this._qiraat = qiraat ?? {};

    // Cumulative ayah offset per surah id (0-based count of ayahs in all earlier surahs).
    // Used for the global ayah number (1..6236) in audio + indexing.
    /** @type {Map<number,number>} */
    this._cumulativeOffset = new Map();
    let acc = 0;
    for (const s of surahs) {
      this._cumulativeOffset.set(s.id, acc);
      acc += s.numberOfAyahs;
    }
    /** Total ayah count across the mushaf (6236 for the standard Hafs count). */
    this.totalAyahs = acc;
  }

  /** All surahs in mushaf order (1..114). */
  all() {
    return this.surahs;
  }

  /** @param {number} id @returns {Surah|undefined} */
  surah(id) {
    return this._byId.get(id);
  }

  /**
   * @param {number} surahId
   * @param {number} ayahId
   * @returns {Ayah|undefined}
   */
  ayah(surahId, ayahId) {
    return this._byId.get(surahId)?.ayahs.find((a) => a.id === ayahId);
  }

  /**
   * Global ayah number (1-based, 1..6236) used by the ayah-audio CDN and as a stable verse key.
   * @param {number} surahId
   * @param {number} ayahId
   */
  globalAyahNumber(surahId, ayahId) {
    const off = this._cumulativeOffset.get(surahId);
    if (off == null) throw new Error(`Unknown surah ${surahId}`);
    return off + ayahId;
  }

  /** "About this surah" write-ups (Maududi / Ibn Ashur). @param {number} surahId */
  info(surahId) {
    return this._info.get(surahId) ?? [];
  }

  /**
   * Arabic text of an ayah for the requested riwayah. Falls back to the bundled Hafs text
   * (`textArabic`) when no qiraah override exists. Mirrors Ayah.textArabic(for:).
   * @param {number} surahId
   * @param {number} ayahId
   * @param {string} [riwayah]  e.g. "warsh"; omit/"hafs" for the default.
   */
  arabicText(surahId, ayahId, riwayah) {
    const ayah = this.ayah(surahId, ayahId);
    if (!ayah) return undefined;
    if (riwayah && riwayah.toLowerCase() !== "hafs") {
      const set = this._qiraat[riwayah.toLowerCase()];
      const verses = set?.[String(surahId)];
      const match = verses?.find((v) => v.id === ayahId);
      if (match) return match.text;
    }
    return ayah.textArabic;
  }

  /** Arabic text with all diacritics/recitation marks stripped (clean reading + search source). */
  cleanArabicText(surahId, ayahId, riwayah) {
    const raw = this.arabicText(surahId, ayahId, riwayah);
    return raw == null ? undefined : removingArabicDiacriticsAndSigns(raw);
  }

  /** Iterate every ayah with its surah. @returns {Generator<{surah:Surah,ayah:Ayah}>} */
  *eachAyah() {
    for (const surah of this.surahs) {
      for (const ayah of surah.ayahs) yield { surah, ayah };
    }
  }
}

/** Convenience factory. */
export function createQuran(opts) {
  return new Quran(opts);
}
