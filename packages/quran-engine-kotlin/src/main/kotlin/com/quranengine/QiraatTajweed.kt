package com.quranengine

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Riwayah tajweed: where a reading differs from Hafs, and why.
 *
 * A different layer from [Tajweed], which reads the text and works out the universal rules. This
 * carries what is SPECIFIC to a transmission and cannot be detected, because it IS the text's
 * difference: Warsh's taqlil, al-Bazzi's doubled ta, the places two readings part.
 *
 * Two things to get right:
 *
 *  * **The meaning of a colour is per edition.** Each mushaf prints its own legend, so the same code
 *    is a different rule in a different riwayah. Always read [legend]. The `rule` KEY is stable
 *    across riwayat, which is why one catalogue can explain it for all of them.
 *  * **Extents are base-letter indices, not character offsets**, `firstLetter..lastLetter`
 *    inclusive in reading order with diacritics not counted, or the whole word when `wholeWord`.
 *
 * Only the seven verified non-Hafs riwayat carry a pack. See `../../docs/11-qiraat-tajweed.md`.
 */
@Serializable
data class LegendRow(
    val code: String,
    val rule: String,
    val arabic: String,
    val english: String,
)

/** A legend row with its shared explanation merged in. */
data class LegendEntry(
    /** The single letter this riwayah's data uses for the rule. */
    val code: String,
    /** Stable rule key, e.g. `"idgham"`: the same across riwayat. */
    val rule: String,
    /** The rule's name as this mushaf prints it. */
    val arabic: String,
    val english: String,
    /** One-line explanation, from the shared catalogue. */
    val short: String = "",
    val long: String = "",
)

/** What one word of one ayah is coloured for. */
data class WordRule(
    /** 1-based word index within the ayah. */
    val word: Int,
    val rule: String,
    val code: String,
    val arabic: String,
    val english: String,
    /** Inclusive base-letter index the rule colours, or -1 for the whole word. */
    val firstLetter: Int,
    val lastLetter: Int,
    val wholeWord: Boolean,
)

/** One entry of `data/tajweed-qiraat/rules.json`. */
@Serializable
data class RuleDescription(val short: String = "", val long: String = "")

/**
 * `data/tajweed-qiraat/<slug>.json`. The rule triples are `[code, firstLetter, lastLetter]`, 
 * heterogeneous, so they stay as [JsonElement] until [QiraatTajweed.wordRules] reads them.
 */
@Serializable
data class QiraatTajweedPack(
    val riwayah: String = "",
    val version: Int = 1,
    val legend: List<LegendRow> = emptyList(),
    /** Surah -> ayah -> word -> triples. */
    val rules: Map<String, Map<String, Map<String, List<JsonArray>>>> = emptyMap(),
    val khilafMarkers: Map<String, List<Int>> = emptyMap(),
)

class QiraatTajweed(
    private val descriptions: Map<String, RuleDescription> = emptyMap(),
    private val packs: Map<String, QiraatTajweedPack> = emptyMap(),
) {
    private val legendByCode = HashMap<String, Map<String, LegendEntry>>()

    /** The riwayat that have a pack loaded, in slug order. */
    fun available(): List<String> = packs.keys.sorted()

    /** This riwayah's printed legend, each entry carrying the shared explanation of its rule. */
    fun legend(riwayah: String): List<LegendEntry> {
        val pack = packs[riwayah] ?: return emptyList()
        return pack.legend.map { row ->
            val description = descriptions[row.rule]
            LegendEntry(
                code = row.code,
                rule = row.rule,
                arabic = row.arabic,
                english = row.english,
                short = description?.short ?: "",
                long = description?.long ?: "",
            )
        }
    }

    /** What this riwayah colours in one ayah, word by word. */
    fun wordRules(surahId: Int, ayahId: Int, riwayah: String): List<WordRule> {
        val pack = packs[riwayah] ?: return emptyList()
        val words = pack.rules[surahId.toString()]?.get(ayahId.toString()) ?: return emptyList()
        val byCode = codes(riwayah)

        val out = mutableListOf<WordRule>()
        for (key in words.keys.mapNotNull(String::toIntOrNull).sorted()) {
            for (triple in words[key.toString()].orEmpty()) {
                if (triple.size < 3) continue
                val code = triple[0].jsonPrimitive.content
                val lo = triple[1].jsonPrimitive.intOrNull ?: continue
                val hi = triple[2].jsonPrimitive.intOrNull ?: continue
                val entry = byCode[code]
                out += WordRule(
                    word = key,
                    rule = entry?.rule ?: code,
                    code = code,
                    arabic = entry?.arabic ?: "",
                    english = entry?.english ?: "",
                    firstLetter = lo,
                    lastLetter = hi,
                    wholeWord = lo < 0,
                )
            }
        }
        return out
    }

    /**
     * The ayahs of a surah this riwayah reads differently from Hafs somewhere, the index behind a
     * "show me where these two readings part" list, without walking every ayah's rules.
     */
    fun khilafAyahs(surahId: Int, riwayah: String): List<Int> =
        packs[riwayah]?.khilafMarkers?.get(surahId.toString()) ?: emptyList()

    fun hasKhilaf(surahId: Int, ayahId: Int, riwayah: String): Boolean =
        ayahId in khilafAyahs(surahId, riwayah)

    /** What a rule key means, in one line and in a paragraph. Shared across every riwayah using it. */
    fun describe(rule: String): RuleDescription? = descriptions[rule]

    /** Every rule key the catalogue explains. */
    fun ruleKeys(): List<String> = descriptions.keys.sorted()

    private fun codes(riwayah: String): Map<String, LegendEntry> =
        legendByCode.getOrPut(riwayah) { legend(riwayah).associateBy { it.code } }
}
