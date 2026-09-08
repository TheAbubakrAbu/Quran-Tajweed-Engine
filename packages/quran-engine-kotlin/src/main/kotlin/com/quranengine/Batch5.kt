package com.quranengine

import kotlinx.serialization.Serializable

/**
 * The corpora added upstream in Al-Islam 4.6.4: the repeated phrases, the QUL topic indexes, the
 * hizb/ruku/manzil divisions, the qiraat variant matrix and the word of the day. Morphology has its
 * own file.
 *
 * See `../../docs/19-mutashabihat.md`, `20-topics-and-metadata.md`, `21-qiraat-variants.md` and
 * `22-word-of-day.md`.
 */

// ---- mutashabihat -----------------------------------------------------------------

/**
 * One repeated phrase and every place it occurs.
 *
 * A different thing from a similar ayah: that is a whole-ayah match, this is the exact run of words
 * two ayahs share, which is the memoriser's question. Spans are 0-based inclusive token ranges of
 * the raw Hafs text, mapped at build time, so nothing here matches text.
 */
data class MutashabihatPhrase(
    val id: Int,
    /** The ayah the phrase is defined from. */
    val source: String,
    /** Inclusive token range inside [source]. */
    val span: IntRange,
    val count: Int,
    val ayahCount: Int,
    val surahCount: Int,
    /** Ayah key -> the spans carrying the phrase in that ayah. */
    val occurrences: Map<String, List<IntRange>>,
) {
    /** How long the phrase is, in words. */
    val wordCount: Int get() = span.last - span.first + 1

    /** The occurrences in mushaf order. */
    val orderedKeys: List<String> get() = occurrences.keys.sortedWith(AYAH_KEY_ORDER)
}

@Serializable
data class MutashabihatPhraseRow(
    val source: String = "",
    val span: List<Int> = emptyList(),
    val count: Int = 0,
    val ayahCount: Int = 0,
    val surahCount: Int = 0,
    val occurrences: Map<String, List<List<Int>>> = emptyMap(),
)

/** `data/mutashabihat.json`. */
@Serializable
data class MutashabihatFile(
    val phrases: Map<String, MutashabihatPhraseRow> = emptyMap(),
    val index: Map<String, List<Int>> = emptyMap(),
)

class Mutashabihat(private val file: MutashabihatFile = MutashabihatFile()) {

    val isLoaded: Boolean get() = file.phrases.isNotEmpty()

    /** One phrase by id. */
    fun phrase(id: Int): MutashabihatPhrase? {
        val row = file.phrases["$id"] ?: return null
        if (row.span.size != 2 || row.span[1] < row.span[0]) return null
        val occurrences = row.occurrences.mapValues { (_, spans) ->
            spans.mapNotNull { if (it.size == 2 && it[1] >= it[0]) it[0]..it[1] else null }
        }
        return MutashabihatPhrase(
            id = id,
            source = row.source,
            span = row.span[0]..row.span[1],
            count = row.count,
            ayahCount = row.ayahCount,
            surahCount = row.surahCount,
            occurrences = occurrences,
        )
    }

    /** The phrases this ayah carries, longest first so the most distinctive wording leads. */
    fun phrasesFor(surahId: Int, ayahId: Int): List<MutashabihatPhrase> =
        (file.index["$surahId:$ayahId"] ?: emptyList())
            .mapNotNull { phrase(it) }
            .sortedWith(compareByDescending<MutashabihatPhrase> { it.wordCount }.thenBy { it.id })

    /** Whether the ayah carries any: a map hit, cheap enough to gate a button on. */
    fun has(surahId: Int, ayahId: Int): Boolean = !file.index["$surahId:$ayahId"].isNullOrEmpty()

    /** A phrase's occurrences in mushaf order, each with the spans carrying it there. */
    fun occurrences(id: Int): List<PhraseOccurrence> {
        val phrase = phrase(id) ?: return emptyList()
        return phrase.orderedKeys.map { key ->
            val (surah, ayah) = splitAyahKey(key)
            PhraseOccurrence(surah, ayah, key, phrase.occurrences[key] ?: emptyList())
        }
    }

