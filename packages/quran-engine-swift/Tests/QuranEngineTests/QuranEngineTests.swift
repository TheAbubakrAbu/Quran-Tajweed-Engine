import XCTest
@testable import QuranEngine

final class QuranEngineTests: XCTestCase {
    // Loaded once for all tests (parsing quran.json is the expensive part).
    private static let engine: Engine = {
        do { return try Engine.load() }
        catch { fatalError("Failed to load engine: \(error)") }
    }()

    private var engine: Engine { Self.engine }

    func alafasy() throws -> Reciter {
        let r = engine.reciters.all().first { $0.surahLink == "https://server8.mp3quran.net/afs/" }
        return try XCTUnwrap(r, "Mishary Alafasy reciter not found")
    }

    // MARK: - Canonical cases from docs/PORTING.md

    func testTotalAyahs() {
        XCTAssertEqual(engine.quran.totalAyahs, 6236)
    }

    func testGlobalAyahNumber() {
        XCTAssertEqual(engine.quran.globalAyahNumber(1, 1), 1)
        XCTAssertEqual(engine.quran.globalAyahNumber(2, 1), 8)
        XCTAssertEqual(engine.quran.globalAyahNumber(114, 6), 6236)
    }

    func testSurahAudioURL() throws {
        let r = try alafasy()
        XCTAssertEqual(try surahAudioURL(r, 1), "https://server8.mp3quran.net/afs/001.mp3")
    }

    func testAyahAudioURL() throws {
        let r = try alafasy()
        XCTAssertEqual(ayahAudioURL(r, 8), "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3")
    }

    func testJuzBoundaries() throws {
        let j1 = try XCTUnwrap(engine.juzPage.juz(1))
        XCTAssertEqual(j1.startSurah, 1)
        XCTAssertEqual(j1.startAyah, 1)
        let j30 = try XCTUnwrap(engine.juzPage.juz(30))
        XCTAssertEqual(j30.endSurah, 114)
        XCTAssertEqual(j30.endAyah, 6)
    }

    func testJuzFromEndAndStats() throws {
        let jp = engine.juzPage
        XCTAssertEqual(jp.juzFromEnd(1)?.id, 30)
        XCTAssertEqual(jp.juzFromEnd(30)?.id, 1)
        XCTAssertNil(jp.juzFromEnd(0))
        XCTAssertNil(jp.juzFromEnd(31))

        let stats = try XCTUnwrap(jp.juzStats(30))
        XCTAssertEqual(stats.ayahCount, jp.ayahsInJuz(30).count)
        XCTAssertGreaterThanOrEqual(stats.surahCount, 1)
        XCTAssertGreaterThanOrEqual(stats.pageCount, 1)
        XCTAssertGreaterThan(stats.wordCount, 0)
        XCTAssertGreaterThan(stats.letterCount, 0)
        XCTAssertNil(jp.juzStats(99))

        let sum = (1...30).reduce(0) { $0 + (jp.juzStats($1)?.ayahCount ?? 0) }
        XCTAssertEqual(sum, 6236)
    }

    func testSortSurahsAyahsDescending() {
        let sorted = sortSurahs(engine.quran.all(), .ayahs, .descending)
        XCTAssertEqual(sorted.first?.id, 2) // Al-Baqarah, 286 ayahs
    }

    func testParseReference() {
        let ref = engine.search.parseReference("2:255")
        XCTAssertEqual(ref, AyahReference(surah: 2, ayah: 255))
    }

    // MARK: - Tajweed: reconstructed UTF-16 slice equals the recorded text

    func testTajweedSpansReconstructForAyah1() throws {
        let spans = engine.tajweed.tajweedSpans(1, 1)
        XCTAssertFalse(spans.isEmpty, "expected annotations for 1:1")
        let text = try XCTUnwrap(engine.quran.arabicText(1, 1))
        let utf16 = Array(text.utf16)
        for span in spans {
            // Each span must carry a color (rule must be known).
            XCTAssertNotNil(span.colorHex, "rule \(span.rule) has no color")
            // The reconstructed UTF-16 slice must equal the recorded span text.
            let expected = String(utf16: Array(utf16[span.start..<span.end]))
            XCTAssertEqual(span.text, expected)
        }
    }

