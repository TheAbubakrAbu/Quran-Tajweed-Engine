package com.quranengine

/**
 * Arabic text utilities. Ported from `packages/quran-engine-js/src/text.js` (which mirrors the Swift
 * source). Everything operates on Unicode code points, so behaviour is font-independent.
 *
 * This port implements the pieces the "core" search path needs: clean-arabic (display + search source),
 * the `cleanSearch` normalizer, tokenization, digit folding and Arabic-letter detection. The boolean
 * grammar, silent-letter lenient variant and exact/tashkeel blobs are intentionally omitted (documented
 * as skipped in README) since the core search uses substring + phrase-prefix matching only.
 */
object Text {

    /** Canonical Arabic fold map applied before stripping marks during search normalization. */
    private val CANONICAL_ARABIC_MAP: Map<Char, String> = mapOf(
        'ٰ' to "ا", // dagger alif
        'ٱ' to "ا", // alif wasla
        'أ' to "ا", 'إ' to "ا", 'آ' to "ا", 'ٲ' to "ا", 'ٳ' to "ا", 'ٵ' to "ا",
        'ؤ' to "و", 'ئ' to "ي", 'ء' to "", 'ٴ' to "", 'ٶ' to "و", 'ٷ' to "و", 'ٸ' to "ي",
        'ۥ' to "و", // small waw
        'ۦ' to "ي", // small yeh
        'ى' to "ا", // alif maqsura -> alif
        'ة' to "ه", // teh marbuta -> heh
    )

    private val KEPT_OPERATORS = setOf('&', '|', '!', '#')

    /**
     * Remove Quranic recitation marks / diacritics (the "clean Arabic" used for display + search).
     * Mirrors `removingArabicDiacriticsAndSigns`.
     */
    fun removingArabicDiacriticsAndSigns(text: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val charCount = Character.charCount(cp)
            when {
                cp == 0x0671 -> sb.append('ا') // hamzat wasl -> alif
                (cp in 0x064b..0x065f) ||
                    (cp in 0x06d6..0x06ed) ||
                    cp == 0x0670 || cp == 0x0657 || cp == 0x0674 || cp == 0x0656 -> {
                    // drop
                }
                else -> sb.appendCodePoint(cp)
            }
            i += charCount
        }
        return sb.toString()
    }

    /** Convert Arabic-Indic and Eastern-Arabic digits to Western. */
    fun arabicDigitsToWestern(text: String): String {
        val sb = StringBuilder(text.length)
        for (ch in text) {
            sb.append(
                when (ch) {
                    '٠', '۰' -> '0'
                    '١', '۱' -> '1'
                    '٢', '۲' -> '2'
                    '٣', '۳' -> '3'
                    '٤', '۴' -> '4'
                    '٥', '۵' -> '5'
                    '٦', '۶' -> '6'
                    '٧', '۷' -> '7'
                    '٨', '۸' -> '8'
                    '٩', '۹' -> '9'
                    else -> ch
                }
            )
        }
        return sb.toString()
    }

    /** Collapse runs of whitespace into single spaces. */
    fun collapsingWhitespace(text: String): String =
        text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    /**
     * The core search normalizer. Mirrors `cleanSearch`:
     *   fold Arabic carriers -> strip punctuation/symbols/combining-marks (except & | ! #)
     *   -> lowercase -> collapse whitespace.
     */
    fun cleanSearch(text: String, whitespace: Boolean = false): String {
        // 1. canonical Arabic fold
        var folded = text
        for ((k, v) in CANONICAL_ARABIC_MAP) {
            if (folded.indexOf(k) >= 0) folded = folded.replace(k.toString(), v)
        }
        // 2. strip "unwanted" chars: punctuation, symbols, all combining marks; keep the 4 operators.
        val sb = StringBuilder()
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            val charCount = Character.charCount(cp)
            if (cp <= 0xFFFF && KEPT_OPERATORS.contains(cp.toChar())) {
                sb.append(cp.toChar())
            } else if (!isPunctuationSymbolOrMark(cp)) {
                sb.appendCodePoint(cp)
            }
            i += charCount
        }
        var cleaned = collapsingWhitespace(sb.toString().lowercase())
        if (whitespace) cleaned = cleaned.trim()
        return cleaned
    }

    /** Tokenize a cleaned blob on spaces. */
    fun searchTokens(cleanedText: String): List<String> =
        cleanedText.split(" ").filter { it.isNotEmpty() }

    private val ARABIC_LETTER_RANGES = listOf(
        0x0600 to 0x06ff, 0x0750 to 0x077f, 0x08a0 to 0x08ff,
        0xfb50 to 0xfdff, 0xfe70 to 0xfeff, 0x1ee00 to 0x1eeff,
    )

    /** True if the string contains any Arabic-script letter. */
    fun containsArabicLetters(text: String): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            if (ARABIC_LETTER_RANGES.any { (lo, hi) -> cp in lo..hi }) return true
            i += Character.charCount(cp)
        }
        return false
    }

    /**
     * Approximates the JS `/\p{P}|\p{S}|\p{M}/u` test: Unicode punctuation, symbols, or combining marks.
     * Uses `Character.getType` so it works for all code points (incl. supplementary).
     */
    private fun isPunctuationSymbolOrMark(cp: Int): Boolean {
        return when (Character.getType(cp)) {
            // Marks (\p{M})
            Character.NON_SPACING_MARK.toInt(),
            Character.COMBINING_SPACING_MARK.toInt(),
            Character.ENCLOSING_MARK.toInt(),
            // Punctuation (\p{P})
            Character.CONNECTOR_PUNCTUATION.toInt(),
            Character.DASH_PUNCTUATION.toInt(),
            Character.START_PUNCTUATION.toInt(),
            Character.END_PUNCTUATION.toInt(),
            Character.INITIAL_QUOTE_PUNCTUATION.toInt(),
            Character.FINAL_QUOTE_PUNCTUATION.toInt(),
            Character.OTHER_PUNCTUATION.toInt(),
            // Symbols (\p{S})
            Character.MATH_SYMBOL.toInt(),
            Character.CURRENCY_SYMBOL.toInt(),
            Character.MODIFIER_SYMBOL.toInt(),
            Character.OTHER_SYMBOL.toInt() -> true
            else -> false
        }
    }
}
