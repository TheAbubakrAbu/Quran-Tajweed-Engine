import Foundation

// MARK: - Quran models
//
// These Codable structs decode the JSON in `/data` directly. The JSON uses camelCase
// keys (`nameEnglish`, `numberOfAyahs`, `textArabic`, …) which already match Swift's
// idiomatic property names, so no custom CodingKeys are required.

/// A single verse. Mirrors `quran.json` → `surahs[].ayahs[]`.
public struct Ayah: Codable, Equatable, Sendable {
    public let id: Int
    public let textArabic: String
    public let textTransliteration: String?
    public let textEnglishSaheeh: String?
    public let textEnglishMustafa: String?
    public let juz: Int?
    public let page: Int?
    public let wordCount: Int?
    public let letterCount: Int?
}

/// A chapter. Mirrors `quran.json` → `surahs[]`.
public struct Surah: Codable, Equatable, Sendable {
    public let id: Int
    /// `"makkan"` or `"madinan"`.
    public let type: String
    public let nameArabic: String
    public let nameTransliteration: String
    public let nameEnglish: String
    public let numberOfAyahs: Int
    public let pageStart: Int?
    public let pageEnd: Int?
    public let numberOfPages: Int?
    public let firstJuz: Int?
    public let lastJuz: Int?
    public let juzs: [Int]?
    public let revelationOrder: Int?
    public let similarNames: [String]?
    public let wordCount: Int?
    public let letterCount: Int?
    public let ayahs: [Ayah]
}

/// A juz (para) boundary entry. Mirrors `juz.json`.
public struct JuzEntry: Codable, Equatable, Sendable {
    public let id: Int
    public let nameArabic: String
    public let nameTransliteration: String
    public let startSurah: Int
    public let startAyah: Int
    public let endSurah: Int
    public let endAyah: Int
}

/// A reciter directory entry. Mirrors `reciters.json`.
///
/// `id` is `"{name}|{qiraah or 'Hafs'}|{surahLink}"`. `qiraah` is `nil` for Hafs.
public struct Reciter: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let ayahIdentifier: String
    /// String, used verbatim in the CDN URL (e.g. `"128"`).
    public let ayahBitrate: String
    /// Full-surah CDN base, with trailing slash.
    public let surahLink: String
    /// `nil` => Hafs; otherwise the riwayah label.
    public let qiraah: String?
    public let group: String?
}

// MARK: - Tajweed

/// One tajweed-rule category from `tajweed-rules.json` → `categories[]`.
public struct TajweedCategory: Codable, Equatable, Sendable {
    public let id: String
    public let section: String?
    public let sortRank: Int?
    public let colorHex: String
    public let englishTitle: String?
    public let arabicTitle: String?
    public let transliteration: String?
    public let shortDescription: String?
}

/// The catalogue wrapper of `tajweed-rules.json`.
struct TajweedRules: Codable {
    let categories: [TajweedCategory]
}

/// One raw annotation from `tajweed/NNN.json` / `tajweed-annotations.json`.
/// `start`/`end` are UTF-16 code-unit offsets into the ayah's `textArabic`.
struct TajweedAnnotation: Codable {
    let start: Int
    let end: Int
    let rule: String
}

/// One ayah's annotation record.
struct TajweedAyahRecord: Codable {
    let surah: Int
    let ayah: Int
    let annotations: [TajweedAnnotation]
}

/// A colored slice of an ayah, produced by mapping an annotation's rule to a color.
public struct TajweedSpan: Equatable, Sendable {
    /// UTF-16 start offset into the ayah text.
    public let start: Int
    /// UTF-16 end offset (exclusive).
    public let end: Int
    /// The rule id (e.g. `"maddNatural"`).
    public let rule: String
    /// Hex color (`"#RRGGBB"`) from the rule category; `nil` if the rule is unknown.
    public let colorHex: String?
    /// The reconstructed UTF-16 substring `[start, end)` of the ayah text.
    public let text: String
}
