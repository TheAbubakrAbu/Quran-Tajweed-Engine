// @ts-check
/**
 * Quran browsing module: surahs, ayahs, translations, qiraat (riwayat) text, and "About this surah".
 *
 * The engine is data-driven. Pass the parsed JSON from `/data` into `createQuran(...)`.
 * In Node you can use `loadFromDisk()` from `./node.js`.
 */

import { removingArabicDiacriticsAndSigns } from "./text.js";

/** ۩ ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs. */
const SAJDAH_MARK = "۩";

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
  constructor({ surahs, surahInfo, qiraat, qiraatCounts } = /** @type any */ ({})) {
    if (!Array.isArray(surahs)) throw new Error("Quran: `surahs` (data/quran.json) is required");
    /** @type {Surah[]} */
    this.surahs = surahs;
    /** @type {Map<number,Surah>} */
    this._byId = new Map(surahs.map((s) => [s.id, s]));
    /** @type {Map<number,{name:string,contents:string}[]>} */
    this._info = new Map((surahInfo ?? []).map((e) => [e.id, e.sources]));
    /** @type {Record<string, Record<string, {id:number,text:string}[]>>} */
    this._qiraat = qiraat ?? {};
    /** @type {Record<string, Record<string, number>>} riwayah -> surahId(str) -> ayah count (data/qiraat-counts.json) */
    this._qiraatCounts = qiraatCounts ?? {};

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
   * Resolve a surah counted from the END of the mushaf: 1 → An-Nās (114), 2 → Al-Falaq … 114 →
   * Al-Fātiḥah. Mirrors the search-bar `-N` shorthand (companion to JuzPage.juzFromEnd). Returns
   * undefined for n outside 1..114.
   * @param {number} n
   */
  surahFromEnd(n) {
    if (!Number.isInteger(n) || n < 1 || n > this.surahs.length) return undefined;
    return this.surah(this.surahs.length + 1 - n);
  }

  /** Whether an ayah is a sajdah (prostration) ayah — carries the ۩ mark (U+06E9). */
  isSajdahAyah(surahId, ayahId) {
    return (this.ayah(surahId, ayahId)?.textArabic ?? "").includes(SAJDAH_MARK);
  }

  /** Whether a mushaf page boundary falls inside this surah. Mirrors Surah.pageChangesWithinSurah. */
  pageChangesWithinSurah(surahId) {
    const s = this.surah(surahId);
    if (!s) return false;
    if ((s.numberOfPages ?? 1) > 1) return true;
    return new Set(s.ayahs.map((a) => a.page).filter((p) => p != null)).size > 1;
  }

  /** Whether a juz boundary falls inside this surah. Mirrors Surah.juzChangesWithinSurah. */
  juzChangesWithinSurah(surahId) {
    const s = this.surah(surahId);
    if (!s) return false;
    if ((s.juzs?.length ?? 0) > 1) return true;
    if (s.firstJuz != null && s.lastJuz != null && s.firstJuz !== s.lastJuz) return true;
    return new Set(s.ayahs.map((a) => a.juz).filter((j) => j != null)).size > 1;
  }

  /** Whether a page OR juz boundary falls inside this surah. Mirrors Surah.pageOrJuzChangesWithinSurah. */
  pageOrJuzChangesWithinSurah(surahId) {
    return this.pageChangesWithinSurah(surahId) || this.juzChangesWithinSurah(surahId);
  }

  /**
   * The 15 sajdah (prostration) ayahs, in mushaf order, detected by the ۩ mark in the Arabic text.
   * Mirrors sajdahAyahResults() in QuranData.swift.
   * @returns {Array<{surah:Surah, ayah:Ayah}>}
   */
  sajdahAyahs() {
    const out = [];
    for (const { surah, ayah } of this.eachAyah()) {
      if ((ayah.textArabic ?? "").includes(SAJDAH_MARK)) out.push({ surah, ayah });
    }
    return out;
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

  /**
   * Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs every ayah exists; other
   * riwayat merge/split some ayahs, so a Hafs ayah "exists" iff the riwayah's feed carries an ayah with
   * that id (its feeds are numbered contiguously 1..count, so this is `ayahId <= count`). Mirrors
   * Ayah.existsInQiraah(_:). An unknown/unloaded riwayah falls back to Hafs (exists).
   * @param {number} surahId @param {number} ayahId @param {string} [riwayah]
   */
  existsInQiraah(surahId, ayahId, riwayah) {
    if (this.ayah(surahId, ayahId) == null) return false;
    const r = (riwayah ?? "").toLowerCase();
    if (!r || r === "hafs") return true;
    const count = this._qiraatCounts[r]?.[String(surahId)];
    if (count == null) return true;
    return ayahId <= count;
  }

  /**
   * Ayah count of a surah in the given riwayah — the number of Hafs ayahs that exist there (e.g. Baqarah
   * is 286 in Hafs but 285 in Warsh). Mirrors Surah.numberOfAyahs(for:).
   * @param {number} surahId @param {string} [riwayah]
   */
  numberOfAyahsInQiraah(surahId, riwayah) {
    const s = this.surah(surahId);
    if (!s) return 0;
    const r = (riwayah ?? "").toLowerCase();
    if (!r || r === "hafs") return s.numberOfAyahs;
    const count = this._qiraatCounts[r]?.[String(surahId)];
    if (count == null) return s.numberOfAyahs;
    return Math.min(s.numberOfAyahs, count);
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
