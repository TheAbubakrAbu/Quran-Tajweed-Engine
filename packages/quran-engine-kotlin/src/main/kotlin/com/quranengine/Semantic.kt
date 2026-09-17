package com.quranengine

import kotlin.math.sqrt

/**
 * Meaning-based ("AI") search: find the ayahs about a topic whether or not they use its words.
 *
 * ## Why word vectors and MaxSim, not a sentence embedding
 *
 * Measured, not assumed. Scoring an ayah by the cosine between a SENTENCE embedding of the query and
 * one of the ayah ranks this corpus close to randomly: translated scripture is dense, and one vector
 * for a whole verse washes out the single idea the query is asking about. Scoring word by word fixes
 * it, embed every word, and score a text as the MEAN over the query's words of the BEST matching
 * word in the text. On real verses that separates related (0.42–0.70) from unrelated (0.27–0.41)
 * cleanly, and it degrades gracefully: a query word the model has never seen contributes nothing
 * instead of poisoning the vector.
 *
 * ## The embedder is yours
 *
 * This engine ships no model, word vectors are tens of megabytes and every platform already has one
 * worth using (ML Kit on Android, a GloVe file on the JVM). Hand the constructor a function from a
 * lowercased word to its vector, or null when it has none. Vectors are cached per word, so a
 * repeated word costs one lookup for the whole corpus.
 *
 * See `../../docs/14-ask-ai.md`.
 */
class Semantic(
    private val embed: (String) -> FloatArray?,
    /** Words shorter than this are skipped on both sides. */
    private val minWordLength: Int = 3,
) {
    /** One scored document. */
    data class Hit(val id: String, val score: Float)

    /** One corpus entry to index. */
    data class Document(val id: String, val text: String)

    private val vectors = HashMap<String, FloatArray?>()
    private val documents = mutableListOf<Pair<String, List<FloatArray>>>()

    /** How many documents are indexed. */
    val size: Int get() = documents.size

    /** Build (or rebuild) the index. Call once per corpus. */
    fun index(corpus: Iterable<Document>): Semantic {
        documents.clear()
        for (document in corpus) {
            val vectorized = vectorize(document.text)
            if (vectorized.isNotEmpty()) documents += document.id to vectorized
        }
        return this
    }

    /**
     * The documents closest in meaning to [query], best first. [minScore] is a floor on "actually
     * related": 0.42 is a sensible start on English translations, but calibrate it against YOUR
     * embedder.
     */
    fun search(query: String, limit: Int = 10, minScore: Float = 0f): List<Hit> {
        val queryVectors = vectorize(query)
        if (queryVectors.isEmpty()) return emptyList()

        val hits = mutableListOf<Hit>()
        for ((id, wordVectors) in documents) {
            var total = 0f
            for (q in queryVectors) {
                var best = -1f
                for (w in wordVectors) {
                    val score = cosine(q, w)
                    if (score > best) best = score
                }
                total += best
            }
            val score = total / queryVectors.size
            if (score >= minScore) hits += Hit(id, score)
        }
        return hits.sortedWith(compareByDescending<Hit> { it.score }.thenBy { it.id }).take(limit)
    }

    /** Drop the index and the vector cache. */
    fun clear(): Semantic {
        documents.clear()
        vectors.clear()
        return this
    }

    private fun vectorize(text: String): List<FloatArray> {
        val out = mutableListOf<FloatArray>()
        val seen = HashSet<String>()
        for (raw in text.lowercase().split(WORD)) {
            if (raw.length < minWordLength || !seen.add(raw)) continue
            vector(raw)?.let { out += it }
        }
        return out
    }

    private fun vector(word: String): FloatArray? = vectors.getOrPut(word) {
        // Normalized once here, so scoring is a dot product rather than three passes per pair.
        embed(word)?.takeIf { it.isNotEmpty() }?.let(::normalize)
    }

    companion object {
        private val WORD = Regex("[^\\p{L}\\p{N}]+")

        /** Cosine similarity of two ALREADY NORMALIZED vectors, i.e. their dot product. */
        fun cosine(a: FloatArray, b: FloatArray): Float {
            var sum = 0f
            for (i in 0 until minOf(a.size, b.size)) sum += a[i] * b[i]
            return sum
        }

        private fun normalize(raw: FloatArray): FloatArray {
            var magnitude = 0f
            for (value in raw) magnitude += value * value
            magnitude = sqrt(magnitude)
            if (magnitude == 0f) return FloatArray(raw.size)
            return FloatArray(raw.size) { raw[it] / magnitude }
        }
    }
}
