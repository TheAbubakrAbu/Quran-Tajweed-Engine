package com.quranengine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The printed mushaf: twenty riwayat as page-exact facsimiles, and the page table each one is
 * actually paginated by.
 *
 * A riwayah's pagination is NOT Hafs' pagination. Readings merge and split ayahs and spell words
 * differently, so the same ayah sits on a different page in Warsh's print than in Hafs'. The page
 * numbers on `quran.json`'s ayahs are the Madani (Hafs) ones; [page] is that riwayah's own. Every
 * facsimile is exactly 604 pages on the Madani division, so PDF page N is mushaf page N with no
 * offset table.
 *
 * Twelve of the twenty ship their printed mushaf and page table but no text: their text is
 * machine-extracted and not yet proofread, so it is not published, and the line and tajweed data
 * that index into it stay out with it. [RiwayahEntry.textIncluded] says which is which.
 *
 * See `../../docs/10-mushaf.md`.
 */
@Serializable
data class RiwayahEntry(
    /** Slug, e.g. `"warsh"`. */
    val riwayah: String,
    /** The tag the Al-Islam app stores for this riwayah (`""` for Hafs). */
    val tag: String,
    val name: String,
    val nameArabic: String,
    /** The qiraah's imam, e.g. `"Nafi"`. */
    val imam: String,
    val imamArabic: String,
    /** The JSON spells this with a trailing capital AH, unlike every other camelCase key. */
    @SerialName("narratorDiedAH") val narratorDiedAH: Int,
    /** Path to the facsimile, relative to `data/mushaf/`. One solid xz stream over the PDF. */
    val pdf: String,
    val pdfBytes: Long,
    val pages: String,
  /** Null when the riwayah's text (and so its line table), is not published. */
    val lines: String? = null,
    /** Null when the riwayah has no tajweed pack. */
    val tajweed: String? = null,
    val textIncluded: Boolean,
)

@Serializable
data class MushafIndex(
    val totalPages: Int = 604,
    val note: String? = null,
    val riwayat: List<RiwayahEntry> = emptyList(),
)

/** `data/mushaf/pages/<slug>.json`: surah id -> ayah id -> page. */
@Serializable
data class MushafPageTable(
    val riwayah: String = "",
    val totalPages: Int = 604,
    val pages: Map<String, Map<String, Int>> = emptyMap(),
)

/** `data/mushaf/lines/<slug>.json`: surah id -> ayah id -> the offsets a printed line starts at. */
@Serializable
data class MushafLineTable(
    val riwayah: String = "",
    val version: Int = 1,
    val lineBreaks: Map<String, Map<String, List<Int>>> = emptyMap(),
)

/** A surah+ayah pair by number: what the page tables index and return. */
data class VerseRef(val surah: Int, val ayah: Int)

class Mushaf(
    private val index: MushafIndex? = null,
    private val pageTables: Map<String, MushafPageTable> = emptyMap(),
    private val lineTables: Map<String, MushafLineTable> = emptyMap(),
) {
    private val byRiwayah: Map<String, RiwayahEntry> = riwayat().associateBy { it.riwayah }

    /** Built the first time a riwayah is asked for by page. */
    private val onPage = HashMap<String, Map<Int, List<VerseRef>>>()

    /** Every riwayah, in the classical order of the Ten Qiraat. */
    fun riwayat(): List<RiwayahEntry> = index?.riwayat ?: emptyList()

    /** Only the riwayat whose text this engine publishes (the eight verified ones). */
    fun riwayatWithText(): List<RiwayahEntry> = riwayat().filter { it.textIncluded }

    fun riwayah(slug: String): RiwayahEntry? = byRiwayah[slug]

    /** 604 for every facsimile in the set. */
    fun totalPages(): Int = index?.totalPages ?: 604

    /**
     * The facsimile's path, relative to `data/mushaf/`. It is one solid xz stream over the PDF:
     * decompress it before handing the bytes to a PDF renderer.
     */
    fun pdfPath(slug: String): String? = byRiwayah[slug]?.pdf

    /** The page an ayah is printed on in this riwayah's own mushaf. */
    fun page(surahId: Int, ayahId: Int, riwayah: String = "hafs"): Int? =
        pageTables[riwayah]?.pages?.get(surahId.toString())?.get(ayahId.toString())

    /** Every ayah printed on a page of this riwayah's mushaf, in mushaf order. */
    fun ayahsOnPage(page: Int, riwayah: String = "hafs"): List<VerseRef> =
        pageIndex(riwayah)[page] ?: emptyList()

    /** What a "go to page 213" jump lands on. */
    fun firstAyahOfPage(page: Int, riwayah: String = "hafs"): VerseRef? =
        ayahsOnPage(page, riwayah).firstOrNull()

    /**
     * The character offsets into the ayah's own text at which this riwayah's print starts a new
   * line. Null when the riwayah's text (and so its line table), is not published.
     */
    fun lineBreaks(surahId: Int, ayahId: Int, riwayah: String = "hafs"): List<Int>? =
        lineTables[riwayah]?.lineBreaks?.get(surahId.toString())?.get(ayahId.toString())

    /** Whether `tajweed-qiraat/<slug>.json` exists for this riwayah. */
    fun hasTajweedPack(riwayah: String): Boolean = byRiwayah[riwayah]?.tajweed != null

    private fun pageIndex(riwayah: String): Map<Int, List<VerseRef>> = onPage.getOrPut(riwayah) {
        val table = pageTables[riwayah]?.pages ?: return@getOrPut emptyMap()
        val index = LinkedHashMap<Int, MutableList<VerseRef>>()
        for (surah in table.keys.mapNotNull(String::toIntOrNull).sorted()) {
            val ayahs = table[surah.toString()] ?: continue
            for (ayah in ayahs.keys.mapNotNull(String::toIntOrNull).sorted()) {
                val page = ayahs[ayah.toString()] ?: continue
                index.getOrPut(page) { mutableListOf() }.add(VerseRef(surah, ayah))
            }
        }
        index
    }
}
