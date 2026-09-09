package com.quranengine

import kotlinx.serialization.Serializable

/**
 * Who among the Ten reads a word differently, what they read, and what the difference means.
 *
 * This is the layer the qiraah texts cannot supply. `data/qiraat/` gives each reading its own
 * words, and [QiraatComparison] will align two of them: that answers WHAT each riwayah reads. It
 * cannot say that a form is Hamzah's rather than Nafi's, that it is a passive where Hafs has an
 * active, or that al-Mahdawi held the two to mean the same thing. That is this module, from the
 * Quran.com qiraat matrix.
 *
 * Readers against transmitters: a reading lists [VariantReading.readers] when both of an imam's
 * transmitters follow it, and [VariantReading.transmitters] when the two part company. Segment
 * ranges are 0-based inclusive token indices of the raw Hafs text, null where the builder could
 * not place the word, in which case a consumer shows the word untinted rather than guessing.
 *
 * Only the eight riwayat whose text this engine publishes appear in [QiraatVariants.places]. The
 * other twelve do appear as attributions, which is right: attributing a reading to Ibn Dhakwan
 * says nothing about the state of his extracted text.
 *
 * See `../../docs/21-qiraat-variants.md`.
 */

/** One of the ten imams. */
@Serializable
data class VariantReader(
    val id: Int,
    val name: String,
    val abbreviation: String = "",
    val city: String = "",
    val position: Int = 99,
)

/** One of the twenty riwayat. */
@Serializable
data class VariantTransmitter(
    val id: Int,
    val name: String,
    val reader: Int,
    /** This engine's own slug, so a consumer can join to `data/qiraat` and `data/mushaf`. */
    val riwayah: String? = null,
    /** False for the twelve riwayat whose extracted text is not published. */
    val textPublished: Boolean = false,
)

/** One form of a word, and who reads it. */
@Serializable
data class VariantReading(
    val text: String,
    val transliteration: String = "",
    val english: String = "",
    val explanation: String = "",
    val grammaticalForm: String = "",
    val rootLetters: String = "",
    /** Imams whose two transmitters both read it. */
    val readers: List<Int> = emptyList(),
    /** Individual transmitters, where an imam's two differ. */
    val transmitters: List<Int> = emptyList(),
)

/** Where the word sits. [span] is null where the builder could not place it. */
@Serializable
data class VariantSegment(val ayah: String, val span: List<Int>? = null) {
    /** The span as a range, or null when it is absent or malformed. */
    val range: IntRange?
        get() = span?.takeIf { it.size == 2 && it[0] >= 0 && it[1] >= it[0] }?.let { it[0]..it[1] }
}

/** One word of an ayah that the Ten read differently. */
@Serializable
data class Juncture(
    val word: String = "",
    val category: String = "",
    val segments: List<VariantSegment> = emptyList(),
    val readings: List<VariantReading> = emptyList(),
    val note: String = "",
)

/** `data/qiraat-variants.json`. */
@Serializable
data class QiraatVariantsFile(
    val readers: Map<String, VariantReader> = emptyMap(),
    val transmitters: Map<String, VariantTransmitter> = emptyMap(),
    val ayahs: Map<String, List<Juncture>> = emptyMap(),
)

/** One row of `data/qiraat-places.json`. */
@Serializable
data class QiraatPlaceRow(
    val word: List<Int> = emptyList(),
    val letter: List<Int> = emptyList(),
)

/** `data/qiraat-places.json`. */
@Serializable
data class QiraatPlacesFile(
    val riwayat: Map<String, Map<String, Map<String, QiraatPlaceRow>>> = emptyMap(),
)

/**
 * One ayah where a riwayah differs from Hafs.
 *
 * Two kinds, because they are found two ways and a consumer may want only the first: a [word]
 * index is a word dropped, added or spelled differently, which a text diff finds; a [letter] index
 * is a word the printed mushaf marks as read with other vowels over the SAME skeleton, which no
 * text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).
 */
data class QiraatPlace(val ayah: Int, val word: List<Int>, val letter: List<Int>)

/** A reciter who published both readings, and the two feeds they live in. */
@Serializable
data class VariantAudioSource(
    /** `"file"` for a whole per-verse recording, `"span"` for a seek inside a full-surah one. */
    val kind: String,
    val reciter: String,
    val hafsBase: String,
    val riwayahBase: String,
)

/** `data/qiraat-variant-audio.json`. */
@Serializable
data class QiraatVariantAudioFile(
    val sources: List<VariantAudioSource> = emptyList(),
    val riwayat: Map<String, Map<String, List<List<Int>>>> = emptyMap(),
)

/** One side of a paired recording. [startMs] and [endMs] are null for a whole per-verse file. */
data class VariantClip(val url: String, val startMs: Int?, val endMs: Int?)

/** The same reciter reading a verse both ways. */
data class VariantAudioPair(
    val reciter: String,
    val hafs: VariantClip,
    val riwayah: VariantClip,
)

