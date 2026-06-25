package com.quranengine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Data models for the Quran Tajweed Engine. Mirrors the JSON shapes in `/data` and the JS reference
 * (`packages/quran-engine-js/src/*.js`). `@SerialName` annotations map to the camelCase JSON keys.
 *
 * All models tolerate unknown/extra keys (the loader uses `Json { ignoreUnknownKeys = true }`), so the
 * data files can carry fields a given port does not model (e.g. `revelationExceptions`, `juzChangesWithinSurah`).
 */

/** A single ayah (verse). Mirrors the JS `Ayah` typedef and `quran.json[].ayahs[]`. */
@Serializable
data class Ayah(
    @SerialName("id") val id: Int,
    @SerialName("textArabic") val textArabic: String,
    @SerialName("textTransliteration") val textTransliteration: String = "",
    @SerialName("textEnglishSaheeh") val textEnglishSaheeh: String = "",
    @SerialName("textEnglishMustafa") val textEnglishMustafa: String = "",
    @SerialName("juz") val juz: Int? = null,
    @SerialName("page") val page: Int? = null,
    @SerialName("wordCount") val wordCount: Int? = null,
    @SerialName("letterCount") val letterCount: Int? = null,
)

/** A surah (chapter). Mirrors the JS `Surah` typedef and `quran.json[]`. */
@Serializable
data class Surah(
    @SerialName("id") val id: Int,
    @SerialName("type") val type: String,                // "makkan" | "madinan"
    @SerialName("nameArabic") val nameArabic: String,
    @SerialName("nameTransliteration") val nameTransliteration: String,
    @SerialName("nameEnglish") val nameEnglish: String,
    @SerialName("numberOfAyahs") val numberOfAyahs: Int,
    @SerialName("pageStart") val pageStart: Int? = null,
    @SerialName("pageEnd") val pageEnd: Int? = null,
    @SerialName("numberOfPages") val numberOfPages: Int? = null,
    @SerialName("firstJuz") val firstJuz: Int? = null,
    @SerialName("lastJuz") val lastJuz: Int? = null,
    @SerialName("juzs") val juzs: List<Int>? = null,
    @SerialName("revelationOrder") val revelationOrder: Int? = null,
    @SerialName("similarNames") val similarNames: List<String>? = null,
    @SerialName("wordCount") val wordCount: Int? = null,
    @SerialName("letterCount") val letterCount: Int? = null,
    @SerialName("ayahs") val ayahs: List<Ayah>,
)

/** A juz (para) boundary entry. Mirrors the JS `JuzEntry` typedef and `juz.json[]`. */
@Serializable
data class JuzEntry(
    @SerialName("id") val id: Int,
    @SerialName("nameArabic") val nameArabic: String,
    @SerialName("nameTransliteration") val nameTransliteration: String,
    @SerialName("startSurah") val startSurah: Int,
    @SerialName("startAyah") val startAyah: Int,
    @SerialName("endSurah") val endSurah: Int,
    @SerialName("endAyah") val endAyah: Int,
)

/** A reciter. Mirrors the JS `Reciter` typedef and `reciters.json[]`. */
@Serializable
data class Reciter(
    @SerialName("id") val id: String,                    // "{name}|{qiraah??'Hafs'}|{surahLink}"
    @SerialName("name") val name: String,
    @SerialName("ayahIdentifier") val ayahIdentifier: String,
    @SerialName("ayahBitrate") val ayahBitrate: String,  // string, used verbatim
    @SerialName("surahLink") val surahLink: String,
    @SerialName("qiraah") val qiraah: String? = null,    // null => Hafs
    @SerialName("group") val group: String? = null,
)

/**
 * A pre-computed tajweed annotation from `data/tajweed/NNN.json` / `tajweed-annotations.json`.
 * `start`/`end` are UTF-16 code-unit offsets into the ayah's `textArabic`.
 */
@Serializable
data class TajweedAnnotation(
    @SerialName("start") val start: Int,
    @SerialName("end") val end: Int,
    @SerialName("rule") val rule: String,
)

/** One ayah's worth of annotations, as stored in `tajweed-annotations.json[]`. */
@Serializable
data class TajweedAyahAnnotations(
    @SerialName("surah") val surah: Int,
    @SerialName("ayah") val ayah: Int,
    @SerialName("annotations") val annotations: List<TajweedAnnotation>,
)

/**
 * A resolved, colored tajweed span over an ayah's text. `text` is the exact UTF-16 slice
 * `ayahText.substring(start, end)`; `colorHex` is the rule's canonical color from `tajweed-rules.json`.
 */
data class TajweedSpan(
    val start: Int,
    val end: Int,
    val rule: String,
    val text: String,
    val colorHex: String?,
)

/** A parsed ayah reference like "2:255". Mirrors the JS `{surah, ayah}` return of `parseReference`. */
data class AyahReference(
    val surah: Int,
    val ayah: Int? = null,
)

/** A surah+ayah pair used when iterating (e.g. juz/page membership). */
data class SurahAyah(
    val surah: Surah,
    val ayah: Ayah,
)

// ---- tajweed-rules.json (categories -> colorHex) -----------------------------------

@Serializable
data class TajweedCategory(
    @SerialName("id") val id: String,
    @SerialName("colorHex") val colorHex: String? = null,
)

@Serializable
data class TajweedRules(
    @SerialName("categories") val categories: List<TajweedCategory> = emptyList(),
)