    /**
     * The phrase's own words, sliced out of the ayah text you hand it. The engine does not carry
     * the text in here: the caller already has the ayah it is displaying.
     */
    fun textOf(id: Int, sourceAyahText: String): String {
        val phrase = phrase(id) ?: return ""
        val tokens = sourceAyahText.split(WHITESPACE).filter { it.isNotEmpty() }
        if (phrase.span.last >= tokens.size) return ""
        return tokens.subList(phrase.span.first, phrase.span.last + 1).joinToString(" ")
    }

    /** How many phrases there are, and how many ayahs carry one. */
    fun count(): Pair<Int, Int> = file.phrases.size to file.index.size
}

/** One place a phrase occurs. */
data class PhraseOccurrence(
    val surah: Int,
    val ayah: Int,
    val key: String,
    val spans: List<IntRange>,
)

// ---- QUL topics -------------------------------------------------------------------

/**
 * One of the three QUL indexes.
 *
 * They are three trees over ONE pool of topics, not three partitions of it: a topic can be a node
 * in more than one (17 are), and a tree's parent need not itself be listed in that tree.
 */
@Serializable
enum class TopicTree {
    thematic,
    ontology,
    index,
}

/** One topic of the Quranic Universal Library's indexes. */
@Serializable
data class QulTopic(
    val id: Int,
    val name: String,
    val arabic: String = "",
    /** The indexes listing this topic; 17 topics are listed in two. */
    val families: List<TopicTree> = emptyList(),
    /**
     * One parent per tree, independently. Absent or null where the topic is not in that tree, or
     * is one of its roots.
     */
    val parents: Map<String, Int?> = emptyMap(),
    val description: String = "",
    val wiki: String = "",
    /** `"2:255"` references, in the corpus's order. */
    val ayahs: List<String> = emptyList(),
    val related: List<Int> = emptyList(),
) {
    /** The parent in one tree, if any. */
    fun parentIn(tree: TopicTree): Int? = parents[tree.name]

    /** Whether this index lists the topic. */
    fun isListedIn(tree: TopicTree): Boolean = tree in families

    /** The tree to use when a caller does not name one: the first index listing the topic. */
    val defaultTree: TopicTree? get() = families.firstOrNull()
}

/** `data/quran-topics.json`. */
@Serializable
data class QulTopicsFile(val topics: List<QulTopic> = emptyList())

class QuranTopics(private val all: List<QulTopic> = emptyList()) {
    private val byId: Map<Int, QulTopic> = all.associateBy { it.id }

    val isLoaded: Boolean get() = all.isNotEmpty()

    /** Every topic, in corpus order. */
    fun topics(): List<QulTopic> = all

    fun topic(id: Int): QulTopic? = byId[id]

    /** The topics an index lists. */
    fun inFamily(tree: TopicTree): List<QulTopic> = all.filter { it.isListedIn(tree) }

    /** Topics an index lists that have no parent in that same tree. */
    fun roots(tree: TopicTree): List<QulTopic> =
        all.filter { it.isListedIn(tree) && it.parentIn(tree) == null }

    /**
     * The parent in one tree. Pass null for the topic's first listed index, which is a convenience
     * for a caller that does not care.
     */
    fun parent(id: Int, tree: TopicTree? = null): QulTopic? {
        val topic = byId[id] ?: return null
        val which = tree ?: topic.defaultTree ?: return null
        return topic.parentIn(which)?.let { byId[it] }
    }

    /** Direct children in one tree, in id order. */
    fun children(id: Int, tree: TopicTree? = null): List<QulTopic> {
        val topic = byId[id] ?: return emptyList()
        val which = tree ?: topic.defaultTree ?: return emptyList()
        return childIndex.getValue(which)[id].orEmpty().mapNotNull { byId[it] }
    }

