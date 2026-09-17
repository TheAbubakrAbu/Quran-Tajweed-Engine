package com.quranengine

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * Three curated corpora that answer questions the text alone cannot: where else the Quran says this,
 * what it says about a topic, and how to learn to recite it.
 *
 * See `../../docs/13-similar-and-themes.md`.
 */

/** One similar-ayah match, in display order. */
data class SimilarMatch(
    val surah: Int,
    val ayah: Int,
    /** True for the classical corpus, false for a generated phrase-overlap match. */
    val verified: Boolean,
    /** Why a generated row matched; empty for verified rows. */
    val labels: List<String>,
    /**
     * The shared wording: 0-based inclusive token ranges into the MATCHED ayah's raw text. QUL's
     * own placement where it lists the pair, else the wording the corpus recorded, located in the
     * ayah when the data was built. Empty when no source records shared wording.
     *
     * The data carries no text of its own: cut the words out of `quran.json` by these spans, so
     * what you show is the Quran text you already have and not a second copy of it.
     */
    val spans: List<IntRange> = emptyList(),
    /**
     * QUL's 0-100 similarity, where it listed the pair. Null for rows from the other two sources:
     * they rank, but they do not score.
     */
    val score: Int? = null,
)

/**
 * `data/similar-ayahs.json` as it ships: `{v, ayahs}`, the rows keyed `"surah:ayah"`. A row is
 * `[surah, ayah, verifiedFlag, spans, labels, score]`, which is heterogeneous, so the rows stay as
 * [JsonArray] until [SimilarAyahs.matches] reads them. A version-1 file (rows keyed at the top
 * level) decodes to `v == 0` with no rows, since its keys are unknown here.
 */
@Serializable
data class SimilarAyahsFile(val v: Int = 0, val ayahs: Map<String, List<JsonArray>> = emptyMap())

/**
 * Similar ayahs (mutashabihat): the other places the Quran says something close to this.
 *
 * Three sources, already merged and ranked at build time so nothing here scores or sorts. Verified
 * rows come from the classical corpus and are listed first; generated rows are phrase-overlap
 * matches carrying the labels that explain why they matched. They are a reading aid, not a
 * scholarly claim, so `verified` is the flag to gate on if you show only one kind. The Quranic
 * Universal Library's table is the third source, and it adds `score`, its own 0-100 similarity.
 *
 * The data carries no phrase text (version 2). The shared wording is `spans`, token ranges into
 * the MATCHED ayah's raw text: read the words out of `quran.json` by those spans, so what you show
 * is the Quran text you already have and not a second copy of it.
 */
class SimilarAyahs(private val data: Map<String, List<JsonArray>> = emptyMap()) {
    /**
     * From the file as it ships. Only version 2 is read. A version-1 file (rows keyed at the top
     * level, the phrase as text) would put the shared wording where a span is expected, so it is
     * treated as no data rather than half a one, as the JS port does.
     */
    constructor(file: SimilarAyahsFile) : this(if (file.v == 2) file.ayahs else emptyMap())

    /** Matches for an ayah, in display order. Empty for most short ayahs. */
    fun matches(surahId: Int, ayahId: Int): List<SimilarMatch> {
        val rows = data["$surahId:$ayahId"] ?: return emptyList()
        return rows.mapNotNull { row ->
            // Positions: 0 surah, 1 ayah, 2 verified flag, 3 spans, 4 labels, 5 score (or null).
            val surah = (row.getOrNull(0) as? JsonPrimitive)?.intOrNull ?: return@mapNotNull null
            val ayah = (row.getOrNull(1) as? JsonPrimitive)?.intOrNull ?: return@mapNotNull null
            SimilarMatch(
                surah = surah,
                ayah = ayah,
                verified = (row.getOrNull(2) as? JsonPrimitive)?.intOrNull == 1,
                labels = (row.getOrNull(4) as? JsonArray)
                    ?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
                    ?: emptyList(),
                spans = (row.getOrNull(3) as? JsonArray)
                    ?.mapNotNull { span ->
                        val pair = (span as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.intOrNull }
                        if (pair != null && pair.size == 2 && pair[1] >= pair[0]) pair[0]..pair[1] else null
                    }
                    ?: emptyList(),
                // JsonNull is a JsonPrimitive whose intOrNull is null, so a scoreless row reads as null.
                score = (row.getOrNull(5) as? JsonPrimitive)?.intOrNull,
            )
        }
    }

