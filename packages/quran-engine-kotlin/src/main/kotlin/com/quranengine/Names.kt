package com.quranengine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The 99 Names of Allah (Asma' ul-Husna). Ported from `packages/quran-engine-js/src/names.js`.
 *
 * Thin accessor over `data/names-of-allah.json`.
 */

/** A single Name of Allah. Mirrors the JS `NameOfAllah` typedef and `names-of-allah.json[]`. */
@Serializable
data class NameOfAllah(
    @SerialName("name") val name: String,                       // Arabic
    @SerialName("transliteration") val transliteration: String,
    @SerialName("number") val number: Int,                      // 1..99
    @SerialName("found") val found: String = "",                // ayah references, e.g. "(1:3) (17:110)"
    @SerialName("meaning") val meaning: String = "",
    @SerialName("desc") val desc: String = "",
    @SerialName("otherNames") val otherNames: List<String> = emptyList(),
)

/** Accessor over the 99 Names, ordered by `number`. */
class NamesOfAllah(list: List<NameOfAllah> = emptyList()) {
    /** All names, ordered by number. */
    private val list: List<NameOfAllah> = list.sortedBy { it.number }

    private val byNumber: Map<Int, NameOfAllah> = this.list.associateBy { it.number }

    /** All 99 names, ordered by number. */
    fun all(): List<NameOfAllah> = list

    /** The name with the given [number] (1..99), or null if unknown. */
    fun byNumber(number: Int): NameOfAllah? = byNumber[number]
}