    /**
     * The chain up to the root of one tree, nearest first. Cycle-safe: the corpus is trusted for
     * its content, not for its shape.
     */
    fun ancestors(id: Int, tree: TopicTree? = null): List<QulTopic> {
        val topic = byId[id] ?: return emptyList()
        val which = tree ?: topic.defaultTree ?: return emptyList()
        val out = ArrayList<QulTopic>()
        val seen = HashSet<Int>().apply { add(id) }
        var current = parent(id, which)
        while (current != null && seen.add(current.id)) {
            out.add(current)
            current = parent(current.id, which)
        }
        return out
    }

    /** Every topic annotating this ayah, across all three indexes. */
    fun topicsFor(surahId: Int, ayahId: Int): List<QulTopic> =
        ayahIndex["$surahId:$ayahId"].orEmpty().mapNotNull { byId[it] }

    /** Name and Arabic-name substring search, exact-prefix hits first. */
    fun search(query: String, limit: Int = 50): List<QulTopic> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val starts = ArrayList<QulTopic>()
        val contains = ArrayList<QulTopic>()
        for (topic in all) {
            val name = topic.name.lowercase()
            when {
                name.startsWith(q) -> starts.add(topic)
                name.contains(q) || topic.arabic.contains(query) -> contains.add(topic)
            }
            if (starts.size >= limit) break
        }
        return (starts + contains).take(limit)
    }

    /**
     * Corpus size. The per-index counts deliberately sum to MORE than the topic count: the 17
     * topics listed in two indexes are counted in both.
     */
    fun count(): TopicCounts {
        var thematic = 0
        var ontology = 0
        var index = 0
        var references = 0
        for (topic in all) {
            for (family in topic.families) {
                when (family) {
                    TopicTree.thematic -> thematic++
                    TopicTree.ontology -> ontology++
                    TopicTree.index -> index++
                }
            }
            references += topic.ayahs.size
        }
        return TopicCounts(all.size, thematic, ontology, index, references)
    }

    private val childIndex: Map<TopicTree, Map<Int, List<Int>>> by lazy {
        TopicTree.entries.associateWith { tree ->
            val table = HashMap<Int, MutableList<Int>>()
            for (topic in all) {
                topic.parentIn(tree)?.let { table.getOrPut(it) { ArrayList() }.add(topic.id) }
            }
            table.mapValues { (_, ids) -> ids.sorted() }
        }
    }

    private val ayahIndex: Map<String, List<Int>> by lazy {
        val table = HashMap<String, MutableList<Int>>()
        for (topic in all) {
            for (key in topic.ayahs) table.getOrPut(key) { ArrayList() }.add(topic.id)
        }
        table
    }
}

data class TopicCounts(
    val topics: Int,
    val thematic: Int,
    val ontology: Int,
    val index: Int,
    val references: Int,
)

// ---- passage themes ---------------------------------------------------------------

/**
 * One short sentence describing a run of ayahs.
 *
 * Passages run in order through a surah and do not nest. They do not tile it either: an ayah
 * between two passages has none.
 */
@Serializable
data class ThemePassage(
    val from: Int,
    val to: Int,
    val theme: String,
    val topic: String = "",
)

class AyahThemes(private val data: Map<String, List<ThemePassage>> = emptyMap()) {

    val isLoaded: Boolean get() = data.isNotEmpty()

    /** A surah's passages, in order. */
    fun passages(surahId: Int): List<ThemePassage> = data["$surahId"] ?: emptyList()

    /**
     * The passage an ayah falls in. Passages do not overlap, so this is the one answer; null for
     * an ayah between two of them.
     */
    fun passageFor(surahId: Int, ayahId: Int): ThemePassage? =
        passages(surahId).firstOrNull { ayahId >= it.from && ayahId <= it.to }

    /** Matches the theme sentence and the topic it sits under. */
    fun search(query: String, limit: Int = 50): List<Pair<Int, ThemePassage>> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val out = ArrayList<Pair<Int, ThemePassage>>()
        for (surah in data.keys.mapNotNull(String::toIntOrNull).sorted()) {
            for (passage in passages(surah)) {
                if (passage.theme.lowercase().contains(q) || passage.topic.lowercase().contains(q)) {
                    out.add(surah to passage)
                    if (out.size >= limit) return out
                }
            }
        }
        return out
    }

    fun count(): Pair<Int, Int> = data.size to data.values.sumOf { it.size }
}

