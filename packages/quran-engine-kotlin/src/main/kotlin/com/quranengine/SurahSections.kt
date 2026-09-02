package com.quranengine

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one sentence
 * saying what the surah as a whole is about.
 *
 * This answers "I am at 18:60 - what is this passage doing here", which neither the translation nor
 * the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
 * outline; al-Fatihah, Fussilat and ad-Dukhan do not.
 *
 * **The outline is a tree, flattened.** Ranges are inclusive, in mushaf order, and MAY NEST: a broad
 * section is followed by the sections inside it, parent before children (Hud opens with 1-24
 * "Doctrine facts", then 1-4, 5-6, 7-11, 12-17, 18-24 within it). They also do not tile the surah -
 * an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
 * which is what [SurahSections.sectionsFor] returns; [SurahSections.outline] rebuilds it as a tree.
 *
 * See `../../docs/15-surah-sections.md`.
 */
data class SurahSection(
    /** First ayah, inclusive. */
    val from: Int,
    /** Last ayah, inclusive. */
    val to: Int,
    val english: String,
    val arabic: String,
) {
    fun contains(ayahId: Int): Boolean = ayahId in from..to
}

/** A section with the sections inside it. */
data class OutlineNode(val section: SurahSection, val children: MutableList<OutlineNode> = mutableListOf())

/**
 * One surah's entry in `data/surah-sections.json`. The section rows are
 * `[from, to, english, arabic]` - heterogeneous, so they stay as [JsonArray] until they are read.
 */
@Serializable
data class SurahSectionsEntry(
    val overview: String = "",
    val sections: List<JsonArray> = emptyList(),
)

class SurahSections(private val data: Map<String, SurahSectionsEntry> = emptyMap()) {

    /** One sentence on what the whole surah is about, "" when none is recorded. */
    fun overview(surahId: Int): String = data[surahId.toString()]?.overview ?: ""

    /**
     * The surah's sections, flat and in the order the source records them (a parent immediately
     * before the sections inside it).
     */
    fun sections(surahId: Int): List<SurahSection> =
        data[surahId.toString()]?.sections.orEmpty().mapNotNull { row ->
            if (row.size < 4) return@mapNotNull null
            val from = row[0].jsonPrimitive.intOrNull ?: return@mapNotNull null
            val to = row[1].jsonPrimitive.intOrNull ?: return@mapNotNull null
            val english = (row[2] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return@mapNotNull null
            val arabic = (row[3] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return@mapNotNull null
            SurahSection(from, to, english, arabic)
        }

    /** The same sections as a tree: top-level passages, each with what is inside it. */
    fun outline(surahId: Int): List<OutlineNode> {
        val roots = mutableListOf<OutlineNode>()
        val open = mutableListOf<OutlineNode>()
        for (section in sections(surahId)) {
            // A section belongs to the nearest still-open range that fully contains it.
            while (open.isNotEmpty() &&
                !(open.last().section.from <= section.from && section.to <= open.last().section.to)
            ) {
                open.removeAt(open.size - 1)
            }
            val node = OutlineNode(section)
            if (open.isEmpty()) roots += node else open.last().children += node
            open += node
        }
        return roots
    }

    /**
     * Every section covering an ayah, outermost first - the breadcrumb for "you are here". Empty
     * when the surah has no outline, or when this ayah falls between sections.
     */
    fun sectionsFor(surahId: Int, ayahId: Int): List<SurahSection> =
        sections(surahId).filter { it.contains(ayahId) }

    /** The most specific section covering an ayah - the heading a reader wants beside the verse. */
    fun sectionFor(surahId: Int, ayahId: Int): SurahSection? = sectionsFor(surahId, ayahId).lastOrNull()

    /** Whether this surah has an outline at all. */
    fun hasSections(surahId: Int): Boolean = !data[surahId.toString()]?.sections.isNullOrEmpty()

    /** How many surahs carry an outline. */
    fun count(): Int = data.values.count { it.sections.isNotEmpty() }

    /** Sections whose title carries [query], across every surah. */
    fun search(query: String): List<Pair<Int, SurahSection>> {
        val trimmed = query.trim()
        val needle = trimmed.lowercase()
        if (needle.isEmpty()) return emptyList()
        val out = mutableListOf<Pair<Int, SurahSection>>()
        for (id in data.keys.mapNotNull(String::toIntOrNull).sorted()) {
            for (section in sections(id)) {
                if (section.english.lowercase().contains(needle) || section.arabic.contains(trimmed)) {
                    out += id to section
                }
            }
        }
        return out
    }
}
