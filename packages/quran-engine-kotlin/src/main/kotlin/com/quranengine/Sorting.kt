package com.quranengine

/**
 * Surah sorting & filtering. Ported from `packages/quran-engine-js/src/sorting.js`.
 *
 * Every comparator is ascending with `id` as the tiebreaker; descending is the reverse of that array
 * (so ties stay id-ascending within a reversed block). The "surah" natural order bypasses sorting.
 */

/** Sort modes that honour a direction. Others are intrinsically ordered. */
private val DIRECTIONAL = setOf("revelation", "page", "ayahs", "words", "letters")

/**
 * Sort surahs by [mode] in [direction].
 * @param mode      "surah" | "revelation" | "ayahs" | "page" | "words" | "letters"
 * @param direction "surahOrder" | "ascending" | "descending"
 */
fun sortSurahs(
    surahs: List<Surah>,
    mode: String = "surah",
    direction: String = "ascending",
): List<Surah> {
    if (direction == "surahOrder" || mode == "surah") {
        return surahs.sortedBy { it.id }
    }

    fun key(s: Surah): Int = when (mode) {
        "revelation" -> s.revelationOrder ?: Int.MAX_VALUE
        "ayahs" -> s.numberOfAyahs
        "page" -> s.numberOfPages ?: 0
        "words" -> s.wordCount ?: 0
        "letters" -> s.letterCount ?: 0
        else -> s.id
    }

    // Ascending with id as the tiebreaker.
    val asc = surahs.sortedWith(compareBy({ key(it) }, { it.id }))

    return if (direction == "descending" && DIRECTIONAL.contains(mode)) asc.reversed() else asc
}

/** Whether a sort mode honours a direction. */
fun supportsDirection(mode: String): Boolean = DIRECTIONAL.contains(mode)

/** Filter by revelation type ("makkan" | "madinan"). */
fun filterByRevelationType(surahs: List<Surah>, type: String): List<Surah> =
    surahs.filter { it.type == type }

/** A count predicate: `op` in `< <= > >= ==`, compared against `value`. */
data class CountFilter(val op: String, val value: Int)

/** Whether [n] passes the optional count filter [f]. An absent filter passes. */
private fun passesCount(n: Int, f: CountFilter?): Boolean {
    if (f == null) return true
    return when (f.op) {
        "<" -> n < f.value
        "<=" -> n <= f.value
        ">" -> n > f.value
        ">=" -> n >= f.value
        else -> n == f.value // "==" and any unknown op fall back to equality
    }
}

/**
 * Filter surahs by ayah-count and/or page-count predicates. Ported from `filterByCounts` in
 * `sorting.js`. A surah passes when it satisfies BOTH provided filters; an omitted (null) filter is
 * ignored. `value` is compared against the surah's `numberOfAyahs` / `numberOfPages` (0 when absent).
 */
fun filterByCounts(
    surahs: List<Surah>,
    ayahs: CountFilter? = null,
    pages: CountFilter? = null,
): List<Surah> =
    surahs.filter { passesCount(it.numberOfAyahs, ayahs) && passesCount(it.numberOfPages ?: 0, pages) }
