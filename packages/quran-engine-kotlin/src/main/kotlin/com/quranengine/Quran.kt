package com.quranengine

/**
 * Quran browsing: surahs, ayahs, qiraat (riwayat) text, global ayah numbering. Ported from
 * `packages/quran-engine-js/src/quran.js`.
 *
 * The engine is data-driven: pass the parsed `quran.json` (and optional qiraat / surah-info) in.
 *
 * @param surahs    parsed `data/quran.json`
 * @param qiraat    map of riwayah key -> qiraah JSON (riwayah -> ("surahId" -> [Ayah-ish {id,text}]))
 * @param surahInfo "about this surah" sources, keyed by surah id
 */
class Quran(
    val surahs: List<Surah>,
    private val qiraat: Map<String, Map<String, List<QiraahVerse>>> = emptyMap(),
    private val surahInfo: Map<Int, List<SurahInfoSource>> = emptyMap(),
) {
    /** A verse override from a qiraah file: `{ id, text }`. */
    data class QiraahVerse(val id: Int, val text: String)

    /** An "about this surah" source: `{ name, contents }`. */
    data class SurahInfoSource(val name: String, val contents: String)

    private val byId: Map<Int, Surah> = surahs.associateBy { it.id }

    /** Cumulative ayah offset per surah id (0-based count of ayahs in all earlier surahs). */
    private val cumulativeOffset: Map<Int, Int>

    /** Total ayah count across the mushaf (6236 for the standard Hafs count). */
    val totalAyahs: Int

    init {
        val offsets = LinkedHashMap<Int, Int>()
        var acc = 0
        for (s in surahs) {
            offsets[s.id] = acc
            acc += s.numberOfAyahs
        }
        cumulativeOffset = offsets
        totalAyahs = acc
    }

    /** All surahs in mushaf order (1..114). */
    fun all(): List<Surah> = surahs

    fun surah(id: Int): Surah? = byId[id]

    fun ayah(surahId: Int, ayahId: Int): Ayah? =
        byId[surahId]?.ayahs?.firstOrNull { it.id == ayahId }

    /**
     * Global ayah number (1-based, 1..6236) used by the ayah-audio CDN and as a stable verse key.
     * @throws IllegalArgumentException for an unknown surah.
     */
    fun globalAyahNumber(surahId: Int, ayahId: Int): Int {
        val off = cumulativeOffset[surahId]
            ?: throw IllegalArgumentException("Unknown surah $surahId")
        return off + ayahId
    }

    /** "About this surah" write-ups (Maududi / Ibn Ashur). */
    fun info(surahId: Int): List<SurahInfoSource> = surahInfo[surahId] ?: emptyList()

    /**
     * Arabic text of an ayah for the requested riwayah. Falls back to the bundled Hafs text
     * (`textArabic`) when no qiraah override exists.
     */
    fun arabicText(surahId: Int, ayahId: Int, riwayah: String? = null): String? {
        val ayah = ayah(surahId, ayahId) ?: return null
        if (riwayah != null && riwayah.lowercase() != "hafs") {
            val verses = qiraat[riwayah.lowercase()]?.get(surahId.toString())
            val match = verses?.firstOrNull { it.id == ayahId }
            if (match != null) return match.text
        }
        return ayah.textArabic
    }

    /** Arabic text with all diacritics/recitation marks stripped (clean reading + search source). */
    fun cleanArabicText(surahId: Int, ayahId: Int, riwayah: String? = null): String? {
        val raw = arabicText(surahId, ayahId, riwayah) ?: return null
        return Text.removingArabicDiacriticsAndSigns(raw)
    }

    /** Every ayah with its surah, in mushaf order. */
    fun eachAyah(): Sequence<SurahAyah> = sequence {
        for (surah in surahs) {
            for (ayah in surah.ayahs) yield(SurahAyah(surah, ayah))
        }
    }
}
