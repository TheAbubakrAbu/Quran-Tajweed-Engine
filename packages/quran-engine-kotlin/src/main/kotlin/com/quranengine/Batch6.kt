package com.quranengine

import kotlinx.serialization.Serializable

/**
 * The corpora added upstream in Al-Islam 4.6.5: the 99 Names in depth, and the chains of
 * transmission of the Ten Readings.
 *
 * See `../../docs/23-names-depth.md` and `24-isnad.md`.
 */

// ---- the Names in depth ----------------------------------------------------------

/** One of the nine themes the Names are grouped under. */
@Serializable
data class NameTheme(val id: String, val label: String = "")

/** One ayah a Name appears in. */
@Serializable
data class NameOccurrence(
    val surah: Int,
    val ayah: Int,
    /**
     * 0-based whitespace-token index into the ayah's raw text, or null where the corpus could not
     * place the Name in the ayah (ten occurrences across four Names). The ayah is still right: show
     * the verse whole and highlight nothing.
     */
    val token: Int? = null,
    /** How many tokens the Name spans (0 for an unplaced occurrence). */
    val tokens: Int = 0,
)

/**
 * The layer under `names-of-allah.json`: what the Name is built on and what it asks of a reader.
 *
 * The written material is Tilawa's (Jamil Hammoudeh), used with permission; the occurrences point
 * into this engine's own Hafs text.
 */
@Serializable
data class NameDepth(
    val number: Int,
    /**
     * Printed SPACED, the way a grammar book sets a root ("ر ح م"). [rootKey] closes it up to the
     * form `morphology.json` stores.
     */
    val root: String = "",
    val theme: String = "",
    val explanation: String = "",
    val living: String = "",
    val occurrences: List<NameOccurrence> = emptyList(),
)

/** `data/names-depth.json`. */
@Serializable
data class NamesDepthFile(
    val themes: List<NameTheme> = emptyList(),
    val names: List<NameDepth> = emptyList(),
)

/**
 * A spaced root as morphology stores it: `"ر ح م"` -> `"رحم"`.
 *
 * Java's `\s` is ASCII-only, so the split is `(?U)\s+` like every other whitespace fold here.
 */
fun rootKey(root: String): String = root.split(Regex("(?U)\\s+")).joinToString("")

/** A Name and the occurrence that put it in an ayah. */
data class NameInAyah(val name: NameDepth, val occurrence: NameOccurrence)

class NamesDepth(
    private val names: List<NameDepth> = emptyList(),
    private val themeList: List<NameTheme> = emptyList(),
) {
    private val byNumber: Map<Int, NameDepth> = names.associateBy { it.number }

    val isLoaded: Boolean get() = names.isNotEmpty()

    /** All 99, ordered by number. */
    fun all(): List<NameDepth> = names

    fun byNumber(number: Int): NameDepth? = byNumber[number]

    /** The nine themes, in the corpus's own order. */
    fun themes(): List<NameTheme> = themeList

    fun theme(id: String): NameTheme? = themeList.firstOrNull { it.id == id }

    /** Every Name under one theme, by number. */
    fun byTheme(id: String): List<NameDepth> = names.filter { it.theme == id }

    /** Every Name built on one root. Accepts either spelling, spaced or closed up. */
    fun byRoot(root: String): List<NameDepth> {
        val key = rootKey(root)
        if (key.isEmpty()) return emptyList()
        return names.filter { rootKey(it.root) == key }
    }

    /**
     * Every Name appearing in an ayah, in token order. An unplaced occurrence (a null token) sorts
     * last, so a highlighted list stays in reading order.
     */
    fun inAyah(surahId: Int, ayahId: Int): List<NameInAyah> =
        names.flatMap { name ->
            name.occurrences
                .filter { it.surah == surahId && it.ayah == ayahId }
                .map { NameInAyah(name, it) }
        }.sortedBy { it.occurrence.token ?: Int.MAX_VALUE }

    /** Matches the root (spaces closed on both sides), the explanation and the living line. */
    fun search(query: String, limit: Int = 25): List<NameDepth> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        val lower = q.lowercase()
        val key = rootKey(q)
        return names.filter { name ->
            (key.isNotEmpty() && rootKey(name.root).contains(key)) ||
                name.explanation.lowercase().contains(lower) ||
                name.living.lowercase().contains(lower)
        }.take(limit)
    }

    /** How many Names carry depth, how many themes, and how many occurrences they cover. */
    fun count(): Triple<Int, Int, Int> =
        Triple(names.size, themeList.size, names.sumOf { it.occurrences.size })
}

// ---- the chains of transmission --------------------------------------------------

/** One person in a chain. */
@Serializable
data class IsnadNode(
    val name: String,
    val arabic: String = "",
    /** The death year, e.g. "d. 117 AH". */
    val detail: String = "",
    val role: String = "",
)

/** One generation of a chain, as a consumer draws it: a row, connected downward. */
data class IsnadLayer(val title: String, val nodes: List<IsnadNode>)

/** An imam's side: the Successors he read on, and the Companions they read on. */
@Serializable
data class ImamChain(
    val teachers: List<IsnadNode> = emptyList(),
    val companions: List<IsnadNode> = emptyList(),
)

/**
 * A narrator's side: the links between him and the imam (empty where he read on the imam himself),
 * and the students who carried his narration on.
 */