    /** Whether the ayah has any: a map hit, cheap enough to gate a button on. */
    fun has(surahId: Int, ayahId: Int): Boolean = !data["$surahId:$ayahId"].isNullOrEmpty()

    /** How many ayahs have at least one match. */
    fun count(): Int = data.size
}

/** One curated topic and the ayahs that speak to it. */
@Serializable
data class Topic(
    val id: String,
    val name: String,
    val description: String,
    val category: String,
    val domain: String,
    /** `"2:255"` references, in mushaf order. */
    val ayahs: List<String> = emptyList(),
)

@Serializable
data class ThemesFile(val topics: List<Topic> = emptyList())

/**
 * Browse the Quran by theme: curated topics grouped under a category and a domain, each listing the
 * ayahs that speak to it. The lists are curated, not derived, so a topic is a real reading path
 * rather than a keyword hit list; [topicsFor] inverts them.
 */
class Themes(private val topics: List<Topic> = emptyList()) {
    private val byId: Map<String, Topic> = topics.associateBy { it.id }
    private val byAyah: Map<String, List<Topic>> by lazy {
        val index = LinkedHashMap<String, MutableList<Topic>>()
        for (topic in topics) for (reference in topic.ayahs) {
            index.getOrPut(reference) { mutableListOf() }.add(topic)
        }
        index
    }

    /** Every topic, in the order the corpus lists them. */
    fun all(): List<Topic> = topics

    fun topic(id: String): Topic? = byId[id]

    /** The distinct domains, in first-seen order. */
    fun domains(): List<String> = topics.map { it.domain }.distinct()

    /** The distinct categories, optionally within one domain. */
    fun categories(domain: String? = null): List<String> =
        topics.filter { domain == null || it.domain == domain }.map { it.category }.distinct()

    fun inDomain(domain: String): List<Topic> = topics.filter { it.domain == domain }

    fun inCategory(category: String): List<Topic> = topics.filter { it.category == category }

    /** The topics an ayah appears under. */
    fun topicsFor(surahId: Int, ayahId: Int): List<Topic> = byAyah["$surahId:$ayahId"] ?: emptyList()

    /** Topics whose name, description, category or domain carries [query]. */
    fun search(query: String): List<Topic> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return emptyList()
        return topics.filter { topic ->
            listOf(topic.name, topic.description, topic.category, topic.domain)
                .any { it.lowercase().contains(needle) }
        }
    }
}

/**
 * One practice fragment: a short Arabic snippet with a caption saying what to listen for.
 *
 * The Arabic is in exactly one of two places. Teaching Arabic a tutor wrote (invented drill
 * syllables, single letters, the isti'adhah) is [text]. Arabic that IS Quran is [ayah], a
 * reference into this engine's own text, and then [text] is empty: version 4 stopped copying
 * verses into the lesson pack for the same reason nothing else here copies them.
 */
@Serializable
data class TajweedDrill(
    val caption: String = "",
    /** The fragment as written, or empty when [ayah] locates it instead. */
    val text: String = "",
    /**
     * Where the words are in the Quran when this drill is a real verse. Cut them out of
     * `quran.json` by it; the data carries no copy of them. Null when [text] holds the Arabic.
     */
    val ayah: TajweedAyahWords? = null,
)

/**
 * A run of Quran words a lesson points at: `[surah, ayah, first, last]` in the JSON, with the
 * span 0-based and inclusive over the ayah's whitespace-separated tokens.
 */
@Serializable(with = TajweedAyahWordsSerializer::class)
data class TajweedAyahWords(val surahId: Int, val ayahNumber: Int, val span: IntRange)