    /// Stronger: across many ayahs, every span's UTF-16 slice round-trips.
    func testTajweedSpansReconstructAcrossCorpus() throws {
        var checked = 0
        for (surah, ayah) in engine.quran.eachAyah() where surah.id <= 5 {
            guard let text = engine.quran.arabicText(surah.id, ayah.id) else { continue }
            let utf16 = Array(text.utf16)
            for span in engine.tajweed.tajweedSpans(surah.id, ayah.id) {
                guard span.start >= 0, span.end <= utf16.count, span.start <= span.end else {
                    XCTFail("span out of bounds for \(surah.id):\(ayah.id)"); continue
                }
                let expected = String(utf16: Array(utf16[span.start..<span.end]))
                XCTAssertEqual(span.text, expected, "mismatch at \(surah.id):\(ayah.id)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - Extra sanity

    func testSanitizeReciterDir() {
        XCTAssertEqual(sanitizeReciterDir("Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/"),
                       "Mishary_Alafasy_Hafs_https___server8_mp3quran_net_afs_")
        XCTAssertEqual(sanitizeReciterDir(""), "reciter")
    }

    func testLocalSurahPath() throws {
        let r = try alafasy()
        XCTAssertEqual(localSurahPath(r, 1), "\(sanitizeReciterDir(r.id))/001.mp3")
    }

    func testSearchSurahsByNumberAndName() {
        XCTAssertEqual(engine.search.searchSurahs("2").first?.id, 2)
        XCTAssertTrue(engine.search.searchSurahs("fatihah").contains { $0.id == 1 })
        XCTAssertTrue(engine.search.searchSurahs("makkan").allSatisfy { $0.type == "makkan" })
    }

    func testSearchVersesRejectsDigits() {
        XCTAssertTrue(engine.search.searchVerses("255").isEmpty)
    }

    func testSearchVersesBehaviorMatchesJSReference() {
        func hits(_ q: String) -> [String] { engine.search.searchVerses(q).map { $0.id } }

        // 1) Regular (non-boolean) search is a PURE mid-word substring match: "orld" matches "worlds".
        XCTAssertTrue(hits("orld").contains("1:2"), "mid-word substring 'orld' should hit 1:2")

        // 2) The `=` whole-word operator matches whole tokens only: "=lord" hits 1:2, "=lor" does not,
        //    while the plain substring "lor" still does (it appears inside "lord"/"worlds").
        XCTAssertTrue(hits("=lord").contains("1:2"), "whole-word '=lord' should hit 1:2")
        XCTAssertFalse(hits("=lor").contains("1:2"), "whole-word '=lor' should NOT hit 1:2")
        XCTAssertTrue(hits("lor").contains("1:2"), "substring 'lor' should hit 1:2")

        // 3) Any decimal digit anywhere (even in a boolean query) returns []. `=` triggers boolean,
        //    but the digit check runs first.
        XCTAssertTrue(engine.search.searchVerses("allah & 2").isEmpty, "'allah & 2' should return 0")
    }

    // MARK: - Parity features (mirroring the JS reference)

    func testSajdahAyahs() {
        XCTAssertEqual(engine.quran.sajdahAyahs().count, 15)
        XCTAssertTrue(engine.quran.isSajdahAyah(32, 15))
        XCTAssertFalse(engine.quran.isSajdahAyah(1, 1))
    }

    func testSurahFromEnd() {
        XCTAssertEqual(engine.quran.surahFromEnd(1)?.id, 114)
        XCTAssertNil(engine.quran.surahFromEnd(115))
    }

    func testExistsInQiraah() {
        // Baqarah is 285 ayahs in Warsh, 286 in Hafs.
        XCTAssertTrue(engine.quran.existsInQiraah(2, 285, riwayah: "warsh"))
        XCTAssertFalse(engine.quran.existsInQiraah(2, 286, riwayah: "warsh"))
        // Shubah keeps Baqarah at 286, so 286 exists there.
        XCTAssertTrue(engine.quran.existsInQiraah(2, 286, riwayah: "shubah"))
        // No riwayah / Hafs: every ayah exists.
        XCTAssertTrue(engine.quran.existsInQiraah(2, 286, riwayah: nil))
    }

    func testNumberOfAyahsInQiraah() {
        XCTAssertEqual(engine.quran.numberOfAyahsInQiraah(2, riwayah: nil), 286)
        XCTAssertEqual(engine.quran.numberOfAyahsInQiraah(2, riwayah: "warsh"), 285)
    }

    func testNamesOfAllah() {
        XCTAssertEqual(engine.namesOfAllah.all().count, 99)
        XCTAssertEqual(engine.namesOfAllah.byNumber(1)?.transliteration, "Ar-Rahman")
    }

    func testSurahInfo() {
        XCTAssertGreaterThanOrEqual(engine.quran.info(1).count, 1)
    }

    func testFilterByCounts() {
        let ids = filterByCounts(engine.quran.all(), ayahs: CountFilter(.equal, 286)).map { $0.id }
        XCTAssertEqual(ids, [2])
    }

    func testSearchVersesEnglishReturnsMushafOrder() {
        let results = engine.search.searchVerses("mercy", limit: 5)
        XCTAssertFalse(results.isEmpty)
        // mushaf order: surah then ayah ascending. Encode each (surah, ayah) as surah*1000+ayah.
        let keys = results.map { $0.surah * 1000 + $0.ayah }
        XCTAssertEqual(keys, keys.sorted())
    }

    func testMuqattaat() {
        let m = engine.muqattaat
        XCTAssertEqual(m.all().count, 30)
        XCTAssertEqual(m.pronunciation(2, 1)?.transliteration, "Alif Lām Mīm")
        XCTAssertEqual(m.pronunciation(42, 2)?.transliteration, "ʿAyn Sīn Qāf")
        XCTAssertNil(m.pronunciation(1, 1))
        XCTAssertEqual(m.letterName("ا"), "Alif")
        // Long vowels carry the madd-lāzim maddah U+0653.
        XCTAssertTrue(m.pronunciation(2, 1)?.spelledOutArabic.contains("\u{0653}") ?? false)
    }

    func testSurahFlags() {
        XCTAssertTrue(engine.quran.juzChangesWithinSurah(2))
        XCTAssertFalse(engine.quran.juzChangesWithinSurah(1))
        XCTAssertFalse(engine.quran.pageOrJuzChangesWithinSurah(112))
    }
}

private extension String {
    /// Build a String from an array of UTF-16 code units.
    init(utf16 units: [UInt16]) {
        self = String(decoding: units, as: UTF16.self)
    }
}
