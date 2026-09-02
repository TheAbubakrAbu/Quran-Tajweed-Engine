import Foundation

/// Word by word: what each word of an ayah means, and how it is said.
///
/// Two layers over the SAME tokens - the English gloss and a Latin transliteration - where the
/// tokens are the ayah's own whitespace-separated words. Split the ayah and index straight in; the
/// alignment against a corpus that tokenizes ~200 ayahs differently was done once, at build time.
///
/// A token with no word of its own (the ۞ ornament, the tail of a word the corpus writes as two)
/// carries "" in both layers - show nothing for it rather than a neighbour's meaning.
///
/// See docs/12-word-by-word.md.
public struct WordByWordPack: Decodable, Sendable {
    /// Surah id -> ayahs in id order -> one entry per token.
    public let english: [String: [[String]]]
    public let transliteration: [String: [[String]]]
}

public struct GlossedWord: Sendable, Equatable {
    /// 1-based index of the word in the ayah.
    public let position: Int
    /// The ayah's own token.
    public let arabic: String
    /// The gloss, "" when the token has none.
    public let english: String
    public let transliteration: String
}

public final class WordByWord {
    public enum Layer { case english, transliteration }

    private let englishLayer: [String: [[String]]]
    private let latinLayer: [String: [[String]]]
    private weak var quran: Quran?

    public init(pack: WordByWordPack? = nil, quran: Quran? = nil) {
        self.englishLayer = pack?.english ?? [:]
        self.latinLayer = pack?.transliteration ?? [:]
        self.quran = quran
    }

    /// Whether a pack is loaded at all - cheap enough to gate UI on.
    public var isLoaded: Bool { !englishLayer.isEmpty }

    /// Every word of an ayah, in reading order.
    public func words(_ surahId: Int, _ ayahId: Int) -> [GlossedWord] {
        guard let english = glosses(surahId, ayahId) else { return [] }
        let latin = transliterations(surahId, ayahId) ?? []
        let tokens = self.tokens(surahId, ayahId)
        return english.enumerated().map { index, gloss in
            GlossedWord(position: index + 1,
                        arabic: index < tokens.count ? tokens[index] : "",
                        english: gloss,
                        transliteration: index < latin.count ? latin[index] : "")
        }
    }

    /// One word, by its 1-based position.
    public func word(_ surahId: Int, _ ayahId: Int, position: Int) -> GlossedWord? {
        let all = words(surahId, ayahId)
        return position >= 1 && position <= all.count ? all[position - 1] : nil
    }

    public func glosses(_ surahId: Int, _ ayahId: Int) -> [String]? {
        row(englishLayer, surahId, ayahId)
    }

    public func transliterations(_ surahId: Int, _ ayahId: Int) -> [String]? {
        row(latinLayer, surahId, ayahId)
    }

    public func entries(_ layer: Layer, _ surahId: Int, _ ayahId: Int) -> [String]? {
        layer == .english ? glosses(surahId, ayahId) : transliterations(surahId, ayahId)
    }

    /// Ayahs containing a word whose gloss carries `term` - a word-level English search, which finds
    /// ayahs a translation search misses because no translator used that phrasing.
    public func find(_ term: String, limit: Int = 50) -> [(surah: Int, ayah: Int, position: Int, english: String, transliteration: String)] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [(surah: Int, ayah: Int, position: Int, english: String, transliteration: String)] = []
        for surahKey in englishLayer.keys.compactMap(Int.init).sorted() {
            let rows = englishLayer["\(surahKey)"] ?? []
            for (ayahIndex, glosses) in rows.enumerated() {
                for (index, gloss) in glosses.enumerated() where gloss.lowercased().contains(needle) {
                    let latinRows = latinLayer["\(surahKey)"] ?? []
                    let latin = ayahIndex < latinRows.count && index < latinRows[ayahIndex].count
                        ? latinRows[ayahIndex][index] : ""
                    out.append((surah: surahKey, ayah: ayahIndex + 1, position: index + 1,
                                english: gloss, transliteration: latin))
                    if out.count >= limit { return out }
                }
            }
        }
        return out
    }

    private func row(_ layer: [String: [[String]]], _ surahId: Int, _ ayahId: Int) -> [String]? {
        guard let rows = layer["\(surahId)"], ayahId >= 1, ayahId <= rows.count else { return nil }
        return rows[ayahId - 1]
    }

    private func tokens(_ surahId: Int, _ ayahId: Int) -> [String] {
        guard let text = quran?.ayah(surahId, ayahId)?.textArabic else { return [] }
        return text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
