import XCTest
@testable import QuranEngine

/// The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah outlines,
/// alphabet reference and qiraat comparison that followed it.
///
/// Mirrors the JS `test/parity.test.js` and the Python `tests/test_parity.py` case for case, so a
/// divergence between the ports shows up as a failing test rather than as a surprise in an app.
final class ParityTests: XCTestCase {
    private static let engine: Engine = {
        do {
            return try Engine.load(loadMushaf: true, loadQiraatTajweed: true,
                                   loadWordByWord: true, loadSimilarAyahs: true,
                                   loadQiraat: true)
        } catch {
            fatalError("Failed to load engine: \(error)")
        }
    }()

    private var engine: Engine { Self.engine }

    // MARK: Mushaf

    func testTwentyRiwayatEightWithText() {
        XCTAssertEqual(engine.mushaf.riwayat().count, 20)
        XCTAssertEqual(engine.mushaf.riwayatWithText().count, 8)
        XCTAssertEqual(engine.mushaf.totalPages(), 604)
        XCTAssertEqual(engine.mushaf.riwayah("warsh")?.imam, "Nafi")
        XCTAssertEqual(engine.mushaf.riwayah("hisham")?.textIncluded, false)
    }

    func testEveryRiwayahHasAFacsimileAndAFullPageTable() {
        for entry in engine.mushaf.riwayat() {
            XCTAssertTrue(entry.pdf.hasPrefix("pdfs/"), entry.riwayah)
            XCTAssertTrue(entry.pdf.hasSuffix(".pdf.xz"), entry.riwayah)
            XCTAssertGreaterThan(entry.pdfBytes, 100_000, entry.riwayah)
            // Al-Fatihah opens page 1 and an-Nas closes page 604 in every print of the set.
            XCTAssertEqual(engine.mushaf.page(1, 1, riwayah: entry.riwayah), 1, entry.riwayah)
            XCTAssertEqual(engine.mushaf.page(114, 6, riwayah: entry.riwayah), 604, entry.riwayah)
        }
    }

    func testPagesResolveBackToTheirAyahs() {
        XCTAssertEqual(engine.mushaf.page(2, 255), 42)
        let onPage = engine.mushaf.ayahsOnPage(42)
        XCTAssertTrue(onPage.contains { $0.surah == 2 && $0.ayah == 255 })
        let first = engine.mushaf.firstAyahOfPage(1)
        XCTAssertEqual(first?.surah, 1)
        XCTAssertEqual(first?.ayah, 1)
    }

    func testLineTablesShipExactlyWhereTheTextDoes() {
        for entry in engine.mushaf.riwayat() {
            let breaks = engine.mushaf.lineBreaks(1, 1, riwayah: entry.riwayah)
            if entry.textIncluded { XCTAssertNotNil(breaks, entry.riwayah) }
            else { XCTAssertNil(breaks, entry.riwayah) }
        }
    }

    // MARK: Riwayah tajweed

    func testSevenVerifiedPacks() {
        XCTAssertEqual(engine.qiraatTajweed.available(),
                       ["buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"])
    }

    func testLegendCarriesItsExplanation() {
        let legend = engine.qiraatTajweed.legend("warsh")
        XCTAssertGreaterThanOrEqual(legend.count, 3)
        for entry in legend {
            XCTAssertEqual(entry.code.count, 1)
            XCTAssertFalse(entry.rule.isEmpty)
            XCTAssertFalse(entry.arabic.isEmpty)
            XCTAssertFalse(entry.english.isEmpty)
            XCTAssertFalse(entry.short.isEmpty, "no description for \(entry.rule)")
        }
    }

    func testWordRulesNameRealLegendCodes() {
        let rules = engine.qiraatTajweed.wordRules(2, 3, riwayah: "warsh")
        XCTAssertFalse(rules.isEmpty)
        let codes = Set(engine.qiraatTajweed.legend("warsh").map(\.code))
        for rule in rules {
            XCTAssertTrue(codes.contains(rule.code), rule.code)
            XCTAssertEqual(rule.wholeWord, rule.firstLetter < 0)
            XCTAssertGreaterThanOrEqual(rule.word, 1)
        }
    }

