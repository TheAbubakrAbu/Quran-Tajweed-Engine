import Foundation

/// A curated word of Quranic vocabulary, with every ayah the same written form appears in.
///
/// 149 words, ordered so that consecutive days feel varied (the themes are interleaved in the
/// corpus itself), which is why the day mapping below is a walk and not a hash: hashing would
/// scatter the curation's own ordering, and the ordering is the point.
///
/// The occurrence list is derived from the Hafs text by matching the form folded, so the count on
/// a card and the list behind it are one derivation and cannot disagree. A form can repeat inside
/// a single ayah, so an occurrence carries token indices, plural.
///
/// Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission.
///
/// See docs/22-word-of-day.md.

/// One ayah carrying a curated form.
public struct WordOfDayOccurrence: Decodable, Sendable, Equatable {
    public let surah: Int
    public let ayah: Int
    /// 0-based whitespace-token indices into the ayah's raw text.
    public let tokens: [Int]
}

/// One curated word.
public struct WordOfDayEntry: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    /// The form as it stands at its first appearance.
    public let arabic: String
    public let transliteration: String
    public let meaning: String
    /// The anchor: where the form first appears.
    public let surah: Int
    public let ayah: Int
    public let token: Int
    /// Hits across the whole Quran.
    public let count: Int
    /// Every ayah carrying the form, in mushaf order.
    public let occurrences: [WordOfDayOccurrence]
}

/// `data/word-of-day.json`.
public struct WordOfDayFile: Decodable, Sendable {
    public let words: [WordOfDayEntry]
}

public final class WordOfDay: Sendable {
    private let words: [WordOfDayEntry]
    private let byID: [String: WordOfDayEntry]

    public init(_ file: WordOfDayFile? = nil) {
        words = file?.words ?? []
        byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var isLoaded: Bool { !words.isEmpty }

    /// The whole corpus, in curation order.
    public func all() -> [WordOfDayEntry] { words }

    public func word(id: String) -> WordOfDayEntry? { byID[id] }

    /// The word for a day number: the corpus walked in order, wrapping.
    ///
    /// Take this rather than `word(for:)` if your app has its own idea of when a day turns over
    /// (the upstream app rolls at Fajr, not midnight): hand it your own day number and the
    /// mapping is identical.
    public func word(dayIndex: Int) -> WordOfDayEntry? {
        guard !words.isEmpty else { return nil }
        let n = words.count
        return words[((dayIndex % n) + n) % n]
    }

    /// Today's word, by the calendar day of the given date in the given time zone.
    public func word(for date: Date = Date(),
                     calendar: Calendar = Calendar(identifier: .gregorian),
                     timeZone: TimeZone = .current) -> WordOfDayEntry? {
        var calendar = calendar
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        return word(dayIndex: Int(floor(start.timeIntervalSince1970 / 86_400)))
    }

    /// Matches the written form, the transliteration and the gloss.
    public func search(_ query: String, limit: Int = 25) -> [WordOfDayEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        return Array(words.filter {
            $0.arabic.contains(q)
                || $0.transliteration.lowercased().contains(lower)
                || $0.meaning.lowercased().contains(lower)
        }.prefix(limit))
    }

    /// Every curated word appearing in an ayah.
    public func words(surah: Int, ayah: Int) -> [WordOfDayEntry] {
        words.filter { entry in
            entry.occurrences.contains { $0.surah == surah && $0.ayah == ayah }
        }
    }

    public func count() -> (words: Int, occurrences: Int) {
        (words.count, words.reduce(0) { $0 + $1.count })
    }
}
