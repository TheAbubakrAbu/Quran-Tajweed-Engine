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

/// Search verses & surahs. Port of the core path in `search.js`.
///
/// IMPORTANT — scope of this port:
///   • Implemented: cleaned-blob substring match, phrase-prefix token match, mushaf-order results,
///     digit-rejection for verse text, optional "ignore silent letters" Arabic variant,
///     surah search by name / number / `2:255` reference / makkan-madani, `parseReference`.
///   • OMITTED: the boolean grammar (`& | ! # ^ % $`). A query containing those operators is
///     treated as plain text (operators are stripped by `cleanSearch`, except `& | ! #` which are
///     kept and matched literally). This matches the "minimal port" allowance in docs/PORTING.md.
public final class Search {
    private let quran: Quran
    private let riwayah: String?

    private struct VerseEntry {
        let surah: Int
        let ayah: Int
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
    /// contains a digit.
    public func searchVerses(_ query: String, offset: Int = 0, limit: Int? = nil,
                             ignoreSilentLetters: Bool = false) -> [VerseMatch] {
        let cleaned = ArabicText.cleanSearch(query, whitespace: true)
        if cleaned.isEmpty { return [] }
        // Verse-text search rejects any query containing a digit.
        if cleaned.unicodeScalars.contains(where: { ("0"..."9").contains(Character($0)) }) { return [] }

        let useArabic = ArabicText.containsArabicLetters(query)
        let silentQuery: String = (useArabic && ignoreSilentLetters)
            ? ArabicText.cleanSearch(ArabicText.removingSilentArabicLettersForSearch(query), whitespace: true)
            : ""

        let qTokens = ArabicText.searchTokens(cleaned)
        let sTokens = silentQuery.isEmpty ? [] : ArabicText.searchTokens(silentQuery)

        let matched = index.filter { e in
            if useArabic {
                if e.arabicBlob.contains(cleaned) || Search.phrasePrefixMatch(e.arabicTokens, qTokens) { return true }
                if silentQuery.isEmpty { return false }
                return e.silentArabicBlob.contains(silentQuery) || Search.phrasePrefixMatch(e.silentArabicTokens, sTokens)
            }
            return e.englishBlob.contains(cleaned) || Search.phrasePrefixMatch(e.englishTokens, qTokens)
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

    /// Phrase-prefix match: query tokens match a consecutive run of haystack tokens; all-but-last
    /// exact, last is a prefix. Mirrors `phrasePrefixMatch`.
    static func phrasePrefixMatch(_ haystack: [String], _ query: [String]) -> Bool {
        if query.isEmpty || haystack.count < query.count { return false }
        var start = 0
        while start <= haystack.count - query.count {
            var ok = true
            for k in 0..<query.count {
                let word = haystack[start + k], term = query[k]
                if k == query.count - 1 {
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
