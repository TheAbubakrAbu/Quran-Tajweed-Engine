package com.quranengine

/**
 * Ayah & surah search. Faithful port of `packages/quran-engine-js/src/search.js`.
 *
 * Verse matching is unranked: results come back in mushaf order. The regular (non-boolean) path is a
 * pure substring match of the whole cleaned query against the relevant blob. A small boolean grammar
 * (`& | ! # ^ % $ =`) provides AND/OR/NOT plus whole-word / starts-with / ends-with / exact /
 * tashkeel-sensitive operators. Any query containing a Unicode decimal digit returns no verse results
 * (numeric/refs go via surah search) — checked BEFORE the boolean branch.
 */
class Search(
    private val quran: Quran,
    private val riwayah: String? = null,
) {
    /** Match mode for a boolean term. Mirrors the JS `matchMode` string union. */
    enum class MatchMode { CONTAINS, STARTS_WITH, ENDS_WITH, EXACT, WHOLE_WORD }

    /** A single parsed boolean term. Mirrors the object returned by `parseTerm`. */
    data class BooleanTerm(
        val value: String,
        val negate: Boolean,
        val matchMode: MatchMode,
        val requiresTashkeelMatch: Boolean,
        val tashkeelPattern: String,
        val requiresExactEnglishMatch: Boolean,
        val exactEnglishPhrase: String,
    )

    /** One indexed verse. */
    data class VerseIndexEntry(
        val id: String,            // "surah:ayah"
        val surah: Int,
        val ayah: Int,
        val arabicTashkeelBlob: String,
        val englishExactBlob: String,
        val arabicBlob: String,
        val silentArabicBlob: String,
        val englishBlob: String,
        val arabicTokens: List<String>,
        val silentArabicTokens: List<String>,
        val englishTokens: List<String>,
    )

    private data class SurahIndexEntry(
        val surah: Surah,
        val blob: String,
        val compact: String,
        val upper: String,
    )

    var index: List<VerseIndexEntry> = emptyList()
        private set

    private var surahIndex: List<SurahIndexEntry> = emptyList()

    init {
        rebuild()
        buildSurahIndex()
    }

    fun rebuild() {
        val idx = ArrayList<VerseIndexEntry>(quran.totalAyahs)
        for ((surah, ayah) in quran.eachAyah()) {
            val raw = quran.arabicText(surah.id, ayah.id, riwayah) ?: ""
            val clean = quran.cleanArabicText(surah.id, ayah.id, riwayah) ?: ""
            idx.add(makeEntry(surah.id, ayah.id, raw, clean, ayah.textEnglishSaheeh, ayah.textEnglishMustafa, ayah.textTransliteration))
        }
        index = idx
    }

    /**
     * Search verse text. Returns matches in mushaf order. Verse search rejects any query containing a
     * digit (numeric/refs go via surah search) — checked BEFORE the boolean branch. The regular path
     * is a pure substring match; the boolean grammar handles whole-word / phrase / exact matching.
     */
    fun searchVerses(
        query: String,
        offset: Int = 0,
        limit: Int? = null,
        ignoreSilentLetters: Boolean = false,
    ): List<VerseIndexEntry> {
        val cleaned = Text.cleanSearch(query, whitespace = true)
        if (cleaned.isEmpty()) return emptyList()

        // Reject any query containing a Unicode decimal digit (Char.isDigit covers Arabic-Indic too).
        // Done BEFORE the boolean path, so even a boolean query with a digit returns []. e.g. "allah & 2".
        if (cleaned.any { it.isDigit() }) return emptyList()

        // Boolean grammar?
        if (query.any { it in BOOLEAN_CHARS }) return booleanSearch(query, offset, limit)

        val useArabic = Text.containsArabicLetters(query)
        val silentQuery = if (useArabic && ignoreSilentLetters) {
            Text.cleanSearch(Text.removingSilentArabicLettersForSearch(query), whitespace = true)
        } else {
            ""
        }

        // Pure substring search in mushaf order — word/sentence boundaries DON'T matter (a query
        // matches anywhere it appears). Whole-word/phrase matching lives in the boolean operators.
        fun matches(e: VerseIndexEntry): Boolean {
            return if (useArabic) {
                if (e.arabicBlob.contains(cleaned)) return true
                if (silentQuery.isEmpty()) return false
                e.silentArabicBlob.contains(silentQuery)
            } else {
                e.englishBlob.contains(cleaned)
            }
        }

        return paginate(index.filter(::matches), offset, limit)
    }

    // ---- Boolean search ----------------------------------------------------------
    private fun booleanSearch(query: String, offset: Int, limit: Int?): List<VerseIndexEntry> {
        val useArabic = Text.containsArabicLetters(query)
        val normalized = query.replace("&&", "&").replace("||", "|")
        // Drop any term whose cleaned value is empty — parseTerm-equivalent returns nil in that case.
        val orGroups = normalized.split("|")
            .map { group -> group.split("&").map { parseTerm(it) }.filter { it.value.isNotEmpty() } }
            .filter { it.isNotEmpty() }
        if (orGroups.isEmpty()) return emptyList()

        fun matches(e: VerseIndexEntry): Boolean =
            orGroups.any { andTerms ->
                andTerms.all { term ->
                    val hit = termMatch(e, term, useArabic)
                    if (term.negate) !hit else hit
                }
            }

        return paginate(index.filter(::matches), offset, limit)
    }

    private fun buildSurahIndex() {
        surahIndex = quran.all().map { s ->
            val names = buildList {
                add(s.nameArabic); add(s.nameTransliteration); add(s.nameEnglish)
                s.similarNames?.let { addAll(it) }
            }
            val parts = names + listOf(s.id.toString(), s.nameArabic)
            val blob = Text.cleanSearch(parts.joinToString(" "))
            SurahIndexEntry(
                surah = s,
                blob = blob,
                compact = blob.replace(" ", ""),
                upper = "${s.nameEnglish} ${s.nameTransliteration}".uppercase(),
            )
        }
    }

    /** Search surahs by name, number, "2:255" reference, or makkan/madani. */
    fun searchSurahs(query: String): List<Surah> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return quran.all()

        val norm = Text.cleanSearch(trimmed).replace(" ", "")
        val makkan = listOf("makkah", "makkan", "makki")
        val madinan = listOf("madinah", "madinan", "madina", "madani")
        fun aliasHit(aliases: List<String>) = aliases.any { it.startsWith(norm) || norm.startsWith(it) }
        if (norm.isNotEmpty() && aliasHit(makkan)) return quran.all().filter { it.type == "makkan" }
        if (norm.isNotEmpty() && aliasHit(madinan)) return quran.all().filter { it.type == "madinan" }

        val ref = parseReference(trimmed)
        val cleaned = Text.cleanSearch(trimmed.replace(":", ""))
        val compact = cleaned.replace(" ", "")
        val upper = trimmed.uppercase()
        val numeric = ref?.surah ?: toNumber(cleaned)

        return surahIndex.filter { e ->
            numeric == e.surah.id ||
                (e.upper.isNotEmpty() && upper.contains(e.upper)) ||
                (cleaned.isNotEmpty() && e.blob.contains(cleaned)) ||
                (compact.isNotEmpty() && e.compact.contains(compact))
        }.map { it.surah }
    }

    /** Parse an ayah reference like "2:255", "2 255", or Arabic-digit forms. */
    fun parseReference(query: String): AyahReference? {
        val parts = Text.arabicDigitsToWestern(query).split(Regex("[:\\s]+")).filter { it.isNotEmpty() }
        if (parts.isEmpty()) return null

        var surah: Int? = toNumber(parts[0])
        if (surah == null) {
            val cleaned = Text.cleanSearch(parts[0])
            val m = surahIndex.firstOrNull { x ->
                x.blob.split(" ").contains(cleaned) || x.compact.contains(cleaned.replace(" ", ""))
            }
            surah = m?.surah?.id
        }
        if (surah == null) return null
        val ayah = if (parts.size >= 2) toNumber(parts[1]) else null
        return AyahReference(surah = surah, ayah = ayah)
    }

    private fun makeEntry(
        surahId: Int, ayahId: Int, raw: String, clean: String,
        saheeh: String, mustafa: String, translit: String,
    ): VerseIndexEntry {
        val arabicBlob = listOf(raw, clean).joinToString(" ") { Text.cleanSearch(it) }
        val silentArabicBlob = listOf(raw, clean)
            .joinToString(" ") { Text.cleanSearch(Text.removingSilentArabicLettersForSearch(it)) }
        val englishBlob = listOf(saheeh, mustafa, translit).joinToString(" ") { Text.cleanSearch(it) }
        return VerseIndexEntry(
            id = "$surahId:$ayahId", surah = surahId, ayah = ayahId,
            arabicTashkeelBlob = Text.arabicTashkeelBlob(raw),
            englishExactBlob = Text.exactPhraseBlob(listOf(saheeh, mustafa, translit).joinToString(" ")),
            arabicBlob = arabicBlob,
            silentArabicBlob = silentArabicBlob,
            englishBlob = englishBlob,
            arabicTokens = Text.searchTokens(arabicBlob),
            silentArabicTokens = Text.searchTokens(silentArabicBlob),
            englishTokens = Text.searchTokens(englishBlob),
        )
    }
}