internal object TajweedAyahWordsSerializer : KSerializer<TajweedAyahWords> {
    private val delegate = ListSerializer(Int.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun serialize(encoder: Encoder, value: TajweedAyahWords) =
        delegate.serialize(
            encoder,
            listOf(value.surahId, value.ayahNumber, value.span.first, value.span.last),
        )

    override fun deserialize(decoder: Decoder): TajweedAyahWords {
        val row = delegate.deserialize(decoder)
        if (row.size != 4 || row[2] < 0 || row[3] < row[2]) {
            throw SerializationException(
                "A lesson ayah reference is [surah, ayah, first, last] with 0 <= first <= last, got $row",
            )
        }
        return TajweedAyahWords(row[0], row[1], row[2]..row[3])
    }
}

/**
 * A `[start, end]` pair in the JSON, an [IntRange] in Kotlin. Anything else in that place is a
 * corrupt pack and fails the decode, like any other malformed field.
 */
internal object TokenSpanSerializer : KSerializer<IntRange> {
    private val delegate = ListSerializer(Int.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun serialize(encoder: Encoder, value: IntRange) =
        delegate.serialize(encoder, listOf(value.first, value.last))

    override fun deserialize(decoder: Decoder): IntRange {
        val pair = delegate.deserialize(decoder)
        if (pair.size != 2 || pair[1] < pair[0]) {
            throw SerializationException("A token span is [start, end] with end >= start, got $pair")
        }
        return pair[0]..pair[1]
    }
}

/** An ayah to hear the rule in, with the words to focus on. */
@Serializable
data class TajweedExample(
    val surahId: Int = 0,
    val ayahNumber: Int = 0,
    val focus: String = "",
    /**
     * The 0-based inclusive token range of the words to listen at, into the ayah's raw text. Read
     * them out of `quran.json` by this span: the data carries no copy of the words. Null when the
     * lesson names the whole ayah.
     */
    @Serializable(with = TokenSpanSerializer::class)
    val wordSpan: IntRange? = null,
)

/**
 * The memory-hook word a rule card hangs on, with what it means. Teaching Arabic chosen for the
 * rule it demonstrates, so it is written out rather than referenced.
 */
@Serializable
data class TajweedMnemonic(val arabic: String = "", val gloss: String = "")

/**
 * The card that states the rule: when it triggers, what to do, how long to hold it, the mnemonic
 * it hangs on, and fragments to see it in.
 */
@Serializable
data class TajweedRuleCard(
    val fragments: List<TajweedDrill> = emptyList(),
    val trigger: String? = null,
    val action: String? = null,
    val hold: String? = null,
    val mnemonic: TajweedMnemonic? = null,
    val countEn: String? = null,
    val countAr: String? = null,
)

@Serializable
data class TajweedLesson(
    val id: String,
    val titleEn: String = "",
    val titleAr: String = "",
    val summary: String = "",
    val body: List<String> = emptyList(),
    /** Absent on the lessons that teach through examples alone. */
    val drills: List<TajweedDrill> = emptyList(),
    val examples: List<TajweedExample> = emptyList(),
    val ruleCard: TajweedRuleCard? = null,
    /** The tajweed colour this rule is painted in, where it has one. */
    val color: String? = null,
)

@Serializable
data class TajweedChapter(
    val id: String,
    val title: String = "",
    val subtitle: String = "",
    val lessons: List<TajweedLesson> = emptyList(),
)

@Serializable
data class TajweedLessonsFile(val chapters: List<TajweedChapter> = emptyList())

/**
 * The tajweed course: chapters from the Arabic alphabet to the rules of stopping, each lesson
 * carrying its prose, its drills, and Quranic examples to hear the rule in.
 *
 * Content, not algorithm, but it belongs in the engine for the same reason the rule catalogue does:
 * every app that teaches tajweed otherwise rewrites the same curriculum, and a lesson that cites
 * `2:255` should cite the same ayah everywhere.
 */
class TajweedLessons(private val chapters: List<TajweedChapter> = emptyList()) {
    private val byLesson: Map<String, Pair<TajweedChapter, TajweedLesson>> =
        chapters.flatMap { chapter -> chapter.lessons.map { it.id to (chapter to it) } }.toMap()

    /** Every chapter, in course order. */
    fun chapters(): List<TajweedChapter> = chapters

    fun chapter(id: String): TajweedChapter? = chapters.firstOrNull { it.id == id }

    /** Every lesson across every chapter, in course order. */
    fun allLessons(): List<TajweedLesson> = chapters.flatMap { it.lessons }

    fun lesson(id: String): TajweedLesson? = byLesson[id]?.second

    /** Which chapter a lesson belongs to. */
    fun chapterOf(id: String): TajweedChapter? = byLesson[id]?.first

    /** The lesson after this one, walking across chapter boundaries, the "next" button's answer. */
    fun next(id: String): TajweedLesson? {
        val all = allLessons()
        val at = all.indexOfFirst { it.id == id }
        return if (at >= 0) all.getOrNull(at + 1) else null
    }

    fun previous(id: String): TajweedLesson? {
        val all = allLessons()
        val at = all.indexOfFirst { it.id == id }
        return if (at > 0) all[at - 1] else null
    }
}
