import Foundation

/// One indexed verse. Search is unranked; matches return in mushaf order.
public struct VerseMatch: Equatable, Sendable {
    public let id: String   // "surah:ayah"
    public let surah: Int
    public let ayah: Int
}

/// An ayah reference like `2:255`.
public struct AyahReference: Equatable, Sendable {
    public let surah: Int
    public let ayah: Int?
}

/// How a boolean term's value is matched against a verse blob/token list.
enum MatchMode {
    case contains
    case startsWith
    case endsWith
    case exact
    case wholeWord
}

/// A single parsed boolean search term. Mirrors `parseTerm` in search.js.
private struct BooleanTerm {
    let value: String
    let negate: Bool
    let matchMode: MatchMode
    let requiresTashkeelMatch: Bool
    let tashkeelPattern: String
    let requiresExactEnglishMatch: Bool
    let exactEnglishPhrase: String
}

/// Search verses & surahs. Faithful port of the core path in `search.js`.
///
/// Verse matching is unranked (mushaf order). A regular query is a pure substring match against the
/// cleaned blobs; a query containing a boolean operator (`& | ! # ^ % $ =`) is run through the small
/// boolean grammar. Queries containing any decimal digit (including Arabic-Indic) return [].
public final class Search {
    private let quran: Quran
    private let riwayah: String?

    /// Characters that trigger the boolean grammar (mirrors `BOOLEAN_CHARS` in search.js).
    private static let booleanChars: Set<Character> = ["&", "|", "!", "#", "^", "%", "$", "="]

    private struct VerseEntry {
        let surah: Int
        let ayah: Int
        let arabicTashkeelBlob: String
        let englishExactBlob: String
        let arabicBlob: String
        let silentArabicBlob: String
        let englishBlob: String
        let arabicTokens: [String]
        let silentArabicTokens: [String]
        let englishTokens: [String]
    }

    private struct SurahEntry {
        let surah: Surah
        let blob: String
        let compact: String
        let upper: String
    }

    private var index: [VerseEntry] = []
    private var surahIndex: [SurahEntry] = []

    public init(quran: Quran, riwayah: String? = nil) {
        self.quran = quran
        self.riwayah = riwayah
        rebuild()
        buildSurahIndex()
    }

    private func rebuild() {
        var idx = [VerseEntry]()
        idx.reserveCapacity(quran.totalAyahs)
        for (surah, ayah) in quran.eachAyah() {
            let raw = quran.arabicText(surah.id, ayah.id, riwayah: riwayah) ?? ""
            let clean = quran.cleanArabicText(surah.id, ayah.id, riwayah: riwayah) ?? ""
            let saheeh = ayah.textEnglishSaheeh ?? ""
            let mustafa = ayah.textEnglishMustafa ?? ""
            let translit = ayah.textTransliteration ?? ""

            let arabicBlob = [raw, clean].map { ArabicText.cleanSearch($0) }.joined(separator: " ")
            let silentArabicBlob = [raw, clean]
                .map { ArabicText.cleanSearch(ArabicText.removingSilentArabicLettersForSearch($0)) }
                .joined(separator: " ")
            let englishBlob = [saheeh, mustafa, translit].map { ArabicText.cleanSearch($0) }.joined(separator: " ")

            idx.append(VerseEntry(
                surah: surah.id, ayah: ayah.id,
                arabicTashkeelBlob: ArabicText.arabicTashkeelBlob(raw),
                englishExactBlob: ArabicText.exactPhraseBlob([saheeh, mustafa, translit].joined(separator: " ")),
                arabicBlob: arabicBlob, silentArabicBlob: silentArabicBlob, englishBlob: englishBlob,
                arabicTokens: ArabicText.searchTokens(arabicBlob),
                silentArabicTokens: ArabicText.searchTokens(silentArabicBlob),
                englishTokens: ArabicText.searchTokens(englishBlob)
            ))
        }
        index = idx
    }

    private func buildSurahIndex() {
        surahIndex = quran.all().map { s in
            var names = [s.nameArabic, s.nameTransliteration, s.nameEnglish]
            names.append(contentsOf: s.similarNames ?? [])
            let parts = names + [String(s.id), ArabicText.removingArabicMarks(s.nameArabic)]
            let blob = ArabicText.cleanSearch(parts.joined(separator: " "))
            return SurahEntry(
                surah: s,
                blob: blob,
                compact: blob.replacingOccurrences(of: " ", with: ""),
                upper: "\(s.nameEnglish) \(s.nameTransliteration)".uppercased()
            )
        }
    }

