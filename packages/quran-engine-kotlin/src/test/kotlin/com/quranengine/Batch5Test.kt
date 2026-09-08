package com.quranengine

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.time.Instant
import java.time.ZoneOffset

/**
 * Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil, the qiraat variant
 * matrix and the word of the day.
 *
 * Mirrors the JS `test/batch5.test.js`, the Python `tests/test_batch5.py`, the Go `batch5_test.go`,
 * the Rust `tests/batch5.rs` and the Swift `Batch5Tests.swift` case for case. Every count is pinned
 * against the app's own verify gate.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class Batch5Test {

    private lateinit var engine: Engine

    @BeforeAll
    fun setUp() {
        engine = Engine.load(
            loadMorphology = true,
            loadMutashabihat = true,
            loadQuranTopics = true,
            loadQiraatVariants = true,
        )
    }

    private fun tokens(surah: Int, ayah: Int): List<String> =
        (engine.quran.ayah(surah, ayah)?.textArabic ?: "").split(WHITESPACE).filter { it.isNotEmpty() }

    /**
     * The upstream fold: harakat and the waqf marks gone, alif wasla and the hamza seats
     * normalized. Occurrences were matched this way, so ٱلۡحَمۡدُۖ at 64:1 is the same form as
     * ٱلۡحَمۡدُ and a literal comparison would call a pause mark a mismatch.
     */
    private fun fold(text: String): String = buildString {
        for (ch in text) {
            val cp = ch.code
            when {
                cp in 0x064B..0x065F || cp == 0x0670 || cp in 0x06D6..0x06ED || cp == 0x0640 -> {}
                cp == 0x0671 || cp == 0x0623 || cp == 0x0625 -> append('ا')
                cp == 0x0624 -> append('و')
                cp == 0x0626 -> append('ي')
                else -> append(ch)
            }
        }
    }

    // ---- morphology ---------------------------------------------------------------

    @Test
    fun `morphology corpus size matches the app gate`() {
        assertEquals(Triple(1642, 4817, 77629), engine.morphology.count())
    }

    @Test
    fun `morphology ids are one based and zero means no root`() {
        assertNull(engine.morphology.root(0), "id 0 means the token has no root")
        assertNotNull(engine.morphology.root(1))
        assertNull(engine.morphology.root(1643), "root ids stop at the table size")
        val ids = engine.morphology.ids(1, 1)
        assertEquals(4, ids?.first?.size)
        assertEquals(4, ids?.second?.size)
    }

    @Test
    fun `morphology token resolves to root and lemma`() {
        // 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
        val root = engine.morphology.rootOf(1, 2, 2)
        assertEquals("ر ب ب", root?.second?.letters)
        assertEquals("rbb", root?.second?.buckwalter)
        assertEquals("ربب", root?.second?.joined)
        assertNotNull(engine.morphology.lemmaOf(1, 2, 2))
    }

    @Test
    fun `morphology occurrences come back in mushaf order`() {
        val hit = engine.morphology.findRoots("ربب", 5).first()
        val found = engine.morphology.occurrencesOfRoot(hit.first)
        assertEquals(980, found.size)
        assertEquals(WordLocation(1, 2, 2), found.first())
        val ranks = found.map { it.surah * 1_000_000 + it.ayah * 1_000 + it.token }
        assertEquals(ranks.sorted(), ranks, "not in mushaf order")
    }

    @Test
    fun `morphology fold closes the spaces`() {
        // A lexicon prints "ر ب ب" and a reader types "ربب"; the fold has to close the spaces, not
        // merely trim them. Java's \s is ASCII-only, which is why the fold names Unicode.
        assertEquals("ربب", Morphology.fold("ر ب ب"))
        for (query in listOf("ربب", "ر ب ب", "rbb")) {
            assertTrue(
                engine.morphology.findRoots(query, 5).any { it.second.buckwalter == "rbb" },
                "no rbb for $query",
            )
        }
    }

    // ---- mutashabihat -------------------------------------------------------------

    @Test
    fun `mutashabihat counts`() {
        assertEquals(814 to 2232, engine.mutashabihat.count())
    }

    @Test
    fun `mutashabihat phrase shape`() {
        val phrase = engine.mutashabihat.phrase(10167)
        assertNotNull(phrase)
        assertEquals("9:87", phrase!!.source)
        assertEquals(5..10, phrase.span)
        assertEquals(6, phrase.wordCount)
        assertEquals(3, phrase.ayahCount)
        assertEquals(2, phrase.surahCount)
        assertEquals(listOf(13..19), phrase.occurrences["9:93"])
    }

    @Test
    fun `mutashabihat occurrences are in mushaf order not key order`() {
        assertEquals(
            listOf("9:87", "9:93", "63:3"),
            engine.mutashabihat.occurrences(10167).map { it.key },
        )
    }

    @Test
    fun `mutashabihat phrase slices out of the text you hand it`() {
        val source = engine.quran.ayah(9, 87)?.textArabic ?: ""
        val text = engine.mutashabihat.textOf(10167, source)
        assertEquals(6, text.split(WHITESPACE).filter { it.isNotEmpty() }.size)
        assertTrue(source.contains(text.split(WHITESPACE).first()))
    }

    @Test
    fun `mutashabihat has agrees with the lookup`() {
        assertTrue(engine.mutashabihat.has(9, 87))
        assertTrue(engine.mutashabihat.phrasesFor(9, 87).isNotEmpty())
        assertEquals(engine.mutashabihat.has(1, 1), engine.mutashabihat.phrasesFor(1, 1).isNotEmpty())
    }

    // ---- QUL topics ---------------------------------------------------------------

    @Test
    fun `qul topic counts and the double listing`() {
        val counts = engine.quranTopics.count()
        assertEquals(2512, counts.topics)
        assertEquals(30687, counts.references)
        assertEquals(695, counts.thematic)
        assertEquals(284, counts.ontology)
        assertEquals(1550, counts.index)
        // Deliberately sums to MORE than the topic count: the 17 topics listed in two indexes are
        // counted in both, which is what "listed in" means.
        assertEquals(2529, counts.thematic + counts.ontology + counts.index)
    }

    @Test
    fun `qul topics are three independent trees`() {
        assertEquals(17, engine.quranTopics.topics().count { it.families.size > 1 })
        assertEquals(
            listOf(TopicTree.thematic, TopicTree.ontology),
            engine.quranTopics.topic(13)?.families,
        )
        assertEquals(
            "Prophets (25 mentioned by name)",
            engine.quranTopics.parent(13, TopicTree.thematic)?.name,
        )
        assertEquals("Prophet", engine.quranTopics.parent(13, TopicTree.ontology)?.name)
        // A tree is not closed over its own listing either: the A-Z index hangs entries under
        // thematic topics, so asserting a parent shares its child's family would be false.
        val crossing = engine.quranTopics.topics().count { topic ->
            val parentId = topic.parentIn(TopicTree.index) ?: return@count false
            engine.quranTopics.topic(parentId)?.isListedIn(TopicTree.index) == false
        }
        assertTrue(crossing > 0, "expected the index tree to reach outside its own listing")
    }

    @Test
    fun `qul topic parents all resolve`() {
        for (topic in engine.quranTopics.topics()) {
            for (tree in TopicTree.entries) {
                val parentId = topic.parentIn(tree) ?: continue
                assertNotNull(
                    engine.quranTopics.topic(parentId),
                    "topic ${topic.id} (${topic.name}) has a dangling $tree parent $parentId",
                )
            }
        }
    }

    @Test
    fun `qul topic ancestors terminate in every tree`() {
        for (tree in TopicTree.entries) {
            val deep = engine.quranTopics.topics()
                .first { engine.quranTopics.ancestors(it.id, tree).size >= 2 }
            val chain = engine.quranTopics.ancestors(deep.id, tree)
            assertEquals(chain.size, chain.map { it.id }.toSet().size, "cycle in $tree")
            assertNull(chain.last().parentIn(tree))
        }
    }

    @Test
    fun `qul topic children list their parent`() {
        for (tree in TopicTree.entries) {
            val child = engine.quranTopics.topics().first { it.parentIn(tree) != null }
            val parentId = child.parentIn(tree)!!
            assertTrue(
                engine.quranTopics.children(parentId, tree).any { it.id == child.id },
                "${child.name} missing from its $tree parent",
            )
        }
    }

    @Test
    fun `qul topic references are real ayahs`() {
        val sample = engine.quranTopics.topics().take(200)
        for (topic in sample) {
            for (key in topic.ayahs) {
                val (surah, ayah) = splitAyahKey(key)
                assertNotNull(engine.quran.ayah(surah, ayah), "${topic.name} cites $key")
            }
        }
        val first = sample.first()
        val (surah, ayah) = splitAyahKey(first.ayahs.first())
        assertTrue(engine.quranTopics.topicsFor(surah, ayah).any { it.id == first.id })
    }

    // ---- passage themes -----------------------------------------------------------

    @Test
    fun `passage counts`() {
        assertEquals(114 to 1049, engine.ayahThemes.count())
    }

    @Test
    fun `passages are ordered and never overlap`() {
        for (surah in engine.quran.all()) {
            var previousEnd = 0
            for (passage in engine.ayahThemes.passages(surah.id)) {
                assertTrue(
                    previousEnd == 0 || passage.from > previousEnd,
                    "surah ${surah.id}: ${passage.from} overlaps $previousEnd",
                )
                assertTrue(passage.to >= passage.from)
                assertTrue(passage.to <= surah.numberOfAyahs)
                previousEnd = passage.to
            }
        }
    }

    @Test
    fun `passage for finds the containing passage`() {
        val passage = engine.ayahThemes.passageFor(2, 10)
        assertEquals("Hypocrites and the consequences of hypocrisy", passage?.theme)
        assertEquals(8, passage?.from)
        assertEquals(16, passage?.to)
    }

    // ---- hizb / ruku / manzil -----------------------------------------------------

    @Test
    fun `division counts and first starts`() {
        assertEquals(Triple(60, 558, 7), engine.quranMetadata.count())
        for (table in listOf(engine.quranMetadata.hizb, engine.quranMetadata.ruku, engine.quranMetadata.manzil)) {
            assertEquals("1:1", table.start(1)?.key)
        }
    }

    @Test
    fun `division starts ascend and are real ayahs`() {
        for (table in listOf(engine.quranMetadata.hizb, engine.quranMetadata.ruku, engine.quranMetadata.manzil)) {
            val all = table.all()
            for ((a, b) in all.zipWithNext()) {
                assertTrue(
                    a.surah < b.surah || (a.surah == b.surah && a.ayah < b.ayah),
                    "out of order at ${b.key}",
                )
                assertNotNull(engine.quran.ayah(b.surah, b.ayah), "${b.key} is not an ayah")
            }
        }
    }

    @Test
    fun `division lookup contains the ayah`() {
        assertEquals(Triple(1, 1, 1), engine.quranMetadata.divisionsFor(1, 1))
        val last = engine.quranMetadata.divisionsFor(114, 6)
        assertEquals(60, last.first)
        assertEquals(7, last.third)
        val n = engine.quranMetadata.hizb.numberFor(2, 255)
        val (from, until) = engine.quranMetadata.hizb.range(n)!!
        assertTrue(from.surah < 2 || (from.surah == 2 && from.ayah <= 255))
        if (until != null) assertTrue(until.surah > 2 || (until.surah == 2 && until.ayah > 255))
    }

    // ---- qiraat variants ----------------------------------------------------------

    @Test
    fun `qiraat variant counts`() {
        assertEquals(Triple(1409, 1634, 3503), engine.qiraatVariants.count())
    }

    @Test
    fun `juncture names word readings and who reads them`() {
        val junctures = engine.qiraatVariants.junctures(102, 6)
        assertTrue(junctures.isNotEmpty(), "102:6 carries a variant")
        for (juncture in junctures) {
            assertTrue(juncture.readings.size >= 2, "a juncture with one reading is not a variant")
            for (reading in juncture.readings) {
                assertTrue(reading.text.isNotEmpty())
                assertFalse(
                    reading.readers.isEmpty() && reading.transmitters.isEmpty(),
                    "a reading nobody reads",
                )
                assertTrue(engine.qiraatVariants.attribution(reading).isNotEmpty())
            }
        }
    }

    @Test
    fun `hafs follows a reading at junctures he is party to`() {
        var matched = 0
        for (surah in 1..20) {
            for (ayah in 1..20) {
                for (juncture in engine.qiraatVariants.junctures(surah, ayah)) {
                    if (engine.qiraatVariants.readingFor(juncture, "hafs") != null) matched++
                }
            }
        }
        assertTrue(matched > 0, "Hafs reads none of the sampled junctures")
    }

    @Test
    fun `segment spans are inclusive or an honest null`() {
        for (surah in 1..30) {
            for (ayah in 1..30) {
                for (juncture in engine.qiraatVariants.junctures(surah, ayah)) {
                    for (segment in juncture.segments) {
                        val range = segment.range ?: continue
                        val (s, a) = splitAyahKey(segment.ayah)
                        assertTrue(range.last < tokens(s, a).size, "${segment.ayah} span past the end")
                    }
                }
            }
        }
    }

    // ---- qiraat places ------------------------------------------------------------

    @Test
    fun `places cover only the published riwayat`() {
        // Hafs is the reference and indexes nothing against itself.
        assertEquals(
            listOf("buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"),
            engine.qiraatVariants.riwayatWithPlaces(),
        )
    }

    @Test
    fun `places point at tokens the ayah has`() {
        for (slug in engine.qiraatVariants.riwayatWithPlaces()) {
            for (surah in listOf(1, 2, 18)) {
                for (place in engine.qiraatVariants.places(slug, surah)) {
                    val count = tokens(surah, place.ayah).size
                    for (index in place.word + place.letter) {
                        assertTrue(index in 0 until count, "$slug $surah:${place.ayah} index $index")
                    }
                }
            }
        }
    }

    @Test
    fun `al fatihah carries a difference for warsh`() {
        val fourth = engine.qiraatVariants.places("warsh", 1).firstOrNull { it.ayah == 4 }
        assertNotNull(fourth, "Warsh differs from Hafs at 1:4")
        assertTrue(fourth!!.word.isNotEmpty() || fourth.letter.isNotEmpty())
    }

    // ---- paired recordings --------------------------------------------------------

    @Test
    fun `audio covers four riwayat and honestly no others`() {
        assertEquals(4, engine.qiraatVariants.riwayatWithAudio().size)
        assertNull(
            engine.qiraatVariants.audio("qunbul", 1, 4),
            "Qunbul has no reciter who published both sides with timings",
        )
    }

    @Test
    fun `audio pair is one reciter two urls and matching span kinds`() {
        var found = 0
        outer@ for (slug in engine.qiraatVariants.riwayatWithAudio()) {
            for (surah in 1..114) {
                for (ayah in 1..10) {
                    val pair = engine.qiraatVariants.audio(slug, surah, ayah) ?: continue
                    found++
                    assertTrue(pair.reciter.isNotEmpty())
                    assertTrue(pair.hafs.url.endsWith(".mp3"))
                    assertTrue(pair.riwayah.url.endsWith(".mp3"))
                    assertTrue(pair.hafs.url != pair.riwayah.url, "a pair must differ in the reading")
                    assertEquals(pair.hafs.startMs == null, pair.riwayah.startMs == null)
                    val start = pair.hafs.startMs
                    if (start != null) assertTrue(pair.hafs.endMs!! > start)
                    if (found >= 8) break@outer
                    break
                }
            }
        }
        assertTrue(found >= 4, "only found $found pairs")
    }

    // ---- word of the day ----------------------------------------------------------

    @Test
    fun `word of day count`() {
        assertEquals(149, engine.wordOfDay.count().first)
    }

    @Test
    fun `word of day walk wraps and handles a negative index`() {
        val all = engine.wordOfDay.all()
        assertEquals(all.first().id, engine.wordOfDay.forDayIndex(0)?.id)
        assertEquals(all.first().id, engine.wordOfDay.forDayIndex(all.size.toLong())?.id)
        assertEquals(all.last().id, engine.wordOfDay.forDayIndex(-1)?.id)
        val noon = Instant.ofEpochSecond(1_788_000_000)
        assertEquals(
            engine.wordOfDay.forDate(noon, ZoneOffset.UTC)?.id,
            engine.wordOfDay.forDate(noon.plusSeconds(3600), ZoneOffset.UTC)?.id,
        )
    }

    @Test
    fun `word of day count is the length of the list behind it`() {
        for (word in engine.wordOfDay.all()) {
            assertEquals(word.count, word.occurrences.sumOf { it.tokens.size }, word.id)
        }
    }

    @Test
    fun `word of day anchor and folded tokens`() {
        for (word in engine.wordOfDay.all()) {
            val first = word.occurrences.first()
            assertEquals(word.surah, first.surah, word.id)
            assertEquals(word.ayah, first.ayah, word.id)
            assertEquals(word.token, first.tokens.first(), word.id)
            val target = fold(word.arabic)
            for (occurrence in word.occurrences) {
                val row = tokens(occurrence.surah, occurrence.ayah)
                for (index in occurrence.tokens) {
                    assertEquals(
                        target,
                        fold(row[index]),
                        "${word.id} at ${occurrence.surah}:${occurrence.ayah}",
                    )
                }
            }
        }
    }

    @Test
    fun `word of day search and reverse lookup`() {
        val first = engine.wordOfDay.all().first()
        assertTrue(engine.wordOfDay.search(first.arabic).any { it.id == first.id })
        assertTrue(engine.wordOfDay.wordsIn(first.surah, first.ayah).any { it.id == first.id })
    }
}
