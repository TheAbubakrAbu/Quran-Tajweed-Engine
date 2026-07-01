package com.quranengine

/**
 * Quran browsing: surahs, ayahs, qiraat (riwayat) text, global ayah numbering. Ported from
 * `packages/quran-engine-js/src/quran.js`.
 *
 * The engine is data-driven: pass the parsed `quran.json` (and optional qiraat / surah-info) in.
 *
 * @param surahs       parsed `data/quran.json`
 * @param qiraat       map of riwayah key -> qiraah JSON (riwayah -> ("surahId" -> [Ayah-ish {id,text}]))
 * @param surahInfo    "about this surah" sources, keyed by surah id
 * @param qiraatCounts riwayah key -> ("surahId" -> ayah count) from `data/qiraat-counts.json`
 */
class Quran(
    val surahs: List<Surah>,
    private val qiraat: Map<String, Map<String, List<QiraahVerse>>> = emptyMap(),
    private val surahInfo: Map<Int, List<SurahInfoSource>> = emptyMap(),
    private val qiraatCounts: Map<String, Map<String, Int>> = emptyMap(),
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
     * Resolve a surah counted from the END of the mushaf: 1 -> An-Nas (114), 2 -> Al-Falaq ... 114 ->
     * Al-Fatihah. Mirrors the search-bar `-N` shorthand (companion to JuzPage.juzFromEnd). Returns
     * null for n outside 1..114.
     */
    fun surahFromEnd(n: Int): Surah? {
        if (n < 1 || n > surahs.size) return null
        return surah(surahs.size + 1 - n)
    }

    /** Whether an ayah is a sajdah (prostration) ayah — carries the U+06E9 mark. */
    fun isSajdahAyah(surahId: Int, ayahId: Int): Boolean =
        (ayah(surahId, ayahId)?.textArabic ?: "").contains(SAJDAH_MARK)

    /** Whether a mushaf page boundary falls inside this surah. Mirrors `Surah.pageChangesWithinSurah`. */
    fun pageChangesWithinSurah(surahId: Int): Boolean {
        val s = surah(surahId) ?: return false
        if ((s.numberOfPages ?: 1) > 1) return true
        return s.ayahs.mapNotNull { it.page }.toSet().size > 1
    }

    /** Whether a juz boundary falls inside this surah. Mirrors `Surah.juzChangesWithinSurah`. */
    fun juzChangesWithinSurah(surahId: Int): Boolean {
        val s = surah(surahId) ?: return false
        if ((s.juzs?.size ?: 0) > 1) return true
        if (s.firstJuz != null && s.lastJuz != null && s.firstJuz != s.lastJuz) return true
        return s.ayahs.mapNotNull { it.juz }.toSet().size > 1
    }

    /** Whether a page OR juz boundary falls inside this surah. Mirrors `Surah.pageOrJuzChangesWithinSurah`. */
    fun pageOrJuzChangesWithinSurah(surahId: Int): Boolean =
        pageChangesWithinSurah(surahId) || juzChangesWithinSurah(surahId)

    /**
     * The 15 sajdah (prostration) ayahs, in mushaf order, detected by the U+06E9 mark in the Arabic
     * text. Mirrors `sajdahAyahs()` in `quran.js`.
     */
    fun sajdahAyahs(): List<SurahAyah> =
        eachAyah().filter { it.ayah.textArabic.contains(SAJDAH_MARK) }.toList()

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

    /**
     * Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs every ayah exists;
     * other riwayat merge/split some ayahs, so a Hafs ayah "exists" iff the riwayah's feed carries an
     * ayah with that id (its feeds are numbered contiguously 1..count, so this is `ayahId <= count`).
     * An unknown/unloaded riwayah falls back to Hafs (exists).
     */
    fun existsInQiraah(surahId: Int, ayahId: Int, riwayah: String? = null): Boolean {
        if (ayah(surahId, ayahId) == null) return false
        val r = (riwayah ?: "").lowercase()
        if (r.isEmpty() || r == "hafs") return true
        val count = qiraatCounts[r]?.get(surahId.toString()) ?: return true
        return ayahId <= count
    }

    /**
     * Ayah count of a surah in the given riwayah — the number of Hafs ayahs that exist there (e.g.
     * Baqarah is 286 in Hafs but 285 in Warsh). Mirrors `Surah.numberOfAyahs(for:)`.
     */
    fun numberOfAyahsInQiraah(surahId: Int, riwayah: String? = null): Int {
        val s = surah(surahId) ?: return 0
        val r = (riwayah ?: "").lowercase()
        if (r.isEmpty() || r == "hafs") return s.numberOfAyahs
        val count = qiraatCounts[r]?.get(surahId.toString()) ?: return s.numberOfAyahs
        return minOf(s.numberOfAyahs, count)
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

    companion object {
        /** ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs. */
        const val SAJDAH_MARK: String = "۩"
    }
}