// ---- hizb / ruku / manzil ---------------------------------------------------------

/** One hizb, ruku or manzil, identified by where it starts. */
data class Division(val number: Int, val surah: Int, val ayah: Int, val key: String)

/** `data/quran-metadata.json`. */
@Serializable
data class QuranMetadataFile(
    val hizb: List<String> = emptyList(),
    val ruku: List<String> = emptyList(),
    val manzil: List<String> = emptyList(),
)

/**
 * One of the three schedule divisions, stored as its start keys in order so a lookup is a binary
 * search rather than a table with one row per ayah.
 */
class DivisionTable(private val starts: List<String>) {
    private val ranks: List<Int> = starts.map { key ->
        val (surah, ayah) = splitAyahKey(key)
        surah * 1000 + ayah
    }

    val size: Int get() = starts.size

    /** The 1-based number containing an ayah, or 0 when there is no table. */
    fun numberFor(surahId: Int, ayahId: Int): Int {
        val target = surahId * 1000 + ayahId
        var low = 0
        var high = ranks.size - 1
        var found = -1
        while (low <= high) {
            val mid = (low + high) / 2
            if (ranks[mid] <= target) {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found + 1
    }

    /** Where a division begins. */
    fun start(number: Int): Division? {
        val key = starts.getOrNull(number - 1) ?: return null
        val (surah, ayah) = splitAyahKey(key)
        return Division(number, surah, ayah, key)
    }

    /** Every start, in order. */
    fun all(): List<Division> = starts.indices.mapNotNull { start(it + 1) }

    /**
     * A division's start and the start of the next one, which is where it ends. The second is null
     * for the last, which runs to the end of the Quran: no start key says so, and pretending
     * otherwise would be an invented boundary.
     */
    fun range(number: Int): Pair<Division, Division?>? {
        val from = start(number) ?: return null
        return from to start(number + 1)
    }
}

/**
 * 60 hizb (the juz halved, the unit a memorisation plan is written in), 558 ruku (thematic sections
 * printed in the margin of South Asian mushafs), 7 manzil (the seven-day division).
 */
class QuranMetadata(file: QuranMetadataFile = QuranMetadataFile()) {
    val hizb = DivisionTable(file.hizb)
    val ruku = DivisionTable(file.ruku)
    val manzil = DivisionTable(file.manzil)

    val isLoaded: Boolean get() = hizb.size > 0

    /** All three at once, which is what a "where am I" line under an ayah wants. */
    fun divisionsFor(surahId: Int, ayahId: Int): Triple<Int, Int, Int> = Triple(
        hizb.numberFor(surahId, ayahId),
        ruku.numberFor(surahId, ayahId),
        manzil.numberFor(surahId, ayahId),
    )

    fun count(): Triple<Int, Int, Int> = Triple(hizb.size, ruku.size, manzil.size)
}

// ---- shared helpers ---------------------------------------------------------------

/** Java's `\s` is ASCII-only, so every whitespace split in this port names Unicode explicitly. */
internal val WHITESPACE = Regex("(?U)\\s+")

/** Mushaf order for `"surah:ayah"` keys. */
internal val AYAH_KEY_ORDER = Comparator<String> { a, b ->
    val (sa, aa) = splitAyahKey(a)
    val (sb, ab) = splitAyahKey(b)
    if (sa != sb) sa - sb else aa - ab
}

/** Split a `"surah:ayah"` key; `(0, 0)` for anything malformed, which never passes for an ayah. */
internal fun splitAyahKey(key: String): Pair<Int, Int> {
    val parts = key.split(":")
    if (parts.size != 2) return 0 to 0
    return (parts[0].toIntOrNull() ?: 0) to (parts[1].toIntOrNull() ?: 0)
}
