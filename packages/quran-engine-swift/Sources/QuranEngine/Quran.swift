import Foundation

/// ۩ ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs.
private let sajdahMark = "\u{06E9}"

/// One "About this surah" write-up (e.g. Maududi / Ibn Ashur). Mirrors a
/// `surah-info.json` → `sources[]` entry.
public struct SurahInfoSource: Codable, Equatable, Sendable {
    public let name: String
    public let contents: String
    public init(name: String, contents: String) { self.name = name; self.contents = contents }
}

/// One surah's info record. Mirrors a `surah-info.json` top-level entry.
public struct SurahInfo: Codable, Equatable, Sendable {
    public let id: Int
    public let sources: [SurahInfoSource]
    public init(id: Int, sources: [SurahInfoSource]) { self.id = id; self.sources = sources }
}

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
    /// riwayah key (lowercased) -> ["surahId": ayah count] (data/qiraat-counts.json)
    private let qiraatCounts: [String: [String: Int]]
    /// surah id -> "About this surah" sources.
    private let infoById: [Int: [SurahInfoSource]]

    public struct QiraahVerse: Codable, Sendable {
        public let id: Int
        public let text: String
        public init(id: Int, text: String) { self.id = id; self.text = text }
    }

    public init(surahs: [Surah], surahInfo: [SurahInfo] = [], qiraat: [String: [String: [QiraahVerse]]] = [:], qiraatCounts: [String: [String: Int]] = [:]) {
        self.surahs = surahs
        self.qiraat = qiraat
        self.qiraatCounts = qiraatCounts
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
        var info = [Int: [SurahInfoSource]]()
        for e in surahInfo { info[e.id] = e.sources }
        self.infoById = info
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

    /// "About this surah" write-ups (Maududi / Ibn Ashur). Empty if none loaded.
    public func info(_ surahId: Int) -> [SurahInfoSource] {
        infoById[surahId] ?? []
    }

    /// Resolve a surah counted from the END of the mushaf: 1 → An-Nās (114), 2 → Al-Falaq …
    /// 114 → Al-Fātiḥah. Companion to `JuzPage.juzFromEnd`. Returns nil for n outside 1..114.
    public func surahFromEnd(_ n: Int) -> Surah? {
        guard n >= 1, n <= surahs.count else { return nil }
        return surah(surahs.count + 1 - n)
    }

    /// Whether an ayah is a sajdah (prostration) ayah — carries the ۩ mark (U+06E9).
    public func isSajdahAyah(_ surahId: Int, _ ayahId: Int) -> Bool {
        (ayah(surahId, ayahId)?.textArabic ?? "").contains(sajdahMark)
    }

    /// Whether a mushaf page boundary falls inside this surah.
    public func pageChangesWithinSurah(_ surahId: Int) -> Bool {
        guard let s = surah(surahId) else { return false }
        if (s.numberOfPages ?? 1) > 1 { return true }
        return Set(s.ayahs.compactMap { $0.page }).count > 1
    }

    /// Whether a juz boundary falls inside this surah.
    public func juzChangesWithinSurah(_ surahId: Int) -> Bool {
        guard let s = surah(surahId) else { return false }
        if (s.juzs?.count ?? 0) > 1 { return true }
        if let first = s.firstJuz, let last = s.lastJuz, first != last { return true }
        return Set(s.ayahs.compactMap { $0.juz }).count > 1
    }

    /// Whether a page OR juz boundary falls inside this surah.
    public func pageOrJuzChangesWithinSurah(_ surahId: Int) -> Bool {
        pageChangesWithinSurah(surahId) || juzChangesWithinSurah(surahId)
    }

    /// The 15 sajdah (prostration) ayahs, in mushaf order, detected by the ۩ mark.
    public func sajdahAyahs() -> [(surah: Surah, ayah: Ayah)] {
        eachAyah().filter { $0.ayah.textArabic.contains(sajdahMark) }
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

    /// Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs every ayah exists;
    /// other riwayat merge/split some ayahs, so a Hafs ayah "exists" iff the riwayah's feed carries an
    /// ayah with that id (feeds are numbered contiguously 1..count, so this is `ayahId <= count`). An
    /// unknown/unloaded riwayah falls back to Hafs (exists). Mirrors `existsInQiraah` in quran.js.
    public func existsInQiraah(_ surahId: Int, _ ayahId: Int, riwayah: String? = nil) -> Bool {
        guard ayah(surahId, ayahId) != nil else { return false }
        let r = (riwayah ?? "").lowercased()
        if r.isEmpty || r == "hafs" { return true }
        guard let count = qiraatCounts[r]?[String(surahId)] else { return true }
        return ayahId <= count
    }

    /// Ayah count of a surah in the given riwayah — the number of Hafs ayahs that exist there (e.g.
    /// Baqarah is 286 in Hafs but 285 in Warsh). Mirrors `numberOfAyahsInQiraah` in quran.js.
    public func numberOfAyahsInQiraah(_ surahId: Int, riwayah: String? = nil) -> Int {
        guard let s = surah(surahId) else { return 0 }
        let r = (riwayah ?? "").lowercased()
        if r.isEmpty || r == "hafs" { return s.numberOfAyahs }
        guard let count = qiraatCounts[r]?[String(surahId)] else { return s.numberOfAyahs }
        return min(s.numberOfAyahs, count)
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
