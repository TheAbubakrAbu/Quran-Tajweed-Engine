import Foundation

/// Similar ayahs (mutashabihat): the other places the Quran says something close to this.
///
/// Rows are merged and ranked at build time from three sources, so nothing here scores or sorts.
/// `verified` rows come from the classical corpus and are listed first; generated rows carry the
/// `labels` that explain why they matched, and are a reading aid rather than a scholarly claim.
/// The Quranic Universal Library's table is the third, and it adds `score`, its own 0-100
/// similarity; `score` is nil for rows from the other two sources, which rank but do not score.
///
/// The shared wording is `spans`: 0-based inclusive token ranges into the MATCHED ayah's raw
/// text. QUL's own placement where it lists the pair, else the wording the corpus recorded,
/// located in the ayah when the data was built. The data carries no text of its own (version 2):
/// cut the words out of `engine.quran` by those spans, so what you show is the Quran text you
/// already have and not a second copy of it.
///
/// See docs/13-similar-and-themes.md.
public struct SimilarMatch: Sendable, Equatable {
    public let surah: Int
    public let ayah: Int
    public let verified: Bool
    /// Why a generated row matched; empty for verified rows.
    public let labels: [String]
    /// 0-based inclusive token ranges of the shared words in the MATCHED ayah's raw text
    /// (`textArabic` split on spaces); empty when no source records shared wording. Tint these,
    /// or join the tokens they name to show the wording: there is no phrase text to fall back on.
    public let spans: [ClosedRange<Int>]
    /// QUL's 0-100 similarity, where it listed the pair. Nil for rows from the other two
    /// sources: they rank, but they do not score.
    public let score: Int?
}

extension SimilarMatch: Decodable {
    /// One row as it ships: `[surah, ayah, verifiedFlag, spans, labels, score]`, exactly six
    /// fields, decoded by position. `spans` and `labels` may be `[]`, `score` may be `null`.
    /// A span pair that is not `[start, end]` with `0 <= start <= end` is dropped.
    public init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        surah = try row.decode(Int.self)
        ayah = try row.decode(Int.self)
        verified = try row.decode(Int.self) == 1
        spans = try row.decode([[Int]].self).compactMap { pair in
            guard pair.count == 2, pair[0] >= 0, pair[1] >= pair[0] else { return nil }
            return pair[0]...pair[1]
        }
        labels = try row.decode([String].self)
        score = try row.decodeIfPresent(Int.self)
    }
}

/// data/similar-ayahs.json as it ships: `{ "v": 2, "ayahs": { "2:255": [row, ...], ... } }`.
public struct SimilarAyahsFile: Decodable, Sendable {
    /// The data version; this module reads version 2.
    public let v: Int?
    /// Keyed "surah:ayah", each row already in display order.
    public let ayahs: [String: [SimilarMatch]]?
}

public final class SimilarAyahs {
    private let data: [String: [SimilarMatch]]

    /// Reads a version-2 file. A version-1 file (rows keyed at the top level, the phrase as
    /// text) is not read: it would put the shared wording where a span is expected. Treated as
    /// no data rather than half a one, as the JS port does.
    public init(_ file: SimilarAyahsFile? = nil) {
        if let file, file.v == 2, let ayahs = file.ayahs {
            data = ayahs
        } else {
            data = [:]
        }
    }

    /// Matches for an ayah, in display order. Empty for most short ayahs.
    public func matches(_ surahId: Int, _ ayahId: Int) -> [SimilarMatch] {
        data["\(surahId):\(ayahId)"] ?? []
    }

    /// Whether the ayah has any: a dictionary hit, cheap enough to gate a button on.
    public func has(_ surahId: Int, _ ayahId: Int) -> Bool {
        !(data["\(surahId):\(ayahId)"] ?? []).isEmpty
    }

    /// How many ayahs have at least one match.
    public func count() -> Int { data.count }
}
