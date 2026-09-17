import XCTest
@testable import QuranEngine

/// The scientific-miracles corpus: 202 articles under 15 categories.
///
/// Mirrors the JS `test/miracles.test.js`, the Python `tests/test_miracles.py`, the Go
/// `miracles_test.go`, the Rust `tests/miracles.rs`, the Dart `test/miracles_test.dart` and the
/// Kotlin `MiraclesTest.kt` case for case.
final class MiraclesTests: XCTestCase {
    private static let engine: Engine = {
        do {
            return try Engine.load()
        } catch {
            fatalError("Failed to load engine: \(error)")
        }
    }()

    private var engine: Engine { Self.engine }
    private var m: Miracles { Self.engine.miracles }

    func testCounts() {
        let counts = m.count()
        XCTAssertEqual(counts.articles, 202)
        XCTAssertEqual(counts.categories, 15)
        XCTAssertEqual(counts.ayahRefs, 278)
        XCTAssertEqual(m.all().count, 202)
        XCTAssertEqual(m.categories().count, 15)
    }

    func testSlugRoundTrips() {
        let article = m.bySlug("big_bang_crunch")
        XCTAssertNotNil(article)
        XCTAssertEqual(article?.title, "Big Bang")
        XCTAssertEqual(article?.category, "cosmology")
        XCTAssertEqual(article?.level, "extreme")
        XCTAssertNil(m.bySlug("no_such_article"))
        // Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
        XCTAssertEqual(Set(m.all().map(\.slug)).count, 202)
    }

    func testCategoriesPartitionTheCorpus() {
        var total = 0
        for category in m.categories() {
            let members = m.byCategory(category.id)
            XCTAssertFalse(members.isEmpty, "category \(category.id) has no articles")
            total += members.count
        }
        XCTAssertEqual(total, 202)
        XCTAssertEqual(m.byCategory("cosmology").count, 18)
        XCTAssertTrue(m.byCategory("no_such_category").isEmpty)
    }

    func testCategoryLookup() {
        let cosmology = m.category("cosmology")
        XCTAssertNotNil(cosmology)
        XCTAssertEqual(cosmology?.id, "cosmology")
        XCTAssertEqual(cosmology?.level, "advanced")
        XCTAssertNil(m.category("no_such_category"))
    }

    func testArticleLevelIsItsOwn() {
        // Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
        // itself is "extreme". Filtering on the category's level would put it in the wrong bucket,
        // and it is not one article out of place: most of the corpus disagrees with its category.
        XCTAssertEqual(m.category("cosmology")?.level, "advanced")
        XCTAssertEqual(m.bySlug("big_bang_crunch")?.level, "extreme")
        var catLevel: [String: String] = [:]
        for category in m.categories() { catLevel[category.id] = category.level }
        let differing = m.all().filter { $0.level != catLevel[$0.category] }.count
        XCTAssertEqual(differing, 147)
    }

    func testLevelsRunSimpleToExtreme() {
        XCTAssertEqual(m.levels(), ["simple", "intermediate", "advanced", "extreme"])
        XCTAssertEqual(m.levels(), miracleLevels)
        // Sorted as strings, "extreme" would come second. That is the whole reason the rank is
        // hard-coded.
        XCTAssertNotEqual(m.levels(), m.levels().sorted())
        XCTAssertEqual(m.byLevel("simple").count, 6)
        XCTAssertEqual(m.byLevel("intermediate").count, 103)
        XCTAssertEqual(m.byLevel("advanced").count, 37)
        XCTAssertEqual(m.byLevel("extreme").count, 56)
        XCTAssertEqual(miracleLevels.reduce(0) { $0 + m.byLevel($1).count }, m.all().count)
    }

    func testEveryArticleNamesAKnownCategoryAndLevel() {
        let ids = Set(m.categories().map(\.id))
        for article in m.all() {
            XCTAssertFalse(article.slug.isEmpty)
            XCTAssertFalse(article.title.isEmpty, article.slug)
            XCTAssertTrue(ids.contains(article.category), article.slug)
            XCTAssertTrue(miracleLevels.contains(article.level), article.slug)
            XCTAssertFalse(article.blocks.isEmpty, article.slug)
        }
    }

    func testCitingFindsTheArticlesThatReachAnAyah() {
        // 21:30 is cited by exactly two: Big Bang and Exoplanets.
        XCTAssertEqual(m.citing(21, 30).map(\.slug), ["big_bang_crunch", "exoplanets"])
        // 23:14, the embryology verse, by three.
        XCTAssertEqual(m.citing(23, 14).map(\.slug), ["bones", "fetal_development", "human_embryo"])
        XCTAssertTrue(m.citing(21, 999).isEmpty)
        XCTAssertTrue(m.citing(999, 1).isEmpty)
    }

    func testAnAyahBlockIsARange() {
        // Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
        // one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range
        // end is what bounds the search, not the surah).
        XCTAssertEqual(m.ayahRefs("abjad_numerals"),
                       [MiracleAyahRef(surah: 111, ayah: 1, endAyah: 5)])
        for ayah in 1...5 {
            XCTAssertTrue(m.citing(111, ayah).contains { $0.slug == "abjad_numerals" }, "111:\(ayah)")
        }
        XCTAssertFalse(m.citing(111, 6).contains { $0.slug == "abjad_numerals" })
        XCTAssertTrue(m.ayahRefs("no_such_article").isEmpty)
    }