/** Characters that trigger the boolean-search grammar. Mirrors BOOLEAN_CHARS = /[&|!#^%$=]/. */
private val BOOLEAN_CHARS = setOf('&', '|', '!', '#', '^', '%', '$', '=')

/**
 * Parse a single boolean term. Mirrors parseTerm(): strips (in order) leading `!` (negate, toggles),
 * `#` (tashkeel-sensitive), `=` (whole-word), one `^` (starts-with), one trailing `%`/`$` (ends-with);
 * the leftover text becomes the value plus the tashkeel / exact-phrase patterns.
 */
private fun parseTerm(rawTerm: String): Search.BooleanTerm {
    var t = rawTerm.trim()
    var negate = false
    while (t.startsWith("!")) { negate = !negate; t = t.substring(1).trim() }
    var requiresTashkeel = false
    while (t.startsWith("#")) { requiresTashkeel = true; t = t.substring(1).trim() }
    var wholeWord = false
    while (t.startsWith("=")) { wholeWord = true; t = t.substring(1).trim() }
    var startsWith = false
    if (t.startsWith("^")) { startsWith = true; t = t.substring(1).trim() }
    var endsWith = false
    if (t.endsWith("%") || t.endsWith("$")) { endsWith = true; t = t.substring(0, t.length - 1).trim() }

    val value = Text.cleanSearch(t, whitespace = true)
    val matchMode = when {
        wholeWord -> Search.MatchMode.WHOLE_WORD
        startsWith && endsWith -> Search.MatchMode.EXACT
        startsWith -> Search.MatchMode.STARTS_WITH
        endsWith -> Search.MatchMode.ENDS_WITH
        else -> Search.MatchMode.CONTAINS
    }

    val isArabic = Text.containsArabicLetters(t)
    return Search.BooleanTerm(
        value = value,
        negate = negate,
        matchMode = matchMode,
        requiresTashkeelMatch = requiresTashkeel && isArabic,
        tashkeelPattern = Text.arabicTashkeelBlob(t),
        requiresExactEnglishMatch = requiresTashkeel && !isArabic,
        exactEnglishPhrase = Text.exactPhraseBlob(t),
    )
}

