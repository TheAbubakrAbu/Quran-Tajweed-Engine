package com.quranengine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * The Engine facade + disk loader. Mirrors `createEngine` / `loadFromDisk` in `src/index.js` + `src/node.js`.
 *
 * Construct with [load]. The default [load] (no args) locates the repo `/data` directory by walking up
 * from the current working directory; pass a [File] to use a specific data directory (e.g. a bundled
 * Android asset directory you have copied to files).
 */
class Engine internal constructor(
    val quran: Quran,
    val juzPage: JuzPage,
    val reciters: Reciters,
    val search: Search,
    private val tajweedImpl: Tajweed,
) {
    /** Colored tajweed spans for an ayah (empty if the ayah or its annotations are unknown). */
    fun tajweed(surahId: Int, ayahId: Int): List<TajweedSpan> {
        val a = quran.ayah(surahId, ayahId) ?: return emptyList()
        return tajweedImpl.spans(surahId, ayahId, a.textArabic)
    }

    companion object {
        /** Riwayat keys -> `qiraat/qiraah-{key}.json`. */
        private val RIWAYAT = listOf("warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah")

        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Load the engine from a data directory. If [dataDir] is null, the repo `/data` directory is
         * located by walking up from the working directory (see [findDefaultDataDir]).
         */
        fun load(
            dataDir: File? = null,
            loadQiraat: Boolean = false,
            loadSurahInfo: Boolean = false,
            loadTajweed: Boolean = true,
            riwayah: String? = null,
        ): Engine {
            val dir = dataDir ?: findDefaultDataDir()
                ?: throw IllegalStateException("Could not locate the repo /data directory; pass dataDir explicitly")

            fun text(rel: String): String = File(dir, rel).readText(Charsets.UTF_8)

            val surahs: List<Surah> = json.decodeFromString(text("quran.json"))
            val juzList: List<JuzEntry> = json.decodeFromString(text("juz.json"))
            val reciterList: List<Reciter> = json.decodeFromString(text("reciters.json"))
            val rules: TajweedRules = json.decodeFromString(text("tajweed-rules.json"))
            val colors: Map<String, String> = rules.categories
                .mapNotNull { c -> c.colorHex?.let { c.id to it } }
                .toMap()

            val qiraat: Map<String, Map<String, List<Quran.QiraahVerse>>> =
                if (loadQiraat) {
                    RIWAYAT.associateWith { r -> parseQiraah(text("qiraat/qiraah-$r.json")) }
                } else emptyMap()

            val surahInfo: Map<Int, List<Quran.SurahInfoSource>> =
                if (loadSurahInfo) parseSurahInfo(text("surah-info.json")) else emptyMap()

            val quran = Quran(surahs, qiraat = qiraat, surahInfo = surahInfo)

            val ann = LinkedHashMap<Pair<Int, Int>, List<TajweedAnnotation>>()
            if (loadTajweed) {
                val entries: List<TajweedAyahAnnotations> =
                    json.decodeFromString(text("tajweed-annotations.json"))
                for (e in entries) ann[e.surah to e.ayah] = e.annotations
            }

            return Engine(
                quran = quran,
                juzPage = JuzPage(quran, juzList),
                reciters = Reciters(reciterList),
                search = Search(quran, riwayah = riwayah),
                tajweedImpl = Tajweed(ann, colors),
            )
        }

        /**
         * Walk up from the working directory looking for a `data/quran.json`. Returns the `data` dir,
         * or null if not found within 8 levels.
         */
        fun findDefaultDataDir(start: File = File(".").absoluteFile): File? {
            var cur: File? = start
            var depth = 0
            while (cur != null && depth < 12) {
                val candidate = File(cur, "data")
                if (File(candidate, "quran.json").isFile) return candidate
                cur = cur.parentFile
                depth++
            }
            return null
        }

        /** Parse a qiraah file: `{ "<surahId>": [{ id, text }, ...], ... }`. */
        private fun parseQiraah(jsonText: String): Map<String, List<Quran.QiraahVerse>> {
            val root = json.parseToJsonElement(jsonText).jsonObject
            val out = LinkedHashMap<String, List<Quran.QiraahVerse>>()
            for ((surahKey, verses) in root) {
                val list = (verses as? JsonArray)?.mapNotNull { v ->
                    val obj = v as? JsonObject ?: return@mapNotNull null
                    val id = obj["id"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
                    val t = obj["text"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    Quran.QiraahVerse(id, t)
                } ?: emptyList()
                out[surahKey] = list
            }
            return out
        }

        /** Parse `surah-info.json`: `[{ id, sources: [{ name, contents }] }]`. */
        private fun parseSurahInfo(jsonText: String): Map<Int, List<Quran.SurahInfoSource>> {
            val arr = json.parseToJsonElement(jsonText).jsonArray
            val out = LinkedHashMap<Int, List<Quran.SurahInfoSource>>()
            for (el in arr) {
                val obj = el.jsonObject
                val id = obj["id"]?.jsonPrimitive?.intOrNull ?: continue
                val sources = (obj["sources"] as? JsonArray)?.mapNotNull { s ->
                    val so = s as? JsonObject ?: return@mapNotNull null
                    val name = so["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    val contents = so["contents"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    Quran.SurahInfoSource(name, contents)
                } ?: emptyList()
                out[id] = sources
            }
            return out
        }
    }
}