class QiraatVariants(
    private val file: QiraatVariantsFile = QiraatVariantsFile(),
    private val placesFile: QiraatPlacesFile = QiraatPlacesFile(),
    private val audioFile: QiraatVariantAudioFile = QiraatVariantAudioFile(),
) {

    val isLoaded: Boolean get() = file.ayahs.isNotEmpty()

    /** The words of this ayah that the Ten read differently, in corpus order. */
    fun junctures(surahId: Int, ayahId: Int): List<Juncture> =
        file.ayahs["$surahId:$ayahId"] ?: emptyList()

    /** Whether the ayah carries any. Only 1,409 of the 6,236 do. */
    fun has(surahId: Int, ayahId: Int): Boolean = !file.ayahs["$surahId:$ayahId"].isNullOrEmpty()

    fun reader(id: Int): VariantReader? = file.readers["$id"]

    fun transmitter(id: Int): VariantTransmitter? = file.transmitters["$id"]

    /** Every transmitter reading a form: an imam's own pair, plus any listed individually. */
    fun transmittersFollowing(reading: VariantReading): List<VariantTransmitter> {
        val out = ArrayList<VariantTransmitter>()
        val seen = HashSet<Int>()
        for (readerId in reading.readers) {
            for (transmitter in file.transmitters.values.filter { it.reader == readerId }.sortedBy { it.id }) {
                if (seen.add(transmitter.id)) out.add(transmitter)
            }
        }
        for (id in reading.transmitters) {
            val transmitter = transmitter(id) ?: continue
            if (seen.add(id)) out.add(transmitter)
        }
        return out
    }

    /**
     * The reading a riwayah follows at a juncture, by engine slug.
     *
     * A reading names an imam when BOTH his transmitters follow it, and names a transmitter when
     * the two part company, so a transmitter named on one reading overrides his imam's listing on
     * a sibling. Look for him across the whole juncture before falling back to the imams: at
     * 12:109 ʿĀṣim is named on نوحي while Shuʿbah is named on يوحى, and Shuʿbah recites يوحى.
     */
    fun readingFor(juncture: Juncture, riwayah: String): VariantReading? =
        juncture.readings.firstOrNull { reading ->
            reading.transmitters.any { transmitter(it)?.riwayah == riwayah }
        } ?: juncture.readings.firstOrNull { reading ->
            reading.readers.any { readerId ->
                file.transmitters.values.any { it.reader == readerId && it.riwayah == riwayah }
            }
        }

    /**
     * Who reads a form, rendered the way the printed sources do: the imams first in their
     * canonical order, then any lone transmitters with their imam named in parentheses.
     */
    fun attribution(reading: VariantReading): String {
        val readers = reading.readers.mapNotNull { reader(it) }
            .sortedBy { it.position }
            .map { it.abbreviation }
        val transmitters = reading.transmitters.mapNotNull { transmitter(it) }
            .sortedWith(compareBy({ reader(it.reader)?.position ?: 99 }, { it.id }))
            .map { transmitter ->
                val imam = reader(transmitter.reader)?.abbreviation.orEmpty()
                if (imam.isEmpty()) transmitter.name else "${transmitter.name} ($imam)"
            }
        val parts = ArrayList<String>()
        if (readers.isNotEmpty()) parts.add(readers.joinToString(", "))
        if (transmitters.isNotEmpty()) parts.add(transmitters.joinToString(", "))
        return parts.joinToString(" · ")
    }

    /** Where a riwayah differs from Hafs in a surah, in ayah order. */
    fun places(riwayah: String, surahId: Int): List<QiraatPlace> {
        val table = placesFile.riwayat[riwayah]?.get("$surahId") ?: return emptyList()
        return table.keys.mapNotNull(String::toIntOrNull).sorted().mapNotNull { ayah ->
            val row = table["$ayah"] ?: return@mapNotNull null
            QiraatPlace(ayah, row.word, row.letter)
        }
    }

    /** The riwayat [places] can answer for: the published ones. */
    fun riwayatWithPlaces(): List<String> = placesFile.riwayat.keys.sorted()

    /**
     * One reciter reading the verse both ways, for the four riwayat where such a recording exists.
     *
     * The rest carry none: no reciter published both sides with timings. A pair drawn from two
     * shaykhs would differ in voice, pace and maqam as well, and teach nothing about the variant.
     * The honest rendering is "no recording", never a button that does nothing.
     */
    fun audio(riwayah: String, surahId: Int, ayahId: Int): VariantAudioPair? {
        val rows = audioFile.riwayat[riwayah]?.get("$surahId") ?: return null
        val row = rows.firstOrNull { it.firstOrNull() == ayahId } ?: return null
        if (row.size < 6) return null
        val source = audioFile.sources.getOrNull(row[1]) ?: return null
        val isSpan = source.kind == "span"
        val name = if (isSpan) "%03d.mp3".format(surahId) else "%03d%03d.mp3".format(surahId, ayahId)
        fun clip(base: String, start: Int, end: Int) = VariantClip(
            url = "$base/$name",
            startMs = if (isSpan) start else null,
            endMs = if (isSpan) end else null,
        )
        return VariantAudioPair(
            reciter = source.reciter,
            hafs = clip(source.hafsBase, row[2], row[3]),
            riwayah = clip(source.riwayahBase, row[4], row[5]),
        )
    }

    /** The riwayat that have any paired recordings at all. */
    fun riwayatWithAudio(): List<String> = audioFile.riwayat.keys.sorted()

    /** Corpus size: ayahs carrying a variant, junctures, and readings. */
    fun count(): Triple<Int, Int, Int> = Triple(
        file.ayahs.size,
        file.ayahs.values.sumOf { it.size },
        file.ayahs.values.sumOf { rows -> rows.sumOf { it.readings.size } },
    )
}
