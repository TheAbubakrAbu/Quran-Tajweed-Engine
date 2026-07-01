import Foundation

/// Juz (para) and mushaf-page navigation. Mirrors `juzPage.js`.
///
/// Juz boundary names/ranges are static (`juz.json`). Ayah→juz and ayah→page membership comes
/// from the per-ayah `juz` / `page` fields in `quran.json`.
public final class JuzPage {
    public let quran: Quran
    public let juzList: [JuzEntry]

    public init(quran: Quran, juzList: [JuzEntry]) {
        self.quran = quran
        self.juzList = juzList.sorted { $0.id < $1.id }
    }

    /// All 30 juz boundary entries.
    public func juzes() -> [JuzEntry] { juzList }

    public func juz(_ id: Int) -> JuzEntry? { juzList.first { $0.id == id } }

    /// Every ayah in a juz, in mushaf order.
    public func ayahsInJuz(_ juz: Int) -> [(surah: Surah, ayah: Ayah)] {
        quran.eachAyah().filter { $0.ayah.juz == juz }
    }

    /// Every ayah on a mushaf page, in mushaf order.
    public func ayahsOnPage(_ page: Int) -> [(surah: Surah, ayah: Ayah)] {
        quran.eachAyah().filter { $0.ayah.page == page }
    }

    /// First ayah of a juz.
    public func firstAyahOfJuz(_ juz: Int) -> (surah: Surah, ayah: Ayah)? {
        quran.eachAyah().first { $0.ayah.juz == juz }
    }

    /// First ayah of a mushaf page.
    public func firstAyahOfPage(_ page: Int) -> (surah: Surah, ayah: Ayah)? {
        quran.eachAyah().first { $0.ayah.page == page }
    }

    public func juzForAyah(_ surahId: Int, _ ayahId: Int) -> Int? {
        quran.ayah(surahId, ayahId)?.juz
    }

    public func pageForAyah(_ surahId: Int, _ ayahId: Int) -> Int? {
        quran.ayah(surahId, ayahId)?.page
    }

    /// Total page count of the bundled mushaf (max page seen).
    public func totalPages() -> Int {
        quran.eachAyah().reduce(0) { max($0, $1.ayah.page ?? 0) }
    }

    /// Surah ids contained in a juz (by boundary range).
    public func surahsInJuz(_ juzNumber: Int) -> [Int] {
        guard let j = juz(juzNumber) else { return [] }
        return quran.all().filter { $0.id >= j.startSurah && $0.id <= j.endSurah }.map { $0.id }
    }

    /// Resolve a juz counted from the end of the Quran: 1 → juz 30, 2 → juz 29 … 30 → juz 1.
    /// Mirrors the search-bar `-N` shorthand in QuranView.swift. Returns nil for n outside 1...30.
    public func juzFromEnd(_ n: Int) -> JuzEntry? {
        guard (1...30).contains(n) else { return nil }
        return juz(31 - n)
    }

    /// Aggregate counts for a single juz, computed from the ayahs actually assigned to it
    /// (`ayah.juz == juz`) so surahs that straddle a juz boundary are split correctly.
    /// Mirrors `QuranData.juzStats(for:)`. Returns nil for an unknown juz id.
    public func juzStats(_ juz: Int) -> JuzStats? {
        guard self.juz(juz) != nil else { return nil }
        var surahIds = Set<Int>()
        var pages = Set<Int>()
        var ayahCount = 0, wordCount = 0, letterCount = 0
        for (surah, ayah) in quran.eachAyah() where ayah.juz == juz {
            surahIds.insert(surah.id)
            ayahCount += 1
            wordCount += ayah.wordCount ?? 0
            letterCount += ayah.letterCount ?? 0
            if let page = ayah.page { pages.insert(page) }
        }
        return JuzStats(
            surahCount: surahIds.count,
            ayahCount: ayahCount,
            wordCount: wordCount,
            letterCount: letterCount,
            pageCount: pages.count
        )
    }
}

/// Aggregate counts for a single juz. Mirrors `QuranData.JuzStats`.
public struct JuzStats: Equatable {
    public let surahCount: Int
    public let ayahCount: Int
    public let wordCount: Int
    public let letterCount: Int
    public let pageCount: Int

    public init(surahCount: Int, ayahCount: Int, wordCount: Int, letterCount: Int, pageCount: Int) {
        self.surahCount = surahCount
        self.ayahCount = ayahCount
        self.wordCount = wordCount
        self.letterCount = letterCount
        self.pageCount = pageCount
    }
}