    func testKhilafMarkers() {
        XCTAssertTrue(engine.qiraatTajweed.hasKhilaf(2, 253, riwayah: "warsh"))
        XCTAssertFalse(engine.qiraatTajweed.hasKhilaf(2, 254, riwayah: "warsh"))
    }

    // MARK: Word by word

    func testBothLayersAlignedToTheAyahsOwnTokens() throws {
        let words = engine.wordByWord.words(112, 1)
        XCTAssertEqual(words.map(\.transliteration), ["qul", "huwa", "l-lahu", "aḥadun"])
        XCTAssertEqual(words.first?.english, "Say")
        let firstToken = try XCTUnwrap(engine.quran.ayah(112, 1)?.textArabic
            .split(whereSeparator: { $0.isWhitespace }).first).description
        XCTAssertEqual(words.first?.arabic, firstToken)
    }

    func testEveryAyahsArraysMatchItsTokenCount() {
        for surah in engine.quran.all() {
            for ayah in surah.ayahs {
                let tokens = ayah.textArabic.split(whereSeparator: { $0.isWhitespace }).count
                XCTAssertEqual(engine.wordByWord.glosses(surah.id, ayah.id)?.count, tokens,
                               "\(surah.id):\(ayah.id) english")
                XCTAssertEqual(engine.wordByWord.transliterations(surah.id, ayah.id)?.count, tokens,
                               "\(surah.id):\(ayah.id) transliteration")
            }
        }
    }

    func testGlossSearchFindsTheWord() {
        let hits = engine.wordByWord.find("the Ever-Living", limit: 5)
        XCTAssertTrue(hits.contains { $0.surah == 2 && $0.ayah == 255 })
        XCTAssertTrue(hits.allSatisfy { !$0.transliteration.isEmpty })
    }

    // MARK: Similar ayahs, themes, lessons

    func testSimilarAyahs() throws {
        let matches = engine.similarAyahs.matches(2, 255)
        let found = try XCTUnwrap(matches.first { $0.surah == 3 && $0.ayah == 2 })
        XCTAssertTrue(found.verified)
        XCTAssertTrue(engine.similarAyahs.has(2, 255))
        XCTAssertGreaterThan(engine.similarAyahs.count(), 5000)
    }

    func testThemesIndexBothWays() {
        XCTAssertGreaterThanOrEqual(engine.themes.all().count, 300)
        XCTAssertTrue(engine.themes.topic("tawheed")?.ayahs.contains("2:255") ?? false)
        XCTAssertTrue(engine.themes.topicsFor(2, 255).contains { $0.id == "tawheed" })
        XCTAssertGreaterThanOrEqual(engine.themes.domains().count, 2)
    }

    func testLessonsWalkInCourseOrder() throws {
        let lessons = engine.tajweedLessons.allLessons()
        XCTAssertGreaterThanOrEqual(lessons.count, 30)
        let first = try XCTUnwrap(lessons.first)
        XCTAssertNil(engine.tajweedLessons.previous(first.id))
        XCTAssertEqual(engine.tajweedLessons.next(first.id)?.id, lessons[1].id)
        XCTAssertNotNil(engine.tajweedLessons.chapterOf(first.id))
    }

    // MARK: Meaning search

