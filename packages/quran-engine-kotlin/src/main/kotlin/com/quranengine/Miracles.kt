package com.quranengine

import kotlinx.serialization.Serializable

/**
 * The scientific-miracles corpus: 202 short articles, each making one claim about the Quran and
 * anchoring it to the ayahs it rests on, under 15 categories.
 *
 * An article is a list of BLOCKS in reading order rather than one field of prose, because the
 * layout matters: the claim is a headline, the lead sets it up, a quote carries somebody else's
 * words with the source next to them, an ayah block is a hole the consumer fills from
 * `quran.json`, and the closer asks the rhetorical question the article was built toward.
 *
 * An `ayah` block carries NO text, by design: surah, ayah and endAyah only. The verse belongs to
 * this engine's own Hafs text, so duplicating it here would be a second copy to keep in step and
 * would pin the article to one riwayah.
 *
 * There are NO `image` blocks and `imagesIncluded` is false: the site's illustrations are not
 * republished here for licensing reasons, and the prose is written to stand without them. A
 * consumer that leaves a gap for a picture will be waiting forever.
 *
 * Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
 * science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters
 * or sorts by has to come off the ARTICLE.
 *
 * See `../../docs/25-miracles.md`.
 */

/**
 * The four levels, easiest first.
 *
 * Hard-coded because this is the app's own ordering and nothing in the file states it:
 * alphabetically "extreme" would sort second, which is precisely backwards.
 */
val MIRACLE_LEVELS: List<String> = listOf("simple", "intermediate", "advanced", "extreme")

/**
 * The block kinds that carry the article's OWN prose. A quote is somebody else's words and an ayah
 * block has no text at all, so neither belongs in [Miracles.text].
 */
private val PROSE_KINDS = setOf("claim", "lead", "text", "closer")

/** One of the fifteen categories, with the hardest science it covers. */
@Serializable
data class MiracleCategory(
    val id: String,
    /** The CATEGORY's level, which an article under it need not share. */
    val level: String = "",
)

/**
 * A link out of a block: either an outside page or another article in this corpus.
 *
 * Exactly one of [url] and [slug] is set. Both forms occur, so a model that kept only [url] would
 * silently drop the twelve internal cross-references.
 */
@Serializable
data class MiracleLink(
    val label: String = "",
    /** An outside page. */
    val url: String? = null,
    /** Another article's slug: follow it with [Miracles.bySlug]. */
    val slug: String? = null,
)

/** One block of an article. Which fields are set follows from [kind]. */
@Serializable
data class MiracleBlock(
    /** "claim", "lead", "text", "quote", "ayah" or "closer". Never "image". */
    val kind: String,
    /** Set on every kind but `ayah`. */
    val text: String = "",
    /** `lead` and `text` blocks only. */
    val links: List<MiracleLink> = emptyList(),
    /** `quote` only: who is being quoted. */
    val sourceLabel: String? = null,
    val sourceUrl: String? = null,
    /** `ayah` only. */
    val surah: Int? = null,
    /** `ayah` only: the first of the range. */
    val ayah: Int? = null,
    /** `ayah` only: the last of the range, always present and equal to [ayah] for a single verse. */
    val endAyah: Int? = null,
) {
    /**
     * Whether this is an `ayah` block covering one ayah. A block is a RANGE, so an article citing
     * 21:30-33 answers to 21:31 as well.
     */
    fun covers(surahId: Int, ayahId: Int): Boolean {
        if (kind != "ayah" || surah != surahId || ayah == null) return false
        return ayahId >= ayah && ayahId <= (endAyah ?: ayah)
    }
}

/** One article. */
@Serializable
data class MiracleArticle(
    val slug: String,
    val title: String = "",
    /** A [MiracleCategory] id. */
    val category: String = "",
    /** This article's OWN level, not its category's. */
    val level: String = "",
    val blocks: List<MiracleBlock> = emptyList(),
)

/** `data/miracles.json`. */
@Serializable
data class MiraclesFile(
    val source: String = "",
    /** False, always: the illustrations are not republished. */
    val imagesIncluded: Boolean = false,
    val categories: List<MiracleCategory> = emptyList(),
    val articles: List<MiracleArticle> = emptyList(),
)

