package com.quranengine

import kotlin.math.ln
import kotlin.math.max

/**
 * Ask AI: the retrieval and the prompt behind "ask a question, get an answer grounded in the text".
 *
 * ## What this is, and what it is not
 *
 * It is NOT a model. It is the two halves of a question-answering feature that a model cannot do for
 * you and that every app otherwise rebuilds badly:
 *
 *  1. **Retrieval** — turn a natural-language question into the handful of passages that actually
 *     bear on it, each with the reference it must be cited by.
 *  2. **The prompt** — the instructions that keep a model from doing the three things that make a
 *     Quran assistant harmful: inventing verse numbers, quoting scripture it has half-remembered,
 *     and issuing rulings.
 *
 * ## Why the lanes are separate, and interleaved
 *
 * The lanes answer different KINDS of question and one would otherwise drown the others: what the
 * question NAMES (marked [Passage.isSubject], so a model given eight loosely-related verses does not
 * explain the wrong one), IDF-weighted keywords, the curated themes, and — only when you pass a
 * [Semantic] index — meaning. They are interleaved round-robin rather than concatenated, so each
 * lane gets a voice inside the passage budget instead of the first lane filling it.
 *
 * See `../../docs/14-ask-ai.md`.
 */
class AskAI(
    private val quran: Quran,
    private val search: Search,
    private val themes: Themes? = null,
    /** An index over the ayah translations; optional, because the other three lanes need no model. */
    var semantic: Semantic? = null,
) {
    /** What a passage is, for a consumer deciding what to link it to. */
    enum class Kind { AYAH, SURAH, TOPIC }

    /** One passage the assistant may draw on for a turn. */
    data class Passage(
        val kind: Kind,
        /** Cite it exactly like this: `"2:255"`, `"Surah Al-Kahf"`. */
        val reference: String,
        val text: String,
        /** How much of [text] to show the model. */
        val maxCharacters: Int = PASSAGE_CHARACTER_LIMIT,
        /** The verse or surah the question itself named. */
        val isSubject: Boolean = false,
        val surah: Int? = null,
        val ayah: Int? = null,
    )

    /** One completed turn of the conversation. */
    data class Turn(val question: String, val answer: String)

    /** Lazily built document frequencies for the IDF weighting. */
    private var documentFrequency: Map<String, Int>? = null
    private var documentCount = 0

    /**
     * Build a semantic index over the ayah translations with your own embedder, and use it as the
     * meaning lane.
     */
    fun buildSemanticIndex(embed: (String) -> FloatArray?): Semantic {
        val documents = quran.all().flatMap { surah ->
            surah.ayahs.map { Semantic.Document("${surah.id}:${it.id}", it.textEnglishSaheeh) }
        }
        return Semantic(embed).index(documents).also { semantic = it }
    }

    /**
     * The passages for a question, best first.
     *
     * [previousQuestion] and [carried] turn a bare follow-up ("why?") into a search over both
     * questions, with the last answer's passages kept in the pool.
     */
    fun retrieve(
        question: String,
        previousQuestion: String? = null,
        carried: List<Passage> = emptyList(),
        limit: Int = PASSAGE_LIMIT,
    ): List<Passage> {
        val trimmed = question.trim()
        if (trimmed.length < 3) return emptyList()

        val seen = HashSet<String>()
        fun claim(passages: List<Passage>) = passages.filter { seen.add(it.reference) }

        // Lane 0: what the question NAMES.
        val named = claim(referencePassages(trimmed)).toMutableList()

        val bare = isBareFollowUp(trimmed)
        val previous = previousQuestion?.trim().orEmpty()
        val searchText = if (bare && previous.isNotEmpty()) "$previous $trimmed" else trimmed
        if (bare) named += claim(carried.take(3))

        val keyword = claim(keywordPassages(searchText))
        val thematic = claim(themePassages(searchText))
        val meaning = claim(semanticPassages(searchText))

        return (named + interleave(listOf(keyword, meaning, thematic))).take(limit)
    }

    // ---- Lane 0: references ---------------------------------------------------------

    /** The verses and surahs the question names, as subject passages. */
    fun referencePassages(question: String): List<Passage> {
        val lowered = question.lowercase()
        val ayahs = mutableListOf<Pair<Int, Int>>()
        val surahs = mutableListOf<Int>()

        for (match in AYAH_REFERENCE.findAll(question)) {
            val surah = match.groupValues[1].toInt()
            val ayah = match.groupValues[2].toInt()
            if (quran.ayah(surah, ayah) != null) ayahs += surah to ayah
        }
        for (named in NAMED_AYAHS) {
            if (named.names.any { lowered.contains(it) }) ayahs += named.surah to named.ayah
        }
        for (match in SURAH_MENTION.findAll(question)) {
            // Two words then one: "surah al kahf" resolves on the pair, "surah yusuf" on the single.
            val first = match.groupValues[1]
            val second = match.groupValues.getOrElse(2) { "" }
            val candidates = listOfNotNull(
                if (first.isNotEmpty() && second.isNotEmpty()) "$first $second" else null,
                first.takeIf { it.isNotEmpty() },
            )
            for (candidate in candidates) {
                val hit = resolveSurah(candidate)
                if (hit != null) { surahs += hit; break }
            }
        }
        // "surah al-kahf verse 10" — an ayah number on its own belongs to the surah just named.
        val loose = AYAH_MENTION.findAll(question).mapNotNull { it.groupValues[1].toIntOrNull() }.toList()
        if (loose.isNotEmpty() && surahs.isNotEmpty() && ayahs.isEmpty()) {
            for (ayah in loose) if (quran.ayah(surahs[0], ayah) != null) ayahs += surahs[0] to ayah
        }

        val out = mutableListOf<Passage>()
        for ((surah, ayah) in ayahs) {
            ayahPassage(surah, ayah, isSubject = true, maxCharacters = SUBJECT_CHARACTER_LIMIT)
                ?.let { out += it }
        }
        // A surah named on its own (with no verse) is answered by its background prose.
        if (ayahs.isEmpty()) for (id in surahs) surahPassage(id)?.let { out += it }
        return out
    }

    /**
     * A surah named in words. [Search.searchSurahs] is a substring match, so "al kahf" also reaches
     * al-Fatihah (whose similar names include "Al..."); an exact name match wins when there is one,
     * which is the difference between answering about the cave and answering about the opening.
     */
    private fun resolveSurah(candidate: String): Int? {
        val hits = search.searchSurahs(candidate)
        if (hits.isEmpty()) return null
        val wanted = fold(candidate)
        hits.firstOrNull { fold(it.nameTransliteration) == wanted || fold(it.nameEnglish) == wanted }
            ?.let { return it.id }
        if (wanted.length >= 3) {
            hits.firstOrNull { fold(it.nameTransliteration).endsWith(wanted) }?.let { return it.id }
        }
        return hits[0].id
    }

    // ---- Lane 1: keywords, IDF-weighted --------------------------------------------

    /**
     * Ayahs whose translation carries the question's content words, ranked by how INFORMATIVE those
     * words are rather than by how often they occur.
     */
    fun keywordPassages(question: String, limit: Int = 4): List<Passage> {
        val terms = contentWords(question)
        if (terms.isEmpty()) return emptyList()
        val weights = termWeights(terms)

        val scores = LinkedHashMap<String, Double>()
        terms.forEachIndexed { index, term ->
            if (weights[index] <= 0) return@forEachIndexed
            for (hit in search.searchVerses(term, limit = 400)) {
                scores[hit.id] = (scores[hit.id] ?: 0.0) + weights[index]
            }
        }
        // A verse matching two informative words beats one matching a single word twice.
        val ranked = scores.entries.sortedWith(
            compareByDescending<Map.Entry<String, Double>> { it.value }.thenBy { it.key }
        )

        val out = mutableListOf<Passage>()
        for ((id, _) in ranked) {
            val (surah, ayah) = parseReference(id) ?: continue
            ayahPassage(surah, ayah)?.let { out += it }
            if (out.size >= limit) break
        }
        return out
    }

    // ---- Lane 2: themes -------------------------------------------------------------

    /**
     * Ayahs from the curated topic whose name or description the question matches — the lane that
     * reaches verses sharing no wording with the question at all.
     */
    fun themePassages(question: String, limit: Int = 2): List<Passage> {
        val topics = themes?.all() ?: return emptyList()
        val words = contentWords(question)
        if (words.isEmpty()) return emptyList()

        var best: Topic? = null
        var bestScore = 0
        for (topic in topics) {
            val haystack = "${topic.name} ${topic.description} ${topic.category}".lowercase()
            val score = words.sumOf { if (haystack.contains(it.lowercase())) it.length else 0 }
            if (score > bestScore) { bestScore = score; best = topic }
        }
        val topic = best ?: return emptyList()

        val out = mutableListOf<Passage>()
        for (reference in topic.ayahs) {
            val (surah, ayah) = parseReference(reference) ?: continue
            ayahPassage(surah, ayah)?.let { out += it }
            if (out.size >= limit) break
        }
        return out
    }

    // ---- Lane 3: meaning ------------------------------------------------------------

    /**
     * Ayahs closest in MEANING to the question. Empty unless a semantic index was supplied — the
     * other lanes still answer, which is why this one is optional.
     */
    fun semanticPassages(question: String, limit: Int = 3, minScore: Float = 0.42f): List<Passage> {
        val index = semantic ?: return emptyList()
        // The score is a MEAN over query words, so "what does the Quran say about" dilutes the
        // topic: the meaning query is the content words alone.
        val words = contentWords(question)
        val query = if (words.isEmpty()) question else words.joinToString(" ")

        val out = mutableListOf<Passage>()
        for (hit in index.search(query, limit = limit * 2, minScore = minScore)) {
            val (surah, ayah) = parseReference(hit.id) ?: continue
            ayahPassage(surah, ayah)?.let { out += it }
            if (out.size >= limit) break
        }
        return out
    }

    // ---- Passage construction --------------------------------------------------------

    fun ayahPassage(
        surahId: Int,
        ayahId: Int,
        isSubject: Boolean = false,
        maxCharacters: Int = PASSAGE_CHARACTER_LIMIT,
    ): Passage? {
        val ayah = quran.ayah(surahId, ayahId) ?: return null
        val text = ayah.textEnglishSaheeh.ifEmpty { ayah.textEnglishMustafa }
        if (text.isEmpty()) return null
        return Passage(
            kind = Kind.AYAH,
            reference = "$surahId:$ayahId",
            text = text,
            maxCharacters = maxCharacters,
            isSubject = isSubject,
            surah = surahId,
            ayah = ayahId,
        )
    }

    /**
     * A surah's background prose. The bundled notes open with the period of revelation, which
     * answers "what is this surah about" with history — so the theme section, when a source has one,
     * is what the question actually meant.
     */
    fun surahPassage(surahId: Int): Passage? {
        val surah = quran.surah(surahId) ?: return null
        val sources = quran.info(surahId)
        if (sources.isEmpty()) return null

        var text = ""
        for (source in sources) {
            val match = THEME_HEADING.find(source.contents) ?: continue
            val fromTheme = plainProse(source.contents.substring(match.range.first))
            if (fromTheme.length >= 200) { text = fromTheme; break }
        }
        if (text.isEmpty()) text = plainProse(sources[0].contents)
        if (text.isEmpty()) return null

        return Passage(
            kind = Kind.SURAH,
            reference = "Surah ${surah.nameTransliteration}",
            text = text,
            maxCharacters = SUBJECT_CHARACTER_LIMIT,
            isSubject = true,
            surah = surahId,
        )
    }

    // ---- Question analysis -------------------------------------------------------------

    /** The words in a question that actually name its topic. */
    fun contentWords(question: String): List<String> =
        question.split(WORD_SPLIT).filter { it.length >= 3 && it.lowercase() !in QUESTION_WORDS }

    /**
     * A question with fewer than two content words ("why?", "and zakat?") only makes sense with the
     * previous question beside it.
     */
    fun isBareFollowUp(question: String): Boolean =
        question.split(WORD_SPLIT).count { it.length >= 4 && it.lowercase() !in QUESTION_WORDS } < 2

    /**
     * Inverse document frequency per term: `log(N / (1 + df))`, floored at 0. A word in half the
     * Quran weighs almost nothing; a word in ten ayahs weighs a lot. Built once, over the
     * translations.
     */
    fun termWeights(terms: List<String>): List<Double> {
        val frequency = documentFrequency ?: buildDocumentFrequency()
        return terms.map { term ->
            val df = frequency[term.lowercase()] ?: 0
            max(0.0, ln(documentCount.toDouble() / (1 + df)))
        }
    }

    private fun buildDocumentFrequency(): Map<String, Int> {
        val frequency = HashMap<String, Int>()
        var documents = 0
        for (surah in quran.all()) for (ayah in surah.ayahs) {
            documents++
            for (word in ayah.textEnglishSaheeh.lowercase().split(WORD_SPLIT).filter { it.length >= 3 }.toSet()) {
                frequency[word] = (frequency[word] ?: 0) + 1
            }
        }
        documentFrequency = frequency
        documentCount = documents
        return frequency
    }

    companion object {
        /** Words too common to name a topic on their own; the keyword lane never searches for them alone. */
        val QUESTION_WORDS = setOf(
            "what", "why", "how", "when", "where", "who", "whom", "which", "does", "do", "did",
            "is", "are", "was", "were", "can", "could", "should", "would", "will", "shall", "have",
            "has", "had", "there", "their", "these", "those", "this", "that", "with", "from",
            "about", "into", "tell", "explain", "please", "mean", "means", "meaning", "say", "says",
            "said", "some", "many", "much", "islam", "islamic", "muslim", "muslims", "quran",
            "hadith", "hadiths", "allah", "prophet", "verse", "verses", "surah", "ayah", "ayat",
        )

        /** How many passages a turn carries, and how much of each. See [chatPrompt]. */
        const val PASSAGE_LIMIT = 8
        const val PASSAGE_CHARACTER_LIMIT = 500

        /** A subject passage gets more room: when the question names the verse, this text IS the answer. */
        const val SUBJECT_CHARACTER_LIMIT = 1400

        private val AYAH_REFERENCE = Regex("(?<![\\d:])(\\d{1,3})\\s*:\\s*(\\d{1,3})(?![\\d:])")
        private val SURAH_MENTION = Regex(
            "\\b(?:surah|surat|soorah|sura|chapter)\\s+([\\p{L}'’-]+)(?:\\s+([\\p{L}'’-]+))?",
            RegexOption.IGNORE_CASE,
        )
        private val AYAH_MENTION = Regex("\\b(?:ayah|ayat|aya|verse)\\s+(\\d{1,3})\\b", RegexOption.IGNORE_CASE)
        private val WORD_SPLIT = Regex("[^\\p{L}\\p{N}]+")

        /** The prose in a surah's notes that says what it is ABOUT, rather than when it was revealed. */
        private val THEME_HEADING = Regex(
            "^\\s*#*\\s*(?:theme|subject|subject matter|central theme|summary|contents|topics)\\b[^\\n]*$",
            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE),
        )

        /** Household names for specific verses that no pattern catches. */
        private val NAMED_AYAHS = listOf(
            NamedAyah(
                listOf(
                    "ayat al-kursi", "ayatul kursi", "ayat ul kursi", "ayat al kursi",
                    "ayatul-kursi", "throne verse", "verse of the throne",
                ),
                2, 255,
            )
        )

        /**
         * The system instructions. Rules 2, 3 and 5 are the ones that matter: a model left to itself
         * will cite verse numbers it half-remembers, "quote" scripture it has paraphrased, and answer
         * "is X halal" with a verdict. Everything else is tone.
         */
        const val CHAT_INSTRUCTIONS = """You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end."""

        /**
         * The instructions and the user-side prompt for one turn: the passages, the recent
         * conversation, the question.
         *
         * Eight passages of 500 characters is roughly a thousand tokens — sized for a ~4k on-device
         * window with room for the instructions, the conversation, and a full answer. Raise both for
         * a larger model; the shape does not change.
         */
        fun chatPrompt(
            question: String,
            passages: List<Passage>,
            transcript: List<Turn> = emptyList(),
            passageLimit: Int = PASSAGE_LIMIT,
        ): Pair<String, String> {
            val rendered = passages.take(passageLimit).joinToString("\n") { passage ->
                val marker = if (passage.isSubject) "SUBJECT OF THE QUESTION " else ""
                "$marker[${passage.reference}] ${passage.text.take(passage.maxCharacters)}"
            }
            val recent = transcript.takeLast(3).joinToString("\n") { turn ->
                "Earlier question: ${turn.question.take(300)}\nEarlier answer: ${turn.answer.take(500)}"
            }

            val prompt = buildString {
                if (rendered.isNotEmpty()) {
                    append("PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n")
                    append(rendered)
                    append("\n\n")
                }
                if (recent.isNotEmpty()) append("CONVERSATION SO FAR:\n").append(recent).append("\n\n")
                append("QUESTION: ").append(question)
            }
            return CHAT_INSTRUCTIONS to prompt
        }

        private data class NamedAyah(val names: List<String>, val surah: Int, val ayah: Int)

        /** Round-robin the lanes so each gets a voice inside the budget. */
        private fun interleave(lanes: List<List<Passage>>): List<Passage> {
            val depth = lanes.maxOfOrNull { it.size } ?: 0
            val out = mutableListOf<Passage>()
            for (i in 0 until depth) for (lane in lanes) lane.getOrNull(i)?.let { out += it }
            return out
        }

        /** Strip the light markdown the surah notes carry, so a passage reads as prose. */
        private fun plainProse(text: String): String = text
            .replace(Regex("^\\s*#+\\s*", RegexOption.MULTILINE), "")
            .replace(Regex("[*_`]+"), "")
            .replace("\r", "")
            .replace(Regex("\n{2,}"), "\n")
            .trim()

        private fun fold(text: String): String = text.lowercase().filter { it in 'a'..'z' }

        private fun parseReference(text: String): Pair<Int, Int>? {
            val parts = text.split(":", limit = 2)
            if (parts.size != 2) return null
            val surah = parts[0].toIntOrNull() ?: return null
            val ayah = parts[1].toIntOrNull() ?: return null
            return surah to ayah
        }
    }
}