/**
 * Consecutive-token match: query tokens appear as a consecutive run of haystack tokens. Leading
 * tokens must match exactly; the final token must match exactly when [lastMustBeExact], otherwise it
 * only has to be a prefix. Mirrors consecutiveTokenMatch().
 */
private fun consecutiveTokenMatch(
    haystack: List<String>,
    query: List<String>,
    lastMustBeExact: Boolean,
): Boolean {
    if (query.isEmpty() || haystack.size < query.size) return false
    for (start in 0..(haystack.size - query.size)) {
        var ok = true
        for (k in query.indices) {
            val word = haystack[start + k]
            val term = query[k]
            if (k == query.size - 1 && !lastMustBeExact) {
                if (!word.startsWith(term)) { ok = false; break }
            } else if (word != term) {
                ok = false; break
            }
        }
        if (ok) return true
    }
    return false
}

/** Match a single term's value against a blob/token list under one of the five modes. Mirrors ayahTermMatch(). */
private fun ayahTermMatch(
    haystack: String,
    tokens: List<String>,
    term: String,
    mode: Search.MatchMode,
): Boolean = when (mode) {
    Search.MatchMode.CONTAINS -> haystack.contains(term)
    Search.MatchMode.STARTS_WITH -> haystack.startsWith(term) || tokens.any { it.startsWith(term) }
    Search.MatchMode.ENDS_WITH -> haystack.endsWith(term) || tokens.any { it.endsWith(term) }
    Search.MatchMode.EXACT -> haystack == term || tokens.contains(term)
    Search.MatchMode.WHOLE_WORD -> consecutiveTokenMatch(tokens, Text.searchTokens(term), true)
}

/** Per-term match (un-negated). Mirrors the per-term branch of termMatch(). */
private fun termMatch(e: Search.VerseIndexEntry, term: Search.BooleanTerm, useArabic: Boolean): Boolean {
    if (useArabic && term.requiresTashkeelMatch) {
        val lettersMatch = ayahTermMatch(e.arabicBlob, e.arabicTokens, term.value, term.matchMode)
        val tashkeelMatch = term.tashkeelPattern.isEmpty() || e.arabicTashkeelBlob.contains(term.tashkeelPattern)
        return lettersMatch && tashkeelMatch
    }
    if (!useArabic && term.requiresExactEnglishMatch) {
        val exactTokens = Text.searchTokens(term.exactEnglishPhrase)
        return term.exactEnglishPhrase.isNotEmpty() &&
            ayahTermMatch(e.englishExactBlob, exactTokens, term.exactEnglishPhrase, term.matchMode)
    }
    val haystack = if (useArabic) e.arabicBlob else e.englishBlob
    val tokens = if (useArabic) e.arabicTokens else e.englishTokens
    return ayahTermMatch(haystack, tokens, term.value, term.matchMode)
}

private fun <T> paginate(arr: List<T>, offset: Int, limit: Int?): List<T> {
    if (offset >= arr.size) return emptyList()
    return if (limit == null) arr.subList(offset, arr.size).toList()
    else arr.subList(offset, minOf(offset + limit, arr.size)).toList()
}

private fun toNumber(s: String): Int? {
    val t = Text.arabicDigitsToWestern(s).trim()
    if (t.isEmpty()) return null
    return t.toIntOrNull()
}