    /// Search verse text. Returns matches in mushaf order. Empty when the query (after cleaning)
    /// is empty or contains any decimal digit.
    public func searchVerses(_ query: String, offset: Int = 0, limit: Int? = nil,
                             ignoreSilentLetters: Bool = false) -> [VerseMatch] {
        let cleaned = ArabicText.cleanSearch(query, whitespace: true)
        if cleaned.isEmpty { return [] }

        // Reject any query containing a decimal digit (numeric/refs go via surah search). Done BEFORE
        // the boolean path — exactly as QuranData.search(term:) does — so even a boolean query with a
        // digit returns []. `.decimalDigits` also catches Arabic-Indic digits (mirrors `\p{Nd}`).
        if cleaned.rangeOfCharacter(from: .decimalDigits) != nil { return [] }

        // Boolean grammar?
        if query.contains(where: { Search.booleanChars.contains($0) }) {
            return booleanSearch(query, offset: offset, limit: limit)
        }

        let useArabic = ArabicText.containsArabicLetters(query)
        let silentQuery: String = (useArabic && ignoreSilentLetters)
            ? ArabicText.cleanSearch(ArabicText.removingSilentArabicLettersForSearch(query), whitespace: true)
            : ""

        // Plain substring search in mushaf order — word/sentence boundaries DON'T matter (a query
        // matches anywhere it appears, e.g. "رب" inside "ربهم"). Whole-word / phrase matching lives in
        // the boolean `=` operator. Mirrors the regular path in search.js.
        let matched = index.filter { e in
            if useArabic {
                if e.arabicBlob.contains(cleaned) { return true }
                if silentQuery.isEmpty { return false }
                return e.silentArabicBlob.contains(silentQuery)
            }
            return e.englishBlob.contains(cleaned)
        }.map { VerseMatch(id: "\($0.surah):\($0.ayah)", surah: $0.surah, ayah: $0.ayah) }

        return Search.paginate(matched, offset: offset, limit: limit)
    }

    // MARK: - Boolean search

    private func booleanSearch(_ query: String, offset: Int, limit: Int?) -> [VerseMatch] {
        let useArabic = ArabicText.containsArabicLetters(query)
        let normalized = query
            .replacingOccurrences(of: "&&", with: "&")
            .replacingOccurrences(of: "||", with: "|")

        // Split into OR-groups of AND-terms. Drop any term whose cleaned value is empty
        // (booleanAyahSearchTerm() returns nil in that case), then drop emptied groups.
        let orGroups: [[BooleanTerm]] = normalized.components(separatedBy: "|").map { group in
            group.components(separatedBy: "&")
                .map { Search.parseTerm($0) }
                .filter { !$0.value.isEmpty }
        }.filter { !$0.isEmpty }
        if orGroups.isEmpty { return [] }

        let matched = index.filter { e in
            orGroups.contains { andTerms in
                andTerms.allSatisfy { term in
                    let hit = Search.termMatch(e, term, useArabic: useArabic)
                    return term.negate ? !hit : hit
                }
            }
        }.map { VerseMatch(id: "\($0.surah):\($0.ayah)", surah: $0.surah, ayah: $0.ayah) }

        return Search.paginate(matched, offset: offset, limit: limit)
    }

