package com.quranengine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.io.File

/**
 * Conformance test — runs the language-agnostic vectors in `/conformance/vectors.json` against the
 * engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a behavior is specified ONCE in
 * that JSON, and every language port runs the same file (see docs/PORTING.md → "Conformance
 * vectors"). The reference consumer is `packages/quran-engine-js/test/conformance.test.js`; this
 * mirrors that harness.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ConformanceTest {

    private lateinit var engine: Engine
    private lateinit var vectors: JsonObject

    @BeforeAll
    fun setup() {
        val dataDir = Engine.findDefaultDataDir()
        assertNotNull(dataDir, "Could not locate data/quran.json by walking up from the working dir")
        // surah-info is gated behind a flag in the Kotlin port (the JS `loadFromDisk` always loads it);
        // the `surahInfo` conformance section needs it, so opt in here.
        engine = Engine.load(dataDir, loadSurahInfo = true)

        // The conformance file is a sibling of `data/`: <repoRoot>/conformance/vectors.json.
        val repoRoot = dataDir!!.parentFile
        val vectorsFile = File(File(repoRoot, "conformance"), "vectors.json")
        assertTrue(vectorsFile.isFile, "conformance vectors not found at ${vectorsFile.absolutePath}")
        vectors = Json.parseToJsonElement(vectorsFile.readText(Charsets.UTF_8)).jsonObject
    }

    /** A `JsonArray` member of the root object, or empty if absent. */
    private fun cases(key: String): List<JsonObject> =
        (vectors[key] as? JsonArray)?.map { it.jsonObject } ?: emptyList()

    /** String entries of an optional string-array field (e.g. `contains`, `excludes`). */
    private fun strings(obj: JsonObject, key: String): List<String> =
        (obj[key] as? JsonArray)?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList()

    private fun bool(obj: JsonObject, key: String): Boolean =
        (obj[key] as? JsonPrimitive)?.booleanOrNull ?: false

    private fun int(obj: JsonObject, key: String): Int =
        obj.getValue(key).jsonPrimitive.intOrNull ?: error("expected int for '$key'")

    private fun str(obj: JsonObject, key: String): String? =
        (obj[key] as? JsonPrimitive)?.contentOrNull

    @Test
    fun searchVerses() {
        for (v in cases("searchVerses")) {
            val query = str(v, "query") ?: error("searchVerses case missing 'query'")
            val ids = engine.search.searchVerses(query).map { it.id }
            if (bool(v, "empty")) {
                assertEquals(0, ids.size, "\"$query\" should be empty")
            }
            for (id in strings(v, "contains")) {
                assertTrue(ids.contains(id), "\"$query\" should contain $id")
            }
            for (id in strings(v, "excludes")) {
                assertFalse(ids.contains(id), "\"$query\" should exclude $id")
            }
        }
    }

    @Test
    fun juzFromEnd() {
        for (v in cases("juzFromEnd")) {
            val n = int(v, "n")
            // The expected `id` is either a JSON number or JSON null.
            val expected: Int? = (v["id"] as? JsonPrimitive)
                ?.takeUnless { it is JsonNull }
                ?.intOrNull
            assertEquals(expected, engine.juzPage.juzFromEnd(n)?.id, "juzFromEnd($n)")
        }
    }

    @Test
    fun juzStats() {
        for (v in cases("juzStats")) {
            val juz = int(v, "juz")
            val s = engine.juzPage.juzStats(juz)
            if (bool(v, "isNull")) {
                assertNull(s, "juzStats($juz) should be null")
                continue
            }
            assertNotNull(s, "juzStats($juz) should not be null")
            assertEquals(int(v, "surahCount"), s!!.surahCount, "juzStats($juz).surahCount")
            assertEquals(int(v, "ayahCount"), s.ayahCount, "juzStats($juz).ayahCount")
            assertEquals(int(v, "wordCount"), s.wordCount, "juzStats($juz).wordCount")
            assertEquals(int(v, "letterCount"), s.letterCount, "juzStats($juz).letterCount")
            assertEquals(int(v, "pageCount"), s.pageCount, "juzStats($juz).pageCount")
        }
        val invariant = vectors["juzStatsInvariant"]?.jsonObject
            ?: error("vectors missing 'juzStatsInvariant'")
        val sum = (1..30).sumOf { engine.juzPage.juzStats(it)!!.ayahCount }
        assertEquals(int(invariant, "sumAyahCountAllJuz"), sum, "sum of ayahCount over 1..30")
    }

    @Test
    fun surahFromEnd() {
        for (v in cases("surahFromEnd")) {
            val n = int(v, "n")
            val expected: Int? = (v["id"] as? JsonPrimitive)
                ?.takeUnless { it is JsonNull }
                ?.intOrNull
            assertEquals(expected, engine.quran.surahFromEnd(n)?.id, "surahFromEnd($n)")
        }
    }

    @Test
    fun sajdah() {
        val sj = vectors["sajdah"]?.jsonObject ?: error("vectors missing 'sajdah'")
        val ids = engine.quran.sajdahAyahs().map { "${it.surah.id}:${it.ayah.id}" }
        assertEquals(int(sj, "count"), ids.size, "sajdah count")
        for (id in strings(sj, "contains")) {
            assertTrue(ids.contains(id), "sajdah should contain $id")
            val (s, a) = id.split(":").map { it.toInt() }
            assertTrue(engine.quran.isSajdahAyah(s, a), "isSajdahAyah($id)")
        }
        for (id in strings(sj, "excludes")) {
            val (s, a) = id.split(":").map { it.toInt() }
            assertFalse(engine.quran.isSajdahAyah(s, a), "isSajdahAyah($id) should be false")
        }
    }

    @Test
    fun surahInfo() {
        for (v in cases("surahInfo")) {
            val surah = int(v, "surah")
            val sources = engine.quran.info(surah)
            val minSources = (v["minSources"] as? JsonPrimitive)?.intOrNull ?: 1
            assertTrue(sources.size >= minSources, "info($surah) sources")
            str(v, "hasSourceName")?.let { name ->
                assertTrue(sources.any { it.name == name }, "info($surah) has $name")
            }
        }
    }

    @Test
    fun namesOfAllah() {
        val names = vectors["namesOfAllah"]?.jsonObject ?: error("vectors missing 'namesOfAllah'")
        assertEquals(int(names, "count"), engine.namesOfAllah.all().size, "namesOfAllah count")
        for (v in (names["byNumber"] as? JsonArray)?.map { it.jsonObject } ?: emptyList()) {
            val number = int(v, "number")
            assertEquals(
                str(v, "transliteration"),
                engine.namesOfAllah.byNumber(number)?.transliteration,
                "namesOfAllah.byNumber($number)",
            )
        }
    }

    @Test
    fun filterByCounts() {
        for (v in cases("filterByCounts")) {
            val ayahs = countFilter(v["ayahs"] as? JsonObject)
            val pages = countFilter(v["pages"] as? JsonObject)
            val ids = filterByCounts(engine.quran.all(), ayahs = ayahs, pages = pages)
                .map { it.id }
                .sorted()
            val expected = (v["ids"] as? JsonArray)
                ?.mapNotNull { it.jsonPrimitive.intOrNull }
                ?.sorted()
                ?: emptyList()
            assertEquals(expected, ids, "filterByCounts")
        }
    }

    /** Build a [CountFilter] from a `{ op, value }` vector object, or null when absent. */
    private fun countFilter(obj: JsonObject?): CountFilter? {
        if (obj == null) return null
        val op = (obj["op"] as? JsonPrimitive)?.contentOrNull ?: error("count filter missing 'op'")
        val value = obj["value"]?.jsonPrimitive?.intOrNull ?: error("count filter missing 'value'")
        return CountFilter(op, value)
    }

    @Test
    fun tajweed() {
        for (v in cases("tajweed")) {
            val surah = int(v, "surah")
            val ayah = int(v, "ayah")
            val spans = engine.tajweed(surah, ayah)
            val rules = spans.map { it.rule }

            str(v, "excludesRule")?.let { excluded ->
                assertFalse(rules.contains(excluded), "$surah:$ayah should NOT have $excluded")
            }
            str(v, "lastSpanRule")?.let { lastRule ->
                val last = spans.maxByOrNull { it.start }
                assertEquals(lastRule, last?.rule, "$surah:$ayah last span rule")
            }
        }
    }

    @Test
    fun surahFlags() {
        for (v in cases("surahFlags")) {
            val surah = int(v, "surah")
            assertEquals(
                bool(v, "pageChanges"),
                engine.quran.pageChangesWithinSurah(surah),
                "pageChanges($surah)",
            )
            assertEquals(
                bool(v, "juzChanges"),
                engine.quran.juzChangesWithinSurah(surah),
                "juzChanges($surah)",
            )
            assertEquals(
                bool(v, "pageOrJuz"),
                engine.quran.pageOrJuzChangesWithinSurah(surah),
                "pageOrJuz($surah)",
            )
        }
    }

    @Test
    fun existsInQiraah() {
        for (v in cases("existsInQiraah")) {
            val surah = int(v, "surah")
            val ayah = int(v, "ayah")
            val riwayah = str(v, "riwayah")
            assertEquals(
                bool(v, "exists"),
                engine.quran.existsInQiraah(surah, ayah, riwayah),
                "existsInQiraah($surah,$ayah,$riwayah)",
            )
        }
        for (v in cases("numberOfAyahsInQiraah")) {
            val surah = int(v, "surah")
            val riwayah = str(v, "riwayah")
            assertEquals(
                int(v, "count"),
                engine.quran.numberOfAyahsInQiraah(surah, riwayah),
                "numberOfAyahsInQiraah($surah,$riwayah)",
            )
        }
    }

    @Test
    fun muqattaat() {
        val m = vectors["muqattaat"]?.jsonObject ?: error("vectors missing 'muqattaat'")
        assertEquals(int(m, "count"), engine.muqattaat.all().size, "muqattaat count")

        for (p in (m["pronunciations"] as? JsonArray)?.map { it.jsonObject } ?: emptyList()) {
            val surah = int(p, "surah")
            val ayah = int(p, "ayah")
            val got = engine.muqattaat.pronunciation(surah, ayah)
            assertNotNull(got, "muqattaat $surah:$ayah present")
            assertEquals(str(p, "transliteration"), got!!.transliteration, "muqattaat $surah:$ayah transliteration")
            if (bool(p, "spelledContainsMaddah")) {
                // U+0653 ARABIC MADDAH ABOVE — the madd-lāzim mark the tajweed pass colours.
                assertTrue(
                    got.spelledOutArabic.contains("ٓ"),
                    "muqattaat $surah:$ayah keeps madd-lāzim maddah",
                )
            }
        }

        for (a in (m["absent"] as? JsonArray)?.map { it.jsonObject } ?: emptyList()) {
            val surah = int(a, "surah")
            val ayah = int(a, "ayah")
            assertNull(engine.muqattaat.pronunciation(surah, ayah), "muqattaat $surah:$ayah absent")
        }
    }
}
