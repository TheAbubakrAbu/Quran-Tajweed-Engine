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
}
