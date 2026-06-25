package com.quranengine

/**
 * Juz (para) and mushaf-page navigation. Ported from `packages/quran-engine-js/src/juzPage.js`.
 *
 * Juz boundary names/ranges are static (`data/juz.json`); the actual ayah->juz and ayah->page
 * membership comes from the per-ayah `juz` / `page` fields in `quran.json`.
 */
class JuzPage(
    private val quran: Quran,
    juzList: List<JuzEntry>,
) {
    val juzList: List<JuzEntry> = juzList.sortedBy { it.id }

    /** All 30 juz boundary entries. */
    fun juzes(): List<JuzEntry> = juzList

    fun juz(id: Int): JuzEntry? = juzList.firstOrNull { it.id == id }

    /** Every ayah in a juz, in mushaf order. */
    fun ayahsInJuz(juz: Int): List<SurahAyah> =
        quran.eachAyah().filter { it.ayah.juz == juz }.toList()

    /** Every ayah on a mushaf page, in mushaf order. */
    fun ayahsOnPage(page: Int): List<SurahAyah> =
        quran.eachAyah().filter { it.ayah.page == page }.toList()

    /** First ayah of a juz (for "jump to juz"). */
    fun firstAyahOfJuz(juz: Int): SurahAyah? =
        quran.eachAyah().firstOrNull { it.ayah.juz == juz }

    /** First ayah of a mushaf page. */
    fun firstAyahOfPage(page: Int): SurahAyah? =
        quran.eachAyah().firstOrNull { it.ayah.page == page }

    /** The juz number an ayah belongs to. */
    fun juzForAyah(surahId: Int, ayahId: Int): Int? = quran.ayah(surahId, ayahId)?.juz

    /** The mushaf page an ayah is on. */
    fun pageForAyah(surahId: Int, ayahId: Int): Int? = quran.ayah(surahId, ayahId)?.page

    /** Total page count of the bundled mushaf (max page seen). */
    fun totalPages(): Int =
        quran.eachAyah().maxOfOrNull { it.ayah.page ?: 0 } ?: 0

    /** Surah ids contained in a juz (by boundary range). */
    fun surahsInJuz(juz: Int): List<Int> {
        val j = juz(juz) ?: return emptyList()
        return quran.all().filter { it.id in j.startSurah..j.endSurah }.map { it.id }
    }
}
