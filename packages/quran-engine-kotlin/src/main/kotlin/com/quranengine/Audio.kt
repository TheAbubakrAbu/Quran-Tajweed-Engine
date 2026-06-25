package com.quranengine

/**
 * Recitation audio URL builders + reciter directory. Ported from
 * `packages/quran-engine-js/src/audio.js`.
 *
 * Two independent feeds:
 *   - Full-surah  : `surahLink + zeroPad3(surah) + ".mp3"`   (mp3quran.net CDNs)
 *   - Ayah-by-ayah: `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3`
 */

/** Zero-pad to 3 digits: 1 -> "001", 57 -> "057", 114 -> "114". */
internal fun zeroPad3(n: Int): String = n.toString().padStart(3, '0')

/**
 * Full-surah recitation URL.
 * @param surahNumber 1..114
 * @throws IllegalArgumentException if surah out of range or the reciter has no full-surah feed.
 */
fun surahAudioUrl(reciter: Reciter, surahNumber: Int): String {
    require(surahNumber in 1..114) { "surah out of range: $surahNumber" }
    require(reciter.surahLink.isNotEmpty()) { "Reciter \"${reciter.name}\" has no full-surah feed" }
    return "${reciter.surahLink}${zeroPad3(surahNumber)}.mp3"
}

/**
 * Ayah-by-ayah recitation URL. Requires the global ayah number (1..6236); use
 * `Quran.globalAyahNumber(surah, ayah)` to compute it.
 */
fun ayahAudioUrl(reciter: Reciter, globalAyahNumber: Int): String =
    "https://cdn.islamic.network/quran/audio/${reciter.ayahBitrate}/${reciter.ayahIdentifier}/$globalAyahNumber.mp3"

private const val MINSHAWI_FALLBACK_NAME = "Muhammad Al-Minshawi (Murattal)"

/** True if this reciter falls back to Minshawi for individual-ayah audio. */
fun defaultsToMinshawi(reciter: Reciter): Boolean =
    reciter.ayahIdentifier.contains("minshawi") && !reciter.name.contains("Minshawi")

/** Display name to show while ayah audio plays (honest about the fallback). */
fun ayahNowPlayingName(reciter: Reciter): String = when {
    defaultsToMinshawi(reciter) -> MINSHAWI_FALLBACK_NAME
    reciter.qiraah != null -> "${reciter.name} (${reciter.qiraah})"
    else -> reciter.name
}

/** Reciter directory. Sorted by name; lookup by id; filters by feed and qiraah. */
class Reciters(list: List<Reciter>) {
    val list: List<Reciter> = list.sortedBy { it.name }
    private val byId: Map<String, Reciter> = this.list.associateBy { it.id }

    fun all(): List<Reciter> = list

    fun byId(id: String): Reciter? = byId[id]

    /** Reciters that have a full-surah feed (base URL, not a single `.mp3`). */
    fun withSurahFeed(): List<Reciter> =
        list.filter { it.surahLink.isNotEmpty() && !it.surahLink.endsWith(".mp3") }

    /** Reciters for a given riwayah label (null/"hafs" => the default Hafs feeds). */
    fun byQiraah(qiraah: String?): List<Reciter> {
        if (qiraah == null || qiraah.lowercase() == "hafs") return list.filter { it.qiraah == null }
        return list.filter { it.qiraah == qiraah }
    }

    /** Distinct riwayah labels available (excluding default Hafs). */
    fun qiraat(): List<String> =
        list.mapNotNull { it.qiraah }.distinct()
}