@Serializable
data class NarratorChain(
    /** The imam this narration comes from. */
    val imam: String = "",
    val links: List<IsnadNode> = emptyList(),
    val students: List<IsnadNode> = emptyList(),
)

/** `data/isnad.json`. */
@Serializable
data class IsnadFile(
    val prophet: IsnadNode? = null,
    val companions: List<IsnadNode> = emptyList(),
    val imams: Map<String, ImamChain> = emptyMap(),
    val narrators: Map<String, NarratorChain> = emptyMap(),
)

class Isnad(private val file: IsnadFile = IsnadFile()) {
    val isLoaded: Boolean get() = file.imams.isNotEmpty()

    /** The head of every chain. */
    fun prophet(): IsnadNode? = file.prophet

    /** The thirteen Companions the readings are transmitted from. */
    fun companions(): List<IsnadNode> = file.companions

    /** The ten imams' keys, sorted. */
    fun imamKeys(): List<String> = file.imams.keys.sorted()

    /** The twenty riwayah tags, sorted. */
    fun narratorKeys(): List<String> = file.narrators.keys.sorted()

    fun imam(imam: String): ImamChain? = file.imams[imam]

    fun narrator(riwayah: String): NarratorChain? = file.narrators[riwayah]

    /** Whether a narrator read on his imam himself, with nobody between them. */
    fun readsDirectly(riwayah: String): Boolean =
        file.narrators[riwayah]?.links?.isEmpty() == true

    /**
     * The imam a riwayah comes from.
     *
     * Read from the corpus, NOT parsed off the tag: four tags name the imam in the Arabic genitive
     * ("ad-Duri an Abi Amr") while his key is the nominative ("Abu Amr"), so splitting on " an "
     * would resolve those four to nothing.
     */
    fun imamOf(riwayah: String): String? {
        val imam = file.narrators[riwayah]?.imam ?: return null
        return if (file.imams.containsKey(imam)) imam else null
    }

    private fun narratorName(riwayah: String): String {
        val i = riwayah.indexOf(" an ")
        return if (i < 0) riwayah else riwayah.substring(0, i)
    }

    private fun plain(name: String, role: String) = IsnadNode(name = name, role = role)

    /**
     * The layers above any imam: the Prophet, the Companions his teachers read on, and those
     * teachers. Shared by both chain forms, since every chain runs through them.
     */
    fun topLayers(imam: String): List<IsnadLayer> {
        val chain = file.imams[imam] ?: return emptyList()
        val layers = mutableListOf<IsnadLayer>()
        file.prophet?.let { layers += IsnadLayer("THE PROPHET", listOf(it)) }
        if (chain.companions.isNotEmpty()) layers += IsnadLayer("THE COMPANIONS", chain.companions)
        if (chain.teachers.isNotEmpty()) {
            layers += IsnadLayer(
                if (chain.teachers.size == 1) "HIS TEACHER" else "HIS TEACHERS",
                chain.teachers,
            )
        }
        return layers
    }

    /**
     * A whole chain as layers: a riwayah tag for one narration's chain, or an imam key for the
     * reading's, which ends at his two narrators.
     */
    fun chain(key: String): List<IsnadLayer> {
        val k = key.trim()
        if (file.imams.containsKey(k)) {
            val layers = topLayers(k).toMutableList()
            if (layers.isEmpty()) return layers
            layers += IsnadLayer("THE IMAM", listOf(plain(k, "imam")))
            val nodes = narratorKeys()
                .filter { imamOf(it) == k }
                .map { plain(narratorName(it), "narrator") }
            if (nodes.isNotEmpty()) layers += IsnadLayer("HIS TWO NARRATORS", nodes)
            return layers
        }

        val narrator = file.narrators[k] ?: return emptyList()
        val imam = imamOf(k) ?: return emptyList()
        val layers = topLayers(imam).toMutableList()
        if (layers.isEmpty()) return layers
        layers += IsnadLayer("THE IMAM", listOf(plain(imam, "imam")))
        if (narrator.links.isNotEmpty()) {
            layers += IsnadLayer(
                if (narrator.links.size == 1) "THE LINK BETWEEN" else "THE LINKS BETWEEN",
                narrator.links,
            )
        }
        layers += IsnadLayer("THE NARRATOR", listOf(plain(narratorName(k), "narrator")))
        if (narrator.students.isNotEmpty()) layers += IsnadLayer("HIS STUDENTS", narrator.students)
        return layers
    }

    /** One sentence on how a narrator reaches his imam: directly, or through the links between. */
    fun sentence(riwayah: String): String {
        val chain = file.narrators[riwayah] ?: return ""
        val imam = imamOf(riwayah) ?: return ""
        val narrator = narratorName(riwayah)
        if (chain.links.isEmpty()) {
            return "$narrator read on $imam himself, and $imam's chain runs through his teachers " +
                "to the Companions and to the Prophet ﷺ."
        }
        val names = chain.links.map { it.name }
        val path = if (names.size == 1) {
            names.first()
        } else {
            names.dropLast(1).joinToString(", ") + " and then " + names.last()
        }
        return "$narrator did not meet $imam: the reading reached him through $path, and from " +
            "$imam it runs through his teachers to the Companions and to the Prophet ﷺ."
    }

    /** How many imams, narrators and Companions the chains cover. */
    fun count(): Triple<Int, Int, Int> =
        Triple(file.imams.size, file.narrators.size, file.companions.size)
}
