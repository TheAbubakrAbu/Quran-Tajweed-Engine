package com.quranengine

/**
 * How far apart two readings actually are, measured word by word.
 *
 * The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which
 * says what differs but never how much. This measures it: align the two readings' words and sort
 * every pair into one of three buckets.
 *
 *  * **identical** - the same word, written the same way, marks and all.
 *  * **sameSkeleton** - the same consonantal skeleton (rasm), different vowels or spelling. This is
 *    the overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm
 *    was designed to allow: one written form, several sound readings.
 *  * **different** - a different skeleton, i.e. a genuinely different word form.
 *
 * **Why alignment is not indexing.** Readings merge and split ayahs (Warsh's al-Baqarah has 285
 * ayahs to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n
 * of the other. The comparison walks the whole SURAH's word stream on both sides with a two-pointer
 * alignment and bounded lookahead rather than pairing by index.
 *
 * **What it cannot tell you.** This measures the two printed TEXTS, not the two recitations: a
 * difference that lives only in how a letter is sounded (imalah, taqlil, ishmam) shows up only where
 * the print marks it.
 *
 * Needs `Engine.load(loadQiraat = true)`. See `../../docs/17-qiraat-comparison.md`.
 */
class QiraatComparison(private val quran: Quran) {

    /** What happened to one word. */
    enum class Kind { IDENTICAL, SAME_SKELETON, DIFFERENT, ADDED, DROPPED }

    /** One word pair. */
    data class WordDifference(
        /** 1-based word position in the BASE reading's surah. */
        val position: Int,
        /** The base reading's word ("" when the other reading adds one). */
        val base: String,
        /** The compared reading's word ("" when it drops one). */
        val other: String,
        val kind: Kind,
    )

    /** The counts for a surah or for the whole Quran. */
    data class Totals(
        /** Words compared, in the base reading. */
        var words: Int = 0,
        var identical: Int = 0,
        var sameSkeleton: Int = 0,
        var different: Int = 0,
        /** Words the compared reading has and the base does not. */
        var added: Int = 0,
        /** Words the base has and the compared reading does not. */
        var dropped: Int = 0,
    ) {
        val identicalPercent: Double get() = if (words == 0) 0.0 else 100.0 * identical / words
    }

    /**
     * The riwayat whose text is loaded and so can be compared, in slug order. "hafs" is always one
     * of them: it is `quran.json` itself.
     */
    fun available(): List<String> = (listOf("hafs") + quran.loadedRiwayat()).distinct().sorted()

    /** Every word of a surah in one reading, in order. */
    fun words(surahId: Int, riwayah: String): List<String> {
        val surah = quran.surah(surahId) ?: return emptyList()
        // The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking
        // Hafs' ayah ids and asking for each would compare different verses.
        val verses = if (riwayah.lowercase() == "hafs") {
            surah.ayahs.map { it.textArabic }
        } else {
            quran.qiraahVerses(surahId, riwayah).map { it.text }
        }
        return verses.flatMap { it.split(WHITESPACE) }.filter { it.isNotEmpty() }
    }

    /** Compare one surah, word by word. */
    fun compareSurah(surahId: Int, riwayah: String, against: String = "hafs"): Totals =
        totals(align(surahId, against, riwayah))

    /**
     * Compare the whole Quran. This walks every word of both readings - about 155,000 comparisons -
     * so cache the result rather than calling it per render.
     */
    fun compare(riwayah: String, against: String = "hafs"): Totals {
        val sum = Totals()
        for (surah in quran.all()) {
            val part = compareSurah(surah.id, riwayah, against)
            sum.words += part.words
            sum.identical += part.identical
            sum.sameSkeleton += part.sameSkeleton
            sum.different += part.different
            sum.added += part.added
            sum.dropped += part.dropped
        }
        return sum
    }

