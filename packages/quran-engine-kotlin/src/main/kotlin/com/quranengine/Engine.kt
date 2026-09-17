package com.quranengine

import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
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
    val namesOfAllah: NamesOfAllah,
    val muqattaat: Muqattaat,
    private val tajweedImpl: Tajweed,
    /** The printed facsimiles and their page tables. Empty unless `loadMushaf`. */
    val mushaf: Mushaf = Mushaf(),
    /** Per-riwayah printed tajweed. Empty unless `loadQiraatTajweed`. */
    val qiraatTajweed: QiraatTajweed = QiraatTajweed(),
    /** The two aligned gloss layers. Empty unless `loadWordByWord`. */
    val wordByWord: WordByWord = WordByWord(),
    /** Mutashabihat. Empty unless `loadSimilarAyahs`. */
    val similarAyahs: SimilarAyahs = SimilarAyahs(),
    /** The curated topics; loaded by default. */
    val themes: Themes = Themes(),
    /** The tajweed course; loaded by default. */
    val tajweedLessons: TajweedLessons = TajweedLessons(),
    /** The per-surah outlines; loaded by default. */
    val surahSections: SurahSections = SurahSections(),
    /** The letter/tashkeel/waqf reference; loaded by default. */
    val alphabet: ArabicAlphabet = ArabicAlphabet(),
    /** Root and lemma of every word. Empty unless `loadMorphology`. */
    val morphology: Morphology = Morphology(),
    /** The repeated phrases. Empty unless `loadMutashabihat`. */
    val mutashabihat: Mutashabihat = Mutashabihat(),
    /** The three QUL topic indexes. Empty unless `loadQuranTopics`. */
    val quranTopics: QuranTopics = QuranTopics(),
    /** The passage themes; loaded by default. */
    val ayahThemes: AyahThemes = AyahThemes(),
    /** Hizb, ruku and manzil; loaded by default. */
    val quranMetadata: QuranMetadata = QuranMetadata(),
    /** The variant matrix, place index and paired recordings. Empty unless `loadQiraatVariants`. */
    val qiraatVariants: QiraatVariants = QiraatVariants(),
    /** The curated vocabulary; loaded by default. */
    val wordOfDay: WordOfDay = WordOfDay(),
    val namesDepth: NamesDepth = NamesDepth(),
    val isnad: Isnad = Isnad(),
    /** The scientific-miracles corpus; loaded by default. */
    val miracles: Miracles = Miracles(),
) {
    /** Needs `loadQiraat`; with no qiraah text it reports "hafs" alone and compares nothing. */
    val qiraatComparison: QiraatComparison by lazy { QiraatComparison(quran) }

    /**
     * Ask AI's retrieval and prompt. Built lazily because it holds the IDF table, which is only
     * worth computing for a consumer that actually asks a question.
     */
    val askAI: AskAI by lazy { AskAI(quran, search, themes) }

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
            /** mushaf/index.json plus every riwayah's page table (and line table, where it ships). */
            loadMushaf: Boolean = false,
            /** The shared rule catalogue and the seven verified riwayah packs. */
            loadQiraatTajweed: Boolean = false,
            /** Both aligned layers of word-by-word.json. */
            loadWordByWord: Boolean = false,
            loadSimilarAyahs: Boolean = false,
            /** Root and lemma of every word (~776 KB). */
            loadMorphology: Boolean = false,
            /** The repeated phrases (~178 KB). */
            loadMutashabihat: Boolean = false,
            /** The three QUL topic indexes (~730 KB). */
            loadQuranTopics: Boolean = false,
            /** The variant matrix, place index and paired-recording table (~1.9 MB together). */
            loadQiraatVariants: Boolean = false,
        ): Engine {
            val dir = dataDir ?: findDefaultDataDir()
                ?: throw IllegalStateException("Could not locate the repo /data directory; pass dataDir explicitly")

            fun text(rel: String): String = File(dir, rel).readText(Charsets.UTF_8)

            val surahs: List<Surah> = json.decodeFromString(text("quran.json"))
            val juzList: List<JuzEntry> = json.decodeFromString(text("juz.json"))
            val reciterList: List<Reciter> = json.decodeFromString(text("reciters.json"))
            val nameList: List<NameOfAllah> = json.decodeFromString(text("names-of-allah.json"))
            val muqattaatData: MuqattaatData = json.decodeFromString(text("muqattaat.json"))
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

            // riwayah key -> ("surahId" -> ayah count); always available (a sibling of quran.json).
            val qiraatCounts: Map<String, Map<String, Int>> =
                json.decodeFromString(
                    MapSerializer(String.serializer(), MapSerializer(String.serializer(), Int.serializer())),
                    text("qiraat-counts.json"),
                )

            val quran = Quran(surahs, qiraat = qiraat, surahInfo = surahInfo, qiraatCounts = qiraatCounts)

            val ann = LinkedHashMap<Pair<Int, Int>, List<TajweedAnnotation>>()
            if (loadTajweed) {
                val entries: List<TajweedAyahAnnotations> =
                    json.decodeFromString(text("tajweed-annotations.json"))
                for (e in entries) ann[e.surah to e.ayah] = e.annotations
            }

            // themes.json and tajweed-lessons.json are optional but load by default: together they
            // are ~250 KB, and a topic list is the kind of thing a consumer wants without a flag.
            val themes = Themes(optional<ThemesFile>(dir, "themes.json")?.topics ?: emptyList())
            val lessons = TajweedLessons(
                optional<TajweedLessonsFile>(dir, "tajweed-lessons.json")?.chapters ?: emptyList()
            )
            // Sections (80 KB) and the alphabet (18 KB) join them: small, and both answer questions
            // a consumer should not have to opt into.
            val sections = SurahSections(
                optional<Map<String, SurahSectionsEntry>>(dir, "surah-sections.json") ?: emptyMap()
            )
            val alphabet = ArabicAlphabet(
                optional<ArabicAlphabetFile>(dir, "arabic-alphabet.json") ?: ArabicAlphabetFile()
            )

            var mushaf = Mushaf()
            if (loadMushaf) {
                val index: MushafIndex = json.decodeFromString(text("mushaf/index.json"))
                val pages = LinkedHashMap<String, MushafPageTable>()
                val lines = LinkedHashMap<String, MushafLineTable>()
                for (entry in index.riwayat) {
                    pages[entry.riwayah] = json.decodeFromString(text("mushaf/${entry.pages}"))
                    entry.lines?.let { lines[entry.riwayah] = json.decodeFromString(text("mushaf/$it")) }
                }
                mushaf = Mushaf(index, pages, lines)
            }

            var qiraatTajweed = QiraatTajweed()
            if (loadQiraatTajweed) {
                val descriptions: Map<String, RuleDescription> =
                    json.decodeFromString(text("tajweed-qiraat/rules.json"))
                val packs = RIWAYAT.associateWith { slug ->
                    json.decodeFromString<QiraatTajweedPack>(text("tajweed-qiraat/$slug.json"))
                }
                qiraatTajweed = QiraatTajweed(descriptions, packs)
            }

            val wordByWord =
                if (loadWordByWord) {
                    WordByWord(json.decodeFromString<WordByWordPack>(text("word-by-word.json")), quran)
                } else WordByWord()

            // The file is `{v, ayahs}`; SimilarAyahs keeps the rows only when v == 2.
            val similar =
                if (loadSimilarAyahs) {
                    SimilarAyahs(json.decodeFromString<SimilarAyahsFile>(text("similar-ayahs.json")))
                } else SimilarAyahs()

            // Metadata (8 KB), the passage themes (142 KB) and the word list (128 KB) load by
            // default like the sections and the alphabet: small, and each answers a question a
            // consumer should not have to opt into.
            val metadata = QuranMetadata(
                optional<QuranMetadataFile>(dir, "quran-metadata.json") ?: QuranMetadataFile()
            )
            val ayahThemes = AyahThemes(
                optional<Map<String, List<ThemePassage>>>(dir, "ayah-themes.json") ?: emptyMap()
            )
            // The Names in depth (47 KB) and the chains (20 KB) load by default on the same footing.
            val depthFile = optional<NamesDepthFile>(dir, "names-depth.json") ?: NamesDepthFile()
            val namesDepth = NamesDepth(depthFile.names, depthFile.themes)
            val isnad = Isnad(optional<IsnadFile>(dir, "isnad.json") ?: IsnadFile())
            // The miracles corpus (393 KB) joins them: bigger than those, but smaller than the
            // tajweed course that has always loaded by default, and a consumer cross-linking an
            // ayah to what has been written about it should not have to know a flag existed.
            val miracles = Miracles(optional<MiraclesFile>(dir, "miracles.json") ?: MiraclesFile())
            val wordOfDay = WordOfDay(
                optional<WordOfDayFile>(dir, "word-of-day.json")?.words ?: emptyList()
            )

            val morphology =
                if (loadMorphology) Morphology(json.decodeFromString(text("morphology.json")))
                else Morphology()
            val mutashabihat =
                if (loadMutashabihat) Mutashabihat(json.decodeFromString(text("mutashabihat.json")))
                else Mutashabihat()
            val quranTopics =
                if (loadQuranTopics) {
                    QuranTopics(json.decodeFromString<QulTopicsFile>(text("quran-topics.json")).topics)
                } else QuranTopics()
            val qiraatVariants =
                if (loadQiraatVariants) {
                    QiraatVariants(
                        json.decodeFromString(text("qiraat-variants.json")),
                        json.decodeFromString(text("qiraat-places.json")),
                        json.decodeFromString(text("qiraat-variant-audio.json")),
                    )
                } else QiraatVariants()

            return Engine(
                quran = quran,
                juzPage = JuzPage(quran, juzList),
                reciters = Reciters(reciterList),
                search = Search(quran, riwayah = riwayah),
                namesOfAllah = NamesOfAllah(nameList),
                muqattaat = Muqattaat(muqattaatData),
                tajweedImpl = Tajweed(ann, colors),
                mushaf = mushaf,
                qiraatTajweed = qiraatTajweed,
                wordByWord = wordByWord,
                similarAyahs = similar,
                themes = themes,
                tajweedLessons = lessons,
                surahSections = sections,
                alphabet = alphabet,
                morphology = morphology,
                mutashabihat = mutashabihat,
                quranTopics = quranTopics,
                ayahThemes = ayahThemes,
                quranMetadata = metadata,
                qiraatVariants = qiraatVariants,
                wordOfDay = wordOfDay,
                namesDepth = namesDepth,
                isnad = isnad,
                miracles = miracles,
            )
        }

        /**
         * Decode a file that may not be there. A missing optional corpus is not an error — the
         * accessors simply return nothing — but a file that IS there and will not parse still throws,
         * so a corrupt pack fails loudly instead of silently disappearing.
         */
        private inline fun <reified T> optional(dir: File, rel: String): T? {
            val file = File(dir, rel)
            if (!file.isFile) return null
            return json.decodeFromString<T>(file.readText(Charsets.UTF_8))
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