/** One ayah range an article cites. */
data class MiracleAyahRef(val surah: Int, val ayah: Int, val endAyah: Int)

/** How many articles, categories and ayah refs the corpus carries. */
data class MiraclesCount(val articles: Int, val categories: Int, val ayahRefs: Int)

/** Where a level sorts, or past the end for one the corpus invents later. */
fun miracleLevelRank(level: String): Int =
    MIRACLE_LEVELS.indexOf(level).let { if (it == -1) MIRACLE_LEVELS.size else it }

class Miracles(private val file: MiraclesFile = MiraclesFile()) {
    private val bySlugMap: Map<String, MiracleArticle> = file.articles.associateBy { it.slug }

    val isLoaded: Boolean get() = file.articles.isNotEmpty()

    /** Where the corpus came from and when it was captured. */
    fun source(): String = file.source

    /** False, always: the illustrations are not republished. */
    val imagesIncluded: Boolean get() = file.imagesIncluded

    /** All 202, in corpus order. */
    fun all(): List<MiracleArticle> = file.articles

    fun bySlug(slug: String): MiracleArticle? = bySlugMap[slug]

    /** The fifteen categories, in the corpus's own order. */
    fun categories(): List<MiracleCategory> = file.categories

    fun category(id: String): MiracleCategory? = file.categories.firstOrNull { it.id == id }

    /** Every article filed under one category. */
    fun byCategory(id: String): List<MiracleArticle> = file.articles.filter { it.category == id }

    /**
     * Every article at one level.
     *
     * The ARTICLE's level, not its category's: they disagree far more often than they agree, and a
     * reader who picked "simple" means the article.
     */
    fun byLevel(level: String): List<MiracleArticle> = file.articles.filter { it.level == level }

    /** The article levels actually present, easiest first. */
    fun levels(): List<String> =
        file.articles.map { it.level }.distinct().sortedWith(compareBy({ miracleLevelRank(it) }, { it }))

    /**
     * Every article that cites an ayah: the way into this corpus from elsewhere in the engine.
     *
     * An `ayah` block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An
     * article that cites the same ayah in two blocks is still listed once.
     */
    fun citing(surahId: Int, ayahId: Int): List<MiracleArticle> =
        file.articles.filter { article -> article.blocks.any { it.covers(surahId, ayahId) } }

    /** The ayah ranges one article cites, in the order it cites them. */
    fun ayahRefs(slug: String): List<MiracleAyahRef> {
        val article = bySlugMap[slug] ?: return emptyList()
        return article.blocks
            .filter { it.kind == "ayah" && it.surah != null && it.ayah != null }
            .map { MiracleAyahRef(it.surah!!, it.ayah!!, it.endAyah ?: it.ayah) }
    }

    /**
     * Articles whose title or prose matches a query, case-insensitively.
     *
     * Quotes are searched as well: a reader looking for a word remembers reading it, not who wrote
     * it.
     */
    fun search(query: String, limit: Int = 25): List<MiracleArticle> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        return file.articles
            .filter { article ->
                article.title.lowercase().contains(q) ||
                    article.blocks.any { it.text.lowercase().contains(q) }
            }
            .take(limit)
    }

    /**
     * One article's own prose, blocks joined with a blank line in reading order.
     *
     * Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
     * folding them in would put somebody else's words into the article's voice and would break a
     * citation off from what it cites. Ayah blocks are skipped because they carry no text at all,
     * only a reference for the consumer to resolve.
     */
    fun text(slug: String): String {
        val article = bySlugMap[slug] ?: return ""
        return article.blocks
            .filter { it.kind in PROSE_KINDS && it.text.isNotEmpty() }
            .joinToString("\n\n") { it.text }
    }

    fun count(): MiraclesCount = MiraclesCount(
        file.articles.size,
        file.categories.size,
        file.articles.sumOf { article -> article.blocks.count { it.kind == "ayah" } },
    )
}
