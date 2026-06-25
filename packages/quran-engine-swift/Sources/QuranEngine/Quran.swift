import Foundation

/// Quran browsing: surahs, ayahs, qiraat (riwayat) text, global ayah numbering.
///
/// Data-driven: construct from parsed `quran.json` plus optional qiraah overrides.
/// Mirrors `quran.js`.
public final class Quran {
    public let surahs: [Surah]
    public let totalAyahs: Int

    private let byId: [Int: Surah]
    /// 0-based count of ayahs in all earlier surahs (cumulative offset per surah id).
    private let cumulativeOffset: [Int: Int]
    /// riwayah key (lowercased) -> ["surahId": [(id, text)]]
    private let qiraat: [String: [String: [QiraahVerse]]]

    public struct QiraahVerse: Codable, Sendable {
        public let id: Int
        public let text: String
        public init(id: Int, text: String) { self.id = id; self.text = text }
    }

    public init(surahs: [Surah], qiraat: [String: [String: [QiraahVerse]]] = [:]) {
        self.surahs = surahs
        self.qiraat = qiraat
        var byId = [Int: Surah]()
        var offsets = [Int: Int]()
        var acc = 0
        for s in surahs {
            byId[s.id] = s
            offsets[s.id] = acc
            acc += s.numberOfAyahs
        }
        self.byId = byId
        self.cumulativeOffset = offsets
        self.totalAyahs = acc
    }

    /// All surahs in mushaf order (1..114).
    public func all() -> [Surah] { surahs }

    public func surah(_ id: Int) -> Surah? { byId[id] }

    public func ayah(_ surahId: Int, _ ayahId: Int) -> Ayah? {
        byId[surahId]?.ayahs.first { $0.id == ayahId }
    }

    /// Global ayah number (1-based, 1..6236). Used by ayah-audio CDN and as a stable verse key.
    public func globalAyahNumber(_ surahId: Int, _ ayahId: Int) -> Int? {
        guard let off = cumulativeOffset[surahId] else { return nil }
        return off + ayahId
    }

    /// Arabic text of an ayah for the requested riwayah. Falls back to the bundled Hafs
    /// `textArabic` when no qiraah override exists.
    public func arabicText(_ surahId: Int, _ ayahId: Int, riwayah: String? = nil) -> String? {
        guard let ayah = ayah(surahId, ayahId) else { return nil }
        if let r = riwayah?.lowercased(), r != "hafs",
           let verses = qiraat[r]?[String(surahId)],
           let match = verses.first(where: { $0.id == ayahId }) {
            return match.text
        }
        return ayah.textArabic
    }

    /// Arabic text with all diacritics/recitation marks stripped.
    public func cleanArabicText(_ surahId: Int, _ ayahId: Int, riwayah: String? = nil) -> String? {
        guard let raw = arabicText(surahId, ayahId, riwayah: riwayah) else { return nil }
        return ArabicText.removingArabicDiacriticsAndSigns(raw)
    }

    /// Iterate every ayah with its surah, in mushaf order.
    public func eachAyah() -> [(surah: Surah, ayah: Ayah)] {
        var out = [(Surah, Ayah)]()
        out.reserveCapacity(totalAyahs)
        for surah in surahs {
            for ayah in surah.ayahs { out.append((surah, ayah)) }
        }
        return out
    }
}