    /// Search surahs by name, number, `2:255` reference, or makkan/madani.
    public func searchSurahs(_ query: String) -> [Surah] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return quran.all() }

        // makkan/madani filter
        let norm = ArabicText.cleanSearch(trimmed).replacingOccurrences(of: " ", with: "")
        let makkan = ["makkah", "makkan", "makki"]
        let madinan = ["madinah", "madinan", "madina", "madani"]
        func aliasHit(_ aliases: [String]) -> Bool {
            aliases.contains { $0.hasPrefix(norm) || norm.hasPrefix($0) }
        }
        if !norm.isEmpty && aliasHit(makkan) { return quran.all().filter { $0.type == "makkan" } }
        if !norm.isEmpty && aliasHit(madinan) { return quran.all().filter { $0.type == "madinan" } }

        let ref = parseReference(trimmed)
        let cleaned = ArabicText.cleanSearch(trimmed.replacingOccurrences(of: ":", with: ""))
        let compact = cleaned.replacingOccurrences(of: " ", with: "")
        let upper = trimmed.uppercased()
        let numeric = ref?.surah ?? Search.toNumber(cleaned)

        return surahIndex.filter { e in
            (numeric != nil && numeric == e.surah.id) ||
            (!e.upper.isEmpty && upper.contains(e.upper)) ||
            (!cleaned.isEmpty && e.blob.contains(cleaned)) ||
            (!compact.isEmpty && e.compact.contains(compact))
        }.map { $0.surah }
    }

    /// Parse an ayah reference like `2:255`, `2 255`, or Arabic-digit forms.
    public func parseReference(_ query: String) -> AyahReference? {
        let western = ArabicText.arabicDigitsToWestern(query)
        let parts = western.split(whereSeparator: { $0 == ":" || $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard let first = parts.first else { return nil }

        var surah = Search.toNumber(first)
        if surah == nil {
            let cleaned = ArabicText.cleanSearch(first)
            let cleanedCompact = cleaned.replacingOccurrences(of: " ", with: "")
            if let m = surahIndex.first(where: {
                $0.blob.split(separator: " ").map(String.init).contains(cleaned) ||
                $0.compact.contains(cleanedCompact)
            }) {
                surah = m.surah.id
            }
        }
        guard let s = surah else { return nil }
        let ayah = parts.count >= 2 ? Search.toNumber(parts[1]) : nil
        return AyahReference(surah: s, ayah: ayah)
    }

    // MARK: - helpers

    /// Consecutive-token match: query tokens appear as a consecutive run of haystack tokens. Leading
    /// tokens must match exactly; the final token must match exactly when `lastMustBeExact`, otherwise
    /// it only has to be a prefix. Mirrors `consecutiveTokenMatch`.
    static func consecutiveTokenMatch(_ haystack: [String], _ query: [String], lastMustBeExact: Bool) -> Bool {
        if query.isEmpty || haystack.count < query.count { return false }
        var start = 0
        while start <= haystack.count - query.count {
            var ok = true
            for k in 0..<query.count {
                let word = haystack[start + k], term = query[k]
                if k == query.count - 1 && !lastMustBeExact {
                    if !word.hasPrefix(term) { ok = false; break }
                } else if word != term {
                    ok = false; break
                }
            }
            if ok { return true }
            start += 1
        }
        return false
    }

    /// Parse a single boolean term. Mirrors `parseTerm`: strips (in order) leading `!` (negate,
    /// toggles), `#` (tashkeel-sensitive), `=` (whole-word), one `^` (starts-with), one trailing
    /// `%`/`$` (ends-with); the leftover text becomes the value + tashkeel/exact-phrase patterns.
    private static func parseTerm(_ rawTerm: String) -> BooleanTerm {
        var t = rawTerm.trimmingCharacters(in: .whitespaces)
        var negate = false
        while t.hasPrefix("!") { negate.toggle(); t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        var requiresTashkeel = false
        while t.hasPrefix("#") { requiresTashkeel = true; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        var wholeWord = false
        while t.hasPrefix("=") { wholeWord = true; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        var startsWith = false
        if t.hasPrefix("^") { startsWith = true; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        var endsWith = false
        if t.hasSuffix("%") || t.hasSuffix("$") { endsWith = true; t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }

        let value = ArabicText.cleanSearch(t, whitespace: true)
        let matchMode: MatchMode
        if wholeWord { matchMode = .wholeWord }
        else if startsWith && endsWith { matchMode = .exact }
        else if startsWith { matchMode = .startsWith }
        else if endsWith { matchMode = .endsWith }
        else { matchMode = .contains }

        let isArabic = ArabicText.containsArabicLetters(t)
        return BooleanTerm(
            value: value,
            negate: negate,
            matchMode: matchMode,
            requiresTashkeelMatch: requiresTashkeel && isArabic,
            tashkeelPattern: ArabicText.arabicTashkeelBlob(t),
            requiresExactEnglishMatch: requiresTashkeel && !isArabic,
            exactEnglishPhrase: ArabicText.exactPhraseBlob(t)
        )
    }

    /// Match a single term's value against a blob/token list under one of the five modes. Mirrors
    /// `ayahTermMatch`.
    static func ayahTermMatch(_ haystack: String, _ tokens: [String], _ term: String, _ mode: MatchMode) -> Bool {
        switch mode {
        case .startsWith: return haystack.hasPrefix(term) || tokens.contains { $0.hasPrefix(term) }
        case .endsWith: return haystack.hasSuffix(term) || tokens.contains { $0.hasSuffix(term) }
        case .exact: return haystack == term || tokens.contains(term)
        case .wholeWord: return consecutiveTokenMatch(tokens, ArabicText.searchTokens(term), lastMustBeExact: true)
        case .contains: return haystack.contains(term)
        }
    }

    /// Per-term match (un-negated). Mirrors the per-term branch of `termMatch`/`matchesBooleanAyahSearch`.
    private static func termMatch(_ e: VerseEntry, _ term: BooleanTerm, useArabic: Bool) -> Bool {
        if useArabic && term.requiresTashkeelMatch {
            let lettersMatch = ayahTermMatch(e.arabicBlob, e.arabicTokens, term.value, term.matchMode)
            let tashkeelMatch = term.tashkeelPattern.isEmpty || e.arabicTashkeelBlob.contains(term.tashkeelPattern)
            return lettersMatch && tashkeelMatch
        }
        if !useArabic && term.requiresExactEnglishMatch {
            let exactTokens = ArabicText.searchTokens(term.exactEnglishPhrase)
            return !term.exactEnglishPhrase.isEmpty
                && ayahTermMatch(e.englishExactBlob, exactTokens, term.exactEnglishPhrase, term.matchMode)
        }
        let haystack = useArabic ? e.arabicBlob : e.englishBlob
        let tokens = useArabic ? e.arabicTokens : e.englishTokens
        return ayahTermMatch(haystack, tokens, term.value, term.matchMode)
    }

    static func paginate(_ arr: [VerseMatch], offset: Int, limit: Int?) -> [VerseMatch] {
        guard offset < arr.count else { return [] }
        let start = max(0, offset)
        if let limit = limit {
            let end = min(arr.count, start + max(0, limit))
            return Array(arr[start..<end])
        }
        return Array(arr[start...])
    }

    static func toNumber(_ s: String) -> Int? {
        let t = ArabicText.arabicDigitsToWestern(s).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        return Int(t)
    }
}
