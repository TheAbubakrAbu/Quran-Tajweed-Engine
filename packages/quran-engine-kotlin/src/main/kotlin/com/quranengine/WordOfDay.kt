package com.quranengine

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant

/**
 * A curated word of Quranic vocabulary, with every ayah the same written form appears in.
 *
 * 149 words, ordered so that consecutive days feel varied (the themes are interleaved in the corpus
 * itself), which is why the day mapping below is a walk and not a hash: hashing would scatter the
 * curation's own ordering, and the ordering is the point.
 *
 * The occurrence list is derived from the Hafs text by matching the form folded, so the count on a
 * card and the list behind it are one derivation and cannot disagree. A form can repeat inside a
 * single ayah, so an occurrence carries token indices, plural.
 *
 * Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission.
 *
 * See `../../docs/22-word-of-day.md`.
 */

/** One ayah carrying a curated form. */
@Serializable
data class WordOfDayOccurrence(
    val surah: Int,
    val ayah: Int,
    /** 0-based whitespace-token indices into the ayah's raw text. */
    val tokens: List<Int> = emptyList(),
)

/** One curated word. */
@Serializable
data class WordOfDayEntry(
    val id: String,
    /** The form as it stands at its first appearance. */
    val arabic: String,
    val transliteration: String = "",
    val meaning: String = "",
    /** The anchor: where the form first appears. */
    val surah: Int,
    val ayah: Int,
    val token: Int,
    /** Hits across the whole Quran. */
    val count: Int,
    /** Every ayah carrying the form, in mushaf order. */
    val occurrences: List<WordOfDayOccurrence> = emptyList(),
)

/** `data/word-of-day.json`. */
@Serializable
data class WordOfDayFile(val words: List<WordOfDayEntry> = emptyList())

class WordOfDay(private val words: List<WordOfDayEntry> = emptyList()) {
    private val byId: Map<String, WordOfDayEntry> = words.associateBy { it.id }

    val isLoaded: Boolean get() = words.isNotEmpty()

    /** The whole corpus, in curation order. */
    fun all(): List<WordOfDayEntry> = words

    fun word(id: String): WordOfDayEntry? = byId[id]

    /**
     * The word for a day number: the corpus walked in order, wrapping.
     *
     * Take this rather than [forDate] if your app has its own idea of when a day turns over (the
     * upstream app rolls at Fajr, not midnight): hand it your own day number and the mapping is
     * identical.
     */
    fun forDayIndex(dayIndex: Long): WordOfDayEntry? {
        if (words.isEmpty()) return null
        val n = words.size
        return words[(((dayIndex % n) + n) % n).toInt()]
    }

    /** Today's word, by the calendar day of the given instant in the given zone. */
    fun forDate(
        instant: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): WordOfDayEntry? = forDayIndex(LocalDate.ofInstant(instant, zone).toEpochDay())

    /** Matches the written form, the transliteration and the gloss. */
    fun search(query: String, limit: Int = 25): List<WordOfDayEntry> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        val lower = q.lowercase()
        return words.filter {
            it.arabic.contains(q) ||
                it.transliteration.lowercase().contains(lower) ||
                it.meaning.lowercase().contains(lower)
        }.take(limit)
    }

    /** Every curated word appearing in an ayah. */
    fun wordsIn(surahId: Int, ayahId: Int): List<WordOfDayEntry> =
        words.filter { entry ->
            entry.occurrences.any { it.surah == surahId && it.ayah == ayahId }
        }

    fun count(): Pair<Int, Int> = words.size to words.sumOf { it.count }
}