    /**
     * The words that are not identical, in reading order - the rows behind a comparison view.
     * A [limit] of 0 returns them all.
     */
    fun differences(surahId: Int, riwayah: String, against: String = "hafs", limit: Int = 0):
        List<WordDifference> {
        val rows = align(surahId, against, riwayah).filter { it.kind != Kind.IDENTICAL }
        return if (limit > 0) rows.take(limit) else rows
    }

    /** Two-pointer alignment with bounded lookahead. */
    private fun align(surahId: Int, base: String, other: String): List<WordDifference> {
        val left = words(surahId, base)
        val right = words(surahId, other)
        val leftSkeletons = left.map(::skeleton)
        val rightSkeletons = right.map(::skeleton)
        val rows = mutableListOf<WordDifference>()

        var i = 0
        var j = 0
        while (i < left.size && j < right.size) {
            if (left[i] == right[j]) {
                rows += WordDifference(i + 1, left[i], right[j], Kind.IDENTICAL)
                i++; j++
                continue
            }
            if (leftSkeletons[i] == rightSkeletons[j]) {
                rows += WordDifference(i + 1, left[i], right[j], Kind.SAME_SKELETON)
                i++; j++
                continue
            }
            // Not a match. Before calling it a different word, see whether one side simply has an
            // extra word here - a merge or a split - by looking for the next place they agree.
            val resync = findResync(leftSkeletons, rightSkeletons, i, j)
            if (resync != null) {
                for (k in i until resync.first) rows += WordDifference(k + 1, left[k], "", Kind.DROPPED)
                for (k in j until resync.second) rows += WordDifference(i + 1, "", right[k], Kind.ADDED)
                i = resync.first
                j = resync.second
                continue
            }
            rows += WordDifference(i + 1, left[i], right[j], Kind.DIFFERENT)
            i++; j++
        }
        while (i < left.size) { rows += WordDifference(i + 1, left[i], "", Kind.DROPPED); i++ }
        while (j < right.size) { rows += WordDifference(left.size, "", right[j], Kind.ADDED); j++ }
        return rows
    }

    private fun totals(rows: List<WordDifference>): Totals {
        val out = Totals()
        for (row in rows) {
            if (row.kind == Kind.ADDED) { out.added++; continue }
            out.words++
            when (row.kind) {
                Kind.IDENTICAL -> out.identical++
                Kind.SAME_SKELETON -> out.sameSkeleton++
                Kind.DROPPED -> out.dropped++
                else -> out.different++
            }
        }
        return out
    }

    companion object {
        /** How far ahead to look for a resync before declaring a word added or dropped. */
        private const val LOOKAHEAD = 3

        // (?U) for the same reason WordByWord needs it: Java's \s is ASCII-only, and the Quran text
        // separates some words with U+00A0.
        private val WHITESPACE = Regex("(?U)\\s+")

        /**
         * The consonantal skeleton of a word: diacritics and recitation signs gone, the letters that
         * are written differently for the same consonant folded together.
         */
        fun skeleton(word: String): String = buildString {
            for (ch in Text.removingArabicDiacriticsAndSigns(word)) {
                when (ch) {
                    'ٱ', 'أ', 'إ', 'آ', 'ى', 'ٰ' -> append('ا')
                    'ؤ' -> append('و')
                    'ئ' -> append('ي')
                    'ة' -> append('ه')
                    'ء', 'ـ' -> {}
                    else -> append(ch)
                }
            }
        }

        /**
         * The nearest offset within the lookahead window at which the two streams agree again by
         * skipping words on ONE side only - an insertion or a deletion.
         *
         * Skipping on both sides at once is deliberately not a resync: that is a substitution, one
         * word standing where another does, which is the DIFFERENT bucket. Allowing it here
         * collapsed every genuine word difference into a dropped+added pair.
         */
        private fun findResync(left: List<String>, right: List<String>, i: Int, j: Int): Pair<Int, Int>? {
            for (skip in 1..LOOKAHEAD) {
                if (i + skip < left.size && left[i + skip] == right[j]) return (i + skip) to j
                if (j + skip < right.size && left[i] == right[j + skip]) return i to (j + skip)
            }
            return null
        }
    }
}
