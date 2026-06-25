package com.quranengine

/**
 * Ayah & surah search — the **core path** only. Ported from `packages/quran-engine-js/src/search.js`.
 *
 * Verse matching is unranked: results come back in mushaf order. A verse matches when the whole cleaned
 * query is a substring of the relevant blob OR the query tokens phrase-prefix-match the verse tokens.
 *
 * Documented omissions vs. the JS reference (see README "What is omitted"):
 *   - the boolean grammar (`& | ! # ^ % $`) is not implemented;
 *   - the lenient "silent letters ignored" Arabic variant is not implemented;
 *   - the exact-phrase / tashkeel blobs are not built.
 * The remaining behaviour (Arabic/English fold, substring + phrase-prefix match, digit rejection for
 * verse search, mushaf order, surah-name/number/reference/makkan-madani search, reference parsing)
 * matches the reference.
 */
class Search(
    private val quran: Quran,
    private val riwayah: String? = null,
) {
    /** One indexed verse. */
    data class VerseIndexEntry(
        val id: String,            // "surah:ayah"
        val surah: Int,
        val ayah: Int,
        val arabicBlob: String,
        val englishBlob: String,
        val arabicTokens: List<String>,
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
     * digit (numeric/refs go via surah search).
     */
    fun searchVerses(
        query: String,
        offset: Int = 0,
        limit: Int? = null,
    ): List<VerseIndexEntry> {
        val cleaned = Text.cleanSearch(query, whitespace = true)
        if (cleaned.isEmpty()) return emptyList()
        if (cleaned.any { it.isDigit() }) return emptyList()

        val useArabic = Text.containsArabicLetters(query)
        val qTokens = Text.searchTokens(cleaned)

        fun matches(e: VerseIndexEntry): Boolean {
            return if (useArabic) {
                e.arabicBlob.contains(cleaned) || phrasePrefixMatch(e.arabicTokens, qTokens)
            } else {
                e.englishBlob.contains(cleaned) || phrasePrefixMatch(e.englishTokens, qTokens)
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
        val englishBlob = listOf(saheeh, mustafa, translit).joinToString(" ") { Text.cleanSearch(it) }
        return VerseIndexEntry(
            id = "$surahId:$ayahId", surah = surahId, ayah = ayahId,
            arabicBlob = arabicBlob, englishBlob = englishBlob,
            arabicTokens = Text.searchTokens(arabicBlob),
            englishTokens = Text.searchTokens(englishBlob),
        )
    }
}

/**
 * Phrase-prefix match: query tokens match a consecutive run of haystack tokens, all-but-last exact,
 * last is a prefix.
 */
private fun phrasePrefixMatch(haystack: List<String>, query: List<String>): Boolean {
    if (query.isEmpty() || haystack.size < query.size) return false
    for (start in 0..(haystack.size - query.size)) {
        var ok = true
        for (k in query.indices) {
            val word = haystack[start + k]
            val term = query[k]
            if (k == query.size - 1) {
                if (!word.startsWith(term)) { ok = false; break }
            } else if (word != term) { ok = false; break }
        }
        if (ok) return true
    }
    return false
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
