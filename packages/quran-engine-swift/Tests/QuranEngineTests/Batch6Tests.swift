import XCTest
@testable import QuranEngine

/// Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.
///
/// Mirrors the JS `test/batch6.test.js`, the Python `tests/test_batch6.py`, the Go
/// `batch6_test.go`, the Rust `tests/batch6.rs`, the Dart `test/batch6_test.dart` and the Kotlin
/// `Batch6Test.kt` case for case.
final class Batch6Tests: XCTestCase {
    private static let engine: Engine = {
        do {
            return try Engine.load()
        } catch {
            fatalError("Failed to load engine: \(error)")
        }
    }()

    private var engine: Engine { Self.engine }

    /// The upstream fold, as in batch 5: harakat and waqf marks gone, the hamza seats normalized.
    private func fold(_ text: String) -> String {
        String(text.unicodeScalars.compactMap { scalar -> Character? in
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: return nil
            case 0x0671, 0x0623, 0x0625: return "\u{0627}"
            case 0x0624: return "\u{0648}"
            case 0x0626: return "\u{064A}"
            default: return Character(scalar)
            }
        })
    }

    // MARK: - The Names in depth

    func testAllNinetyNineNamesCarryDepth() {
        let counts = engine.namesDepth.count()
        XCTAssertEqual(counts.names, 99)
        XCTAssertEqual(counts.themes, 9)
        XCTAssertEqual(counts.occurrences, 194)
        XCTAssertEqual(engine.namesDepth.all().map(\.number), Array(1...99))
    }

    func testEveryNameHasRootThemeAndProse() {
        let ids = Set(engine.namesDepth.themes().map(\.id))
        for name in engine.namesDepth.all() {
            XCTAssertFalse(name.root.isEmpty, "name \(name.number) has no root")
            XCTAssertTrue(ids.contains(name.theme), "name \(name.number) theme \(name.theme)")
            XCTAssertGreaterThan(name.explanation.count, 40, "name \(name.number) explanation")
            XCTAssertGreaterThan(name.living.count, 20, "name \(name.number) living")
        }
    }

    func testThemesPartitionTheNinetyNine() {
        var total = 0
        for theme in engine.namesDepth.themes() {
            let members = engine.namesDepth.byTheme(theme.id)
            XCTAssertFalse(members.isEmpty, "theme \(theme.id) has no Names")
            total += members.count
        }
        XCTAssertEqual(total, 99)
    }

    func testRootIsSpacedAndClosesUp() {
        guard let rahman = engine.namesDepth.byNumber(1) else { return XCTFail("no name 1") }
        XCTAssertEqual(rahman.root, "ر ح م")
        XCTAssertEqual(rootKey(rahman.root), "رحم")
        for spelling in ["رحم", "ر ح م"] {
            XCTAssertEqual(engine.namesDepth.byRoot(spelling).map(\.number), [1, 2])
        }
    }

    func testPlacedOccurrencesAreRealTokens() {
        var placed = 0
        var unplaced = 0
        for name in engine.namesDepth.all() {
            for occurrence in name.occurrences {
                guard let ayah = engine.quran.ayah(occurrence.surah, occurrence.ayah) else {
                    return XCTFail("name \(name.number) points at \(occurrence.surah):\(occurrence.ayah)")
                }
                guard let token = occurrence.token else {
                    XCTAssertEqual(occurrence.tokens, 0, "name \(name.number) unplaced but spans")
                    unplaced += 1
                    continue
                }
                let tokens = ayah.textArabic.split(whereSeparator: { $0.isWhitespace })
                XCTAssertLessThan(token, tokens.count, "name \(name.number) token \(token) past the end")
                XCTAssertFalse(fold(String(tokens[token])).isEmpty)
                placed += 1
            }
        }
        XCTAssertEqual(placed, 184)
        XCTAssertEqual(unplaced, 10)
    }

    func testBasmalahCarriesTwoNames() {
        let hits = engine.namesDepth.inAyah(surah: 1, ayah: 3)
        XCTAssertEqual(hits.map(\.name.number), [1, 2])
        XCTAssertEqual(hits.map(\.occurrence.token), [0, 1])
    }

    func testNamesSearch() {
        XCTAssertTrue(engine.namesDepth.search("رحم").contains { $0.number == 1 })
        guard let first = engine.namesDepth.byNumber(1),
              let word = first.living.split(separator: " ").first(where: { $0.count > 6 })
        else { return XCTFail("no name 1") }
        XCTAssertFalse(engine.namesDepth.search(String(word)).isEmpty)
        XCTAssertTrue(engine.namesDepth.search("").isEmpty)
    }

    // MARK: - The chains of transmission

    func testIsnadCounts() {
        let counts = engine.isnad.count()
        XCTAssertEqual(counts.imams, 10)
        XCTAssertEqual(counts.narrators, 20)
        XCTAssertEqual(counts.companions, 13)
        XCTAssertNotNil(engine.isnad.prophet())
    }

    func testEveryRiwayahResolvesTwoApiece() {
        var per: [String: Int] = [:]
        for tag in engine.isnad.narratorKeys() {
            guard let imam = engine.isnad.imamOf(tag) else {
                return XCTFail("\(tag) resolves to no imam")
            }
            per[imam, default: 0] += 1
        }
        for imam in engine.isnad.imamKeys() {
            XCTAssertEqual(per[imam], 2, "\(imam) has \(per[imam] ?? 0) narrators")
        }
    }

    func testEveryImamReachesCompanions() {
        for imam in engine.isnad.imamKeys() {
            guard let chain = engine.isnad.imam(imam) else { return XCTFail("no chain for \(imam)") }
            // Abu Jafar WAS a Successor and read on Companions himself, so he has no teachers.
            if imam != "Abu Jafar" {
                XCTAssertFalse(chain.teachers.isEmpty, "\(imam) has no teachers")
            }
            XCTAssertFalse(chain.companions.isEmpty, "\(imam) reaches no Companion")
            for node in chain.teachers {
                XCTAssertEqual(node.role, "successor")
                XCTAssertTrue(node.detail.hasPrefix("d."), "\(node.name) has no death year")
            }
            for node in chain.companions {
                XCTAssertEqual(node.role, "companion")
            }
        }
    }

    func testChainRunsProphetToNarrator() {
        for tag in engine.isnad.narratorKeys() {
            let layers = engine.isnad.chain(tag)
            XCTAssertGreaterThanOrEqual(layers.count, 4, "\(tag) chain is only \(layers.count) layers")
            XCTAssertEqual(layers.first?.title, "THE PROPHET")
            XCTAssertEqual(layers.dropFirst().first?.title, "THE COMPANIONS")
            let titles = layers.map(\.title)
            guard let imam = titles.firstIndex(of: "THE IMAM"),
                  let narrator = titles.firstIndex(of: "THE NARRATOR")
            else { return XCTFail("\(tag) is missing a layer") }
            XCTAssertLessThan(imam, narrator, "\(tag) has the narrator above the imam")
        }
    }

    func testImamChainEndsAtTwoNarrators() {
        for imam in engine.isnad.imamKeys() {
            guard let last = engine.isnad.chain(imam).last else { return XCTFail("no chain for \(imam)") }
            XCTAssertEqual(last.title, "HIS TWO NARRATORS", imam)
            XCTAssertEqual(last.nodes.count, 2, imam)
        }
    }

    func testReadsDirectlyMatchesLinks() {
        for tag in engine.isnad.narratorKeys() {
            guard let chain = engine.isnad.narrator(tag) else { return XCTFail("no chain for \(tag)") }
            XCTAssertEqual(engine.isnad.readsDirectly(tag), chain.links.isEmpty, tag)
            let sentence = engine.isnad.sentence(tag)
            XCTAssertFalse(sentence.isEmpty, tag)
            XCTAssertEqual(sentence.contains("did not meet"), !chain.links.isEmpty, tag)
        }
    }

    func testHafsAndQunbul() {
        XCTAssertEqual(engine.isnad.imamOf("Hafs an Asim"), "Asim")
        XCTAssertTrue(engine.isnad.readsDirectly("Hafs an Asim"))
        XCTAssertTrue(engine.isnad.sentence("Hafs an Asim").hasPrefix("Hafs read on Asim himself"))

        XCTAssertEqual(engine.isnad.imamOf("Qunbul an Ibn Kathir"), "Ibn Kathir")
        XCTAssertFalse(engine.isnad.readsDirectly("Qunbul an Ibn Kathir"))
        XCTAssertEqual(engine.isnad.narrator("Qunbul an Ibn Kathir")?.links.count, 3)
    }

    func testUnknownIsnadKey() {
        XCTAssertTrue(engine.isnad.chain("Nobody an Nobody").isEmpty)
        XCTAssertEqual(engine.isnad.sentence("Nobody an Nobody"), "")
        XCTAssertNil(engine.isnad.imamOf("no separator here"))
    }
}
