import XCTest
@testable import QuranEngine

/// Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil, the qiraat variant
/// matrix and the word of the day.
///
/// Mirrors the JS `test/batch5.test.js`, the Python `tests/test_batch5.py`, the Go
/// `batch5_test.go` and the Rust `tests/batch5.rs` case for case. Every count is pinned against
/// the app's own verify gate, so a corpus that reaches the engine half-imported fails loudly
/// rather than quietly answering less than it should.
final class Batch5Tests: XCTestCase {
    private static let engine: Engine = {
        do {
            return try Engine.load(loadMorphology: true, loadMutashabihat: true,
                                   loadQuranTopics: true, loadQiraatVariants: true)
        } catch {
            fatalError("Failed to load engine: \(error)")
        }
    }()

    private var engine: Engine { Self.engine }

    private func tokens(_ surah: Int, _ ayah: Int) -> [String] {
        (engine.quran.ayah(surah, ayah)?.textArabic ?? "")
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The upstream fold: harakat and the waqf marks gone, alif wasla and the hamza seats
    /// normalized. Occurrences were matched this way, so ٱلۡحَمۡدُۖ at 64:1 is the same form as
    /// ٱلۡحَمۡدُ and a literal comparison would call a pause mark a mismatch.
    private func fold(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: continue
            case 0x0671, 0x0623, 0x0625: out.append("ا")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - Morphology

    func testMorphologyCorpusSize() {
        let counts = engine.morphology.count()
        XCTAssertEqual(counts.roots, 1642)
        XCTAssertEqual(counts.lemmas, 4817)
        XCTAssertEqual(counts.tokens, 77629)
    }

    func testMorphologyIdsAreOneBasedAndZeroMeansNoRoot() {
        XCTAssertNil(engine.morphology.root(id: 0), "id 0 means the token has no root")
        XCTAssertNotNil(engine.morphology.root(id: 1))
        XCTAssertNil(engine.morphology.root(id: 1643), "root ids stop at the table size")
        let ids = engine.morphology.ids(surah: 1, ayah: 1)
        XCTAssertEqual(ids?.roots.count, 4)
        XCTAssertEqual(ids?.lemmas.count, 4)
    }

    func testMorphologyTokenResolvesToRootAndLemma() {
        // 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
        let root = engine.morphology.root(surah: 1, ayah: 2, token: 2)
        XCTAssertEqual(root?.root.letters, "ر ب ب")
        XCTAssertEqual(root?.root.buckwalter, "rbb")
        XCTAssertEqual(root?.root.joined, "ربب")
        XCTAssertNotNil(engine.morphology.lemma(surah: 1, ayah: 2, token: 2))
    }

    func testMorphologyOccurrencesAreInMushafOrder() {
        guard let hit = engine.morphology.findRoots("ربب", limit: 5).first else {
            return XCTFail("ربب resolves")
        }
        let found = engine.morphology.occurrences(ofRoot: hit.id)
        XCTAssertEqual(found.count, 980)
        XCTAssertEqual(found.first, WordLocation(surah: 1, ayah: 2, token: 2))
        let ranks = found.map { $0.surah * 1_000_000 + $0.ayah * 1_000 + $0.token }
        XCTAssertEqual(ranks, ranks.sorted(), "not in mushaf order")
    }

    func testMorphologyFoldClosesTheSpaces() {
        // A lexicon prints "ر ب ب" and a reader types "ربب"; the fold has to close the spaces,
        // not merely trim them.
        XCTAssertEqual(Morphology.fold("ر ب ب"), "ربب")
        for query in ["ربب", "ر ب ب", "rbb"] {
            XCTAssertTrue(engine.morphology.findRoots(query, limit: 5)
                .contains { $0.root.buckwalter == "rbb" }, "no rbb for \(query)")
        }
    }

    // MARK: - Mutashabihat

    func testMutashabihatCounts() {
        let counts = engine.mutashabihat.count()
        XCTAssertEqual(counts.phrases, 814)
        XCTAssertEqual(counts.ayahs, 2232)
    }

    func testMutashabihatPhraseShape() {
        guard let phrase = engine.mutashabihat.phrase(id: 10167) else {
            return XCTFail("phrase 10167 exists")
        }
        XCTAssertEqual(phrase.source, "9:87")
        XCTAssertEqual(phrase.span, 5...10)
        XCTAssertEqual(phrase.wordCount, 6)
        XCTAssertEqual(phrase.ayahCount, 3)
        XCTAssertEqual(phrase.surahCount, 2)
        XCTAssertEqual(phrase.occurrences["9:93"], [13...19])
    }

    func testMutashabihatOccurrencesAreInMushafOrderNotKeyOrder() {
        XCTAssertEqual(engine.mutashabihat.occurrences(id: 10167).map(\.key),
                       ["9:87", "9:93", "63:3"])
    }

    func testMutashabihatPhraseSlicesOutOfTheTextYouHandIt() {
        let source = engine.quran.ayah(9, 87)?.textArabic ?? ""
        let text = engine.mutashabihat.text(id: 10167, sourceAyahText: source)
        XCTAssertEqual(text.split(whereSeparator: \.isWhitespace).count, 6)
        XCTAssertTrue(source.contains(text.split(whereSeparator: \.isWhitespace)[0]))
    }

    func testMutashabihatHasAgreesWithTheLookup() {
        XCTAssertTrue(engine.mutashabihat.has(surah: 9, ayah: 87))
        XCTAssertFalse(engine.mutashabihat.phrases(surah: 9, ayah: 87).isEmpty)
        XCTAssertEqual(engine.mutashabihat.has(surah: 1, ayah: 1),
                       !engine.mutashabihat.phrases(surah: 1, ayah: 1).isEmpty)
    }

    // MARK: - QUL topics

    func testQulTopicCountsAndTheDoubleListing() {
        let counts = engine.quranTopics.count()
        XCTAssertEqual(counts.topics, 2512)
        XCTAssertEqual(counts.references, 30687)
        XCTAssertEqual(counts.thematic, 695)
        XCTAssertEqual(counts.ontology, 284)
        XCTAssertEqual(counts.index, 1550)
        // Deliberately sums to MORE than the topic count: the 17 topics listed in two indexes are
        // counted in both, which is what "listed in" means.
        XCTAssertEqual(counts.thematic + counts.ontology + counts.index, 2529)
    }

    func testQulTopicsAreThreeIndependentTrees() {
        let both = engine.quranTopics.topics().filter { $0.families.count > 1 }
        XCTAssertEqual(both.count, 17)
        XCTAssertEqual(engine.quranTopics.topic(id: 13)?.families, [.thematic, .ontology])
        XCTAssertEqual(engine.quranTopics.parent(of: 13, in: .thematic)?.name,
                       "Prophets (25 mentioned by name)")
        XCTAssertEqual(engine.quranTopics.parent(of: 13, in: .ontology)?.name, "Prophet")
        // A tree is not closed over its own listing either: the A-Z index hangs entries under
        // thematic topics, so asserting a parent shares its child's family would be false.
        let crossing = engine.quranTopics.topics().filter { topic in
            guard let parentID = topic.parent(in: .index),
                  let parent = engine.quranTopics.topic(id: parentID) else { return false }
            return !parent.isListed(in: .index)
        }
        XCTAssertFalse(crossing.isEmpty, "expected the index tree to reach outside its listing")
    }

    func testQulTopicParentsAllResolve() {
        for topic in engine.quranTopics.topics() {
            for tree in TopicTree.allCases {
                guard let parentID = topic.parent(in: tree) else { continue }
                XCTAssertNotNil(engine.quranTopics.topic(id: parentID),
                                "topic \(topic.id) (\(topic.name)) has a dangling \(tree) parent")
            }
        }
    }

    func testQulTopicAncestorsTerminateInEveryTree() {
        for tree in TopicTree.allCases {
            guard let deep = engine.quranTopics.topics()
                .first(where: { engine.quranTopics.ancestors(of: $0.id, in: tree).count >= 2 }) else {
                return XCTFail("no topic two levels down in \(tree)")
            }
            let chain = engine.quranTopics.ancestors(of: deep.id, in: tree)
            XCTAssertEqual(Set(chain.map(\.id)).count, chain.count, "cycle in \(tree)")
            XCTAssertNil(chain.last?.parent(in: tree))
        }
    }

    func testQulTopicChildrenListTheirParent() {
        for tree in TopicTree.allCases {
            guard let child = engine.quranTopics.topics()
                .first(where: { $0.parent(in: tree) != nil }),
                  let parentID = child.parent(in: tree) else {
                return XCTFail("no child in \(tree)")
            }
            XCTAssertTrue(engine.quranTopics.children(of: parentID, in: tree)
                .contains { $0.id == child.id }, "\(child.name) missing from its \(tree) parent")
        }
    }

    func testQulTopicReferencesAreRealAyahs() {
        let sample = Array(engine.quranTopics.topics().prefix(200))
        for topic in sample {
            for key in topic.ayahs {
                let (surah, ayah) = splitAyahKey(key)
                XCTAssertNotNil(engine.quran.ayah(surah, ayah), "\(topic.name) cites \(key)")
            }
        }
        guard let first = sample.first, let key = first.ayahs.first else { return }
        let (surah, ayah) = splitAyahKey(key)
        XCTAssertTrue(engine.quranTopics.topics(surah: surah, ayah: ayah)
            .contains { $0.id == first.id })
    }

    // MARK: - Passage themes

    func testPassageCounts() {
        let counts = engine.ayahThemes.count()
        XCTAssertEqual(counts.surahs, 114)
        XCTAssertEqual(counts.passages, 1049)
    }

    func testPassagesAreOrderedAndNeverOverlap() {
        for surah in engine.quran.all() {
            var previousEnd = 0
            for passage in engine.ayahThemes.passages(surah: surah.id) {
                XCTAssertTrue(previousEnd == 0 || passage.from > previousEnd,
                              "surah \(surah.id): \(passage.from) overlaps \(previousEnd)")
                XCTAssertGreaterThanOrEqual(passage.to, passage.from)
                XCTAssertLessThanOrEqual(passage.to, surah.numberOfAyahs)
                previousEnd = passage.to
            }
        }
    }

    func testPassageForFindsTheContainingPassage() {
        let passage = engine.ayahThemes.passage(surah: 2, ayah: 10)
        XCTAssertEqual(passage?.theme, "Hypocrites and the consequences of hypocrisy")
        XCTAssertEqual(passage?.from, 8)
        XCTAssertEqual(passage?.to, 16)
    }

    // MARK: - Hizb, ruku, manzil

    func testDivisionCountsAndFirstStarts() {
        let counts = engine.quranMetadata.count()
        XCTAssertEqual(counts.hizb, 60)
        XCTAssertEqual(counts.ruku, 558)
        XCTAssertEqual(counts.manzil, 7)
        for table in [engine.quranMetadata.hizb, engine.quranMetadata.ruku,
                      engine.quranMetadata.manzil] {
            XCTAssertEqual(table.start(1)?.key, "1:1")
        }
    }

    func testDivisionStartsAscendAndAreRealAyahs() {
        for table in [engine.quranMetadata.hizb, engine.quranMetadata.ruku,
                      engine.quranMetadata.manzil] {
            let all = table.all()
            for (a, b) in zip(all, all.dropFirst()) {
                XCTAssertTrue(a.surah < b.surah || (a.surah == b.surah && a.ayah < b.ayah),
                              "out of order at \(b.key)")
                XCTAssertNotNil(engine.quran.ayah(b.surah, b.ayah), "\(b.key) is not an ayah")
            }
        }
    }

    func testDivisionLookupContainsTheAyah() {
        let first = engine.quranMetadata.divisions(surah: 1, ayah: 1)
        XCTAssertEqual(first.hizb, 1)
        XCTAssertEqual(first.ruku, 1)
        XCTAssertEqual(first.manzil, 1)
        let last = engine.quranMetadata.divisions(surah: 114, ayah: 6)
        XCTAssertEqual(last.hizb, 60)
        XCTAssertEqual(last.manzil, 7)
        let n = engine.quranMetadata.hizb.number(surah: 2, ayah: 255)
        guard let span = engine.quranMetadata.hizb.range(n) else { return XCTFail("a range") }
        XCTAssertTrue(span.from.surah < 2 || (span.from.surah == 2 && span.from.ayah <= 255))
        if let until = span.until {
            XCTAssertTrue(until.surah > 2 || (until.surah == 2 && until.ayah > 255))
        }
    }

    // MARK: - Qiraat variants

    func testQiraatVariantCounts() {
        let counts = engine.qiraatVariants.count()
        XCTAssertEqual(counts.ayahs, 1409)
        XCTAssertEqual(counts.junctures, 1634)
        XCTAssertEqual(counts.readings, 3503)
    }

    func testJunctureNamesWordReadingsAndWhoReadsThem() {
        let junctures = engine.qiraatVariants.junctures(surah: 102, ayah: 6)
        XCTAssertFalse(junctures.isEmpty, "102:6 carries a variant")
        for juncture in junctures {
            XCTAssertGreaterThanOrEqual(juncture.readings.count, 2,
                                        "a juncture with one reading is not a variant")
            for reading in juncture.readings {
                XCTAssertFalse(reading.text.isEmpty)
                XCTAssertFalse(reading.readers.isEmpty && reading.transmitters.isEmpty,
                               "a reading nobody reads")
                XCTAssertFalse(engine.qiraatVariants.attribution(for: reading).isEmpty)
            }
        }
    }

    func testHafsFollowsAReadingAtJuncturesHeIsPartyTo() {
        var matched = 0
        for surah in 1...20 {
            for ayah in 1...20 {
                for juncture in engine.qiraatVariants.junctures(surah: surah, ayah: ayah)
                where engine.qiraatVariants.reading(in: juncture, followedBy: "hafs") != nil {
                    matched += 1
                }
            }
        }
        XCTAssertGreaterThan(matched, 0, "Hafs reads none of the sampled junctures")
    }

    func testSegmentSpansAreInclusiveOrAnHonestNil() {
        for surah in 1...30 {
            for ayah in 1...30 {
                for juncture in engine.qiraatVariants.junctures(surah: surah, ayah: ayah) {
                    for segment in juncture.segments {
                        guard let range = segment.range else { continue }
                        let (s, a) = splitAyahKey(segment.ayah)
                        XCTAssertLessThan(range.upperBound, tokens(s, a).count,
                                          "\(segment.ayah) span past the end")
                    }
                }
            }
        }
    }

    // MARK: - Qiraat places

    func testPlacesCoverOnlyThePublishedRiwayat() {
        // Hafs is the reference and indexes nothing against itself.
        XCTAssertEqual(engine.qiraatVariants.riwayatWithPlaces(),
                       ["buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"])
    }

    func testPlacesPointAtTokensTheAyahHas() {
        for slug in engine.qiraatVariants.riwayatWithPlaces() {
            for surah in [1, 2, 18] {
                for place in engine.qiraatVariants.places(riwayah: slug, surah: surah) {
                    let count = tokens(surah, place.ayah).count
                    for index in place.word + place.letter {
                        XCTAssertTrue(index >= 0 && index < count,
                                      "\(slug) \(surah):\(place.ayah) index \(index)")
                    }
                }
            }
        }
    }

    func testAlFatihahCarriesADifferenceForWarsh() {
        let fourth = engine.qiraatVariants.places(riwayah: "warsh", surah: 1)
            .first { $0.ayah == 4 }
        XCTAssertNotNil(fourth, "Warsh differs from Hafs at 1:4")
        XCTAssertFalse((fourth?.word.isEmpty ?? true) && (fourth?.letter.isEmpty ?? true))
    }

    // MARK: - Paired recordings

    func testAudioCoversFourRiwayatAndHonestlyNoOthers() {
        XCTAssertEqual(engine.qiraatVariants.riwayatWithAudio().count, 4)
        XCTAssertNil(engine.qiraatVariants.audio(riwayah: "qunbul", surah: 1, ayah: 4),
                     "Qunbul has no reciter who published both sides with timings")
    }

    func testAudioPairIsOneReciterTwoUrlsAndMatchingSpanKinds() {
        var found = 0
        outer: for slug in engine.qiraatVariants.riwayatWithAudio() {
            for surah in 1...114 {
                for ayah in 1...10 {
                    guard let pair = engine.qiraatVariants.audio(riwayah: slug, surah: surah,
                                                                 ayah: ayah) else { continue }
                    found += 1
                    XCTAssertFalse(pair.reciter.isEmpty)
                    XCTAssertTrue(pair.hafs.url.hasSuffix(".mp3"))
                    XCTAssertTrue(pair.riwayah.url.hasSuffix(".mp3"))
                    XCTAssertNotEqual(pair.hafs.url, pair.riwayah.url,
                                      "a pair must differ in the reading")
                    XCTAssertEqual(pair.hafs.startMs == nil, pair.riwayah.startMs == nil)
                    if let start = pair.hafs.startMs, let end = pair.hafs.endMs {
                        XCTAssertGreaterThan(end, start)
                    }
                    if found >= 8 { break outer }
                    break
                }
            }
        }
        XCTAssertGreaterThanOrEqual(found, 4, "only found \(found) pairs")
    }

    // MARK: - Word of the day

    func testWordOfDayCount() {
        XCTAssertEqual(engine.wordOfDay.count().words, 149)
    }

    func testWordOfDayWalkWrapsAndHandlesANegativeIndex() {
        let all = engine.wordOfDay.all()
        XCTAssertEqual(engine.wordOfDay.word(dayIndex: 0)?.id, all.first?.id)
        XCTAssertEqual(engine.wordOfDay.word(dayIndex: all.count)?.id, all.first?.id)
        XCTAssertEqual(engine.wordOfDay.word(dayIndex: -1)?.id, all.last?.id)
        let utc = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertEqual(engine.wordOfDay.word(for: noon, timeZone: utc)?.id,
                       engine.wordOfDay.word(for: noon.addingTimeInterval(3600), timeZone: utc)?.id)
    }

    func testWordOfDayCountIsTheLengthOfTheListBehindIt() {
        for word in engine.wordOfDay.all() {
            let total = word.occurrences.reduce(0) { $0 + $1.tokens.count }
            XCTAssertEqual(word.count, total, word.id)
        }
    }

    func testWordOfDayAnchorAndFoldedTokens() {
        for word in engine.wordOfDay.all() {
            guard let first = word.occurrences.first else { return XCTFail(word.id) }
            XCTAssertEqual(first.surah, word.surah, word.id)
            XCTAssertEqual(first.ayah, word.ayah, word.id)
            XCTAssertEqual(first.tokens.first, word.token, word.id)
            let target = fold(word.arabic)
            for occurrence in word.occurrences {
                let row = tokens(occurrence.surah, occurrence.ayah)
                for index in occurrence.tokens {
                    XCTAssertEqual(fold(row[index]), target,
                                   "\(word.id) at \(occurrence.surah):\(occurrence.ayah)")
                }
            }
        }
    }

    func testWordOfDaySearchAndReverseLookup() {
        guard let first = engine.wordOfDay.all().first else { return XCTFail("no words") }
        XCTAssertTrue(engine.wordOfDay.search(first.arabic).contains { $0.id == first.id })
        XCTAssertTrue(engine.wordOfDay.words(surah: first.surah, ayah: first.ayah)
            .contains { $0.id == first.id })
    }
}
