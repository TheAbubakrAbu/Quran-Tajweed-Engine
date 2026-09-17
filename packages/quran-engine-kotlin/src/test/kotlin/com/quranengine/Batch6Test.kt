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
 * Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.
 *
 * Mirrors the JS `test/batch6.test.js`, the Python `tests/test_batch6.py`, the Go `batch6_test.go`,
 * the Rust `tests/batch6.rs`, the Dart `test/batch6_test.dart` and the Swift `Batch6Tests.swift`
 * case for case.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class Batch6Test {

    private lateinit var engine: Engine

    @BeforeAll
    fun setup() {
        engine = Engine.load(Engine.findDefaultDataDir()!!)
    }

    /** The upstream fold, as in batch 5: harakat and waqf marks gone, the hamza seats normalized. */
    private fun fold(text: String): String = buildString {
        for (ch in text) {
            val code = ch.code
            when {
                code in 0x064B..0x065F || code == 0x0670 || code in 0x06D6..0x06ED || code == 0x0640 -> Unit
                code == 0x0671 || code == 0x0623 || code == 0x0625 -> append('ا')
                code == 0x0624 -> append('و')
                code == 0x0626 -> append('ي')
                else -> append(ch)
            }
        }
    }

    // ---- the Names in depth ------------------------------------------------------

    @Test
    fun `all 99 Names carry depth under nine themes`() {
        assertEquals(Triple(99, 9, 194), engine.namesDepth.count())
        assertEquals((1..99).toList(), engine.namesDepth.all().map { it.number })
    }

    @Test
    fun `every Name has a root a known theme and prose`() {
        val ids = engine.namesDepth.themes().map { it.id }.toSet()
        for (name in engine.namesDepth.all()) {
            assertTrue(name.root.isNotEmpty(), "name ${name.number} has no root")
            assertTrue(name.theme in ids, "name ${name.number} theme ${name.theme}")
            assertTrue(name.explanation.length > 40, "name ${name.number} explanation")
            assertTrue(name.living.length > 20, "name ${name.number} living")
        }
    }

    @Test
    fun `the themes partition the ninety nine`() {
        var total = 0
        for (theme in engine.namesDepth.themes()) {
            val members = engine.namesDepth.byTheme(theme.id)
            assertTrue(members.isNotEmpty(), "theme ${theme.id} has no Names")
            total += members.size
        }
        assertEquals(99, total)
    }

    @Test
    fun `a root is spaced in the corpus and closed up for morphology`() {
        val rahman = engine.namesDepth.byNumber(1)!!
        assertEquals("ر ح م", rahman.root)
        assertEquals("رحم", rootKey(rahman.root))
        for (spelling in listOf("رحم", "ر ح م")) {
            assertEquals(listOf(1, 2), engine.namesDepth.byRoot(spelling).map { it.number })
        }
    }

    @Test
    fun `a placed occurrence really is that ayah's token`() {
        var placed = 0
        var unplaced = 0
        for (name in engine.namesDepth.all()) {
            for (o in name.occurrences) {
                val ayah = engine.quran.ayah(o.surah, o.ayah)
                assertNotNull(ayah, "name ${name.number} points at ${o.surah}:${o.ayah}")
                val token = o.token
                if (token == null) {
                    assertEquals(0, o.tokens, "name ${name.number} unplaced but spans ${o.tokens}")
                    unplaced += 1
                    continue
                }
                val tokens = ayah!!.textArabic.split(Regex("(?U)\\s+")).filter { it.isNotEmpty() }
                assertTrue(token < tokens.size, "name ${name.number} token $token past the end")
                assertTrue(fold(tokens[token]).isNotEmpty())
                placed += 1
            }
        }
        assertEquals(184, placed)
        assertEquals(10, unplaced)
    }

    @Test
    fun `the two Names of the Basmalah are found in 1 3 in token order`() {
        val hits = engine.namesDepth.inAyah(1, 3)
        assertEquals(listOf(1, 2), hits.map { it.name.number })
        assertEquals(listOf(0, 1), hits.map { it.occurrence.token })
    }

    @Test
    fun `a Name can be found by root explanation or living line`() {
        assertTrue(engine.namesDepth.search("رحم").any { it.number == 1 })
        val first = engine.namesDepth.byNumber(1)!!
        val word = first.living.split(Regex("(?U)\\s+")).first { it.length > 6 }
        assertTrue(engine.namesDepth.search(word).isNotEmpty())
        assertTrue(engine.namesDepth.search("").isEmpty())
    }

    // ---- the chains of transmission ----------------------------------------------

    @Test
    fun `ten imams twenty narrators thirteen Companions`() {
        assertEquals(Triple(10, 20, 13), engine.isnad.count())
        assertNotNull(engine.isnad.prophet())
    }

    @Test
    fun `every riwayah resolves to one of the ten imams two apiece`() {
        val per = engine.isnad.imamKeys().associateWith { 0 }.toMutableMap()
        for (tag in engine.isnad.narratorKeys()) {
            val imam = engine.isnad.imamOf(tag)
            assertNotNull(imam, "$tag resolves to no imam")
            val key = imam!!
            per[key] = per.getValue(key) + 1
        }
        for ((imam, n) in per) assertEquals(2, n, "$imam has $n narrators")
    }

    @Test
    fun `every imam reaches Companions through Successors or directly`() {
        for (imam in engine.isnad.imamKeys()) {
            val chain = engine.isnad.imam(imam)!!
            // Abu Jafar WAS a Successor and read on Companions himself, so he has no teachers.
            if (imam != "Abu Jafar") {
                assertTrue(chain.teachers.isNotEmpty(), "$imam has no teachers")
            }
            assertTrue(chain.companions.isNotEmpty(), "$imam reaches no Companion")
            for (node in chain.teachers) {
                assertEquals("successor", node.role)
                assertTrue(node.detail.startsWith("d."), "${node.name} has no death year")
            }
            for (node in chain.companions) assertEquals("companion", node.role)
        }
    }

    @Test
    fun `a chain runs from the Prophet down to the narrator`() {
        for (tag in engine.isnad.narratorKeys()) {
            val layers = engine.isnad.chain(tag)
            assertTrue(layers.size >= 4, "$tag chain is only ${layers.size} layers")
            assertEquals("THE PROPHET", layers[0].title)
            assertEquals("THE COMPANIONS", layers[1].title)
            val titles = layers.map { it.title }
            assertTrue("THE IMAM" in titles && "THE NARRATOR" in titles, tag)
            assertTrue(titles.indexOf("THE IMAM") < titles.indexOf("THE NARRATOR"), tag)
        }
    }

    @Test
    fun `an imam's chain ends at his two narrators`() {
        for (imam in engine.isnad.imamKeys()) {
            val last = engine.isnad.chain(imam).last()
            assertEquals("HIS TWO NARRATORS", last.title, imam)
            assertEquals(2, last.nodes.size, imam)
        }
    }

    @Test
    fun `reading directly is exactly having no links between`() {
        for (tag in engine.isnad.narratorKeys()) {
            val chain = engine.isnad.narrator(tag)!!
            assertEquals(chain.links.isEmpty(), engine.isnad.readsDirectly(tag), tag)
            val sentence = engine.isnad.sentence(tag)
            assertTrue(sentence.isNotEmpty(), tag)
            assertEquals(chain.links.isNotEmpty(), sentence.contains("did not meet"), tag)
        }
    }

    @Test
    fun `Hafs read on Asim himself and Qunbul did not meet Ibn Kathir`() {
        assertEquals("Asim", engine.isnad.imamOf("Hafs an Asim"))
        assertTrue(engine.isnad.readsDirectly("Hafs an Asim"))
        assertTrue(engine.isnad.sentence("Hafs an Asim").startsWith("Hafs read on Asim himself"))

        assertEquals("Ibn Kathir", engine.isnad.imamOf("Qunbul an Ibn Kathir"))
        assertFalse(engine.isnad.readsDirectly("Qunbul an Ibn Kathir"))
        assertEquals(3, engine.isnad.narrator("Qunbul an Ibn Kathir")!!.links.size)
    }

    @Test
    fun `an unknown key answers nothing rather than throwing`() {
        assertTrue(engine.isnad.chain("Nobody an Nobody").isEmpty())
        assertEquals("", engine.isnad.sentence("Nobody an Nobody"))
        assertNull(engine.isnad.imamOf("no separator here"))
    }
}
