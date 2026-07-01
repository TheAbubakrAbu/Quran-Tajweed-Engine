import Foundation

/// Pronunciation of a muqaṭṭaʿāt (disconnected opening letters) ayah, e.g. الٓمٓ.
/// The mushaf prints the letters joined with maddah marks but they are recited letter by
/// letter ("Alif Lām Mīm"), so this exposes, per opening ayah, the individual letters, a
/// transliteration, and the fully-vocalized Arabic spelling (whose long vowels carry the
/// madd-lāzim maddah U+0653). Mirrors a `muqattaat.json` → `ayahs[]` entry.
public struct MuqattaatPronunciation: Decodable, Equatable, Sendable {
    public let surah: Int
    public let ayah: Int
    /// Bare letters, e.g. `["ا","ل","م"]`.
    public let letters: [String]
    /// `"Alif Lām Mīm"`.
    public let transliteration: String
    /// Fully vocalized, e.g. `"أَلِفۡ لَآم مِيٓمۡ"`.
    public let spelledOutArabic: String
}

/// Parsed shape of `muqattaat.json`.
private struct MuqattaatFile: Decodable {
    let letterNames: [String: String]
    let ayahs: [MuqattaatPronunciation]
}

/// Muqaṭṭaʿāt — the disconnected opening letters of 29 surahs. Thin accessor over
/// `muqattaat.json`. Ash-Shūra (42) is the one surah whose muqattaʿāt span two ayahs
/// (1: Ḥā Mīm, 2: ʿAyn Sīn Qāf), so there are 30 entries. Mirrors `muqattaat.js`.
public final class Muqattaat: Decodable {
    /// Transliteration of each single letter, e.g. `"ا" → "Alif"`.
    public let letterNames: [String: String]
    /// Every muqattaʿāt opening (30 entries).
    public let ayahs: [MuqattaatPronunciation]
    /// "surah:ayah" -> pronunciation.
    private let byKey: [String: MuqattaatPronunciation]

    /// - Parameters:
    ///   - letterNames: char -> transliteration map.
    ///   - ayahs: parsed `muqattaat.json` → `ayahs[]`.
    public init(letterNames: [String: String] = [:], ayahs: [MuqattaatPronunciation] = []) {
        self.letterNames = letterNames
        self.ayahs = ayahs
        var map = [String: MuqattaatPronunciation]()
        for e in ayahs { map["\(e.surah):\(e.ayah)"] = e }
        self.byKey = map
    }

    /// Decodes the `muqattaat.json` file shape directly.
    public convenience init(from decoder: Decoder) throws {
        let file = try MuqattaatFile(from: decoder)
        self.init(letterNames: file.letterNames, ayahs: file.ayahs)
    }

    /// Every muqattaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd ayah).
    public func all() -> [MuqattaatPronunciation] { ayahs }

    /// Pronunciation for a muqattaʿāt ayah, or nil if that ayah doesn't open with them.
    public func pronunciation(_ surahId: Int, _ ayahId: Int) -> MuqattaatPronunciation? {
        byKey["\(surahId):\(ayahId)"]
    }

    /// Transliteration of a single muqattaʿāt letter, e.g. `"ا" → "Alif"`.
    public func letterName(_ letter: String) -> String? { letterNames[letter] }
}
