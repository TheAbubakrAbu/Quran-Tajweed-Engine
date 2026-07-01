// @ts-check
/**
 * Juz (para) and mushaf-page navigation.
 *
 * Juz boundary names + ranges are static (data/juz.json, mirrors QuranData.juzList). The actual
 * ayah->juz and ayah->page membership comes from the per-ayah `juz` / `page` fields in quran.json.
 */

/**
 * @typedef {Object} JuzEntry
 * @property {number} id
 * @property {string} nameArabic
 * @property {string} nameTransliteration
 * @property {number} startSurah
 * @property {number} startAyah
 * @property {number} endSurah
 * @property {number} endAyah
 */

export class JuzPage {
  /**
   * @param {import('./quran.js').Quran} quran
   * @param {JuzEntry[]} juzList  parsed data/juz.json
   */
  constructor(quran, juzList) {
    this.quran = quran;
    /** @type {JuzEntry[]} */
    this.juzList = [...juzList].sort((a, b) => a.id - b.id);
  }

  /** All 30 juz boundary entries. */
  juzes() {
    return this.juzList;
  }

  /** @param {number} id @returns {JuzEntry|undefined} */
  juz(id) {
    return this.juzList.find((j) => j.id === id);
  }

  /** Every ayah in a juz, in mushaf order. @param {number} juz */
  ayahsInJuz(juz) {
    /** @type {Array<{surah:import('./quran.js').Surah, ayah:import('./quran.js').Ayah}>} */
    const out = [];
    for (const { surah, ayah } of this.quran.eachAyah()) if (ayah.juz === juz) out.push({ surah, ayah });
    return out;
  }

  /** Every ayah on a mushaf page, in mushaf order. @param {number} page */
  ayahsOnPage(page) {
    const out = [];
    for (const { surah, ayah } of this.quran.eachAyah()) if (ayah.page === page) out.push({ surah, ayah });
    return out;
  }

  /** First ayah of a juz (for "jump to juz"). @param {number} juz */
  firstAyahOfJuz(juz) {
    for (const { surah, ayah } of this.quran.eachAyah()) if (ayah.juz === juz) return { surah, ayah };
    return undefined;
  }

  /** First ayah of a mushaf page. @param {number} page */
  firstAyahOfPage(page) {
    for (const { surah, ayah } of this.quran.eachAyah()) if (ayah.page === page) return { surah, ayah };
    return undefined;
  }

  /** The juz number an ayah belongs to. */
  juzForAyah(surahId, ayahId) {
    return this.quran.ayah(surahId, ayahId)?.juz;
  }

  /** The mushaf page an ayah is on. */
  pageForAyah(surahId, ayahId) {
    return this.quran.ayah(surahId, ayahId)?.page;
  }

  /** Total page count of the bundled mushaf (max page seen). */
  totalPages() {
    let max = 0;
    for (const { ayah } of this.quran.eachAyah()) if ((ayah.page ?? 0) > max) max = ayah.page ?? 0;
    return max;
  }

  /** Surah ids contained in a juz (by boundary range). @param {number} juz */
  surahsInJuz(juz) {
    const j = this.juz(juz);
    if (!j) return [];
    return this.quran.all().filter((s) => s.id >= j.startSurah && s.id <= j.endSurah).map((s) => s.id);
  }

  /**
   * Resolve a juz counted from the end of the Quran: 1 → juz 30, 2 → juz 29 … 30 → juz 1.
   * Mirrors the search-bar `-N` shorthand in QuranView.swift. Returns undefined for n outside 1..30.
   * @param {number} n @returns {JuzEntry|undefined}
   */
  juzFromEnd(n) {
    if (!Number.isInteger(n) || n < 1 || n > 30) return undefined;
    return this.juz(31 - n);
  }

  /**
   * Aggregate counts for a single juz, computed from the ayahs actually assigned to it
   * (`ayah.juz === juz`) so surahs that straddle a juz boundary are split correctly.
   * Mirrors QuranData.juzStats(for:). Returns undefined for an unknown juz id.
   * @param {number} juz
   * @returns {{surahCount:number, ayahCount:number, wordCount:number, letterCount:number, pageCount:number}|undefined}
   */
  juzStats(juz) {
    if (!this.juz(juz)) return undefined;
    const surahIds = new Set();
    const pages = new Set();
    let ayahCount = 0, wordCount = 0, letterCount = 0;
    for (const { surah, ayah } of this.quran.eachAyah()) {
      if (ayah.juz !== juz) continue;
      surahIds.add(surah.id);
      ayahCount += 1;
      wordCount += ayah.wordCount ?? 0;
      letterCount += ayah.letterCount ?? 0;
      if (ayah.page != null) pages.add(ayah.page);
    }
    return { surahCount: surahIds.size, ayahCount, wordCount, letterCount, pageCount: pages.size };
  }
}
