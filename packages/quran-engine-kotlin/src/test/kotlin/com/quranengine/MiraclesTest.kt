package com.quranengine

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * The scientific-miracles corpus: 202 articles under 15 categories.
 *
 * Mirrors the JS `test/miracles.test.js`, the Python `tests/test_miracles.py`, the Go
 * `miracles_test.go`, the Rust `tests/miracles.rs`, the Dart `test/miracles_test.dart` and the
 * Swift `MiraclesTests.swift` case for case.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class MiraclesTest {

    private lateinit var engine: Engine
    private lateinit var m: Miracles

    @BeforeAll
    fun setup() {
        engine = Engine.load(Engine.findDefaultDataDir()!!)
        m = engine.miracles
    }

    @Test
    fun `202 articles under 15 categories, citing 278 ayah ranges`() {
        assertEquals(MiraclesCount(202, 15, 278), m.count())
        assertEquals(202, m.all().size)
        assertEquals(15, m.categories().size)
    }

    @Test
    fun `a slug round-trips, with its title, category and level intact`() {
        val article = m.bySlug("big_bang_crunch")
        assertNotNull(article)
        assertEquals("Big Bang", article!!.title)
        assertEquals("cosmology", article.category)
        assertEquals("extreme", article.level)
        assertNull(m.bySlug("no_such_article"))
        // Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
        assertEquals(202, m.all().map { it.slug }.toSet().size)
    }

    @Test
    fun `the categories partition the 202 with nothing left over`() {
        var total = 0
        for (category in m.categories()) {
            val members = m.byCategory(category.id)
            assertTrue(members.isNotEmpty(), "category ${category.id} has no articles")
            total += members.size
        }
        assertEquals(202, total)
        assertEquals(18, m.byCategory("cosmology").size)
        assertTrue(m.byCategory("no_such_category").isEmpty())
    }

    @Test
    fun `a category is found by id, and its level is the category's own`() {
        val cosmology = m.category("cosmology")
        assertNotNull(cosmology)
        assertEquals("cosmology", cosmology!!.id)
        assertEquals("advanced", cosmology.level)
        assertNull(m.category("no_such_category"))
    }

    @Test
    fun `an article's level is its own, not its category's`() {
        // Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
        // itself is "extreme". Filtering on the category's level would put it in the wrong bucket,
        // and it is not one article out of place: most of the corpus disagrees with its category.
        assertEquals("advanced", m.category("cosmology")!!.level)
        assertEquals("extreme", m.bySlug("big_bang_crunch")!!.level)
        val catLevel = m.categories().associate { it.id to it.level }
        val differing = m.all().count { it.level != catLevel[it.category] }
        assertEquals(147, differing)
    }

    @Test
    fun `the levels run simple to extreme, which is not alphabetical`() {
        assertEquals(listOf("simple", "intermediate", "advanced", "extreme"), m.levels())
        assertEquals(MIRACLE_LEVELS, m.levels())
        // Sorted as strings, "extreme" would come second. That is the whole reason the rank is
        // hard-coded.
        assertTrue(m.levels() != m.levels().sorted())
        assertEquals(6, m.byLevel("simple").size)
        assertEquals(103, m.byLevel("intermediate").size)
        assertEquals(37, m.byLevel("advanced").size)
        assertEquals(56, m.byLevel("extreme").size)
        assertEquals(m.all().size, MIRACLE_LEVELS.sumOf { m.byLevel(it).size })
    }

    @Test
    fun `every article names a category and a level the lists know`() {
        val ids = m.categories().map { it.id }.toSet()
        for (article in m.all()) {
            assertTrue(article.slug.isNotEmpty())
            assertTrue(article.title.isNotEmpty(), article.slug)
            assertTrue(article.category in ids, "${article.slug} is filed under ${article.category}")
            assertTrue(article.level in MIRACLE_LEVELS, "${article.slug} is at ${article.level}")
            assertTrue(article.blocks.isNotEmpty(), article.slug)
        }
    }

    @Test
    fun `citing finds the articles that reach an ayah`() {
        // 21:30 is cited by exactly two: Big Bang and Exoplanets.
        assertEquals(listOf("big_bang_crunch", "exoplanets"), m.citing(21, 30).map { it.slug })
        // 23:14, the embryology verse, by three.
        assertEquals(
            listOf("bones", "fetal_development", "human_embryo"),
            m.citing(23, 14).map { it.slug },
        )
        assertTrue(m.citing(21, 999).isEmpty())
        assertTrue(m.citing(999, 1).isEmpty())
    }

    @Test
    fun `an ayah block is a range, so citing answers for the middle of it`() {
        // Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
        // one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range
        // end is what bounds the search, not the surah).
        assertEquals(listOf(MiracleAyahRef(111, 1, 5)), m.ayahRefs("abjad_numerals"))
        for (ayah in 1..5) {
            assertTrue(m.citing(111, ayah).any { it.slug == "abjad_numerals" }, "111:$ayah")
        }
        assertFalse(m.citing(111, 6).any { it.slug == "abjad_numerals" })
        assertTrue(m.ayahRefs("no_such_article").isEmpty())
    }

    @Test
    fun `every ayah ref points at a real ayah of this engine's Quran`() {
        var refs = 0
        var ranges = 0
        for (article in m.all()) {
            for (ref in m.ayahRefs(article.slug)) {
                assertTrue(ref.endAyah >= ref.ayah, article.slug)
                // Both ends resolve, which is the point of storing the reference rather than the
                // text.
                assertNotNull(engine.quran.ayah(ref.surah, ref.ayah), "${article.slug} -> $ref")
                assertNotNull(engine.quran.ayah(ref.surah, ref.endAyah), "${article.slug} -> $ref")
                refs += 1
                if (ref.endAyah > ref.ayah) ranges += 1
            }
        }
        assertEquals(278, refs)
        assertEquals(49, ranges)
    }

    @Test
    fun `no block anywhere is an image, and the corpus says so itself`() {
        // The site's illustrations are deliberately not republished. A consumer that leaves a gap
        // for a picture would wait forever, so the corpus states it and the blocks bear it out.
        assertFalse(m.imagesIncluded)
        val kinds = m.all().flatMap { a -> a.blocks.map { it.kind } }.toSortedSet()
        assertFalse("image" in kinds)
        assertEquals(listOf("ayah", "claim", "closer", "lead", "quote", "text"), kinds.toList())
        assertTrue(m.source().contains("miracles-of-quran.com"))
    }

    @Test
    fun `a link is either an outside url or an internal slug, never both`() {
        var urls = 0
        var slugs = 0
        val known = m.all().map { it.slug }.toSet()
        for (article in m.all()) {
            for (block in article.blocks) {
                for (link in block.links) {
                    assertTrue(link.label.isNotEmpty(), article.slug)
                    assertTrue(
                        (link.url != null) != (link.slug != null),
                        "${article.slug}: ${link.label}",
                    )
                    if (link.url != null) {
                        urls += 1
                    } else {
                        // An internal cross-reference resolves, so following one is `bySlug` and
                        // nothing more.
                        assertTrue(link.slug in known, "${article.slug} -> ${link.slug}")
                        assertNotNull(m.bySlug(link.slug!!))
                        slugs += 1
                    }
                }
            }
        }
        assertEquals(73, urls)
        assertEquals(12, slugs)
        // One of each form, named, so a port that models only one of them fails here.
        val internal = m.bySlug("big_bang_crunch")!!.blocks.flatMap { it.links }
        assertEquals(listOf(MiracleLink("Dark Energy", null, "dark_energy")), internal)
        val external = m.bySlug("atoms")!!.blocks.flatMap { it.links }.filter { it.url != null }
        assertTrue(external.isNotEmpty())
        assertTrue(external.all { it.url!!.startsWith("http") })
    }

    @Test
    fun `text joins the article's own prose and leaves the quotes out`() {
        val abjad = m.bySlug("abjad_numerals")!!
        val quote = abjad.blocks.first { it.kind == "quote" }
        assertEquals("Wikipedia, Abjad Numerals, 2021", quote.sourceLabel)
        val text = m.text("abjad_numerals")
        // The quote sits between the lead and the first text block, and none of it comes through:
        // it is somebody else's words next to a source label, not the article's voice.
        assertFalse(text.contains(quote.text.take(40)))
        assertFalse(text.contains("Wikipedia"))
        // What does come through is claim, lead, text and closer, in reading order.
        assertTrue(text.startsWith("Alphanumeric code."))
        assertTrue(text.contains("We found this ancient numeral system encoded in the Quran."))
        assertEquals(6, text.split("\n\n").size)
        assertEquals(4, m.text("big_bang_crunch").split("\n\n").size)
        assertEquals("", m.text("no_such_article"))
    }

    @Test
    fun `search matches a title or the prose, case-insensitively`() {
        val hits = m.search("big bang").map { it.slug }
        assertTrue("big_bang_crunch" in hits)
        assertEquals(hits, m.search("BIG BANG").map { it.slug })
        assertTrue(m.search("cosmology", 3).size <= 3)
        assertTrue(m.search("").isEmpty())
        assertTrue(m.search("   ").isEmpty())
        assertTrue(m.search("zzzznotaword").isEmpty())
    }

    @Test
    fun `an empty corpus answers nothing rather than throwing`() {
        // `Engine.load` builds this module from an empty file when the pack is absent, and every
        // call has to survive that: a consumer without it sees an empty corpus, not a crash.
        val empty = Miracles()
        assertFalse(empty.isLoaded)
        assertTrue(empty.all().isEmpty())
        assertTrue(empty.categories().isEmpty())
        assertNull(empty.bySlug("big_bang_crunch"))
        assertNull(empty.category("cosmology"))
        assertTrue(empty.levels().isEmpty())
        assertTrue(empty.citing(21, 30).isEmpty())
        assertTrue(empty.ayahRefs("big_bang_crunch").isEmpty())
        assertEquals("", empty.text("big_bang_crunch"))
        assertTrue(empty.search("big bang").isEmpty())
        assertFalse(empty.imagesIncluded)
        assertEquals(MiraclesCount(0, 0, 0), empty.count())
        assertTrue(m.isLoaded)
    }
}
