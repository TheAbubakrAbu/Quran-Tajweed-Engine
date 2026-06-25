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

    func testSearchVersesEnglishReturnsMushafOrder() {
        let results = engine.search.searchVerses("mercy", limit: 5)
        XCTAssertFalse(results.isEmpty)
        // mushaf order: surah then ayah ascending. Encode each (surah, ayah) as surah*1000+ayah.
        let keys = results.map { $0.surah * 1000 + $0.ayah }
        XCTAssertEqual(keys, keys.sorted())
    }
}

private extension String {
    /// Build a String from an array of UTF-16 code units.
    init(utf16 units: [UInt16]) {
        self = String(decoding: units, as: UTF16.self)
    }
}
