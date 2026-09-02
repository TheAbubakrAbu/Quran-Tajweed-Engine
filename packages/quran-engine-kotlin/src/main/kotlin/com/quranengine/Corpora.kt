package com.quranengine

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

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
    /** The shared wording, `""` when none is recorded. */
    val phrase: String,
    /** True for the classical corpus, false for a generated phrase-overlap match. */
    val verified: Boolean,
    /** Why a generated row matched; empty for verified rows. */
    val labels: List<String>,
)

/**
 * Similar ayahs (mutashabihat): the other places the Quran says something close to this.
 *
 * Verified rows come from the classical corpus and are listed first; generated rows are
 * phrase-overlap matches carrying the labels that explain why they matched. They are a reading aid,
 * not a scholarly claim, so `verified` is the flag to gate on if you show only one kind.
 *
 * Rows ship as `[surah, ayah, phrase, verifiedFlag, labels?]`, which is heterogeneous, so they stay
 * as [JsonArray] until [matches] reads them.
 */
class SimilarAyahs(private val data: Map<String, List<JsonArray>> = emptyMap()) {
    /** Matches for an ayah, in display order. Empty for most short ayahs. */
    fun matches(surahId: Int, ayahId: Int): List<SimilarMatch> {
        val rows = data["$surahId:$ayahId"] ?: return emptyList()
        return rows.mapNotNull { row ->
            if (row.size < 4) return@mapNotNull null
            val surah = row[0].jsonPrimitive.intOrNull ?: return@mapNotNull null
            val ayah = row[1].jsonPrimitive.intOrNull ?: return@mapNotNull null
            SimilarMatch(
                surah = surah,
                ayah = ayah,
                phrase = (row[2] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: "",
                verified = row[3].jsonPrimitive.intOrNull == 1,
                labels = (row.getOrNull(4) as? JsonArray)
                    ?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
                    ?: emptyList(),
            )
        }
    }

    /** Whether the ayah has any — a map hit, cheap enough to gate a button on. */
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

/** One practice fragment: a short Arabic snippet with a caption saying what to listen for. */
@Serializable
data class TajweedDrill(val caption: String = "", val text: String = "")

/** An ayah to hear the rule in, with the phrase to focus on. */
@Serializable
data class TajweedExample(val surahId: Int = 0, val ayahNumber: Int = 0, val focus: String = "")

/** The card that shows the rule as it appears in the mushaf. */
@Serializable
data class TajweedMushafCard(
    val fragments: List<TajweedDrill> = emptyList(),
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
    val mushafCard: TajweedMushafCard? = null,
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
 * Content, not algorithm — but it belongs in the engine for the same reason the rule catalogue does:
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

    /** The lesson after this one, walking across chapter boundaries — the "next" button's answer. */
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
