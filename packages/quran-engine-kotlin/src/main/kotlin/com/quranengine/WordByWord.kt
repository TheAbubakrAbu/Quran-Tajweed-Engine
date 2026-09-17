package com.quranengine

import kotlinx.serialization.Serializable

/**
 * Word by word: what each word of an ayah means, and how it is said.
 *
 * Two layers over the SAME tokens (the English gloss and a Latin transliteration), where the
 * tokens are the ayah's own whitespace-separated words. Split the ayah and index straight in; the
 * alignment against a corpus that tokenizes ~200 ayahs differently was done once, at build time.
 *
 * A token with no word of its own (the ۞ ornament, the tail of a word the corpus writes as two)
 * carries `""` in both layers, show nothing for it rather than a neighbour's meaning.
 *
 * See `../../docs/12-word-by-word.md`.
 */
@Serializable
data class WordByWordPack(
    /** Surah id -> ayahs in id order -> one entry per token. */
    val english: Map<String, List<List<String>>> = emptyMap(),
    val transliteration: Map<String, List<List<String>>> = emptyMap(),
)

/** One word of an ayah, in reading order. */
data class GlossedWord(
    /** 1-based index of the word in the ayah. */
    val position: Int,
    /** The ayah's own token. */
    val arabic: String,
    /** The gloss, `""` when the token has none. */
    val english: String,
    val transliteration: String,
)

/** A hit from the word-level gloss search. */
data class GlossHit(
    val surah: Int,
    val ayah: Int,
    val position: Int,
    val english: String,
    val transliteration: String,
)

class WordByWord(
    private val pack: WordByWordPack = WordByWordPack(),
    private val quran: Quran? = null,
) {
    /** Whether a pack is loaded at all, cheap enough to gate UI on. */
    val isLoaded: Boolean get() = pack.english.isNotEmpty()

    /** Every word of an ayah, in reading order. */
    fun words(surahId: Int, ayahId: Int): List<GlossedWord> {
        val english = glosses(surahId, ayahId) ?: return emptyList()
        val latin = transliterations(surahId, ayahId) ?: emptyList()
        val tokens = quran?.ayah(surahId, ayahId)?.textArabic?.trim()?.split(WHITESPACE) ?: emptyList()
        return english.mapIndexed { index, gloss ->
            GlossedWord(
                position = index + 1,
                arabic = tokens.getOrElse(index) { "" },
                english = gloss,
                transliteration = latin.getOrElse(index) { "" },
            )
        }
    }

    /** One word, by its 1-based position. */
    fun word(surahId: Int, ayahId: Int, position: Int): GlossedWord? =
        words(surahId, ayahId).getOrNull(position - 1)

    fun glosses(surahId: Int, ayahId: Int): List<String>? = row(pack.english, surahId, ayahId)

    fun transliterations(surahId: Int, ayahId: Int): List<String>? =
        row(pack.transliteration, surahId, ayahId)

    /**
     * Ayahs containing a word whose gloss carries [term], a word-level English search, which finds
     * ayahs a translation search misses because no translator used that phrasing.
     */
    fun find(term: String, limit: Int = 50): List<GlossHit> {
        val needle = term.trim().lowercase()
        if (needle.isEmpty()) return emptyList()
        val out = mutableListOf<GlossHit>()
        // Mushaf order, so the result is stable across runs.
        for (surah in pack.english.keys.mapNotNull(String::toIntOrNull).sorted()) {
            val rows = pack.english[surah.toString()] ?: continue
            rows.forEachIndexed { ayahIndex, glosses ->
                glosses.forEachIndexed { index, gloss ->
                    if (!gloss.lowercase().contains(needle)) return@forEachIndexed
                    if (out.size >= limit) return out
                    out += GlossHit(
                        surah = surah,
                        ayah = ayahIndex + 1,
                        position = index + 1,
                        english = gloss,
                        transliteration = pack.transliteration[surah.toString()]
                            ?.getOrNull(ayahIndex)?.getOrNull(index) ?: "",
                    )
                }
            }
        }
        return out
    }

    private fun row(layer: Map<String, List<List<String>>>, surahId: Int, ayahId: Int): List<String>? {
        val rows = layer[surahId.toString()] ?: return null
        if (ayahId < 1 || ayahId > rows.size) return null
        return rows[ayahId - 1]
    }

    private companion object {
        // (?U) turns on UNICODE_CHARACTER_CLASS. Without it Java's \s is ASCII-only, and 2:26 -
        // which separates two of its words with U+00A0 - would tokenize one word short of the pack,
        // shifting every Arabic token after it by one. Every other port's split is Unicode-aware
        // already (Go's strings.Fields, Rust's split_whitespace, JS and Dart's \s, Python's \s).
        val WHITESPACE = Regex("(?U)\\s+")
    }
}