    func testEveryAyahRefIsARealAyah() {
        var refs = 0
        var ranges = 0
        for article in m.all() {
            for ref in m.ayahRefs(article.slug) {
                XCTAssertGreaterThanOrEqual(ref.endAyah, ref.ayah, article.slug)
                // Both ends resolve, which is the point of storing the reference rather than the
                // text.
                XCTAssertNotNil(engine.quran.ayah(ref.surah, ref.ayah),
                                "\(article.slug) -> \(ref.surah):\(ref.ayah)")
                XCTAssertNotNil(engine.quran.ayah(ref.surah, ref.endAyah),
                                "\(article.slug) -> \(ref.surah):\(ref.endAyah)")
                refs += 1
                if ref.endAyah > ref.ayah { ranges += 1 }
            }
        }
        XCTAssertEqual(refs, 278)
        XCTAssertEqual(ranges, 49)
    }

    func testNoBlockAnywhereIsAnImage() {
        // The site's illustrations are deliberately not republished. A consumer that leaves a gap
        // for a picture would wait forever, so the corpus states it and the blocks bear it out.
        XCTAssertFalse(m.imagesIncluded)
        let kinds = Set(m.all().flatMap { $0.blocks.map(\.kind) })
        XCTAssertFalse(kinds.contains("image"))
        XCTAssertEqual(kinds.sorted(), ["ayah", "claim", "closer", "lead", "quote", "text"])
        XCTAssertTrue(m.source().contains("miracles-of-quran.com"))
    }

    func testALinkIsAURLOrASlugNeverBoth() {
        var urls = 0
        var slugs = 0
        let known = Set(m.all().map(\.slug))
        for article in m.all() {
            for block in article.blocks {
                for link in block.links {
                    XCTAssertFalse(link.label.isEmpty, article.slug)
                    XCTAssertNotEqual(link.url != nil, link.slug != nil,
                                      "\(article.slug): \(link.label)")
                    if link.url != nil {
                        urls += 1
                    } else {
                        // An internal cross-reference resolves, so following one is `bySlug` and
                        // nothing more.
                        XCTAssertTrue(known.contains(link.slug!), "\(article.slug) -> \(link.slug!)")
                        XCTAssertNotNil(m.bySlug(link.slug!))
                        slugs += 1
                    }
                }
            }
        }
        XCTAssertEqual(urls, 73)
        XCTAssertEqual(slugs, 12)
        // One of each form, named, so a port that models only one of them fails here.
        let internalLinks = m.bySlug("big_bang_crunch")!.blocks.flatMap(\.links)
        XCTAssertEqual(internalLinks, [MiracleLink(label: "Dark Energy", slug: "dark_energy")])
        let external = m.bySlug("atoms")!.blocks.flatMap(\.links).filter { $0.url != nil }
        XCTAssertFalse(external.isEmpty)
        XCTAssertTrue(external.allSatisfy { $0.url!.hasPrefix("http") })
    }

    func testTextLeavesTheQuotesOut() {
        let abjad = m.bySlug("abjad_numerals")!
        let quote = abjad.blocks.first { $0.kind == "quote" }!
        XCTAssertEqual(quote.sourceLabel, "Wikipedia, Abjad Numerals, 2021")
        let text = m.text("abjad_numerals")
        // The quote sits between the lead and the first text block, and none of it comes through:
        // it is somebody else's words next to a source label, not the article's voice.
        XCTAssertFalse(text.contains(quote.text.prefix(40)))
        XCTAssertFalse(text.contains("Wikipedia"))
        // What does come through is claim, lead, text and closer, in reading order.
        XCTAssertTrue(text.hasPrefix("Alphanumeric code."))
        XCTAssertTrue(text.contains("We found this ancient numeral system encoded in the Quran."))
        XCTAssertEqual(text.components(separatedBy: "\n\n").count, 6)
        XCTAssertEqual(m.text("big_bang_crunch").components(separatedBy: "\n\n").count, 4)
        XCTAssertEqual(m.text("no_such_article"), "")
    }

    func testSearchMatchesTitleOrProse() {
        let hits = m.search("big bang").map(\.slug)
        XCTAssertTrue(hits.contains("big_bang_crunch"))
        XCTAssertEqual(m.search("BIG BANG").map(\.slug), hits)
        XCTAssertLessThanOrEqual(m.search("cosmology", limit: 3).count, 3)
        XCTAssertTrue(m.search("").isEmpty)
        XCTAssertTrue(m.search("   ").isEmpty)
        XCTAssertTrue(m.search("zzzznotaword").isEmpty)
    }

    func testAnEmptyCorpusAnswersNothing() {
        // `Engine.load` builds this module from nil when the pack is absent, and every call has to
        // survive that: a consumer without it sees an empty corpus, not a crash.
        let empty = Miracles()
        XCTAssertFalse(empty.isLoaded)
        XCTAssertTrue(empty.all().isEmpty)
        XCTAssertTrue(empty.categories().isEmpty)
        XCTAssertNil(empty.bySlug("big_bang_crunch"))
        XCTAssertNil(empty.category("cosmology"))
        XCTAssertTrue(empty.levels().isEmpty)
        XCTAssertTrue(empty.citing(21, 30).isEmpty)
        XCTAssertTrue(empty.ayahRefs("big_bang_crunch").isEmpty)
        XCTAssertEqual(empty.text("big_bang_crunch"), "")
        XCTAssertTrue(empty.search("big bang").isEmpty)
        XCTAssertFalse(empty.imagesIncluded)
        let counts = empty.count()
        XCTAssertEqual(counts.articles, 0)
        XCTAssertEqual(counts.categories, 0)
        XCTAssertEqual(counts.ayahRefs, 0)
        XCTAssertTrue(m.isLoaded)
    }
}
