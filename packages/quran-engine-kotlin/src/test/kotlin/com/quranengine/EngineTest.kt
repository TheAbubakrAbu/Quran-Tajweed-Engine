package com.quranengine

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.io.File

/**
 * Canonical cases from `docs/PORTING.md`. The data dir is located by walking up from the working
 * directory to find `data/quran.json`.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class EngineTest {

    private lateinit var engine: Engine
    private lateinit var alafasy: Reciter

    @BeforeAll
    fun setup() {
        val dataDir = Engine.findDefaultDataDir()
        assertNotNull(dataDir, "Could not locate data/quran.json by walking up from the working dir")
        engine = Engine.load(dataDir)
        alafasy = engine.reciters.all().first { it.ayahIdentifier == "ar.alafasy" }
    }

    @Test
    fun totalAyahs() {
        assertEquals(6236, engine.quran.totalAyahs)
    }

    @Test
    fun globalAyahNumbers() {
        assertEquals(1, engine.quran.globalAyahNumber(1, 1))
        assertEquals(8, engine.quran.globalAyahNumber(2, 1))
        assertEquals(6236, engine.quran.globalAyahNumber(114, 6))
    }

    @Test
    fun surahAudio() {
        assertEquals("https://server8.mp3quran.net/afs/001.mp3", surahAudioUrl(alafasy, 1))
    }

    @Test
    fun ayahAudio() {
        assertEquals(
            "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3",
            ayahAudioUrl(alafasy, 8),
        )
    }

    @Test
    fun juzBoundaries() {
        val j1 = engine.juzPage.juz(1)!!
        assertEquals(1, j1.startSurah)
        assertEquals(1, j1.startAyah)
        val j30 = engine.juzPage.juz(30)!!
        assertEquals(114, j30.endSurah)
        assertEquals(6, j30.endAyah)
    }

    @Test
    fun juzFromEndAndStats() {
        val jp = engine.juzPage
        assertEquals(30, jp.juzFromEnd(1)?.id)
        assertEquals(1, jp.juzFromEnd(30)?.id)
        assertNull(jp.juzFromEnd(0))
        assertNull(jp.juzFromEnd(31))

        val stats = jp.juzStats(30)!!
        assertEquals(jp.ayahsInJuz(30).size, stats.ayahCount)
        assertTrue(stats.surahCount >= 1 && stats.pageCount >= 1)
        assertTrue(stats.wordCount > 0 && stats.letterCount > 0)
        assertNull(jp.juzStats(99))

        val sum = (1..30).sumOf { jp.juzStats(it)!!.ayahCount }
        assertEquals(6236, sum)
    }

    @Test
    fun sorting() {
        val sorted = sortSurahs(engine.quran.all(), "ayahs", "descending")
        assertEquals(2, sorted[0].id) // Al-Baqarah, 286 ayahs
        assertEquals(286, sorted[0].numberOfAyahs)
    }

    @Test
    fun referenceParsing() {
        val ref = engine.search.parseReference("2:255")
        assertNotNull(ref)
        assertEquals(2, ref!!.surah)
        assertEquals(255, ref.ayah)
        assertEquals(AyahReference(2, 255), ref)
    }

    @Test
    fun tajweedSpansSubstringMatchesRecordedText() {
        val spans = engine.tajweed(1, 1)
        assertTrue(spans.isNotEmpty(), "expected tajweed spans for 1:1")
        val text = engine.quran.ayah(1, 1)!!.textArabic
        for (s in spans) {
            // The span's text must equal the exact UTF-16 slice of the ayah text.
            assertEquals(text.substring(s.start, s.end), s.text)
            assertNotNull(s.colorHex, "rule ${s.rule} should map to a color")
        }
        // Spot-check known annotations from data/tajweed/001.json:
        assertEquals("hamzatWaslSilent", spans[0].rule)
        assertEquals("#B4B4B4", spans[0].colorHex)
    }

    @Test
    fun verseSearchSubstringAndBooleanOperators() {
        val search = engine.search
        fun ids(results: List<Search.VerseIndexEntry>) = results.map { it.id }.toSet()

        // Regular (non-boolean) search is a PURE mid-word substring match: "orld" hits "worlds" in 1:2.
        assertTrue("1:2" in ids(search.searchVerses("orld")), "mid-word substring 'orld' should hit 1:2")

        // Whole-word operator `=`: `=lord` matches the token "lord" in 1:2.
        assertTrue("1:2" in ids(search.searchVerses("=lord")), "=lord should hit 1:2 (whole word)")

        // `=lor` is whole-word so it must NOT match (no token equals "lor")...
        assertTrue("1:2" !in ids(search.searchVerses("=lor")), "=lor should NOT hit 1:2 (not a whole word)")

        // ...but plain substring `lor` DOES match ("lord" contains "lor").
        assertTrue("1:2" in ids(search.searchVerses("lor")), "plain 'lor' substring should hit 1:2")

        // Digit rejection happens BEFORE the boolean branch: `allah & 2` returns no results.
        assertEquals(0, search.searchVerses("allah & 2").size, "a boolean query with a digit returns 0")
    }

    @Test
    fun dataDirContainsQuranJson() {
        val dir = Engine.findDefaultDataDir()!!
        assertTrue(File(dir, "quran.json").isFile)
    }
}
