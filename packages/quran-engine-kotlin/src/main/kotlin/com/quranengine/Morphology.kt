package com.quranengine

import kotlinx.serialization.Serializable

/**
 * Root and lemma of every word of the Quran: the Quranic Arabic Corpus morphology (Kais Dukes), as
 * redistributed by the Quranic Universal Library.
 *
 * The invariant, the same one `word-by-word.json` keeps: one id per whitespace token of the ayah's
 * raw Hafs text, in the text's own token order, so nothing here matches or normalizes text. Id `0`
 * means the token has neither a root nor a lemma, which is the honest answer for particles and the
 * sajdah mark. Ids are 1-based into the root and lemma tables.
 *
 * The reverse indexes are built on first use and kept: walking 77,629 tokens is quick, but a caller
 * asking about ten roots should not pay for it ten times.
 *
 * See `../../docs/18-morphology.md`.
 */

/** A triliteral (or quadriliteral) root, in both spellings a reader might use. */
data class MorphologyRoot(
    /** Spaced the way a lexicon prints it: `"ر ب ب"`. */
    val letters: String,
    /** The same letters transliterated: `"rbb"`. */
    val buckwalter: String,
) {
    /** [letters] with the spaces closed up: `"ربب"`. */
    val joined: String get() = letters.replace(" ", "")
}

/** A dictionary form, marked and unmarked. */
data class MorphologyLemma(val text: String, val clean: String)

/** One word of the Quran: the ayah, and the 0-based index of the token inside it. */
data class WordLocation(val surah: Int, val ayah: Int, val token: Int)

/** `data/morphology.json`. */
@Serializable
data class MorphologyFile(
    val roots: List<List<String>> = emptyList(),
    val lemmas: List<List<String>> = emptyList(),
    val rootIds: Map<String, List<List<Int>>> = emptyMap(),
    val lemmaIds: Map<String, List<List<Int>>> = emptyMap(),
)

class Morphology(private val file: MorphologyFile = MorphologyFile()) {

    /** Whether a corpus was supplied at all. */
    val isLoaded: Boolean get() = file.roots.isNotEmpty()

    /** The root with this 1-based id. */
    fun root(id: Int): MorphologyRoot? {
        val row = file.roots.getOrNull(id - 1) ?: return null
        if (row.size < 2) return null
        return MorphologyRoot(row[0], row[1])
    }

    /** The dictionary form with this 1-based id. */
    fun lemma(id: Int): MorphologyLemma? {
        val row = file.lemmas.getOrNull(id - 1) ?: return null
        if (row.size < 2) return null
        return MorphologyLemma(row[0], row[1])
    }

    /** The root and lemma id of every token of the ayah, or null when it is not covered. */
    fun ids(surahId: Int, ayahId: Int): Pair<List<Int>, List<Int>>? {
        val roots = file.rootIds["$surahId"] ?: return null
        val lemmas = file.lemmaIds["$surahId"] ?: return null
        val index = ayahId - 1
        val rootRow = roots.getOrNull(index) ?: return null
        val lemmaRow = lemmas.getOrNull(index) ?: return null
        return rootRow to lemmaRow
    }

    /** The root of one token; null when it has none (a particle) or the index is out of range. */
    fun rootOf(surahId: Int, ayahId: Int, token: Int): Pair<Int, MorphologyRoot>? {
        val id = ids(surahId, ayahId)?.first?.getOrNull(token) ?: return null
        return root(id)?.let { id to it }
    }

    /** The dictionary form of one token. */
    fun lemmaOf(surahId: Int, ayahId: Int, token: Int): Pair<Int, MorphologyLemma>? {
        val id = ids(surahId, ayahId)?.second?.getOrNull(token) ?: return null
        return lemma(id)?.let { id to it }
    }

    /** Every word carrying this root, in mushaf order. */
    fun occurrencesOfRoot(id: Int): List<WordLocation> = index.first[id] ?: emptyList()

    /** Every word carrying this lemma, in mushaf order. */
    fun occurrencesOfLemma(id: Int): List<WordLocation> = index.second[id] ?: emptyList()

    /** Roots whose Arabic or Buckwalter spelling starts with the query. */
    fun findRoots(query: String, limit: Int = 50): List<Pair<Int, MorphologyRoot>> =
        prefixHits(file.roots, query, limit).mapNotNull { id -> root(id)?.let { id to it } }

    /** Dictionary forms whose marked or unmarked spelling starts with the query. */
    fun findLemmas(query: String, limit: Int = 50): List<Pair<Int, MorphologyLemma>> =
        prefixHits(file.lemmas, query, limit).mapNotNull { id -> lemma(id)?.let { id to it } }

    /** Corpus size: roots, lemmas, and the tokens they cover. */
    fun count(): Triple<Int, Int, Int> {
        val tokens = file.rootIds.values.sumOf { ayahs -> ayahs.sumOf { it.size } }
        return Triple(file.roots.size, file.lemmas.size, tokens)
    }

    // -- internals ------------------------------------------------------------------

    private fun prefixHits(table: List<List<String>>, query: String, limit: Int): List<Int> {
        val folded = fold(query)
        val latin = query.trim().lowercase()
        if (folded.isEmpty() && latin.isEmpty()) return emptyList()
        val out = ArrayList<Int>()
        for ((position, row) in table.withIndex()) {
            if (limit > 0 && out.size >= limit) break
            val first = row.firstOrNull() ?: continue
            val arabic = fold(first)
            val roman = row.getOrNull(1)?.lowercase().orEmpty()
            if ((folded.isNotEmpty() && arabic.startsWith(folded)) ||
                (latin.isNotEmpty() && roman.startsWith(latin))
            ) {
                out.add(position + 1)
            }
        }
        return out
    }

    /** Built once, walking the corpus in mushaf order so the lists come out ordered for free. */
    private val index: Pair<Map<Int, List<WordLocation>>, Map<Int, List<WordLocation>>> by lazy {
        val byRoot = HashMap<Int, MutableList<WordLocation>>()
        val byLemma = HashMap<Int, MutableList<WordLocation>>()
        for (surah in file.rootIds.keys.mapNotNull(String::toIntOrNull).sorted()) {
            val roots = file.rootIds["$surah"] ?: continue
            val lemmas = file.lemmaIds["$surah"] ?: emptyList()
            for ((position, rootRow) in roots.withIndex()) {
                val lemmaRow = lemmas.getOrNull(position) ?: emptyList()
                for ((token, rootId) in rootRow.withIndex()) {
                    val location = WordLocation(surah, position + 1, token)
                    if (rootId != 0) byRoot.getOrPut(rootId) { ArrayList() }.add(location)
                    val lemmaId = lemmaRow.getOrNull(token) ?: 0
                    if (lemmaId != 0) byLemma.getOrPut(lemmaId) { ArrayList() }.add(location)
                }
            }
        }
        @Suppress("UNCHECKED_CAST")
        (byRoot as Map<Int, List<WordLocation>>) to (byLemma as Map<Int, List<WordLocation>>)
    }

    companion object {
        /**
         * The fold a typed query and the tables are both compared under.
         *
         * Every space is removed, not merely trimmed: a root is printed spaced (`"ر ب ب"`) and
         * typed closed up (`"ربب"`), and the two have to meet. Note that Java's `\s` is ASCII-only,
         * so the split is on an explicit Unicode-aware pattern.
         */
        fun fold(text: String): String =
            Text.cleanSearch(Text.removingArabicDiacriticsAndSigns(text)).split(WHITESPACE).joinToString("")

        private val WHITESPACE = Regex("(?U)\\s+")
    }
}
