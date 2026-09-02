package com.quranengine

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah outlines,
 * alphabet reference and qiraat comparison that followed it.
 *
 * Mirrors the JS `test/parity.test.js`, the Python `tests/test_parity.py`, the Swift
 * `ParityTests.swift`, the Rust `tests/parity.rs` and the Go `parity_test.go` case for case, so a
 * divergence between the ports shows up as a failing test rather than as a surprise in an app.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ParityTest {

    private lateinit var engine: Engine

    @BeforeAll
    fun setup() {
        val dataDir = Engine.findDefaultDataDir()
        assertNotNull(dataDir, "Could not locate data/quran.json by walking up from the working dir")
        engine = Engine.load(
            dataDir,
            loadSurahInfo = true,
            loadMushaf = true,
            loadQiraatTajweed = true,
            loadWordByWord = true,
            loadSimilarAyahs = true,
            loadQiraat = true,
        )
    }

    // ---- mushaf -------------------------------------------------------------------------

    @Test
    fun `twenty riwayat, eight with text`() {
        assertEquals(20, engine.mushaf.riwayat().size)
        assertEquals(8, engine.mushaf.riwayatWithText().size)
        assertEquals(604, engine.mushaf.totalPages())
        assertEquals("Nafi", engine.mushaf.riwayah("warsh")?.imam)
        assertEquals(false, engine.mushaf.riwayah("hisham")?.textIncluded)
    }

    @Test
    fun `every riwayah has a facsimile and a full page table`() {
        for (entry in engine.mushaf.riwayat()) {
            assertTrue(entry.pdf.startsWith("pdfs/"), entry.riwayah)
            assertTrue(entry.pdf.endsWith(".pdf.xz"), entry.riwayah)
            assertTrue(entry.pdfBytes > 100_000, entry.riwayah)
            // Al-Fatihah opens page 1 and an-Nas closes page 604 in every print of the set.
            assertEquals(1, engine.mushaf.page(1, 1, entry.riwayah), entry.riwayah)
            assertEquals(604, engine.mushaf.page(114, 6, entry.riwayah), entry.riwayah)
        }
    }

    @Test
    fun `pages resolve back to their ayahs`() {
        assertEquals(42, engine.mushaf.page(2, 255, "hafs"))
        assertTrue(engine.mushaf.ayahsOnPage(42, "hafs").any { it.surah == 2 && it.ayah == 255 })
        assertEquals(VerseRef(1, 1), engine.mushaf.firstAyahOfPage(1, "hafs"))
    }

    @Test
    fun `line tables ship exactly where the text does`() {
        for (entry in engine.mushaf.riwayat()) {
            val breaks = engine.mushaf.lineBreaks(1, 1, entry.riwayah)
            assertEquals(entry.textIncluded, breaks != null, entry.riwayah)
        }
    }

    // ---- riwayah tajweed -----------------------------------------------------------------

    @Test
    fun `seven verified packs`() {
        assertEquals(
            listOf("buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"),
            engine.qiraatTajweed.available(),
        )
    }

    @Test
    fun `legend carries its explanation`() {
        val legend = engine.qiraatTajweed.legend("warsh")
        assertTrue(legend.size >= 3)
        for (entry in legend) {
            assertEquals(1, entry.code.length)
            assertTrue(entry.rule.isNotEmpty() && entry.arabic.isNotEmpty() && entry.english.isNotEmpty())
            assertTrue(entry.short.isNotEmpty(), "no description for ${entry.rule}")
        }
    }

    @Test
    fun `word rules name real legend codes`() {
        val rules = engine.qiraatTajweed.wordRules(2, 3, "warsh")
        assertTrue(rules.isNotEmpty())
        val codes = engine.qiraatTajweed.legend("warsh").map { it.code }
        for (rule in rules) {
            assertTrue(rule.code in codes, rule.code)
            assertEquals(rule.firstLetter < 0, rule.wholeWord)
            assertTrue(rule.word >= 1)
        }
    }

    @Test
    fun `khilaf markers`() {
        assertTrue(engine.qiraatTajweed.hasKhilaf(2, 253, "warsh"))
        assertTrue(!engine.qiraatTajweed.hasKhilaf(2, 254, "warsh"))
    }

    // ---- word by word ---------------------------------------------------------------------

    @Test
    fun `both layers aligned to the ayah's own tokens`() {
        val words = engine.wordByWord.words(112, 1)
        assertEquals(listOf("qul", "huwa", "l-lahu", "aḥadun"), words.map { it.transliteration })
        assertEquals("Say", words[0].english)
        val firstToken = engine.quran.ayah(112, 1)!!.textArabic.trim().split(Regex("(?U)\\s+"))[0]
        assertEquals(firstToken, words[0].arabic)
    }

    @Test
    fun `every ayah's arrays match its token count`() {
        for (surah in engine.quran.all()) {
            for (ayah in surah.ayahs) {
                val tokens = ayah.textArabic.trim().split(Regex("(?U)\\s+")).size
                assertEquals(
                    tokens, engine.wordByWord.glosses(surah.id, ayah.id)?.size,
                    "${surah.id}:${ayah.id} english",
                )
                assertEquals(
                    tokens, engine.wordByWord.transliterations(surah.id, ayah.id)?.size,
                    "${surah.id}:${ayah.id} transliteration",
                )
            }
        }
    }

    @Test
    fun `gloss search finds the word`() {
        val hits = engine.wordByWord.find("the Ever-Living", limit = 5)
        assertTrue(hits.any { it.surah == 2 && it.ayah == 255 })
        assertTrue(hits.all { it.transliteration.isNotEmpty() })
    }

    // ---- similar ayahs, themes, lessons ------------------------------------------------------

    @Test
    fun `similar ayahs`() {
        val matches = engine.similarAyahs.matches(2, 255)
        val found = matches.firstOrNull { it.surah == 3 && it.ayah == 2 }
        assertNotNull(found, "3:2 is a match")
        assertTrue(found!!.verified)
        assertTrue(engine.similarAyahs.has(2, 255))
        assertTrue(engine.similarAyahs.count() > 5000)
    }

    @Test
    fun `themes index both ways`() {
        assertTrue(engine.themes.all().size >= 300)
        assertTrue(engine.themes.topic("tawheed")!!.ayahs.contains("2:255"))
        assertTrue(engine.themes.topicsFor(2, 255).any { it.id == "tawheed" })
        assertTrue(engine.themes.domains().size >= 2)
    }

    @Test
    fun `lessons walk in course order`() {
        val lessons = engine.tajweedLessons.allLessons()
        assertTrue(lessons.size >= 30)
        assertNull(engine.tajweedLessons.previous(lessons[0].id))
        assertEquals(lessons[1].id, engine.tajweedLessons.next(lessons[0].id)?.id)
        assertNotNull(engine.tajweedLessons.chapterOf(lessons[0].id))
    }

    // ---- meaning search ---------------------------------------------------------------------

    @Test
    fun `MaxSim ranks by meaning`() {
        // A toy embedder: enough to prove the scoring, without shipping a model.
        val vectors = mapOf(
            "patience" to floatArrayOf(1.0f, 0.0f, 0.0f),
            "hardship" to floatArrayOf(0.9f, 0.1f, 0.0f),
            "sabr" to floatArrayOf(0.95f, 0.05f, 0.0f),
            "steadfast" to floatArrayOf(0.9f, 0.05f, 0.0f),
            "dawn" to floatArrayOf(0.0f, 1.0f, 0.0f),
            "prayer" to floatArrayOf(0.0f, 0.95f, 0.0f),
        )
        val semantic = Semantic(embed = { vectors[it] }).index(
            listOf(
                Semantic.Document("sabr", "sabr and steadfast endurance"),
                Semantic.Document("fajr", "prayer at dawn"),
            )
        )
        val hits = semantic.search("patience hardship")
        assertEquals("sabr", hits[0].id)
        assertTrue(hits[0].score > hits[1].score)
    }

    // ---- ask AI ------------------------------------------------------------------------------

    @Test
    fun `named verse is the subject`() {
        val passages = engine.askAI.retrieve("explain ayat al-kursi")
        assertEquals("2:255", passages[0].reference)
        assertTrue(passages[0].isSubject)
    }

    @Test
    fun `named surah answers with its background`() {
        val passages = engine.askAI.retrieve("what is surah al-kahf about")
        assertEquals("Surah Al-Kahf", passages[0].reference)
        assertEquals(AskAI.Kind.SURAH, passages[0].kind)
    }

    @Test
    fun `keyword lane is weighted`() {
        val passages = engine.askAI.retrieve("what does the Quran say about patience in hardship")
        assertTrue(passages.any { it.reference == "2:153" })
        for (passage in passages) {
            if (passage.kind == AskAI.Kind.AYAH) {
                assertNotNull(engine.quran.ayah(passage.surah!!, passage.ayah!!))
            }
        }
    }

    @Test
    fun `bare follow-up uses the previous question`() {
        val carried = engine.askAI.retrieve("tell me about 2:153")
        assertTrue(engine.askAI.retrieve("why?").isEmpty())
        val withContext = engine.askAI.retrieve(
            "why?",
            previousQuestion = "tell me about 2:153",
            carried = carried,
        )
        assertTrue(withContext.any { it.reference == "2:153" })
    }

    @Test
    fun `prompt shape`() {
        val passages = engine.askAI.retrieve("explain 2:153")
        val (instructions, prompt) = AskAI.chatPrompt("explain 2:153", passages)
        assertTrue(instructions.contains("Never issue a religious ruling"))
        assertTrue(prompt.contains("SUBJECT OF THE QUESTION [2:153]"))
        assertTrue(prompt.trimEnd().endsWith("QUESTION: explain 2:153"))
        assertTrue("what" in AskAI.QUESTION_WORDS)
    }

    // ---- surah sections ----------------------------------------------------------------

    @Test
    fun `111 surahs carry an outline, and it reads as a chain`() {
        assertEquals(111, engine.surahSections.count())
        assertTrue(engine.surahSections.overview(1).length > 20)
        assertTrue(!engine.surahSections.hasSections(1))

        // Hud opens with a broad passage and the sections inside it - an ayah has a chain, not a row.
        assertEquals(
            listOf("Doctrine facts", "Calling to Allah"),
            engine.surahSections.sectionsFor(11, 3).map { it.english },
        )
        assertEquals("Calling to Allah", engine.surahSections.sectionFor(11, 3)?.english)
    }

    @Test
    fun `the outline rebuilds the nesting the flat list encodes`() {
        val roots = engine.surahSections.outline(11)
        assertTrue(roots.size >= 2)
        assertEquals("Doctrine facts", roots[0].section.english)
        assertEquals(5, roots[0].children.size)
        assertTrue(roots[0].children.all {
            it.section.from >= roots[0].section.from && it.section.to <= roots[0].section.to
        })
    }

    @Test
    fun `every section range is inside its surah`() {
        for (surah in engine.quran.all()) {
            for (section in engine.surahSections.sections(surah.id)) {
                assertTrue(
                    section.from >= 1 && section.to <= surah.numberOfAyahs && section.from <= section.to,
                    "${surah.id}: ${section.from}-${section.to}",
                )
                assertTrue(section.english.isNotEmpty() && section.arabic.isNotEmpty())
            }
        }
        val nuh = engine.surahSections.search("Story of Nuh")
        assertTrue(nuh.size >= 2)
        assertTrue(nuh.any { (surah, _) -> surah == 11 })
    }

    // ---- arabic alphabet ----------------------------------------------------------------

    @Test
    fun `28 letters, each with a tajweed weight the catalogue explains`() {
        val letters = engine.alphabet.letters()
        assertEquals(28, letters.size)
        val weights = engine.alphabet.weightDescriptions()
        for (letter in letters) {
            assertTrue(letter.letter.isNotEmpty() && letter.name.isNotEmpty())
            val weight = letter.weight
            assertNotNull(weight, "${letter.letter} has no weight")
            assertNotNull(weights[weight], "no description for weight $weight")
        }
        // Alif is the one letter with no weight of its own - the fact the whole field exists for.
        assertEquals("followsPrevious", engine.alphabet.weight("ا"))
        assertEquals("heavy", engine.alphabet.weight("ص"))
        assertEquals("light", engine.alphabet.weight("س"))
    }

    @Test
    fun `a letter resolves from any of its joining forms`() {
        assertEquals("Saad", engine.alphabet.letter("ـصـ")?.transliteration)
        assertEquals("ا", engine.alphabet.letterById(1)?.letter)
        assertNull(engine.alphabet.letter("nope"))
    }

    @Test
    fun `tashkeel, numerals and the waqf signs`() {
        assertTrue(engine.alphabet.tashkeel().size >= 8)
        assertEquals(11, engine.alphabet.numbers().size)
        assertEquals("Make Sujood", engine.alphabet.stoppingSign("۩")?.title)
        assertTrue(engine.alphabet.heavyLetters().size >= 7)
    }

    // ---- qiraat comparison ---------------------------------------------------------------

    @Test
    fun `only the published readings, hafs included`() {
        assertEquals(
            listOf("buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh"),
            engine.qiraatComparison.available(),
        )
    }

    @Test
    fun `a reading against itself is entirely identical`() {
        val same = engine.qiraatComparison.compareSurah(2, "hafs")
        assertEquals(same.words, same.identical)
        assertEquals(0, same.sameSkeleton)
        assertEquals(0, same.different)
        assertEquals(0, same.added)
        assertEquals(0, same.dropped)
        assertEquals(100.0, same.identicalPercent)
    }

    @Test
    fun `the buckets add up, and Shubah is nearer to Hafs than Warsh is`() {
        val warsh = engine.qiraatComparison.compareSurah(2, "warsh")
        val shubah = engine.qiraatComparison.compareSurah(2, "shubah")
        for (totals in listOf(warsh, shubah)) {
            assertEquals(
                totals.words,
                totals.identical + totals.sameSkeleton + totals.different + totals.dropped,
            )
        }
        // Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
        assertTrue(shubah.identicalPercent > warsh.identicalPercent)
        assertTrue(shubah.identicalPercent > 95)
    }

    @Test
    fun `differences are the non-identical rows, in reading order`() {
        val rows = engine.qiraatComparison.differences(2, "warsh", limit = 20)
        assertTrue(rows.isNotEmpty())
        assertTrue(rows.all { it.base != it.other })
        assertEquals(rows.map { it.position }.sorted(), rows.map { it.position })
    }

    @Test
    fun `word streams follow the reading's own verse count`() {
        // Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
        // different verses from that point on; the comparison walks the surah's words instead.
        assertEquals(285, engine.quran.numberOfAyahsInQiraah(2, "warsh"))
        assertEquals(285, engine.quran.qiraahVerses(2, "warsh").size)
        assertTrue(engine.qiraatComparison.words(2, "warsh").size > 6000)
    }
}
