package com.quranengine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Muqaṭṭaʿāt — the disconnected opening letters of 29 surahs (e.g. الٓمٓ). The mushaf prints them
 * joined with maddah marks but they are recited letter by letter ("Alif Lām Mīm"), so this exposes,
 * per opening ayah, the individual letters, a transliteration, and the fully-vocalized Arabic
 * spelling (whose long vowels carry the madd-lāzim maddah U+0653, so a tajweed pass colours them
 * like the real ayah).
 *
 * Ported from `packages/quran-engine-js/src/muqattaat.js`. Data: `data/muqattaat.json`. Ash-Shūra
 * (42) is the one surah whose muqattaʿāt span two ayahs (1: Ḥā Mīm, 2: ʿAyn Sīn Qāf).
 */

/** Pronunciation of one muqattaʿāt opening ayah. Mirrors the JS `MuqattaatPronunciation` typedef. */
@Serializable
data class MuqattaatPronunciation(
    @SerialName("surah") val surah: Int,
    @SerialName("ayah") val ayah: Int,
    @SerialName("letters") val letters: List<String> = emptyList(),  // bare letters, e.g. ["ا","ل","م"]
    @SerialName("transliteration") val transliteration: String = "", // "Alif Lām Mīm"
    @SerialName("spelledOutArabic") val spelledOutArabic: String = "", // fully vocalized
)

/** File shape of `data/muqattaat.json`: `{ letterNames, ayahs }`. */
@Serializable
data class MuqattaatData(
    @SerialName("letterNames") val letterNames: Map<String, String> = emptyMap(),
    @SerialName("ayahs") val ayahs: List<MuqattaatPronunciation> = emptyList(),
)

/** Accessor over the muqattaʿāt openings. */
class Muqattaat(data: MuqattaatData = MuqattaatData()) {
    private val letterNames: Map<String, String> = data.letterNames
    private val ayahs: List<MuqattaatPronunciation> = data.ayahs
    private val byKey: Map<String, MuqattaatPronunciation> = ayahs.associateBy { "${it.surah}:${it.ayah}" }

    /** Every muqattaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd ayah). */
    fun all(): List<MuqattaatPronunciation> = ayahs

    /** Pronunciation for a muqattaʿāt ayah, or null if that ayah doesn't open with them. */
    fun pronunciation(surahId: Int, ayahId: Int): MuqattaatPronunciation? = byKey["$surahId:$ayahId"]

    /** Transliteration of a single muqattaʿāt letter, e.g. "ا" -> "Alif", or null if unknown. */
    fun letterName(letter: String): String? = letterNames[letter]
}
