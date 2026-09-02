package com.quranengine

import kotlinx.serialization.Serializable

/**
 * The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name and
 * transliteration, and - the part that matters for tajweed - its WEIGHT.
 *
 * Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
 * pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the
 * divine name), and alif has no weight of its own at all: it inherits the letter before it. That
 * single fact is behind a large share of beginner mistakes, and it is a property of the letter, not
 * of any particular verse, so it lives here beside the letter and not in the annotation corpus.
 *
 * Also carried: the letters outside the 28, the six Persian/Urdu letters some printed mushafs use,
 * the Eastern-Arabic numerals, the tashkeel marks, and the waqf (stopping) signs.
 *
 * See `../../docs/16-arabic-alphabet.md`.
 */
@Serializable
data class ArabicLetter(
    val id: Int = 0,
    /** The isolated form. */
    val letter: String = "",
    /** Final, medial and initial, as the source records them. */
    val forms: List<String> = emptyList(),
    val name: String = "",
    val transliteration: String = "",
    val showTashkeel: Boolean = false,
    val sound: String = "",
    /** "light", "heavy", "conditional", "followsPrevious" - or null where none is recorded. */
    val weight: String? = null,
    /** Why, in one sentence. */
    val weightRule: String? = null,
)

@Serializable
data class Tashkeel(
    val english: String = "",
    val arabic: String = "",
    val mark: String = "",
    val transliteration: String = "",
)

@Serializable
data class StoppingSign(val symbol: String = "", val title: String = "")

@Serializable
data class ArabicNumeral(
    val number: String = "",
    val name: String = "",
    val transliteration: String = "",
    val englishNumber: String = "",
)

/** `data/arabic-alphabet.json`. */
@Serializable
data class ArabicAlphabetFile(
    val description: String = "",
    val weights: Map<String, String> = emptyMap(),
    val standardLetters: List<ArabicLetter> = emptyList(),
    val otherLetters: List<ArabicLetter> = emptyList(),
    val nonArabicScriptLetters: List<ArabicLetter> = emptyList(),
    val numbers: List<ArabicNumeral> = emptyList(),
    val tashkeel: List<Tashkeel> = emptyList(),
    val stoppingSigns: List<StoppingSign> = emptyList(),
    val stoppingSignsSource: String = "",
)

class ArabicAlphabet(private val file: ArabicAlphabetFile = ArabicAlphabetFile()) {

    /** The 28 letters of the alphabet, in order. */
    fun letters(): List<ArabicLetter> = file.standardLetters

    /** Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28. */
    fun otherLetters(): List<ArabicLetter> = file.otherLetters

    /** The Persian/Urdu letters some printed mushafs use for non-Arabic sounds. */
    fun nonArabicScriptLetters(): List<ArabicLetter> = file.nonArabicScriptLetters

    /** Every letter this reference knows, the 28 first. */
    fun allLetters(): List<ArabicLetter> = letters() + otherLetters() + nonArabicScriptLetters()

    /**
     * One letter by its isolated form. Accepts any of its joining forms too, so a letter lifted out
     * of a word still resolves.
     */
    fun letter(letter: String): ArabicLetter? {
        val wanted = letter.trim()
        if (wanted.isEmpty()) return null
        return allLetters().firstOrNull { it.letter == wanted || wanted in it.forms }
    }

    fun letterById(id: Int): ArabicLetter? = allLetters().firstOrNull { it.id == id }

    /** The tajweed weight of a letter, or null when the reference records none. */
    fun weight(letter: String): String? = letter(letter)?.weight

    /** What a weight name means, in one line. */
    fun weightDescriptions(): Map<String, String> = file.weights

    /** The letters pronounced full - the isti'la letters. */
    fun heavyLetters(): List<ArabicLetter> = letters().filter { it.weight == "heavy" }

    fun tashkeel(): List<Tashkeel> = file.tashkeel

    /** The waqf signs, with what each one tells the reciter to do. */
    fun stoppingSigns(): List<StoppingSign> = file.stoppingSigns

    fun stoppingSign(symbol: String): StoppingSign? = stoppingSigns().firstOrNull { it.symbol == symbol }

    /** The Eastern-Arabic numerals, 0 through 10. */
    fun numbers(): List<ArabicNumeral> = file.numbers

    fun stoppingSignsSource(): String = file.stoppingSignsSource
}
