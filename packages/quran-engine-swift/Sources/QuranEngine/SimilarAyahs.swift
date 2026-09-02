import Foundation

/// Similar ayahs (mutashabihat): the other places the Quran says something close to this.
///
/// Rows are merged and ranked at build time, so nothing here scores or sorts. `verified` rows come
/// from the classical corpus and are listed first; generated rows carry the `labels` that explain
/// why they matched, and are a reading aid rather than a scholarly claim.
///
/// See docs/13-similar-and-themes.md.
public struct SimilarMatch: Sendable, Equatable {
    public let surah: Int
    public let ayah: Int
    /// The shared wording, "" when none is recorded.
    public let phrase: String
    public let verified: Bool
    /// Why a generated row matched; empty for verified rows.
    public let labels: [String]
}

public final class SimilarAyahs {
    /// One row as it ships: [surah, ayah, phrase, verifiedFlag, labels?].
    public enum Field: Decodable, Sendable {
        case number(Int)
        case text(String)
        case labels([String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .text(value) }
            else { self = .labels(try container.decode([String].self)) }
        }

        var intValue: Int? { if case .number(let value) = self { return value } else { return nil } }
        var stringValue: String? { if case .text(let value) = self { return value } else { return nil } }
        var listValue: [String]? { if case .labels(let value) = self { return value } else { return nil } }
    }

    private let data: [String: [[Field]]]

    public init(_ data: [String: [[Field]]] = [:]) {
        self.data = data
    }

    /// Matches for an ayah, in display order. Empty for most short ayahs.
    public func matches(_ surahId: Int, _ ayahId: Int) -> [SimilarMatch] {
        (data["\(surahId):\(ayahId)"] ?? []).compactMap { row in
            guard row.count >= 4, let surah = row[0].intValue, let ayah = row[1].intValue,
                  let verified = row[3].intValue else { return nil }
            return SimilarMatch(surah: surah, ayah: ayah,
                                phrase: row[2].stringValue ?? "",
                                verified: verified == 1,
                                labels: row.count > 4 ? (row[4].listValue ?? []) : [])
        }
    }

    /// Whether the ayah has any - a dictionary hit, cheap enough to gate a button on.
    public func has(_ surahId: Int, _ ayahId: Int) -> Bool {
        !(data["\(surahId):\(ayahId)"] ?? []).isEmpty
    }

    /// How many ayahs have at least one match.
    public func count() -> Int { data.count }
}
