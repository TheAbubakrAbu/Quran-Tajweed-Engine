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

    /**
     * Resolve a juz counted from the end of the Quran: 1 -> juz 30, 2 -> juz 29 ... 30 -> juz 1.
     * Mirrors the search-bar `-N` shorthand in QuranView.swift. Returns null for n outside 1..30.
     */
    fun juzFromEnd(n: Int): JuzEntry? {
        if (n < 1 || n > 30) return null
        return juz(31 - n)
    }

    /**
     * Aggregate counts for a single juz, computed from the ayahs actually assigned to it
     * (`ayah.juz == juz`) so surahs that straddle a juz boundary are split correctly.
     * Mirrors `QuranData.juzStats(for:)`. Returns null for an unknown juz id.
     */
    fun juzStats(juz: Int): JuzStats? {
        if (juz(juz) == null) return null
        val surahIds = HashSet<Int>()
        val pages = HashSet<Int>()
        var ayahCount = 0
        var wordCount = 0
        var letterCount = 0
        for (r in quran.eachAyah()) {
            if (r.ayah.juz != juz) continue
            surahIds.add(r.surah.id)
            ayahCount += 1
            wordCount += r.ayah.wordCount ?: 0
            letterCount += r.ayah.letterCount ?: 0
            r.ayah.page?.let { pages.add(it) }
        }
        return JuzStats(
            surahCount = surahIds.size,
            ayahCount = ayahCount,
            wordCount = wordCount,
            letterCount = letterCount,
            pageCount = pages.size,
        )
    }
}

/** Aggregate counts for a single juz. Mirrors `QuranData.JuzStats`. */
data class JuzStats(
    val surahCount: Int,
    val ayahCount: Int,
    val wordCount: Int,
    val letterCount: Int,
    val pageCount: Int,
)