    func testMaxSimRanksByMeaning() {
        // A toy embedder: enough to prove the scoring, without shipping a model.
        let vectors: [String: [Float]] = [
            "patience": [1, 0, 0], "hardship": [0.9, 0.1, 0], "sabr": [0.95, 0.05, 0],
            "steadfast": [0.9, 0.05, 0], "dawn": [0, 1, 0], "prayer": [0, 0.95, 0],
        ]
        let semantic = Semantic { vectors[$0] }
        semantic.index([(id: "sabr", text: "sabr and steadfast endurance"),
                        (id: "fajr", text: "prayer at dawn")])
        let hits = semantic.search("patience hardship")
        XCTAssertEqual(hits.first?.id, "sabr")
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    // MARK: Ask AI

    func testNamedVerseIsTheSubject() {
        let passages = engine.askAI.retrieve("explain ayat al-kursi")
        XCTAssertEqual(passages.first?.reference, "2:255")
        XCTAssertEqual(passages.first?.isSubject, true)
    }

    func testNamedSurahAnswersWithItsBackground() {
        let passages = engine.askAI.retrieve("what is surah al-kahf about")
        XCTAssertEqual(passages.first?.reference, "Surah Al-Kahf")
        XCTAssertEqual(passages.first?.kind, .surah)
    }

    func testKeywordLaneIsWeighted() {
        let passages = engine.askAI.retrieve("what does the Quran say about patience in hardship")
        XCTAssertTrue(passages.contains { $0.reference == "2:153" })
        for passage in passages where passage.kind == .ayah {
            XCTAssertNotNil(engine.quran.ayah(passage.surah ?? 0, passage.ayah ?? 0))
        }
    }

    func testBareFollowUpUsesThePreviousQuestion() {
        let carried = engine.askAI.retrieve("tell me about 2:153")
        XCTAssertTrue(engine.askAI.retrieve("why?").isEmpty)
        let withContext = engine.askAI.retrieve("why?", previousQuestion: "tell me about 2:153",
                                                carried: carried)
        XCTAssertTrue(withContext.contains { $0.reference == "2:153" })
    }

    func testPromptShape() {
        let passages = engine.askAI.retrieve("explain 2:153")
        let built = AskAIPrompt.chatPrompt(question: "explain 2:153", passages: passages)
        XCTAssertTrue(built.instructions.contains("Never issue a religious ruling"))
        XCTAssertTrue(built.prompt.contains("SUBJECT OF THE QUESTION [2:153]"))
        XCTAssertTrue(built.prompt.hasSuffix("QUESTION: explain 2:153"))
        XCTAssertTrue(AskAI.questionWords.contains("what"))
    }

    // MARK: Surah sections

    func testSections111SurahsAndAChain() {
        XCTAssertEqual(engine.surahSections.count, 111)
        XCTAssertGreaterThan(engine.surahSections.overview(1).count, 20)
        XCTAssertFalse(engine.surahSections.hasSections(1))

        // Hud opens with a broad passage and the sections inside it - an ayah has a chain, not a row.
        let chain = engine.surahSections.sections(for: 11, ayah: 3).map(\.english)
        XCTAssertEqual(chain, ["Doctrine facts", "Calling to Allah"])
        XCTAssertEqual(engine.surahSections.section(for: 11, ayah: 3)?.english, "Calling to Allah")
    }

    func testOutlineRebuildsTheNesting() {
        let roots = engine.surahSections.outline(11)
        XCTAssertGreaterThanOrEqual(roots.count, 2)
        XCTAssertEqual(roots[0].section.english, "Doctrine facts")
        XCTAssertEqual(roots[0].children.count, 5)
        XCTAssertTrue(roots[0].children.allSatisfy {
            $0.section.from >= roots[0].section.from && $0.section.to <= roots[0].section.to
        })
    }

    func testSectionRangesAreInsideTheirSurah() {
        for surah in engine.quran.all() {
            for section in engine.surahSections.sections(surah.id) {
                XCTAssertTrue(section.from >= 1 && section.to <= surah.numberOfAyahs,
                              "\(surah.id): \(section.from)-\(section.to)")
                XCTAssertLessThanOrEqual(section.from, section.to)
                XCTAssertFalse(section.english.isEmpty)
                XCTAssertFalse(section.arabic.isEmpty)
            }
        }
        let nuh = engine.surahSections.search("Story of Nuh")
        XCTAssertGreaterThanOrEqual(nuh.count, 2)
        XCTAssertTrue(nuh.contains { $0.surah == 11 })
    }

    // MARK: Arabic alphabet

    func testAlphabet28LettersEachWithAWeight() {
        XCTAssertEqual(engine.alphabet.letters.count, 28)
        let weights = engine.alphabet.weightDescriptions
        for letter in engine.alphabet.letters {
            XCTAssertFalse(letter.letter.isEmpty)
            XCTAssertFalse(letter.name.isEmpty)
            guard let weight = letter.weight else {
                return XCTFail("\(letter.letter) has no weight")
            }
            XCTAssertNotNil(weights[weight], "no description for weight \(weight)")
        }
        // Alif is the one letter with no weight of its own - the fact the whole field exists for.
        XCTAssertEqual(engine.alphabet.weight("ا"), "followsPrevious")
        XCTAssertEqual(engine.alphabet.weight("ص"), "heavy")
        XCTAssertEqual(engine.alphabet.weight("س"), "light")
    }

    func testAlphabetResolvesAJoiningForm() {
        XCTAssertEqual(engine.alphabet.letter("ـصـ")?.transliteration, "Saad")
        XCTAssertEqual(engine.alphabet.letter(id: 1)?.letter, "ا")
        XCTAssertNil(engine.alphabet.letter("nope"))
    }

    func testAlphabetTashkeelNumeralsAndWaqf() {
        XCTAssertGreaterThanOrEqual(engine.alphabet.tashkeel.count, 8)
        XCTAssertEqual(engine.alphabet.numbers.count, 11)
        XCTAssertEqual(engine.alphabet.stoppingSign("۩")?.title, "Make Sujood")
        XCTAssertGreaterThanOrEqual(engine.alphabet.heavyLetters.count, 7)
    }

    // MARK: Qiraat comparison

    func testComparisonListsOnlyPublishedReadings() {
        XCTAssertEqual(engine.qiraatComparison.available(),
                       ["buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh"])
    }

    func testAReadingAgainstItselfIsIdentical() {
        let same = engine.qiraatComparison.compare(surah: 2, riwayah: "hafs")
        XCTAssertEqual(same.identical, same.words)
        XCTAssertEqual(same.sameSkeleton, 0)
        XCTAssertEqual(same.different, 0)
        XCTAssertEqual(same.added, 0)
        XCTAssertEqual(same.dropped, 0)
        XCTAssertEqual(same.identicalPercent, 100)
    }

    func testBucketsAddUpAndShubahIsNearerThanWarsh() {
        let warsh = engine.qiraatComparison.compare(surah: 2, riwayah: "warsh")
        let shubah = engine.qiraatComparison.compare(surah: 2, riwayah: "shubah")
        for totals in [warsh, shubah] {
            XCTAssertEqual(totals.identical + totals.sameSkeleton + totals.different + totals.dropped,
                           totals.words)
        }
        // Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
        XCTAssertGreaterThan(shubah.identicalPercent, warsh.identicalPercent)
        XCTAssertGreaterThan(shubah.identicalPercent, 95)
    }

    func testDifferencesAreInReadingOrder() {
        let rows = engine.qiraatComparison.differences(surah: 2, riwayah: "warsh", limit: 20)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.base != $0.other })
        XCTAssertEqual(rows.map(\.position), rows.map(\.position).sorted())
    }

    func testWordStreamsFollowTheReadingsOwnVerseCount() {
        // Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
        // different verses from that point on; the comparison walks the surah's words instead.
        XCTAssertEqual(engine.quran.numberOfAyahsInQiraah(2, riwayah: "warsh"), 285)
        XCTAssertEqual(engine.quran.qiraahVerses(surah: 2, riwayah: "warsh").count, 285)
        XCTAssertGreaterThan(engine.qiraatComparison.words(surah: 2, riwayah: "warsh").count, 6000)
    }
}
