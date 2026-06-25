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
}
