import Foundation

public enum EngineError: Error, CustomStringConvertible {
    case dataDirectoryNotFound(tried: [String])
    case missingFile(String)

    public var description: String {
        switch self {
        case .dataDirectoryNotFound(let tried):
            return "Could not locate the /data directory. Tried: \(tried.joined(separator: ", "))"
        case .missingFile(let path):
            return "Missing required data file: \(path)"
        }
    }
}

/// Facade tying together every module over a loaded `/data` directory.
///
/// Usage:
/// ```swift
/// let engine = try Engine.load()                       // auto-locate repo /data
/// let engine = try Engine.load(dataDirectory: url)     // explicit data dir
/// ```
public final class Engine {
    public let quran: Quran
    public let juzPage: JuzPage
    public let reciters: Reciters
    public let tajweed: Tajweed
    public let search: Search
    public let namesOfAllah: NamesOfAllah
    public let muqattaat: Muqattaat
    public let mushaf: Mushaf
    public let qiraatTajweed: QiraatTajweed
    public let wordByWord: WordByWord
    public let similarAyahs: SimilarAyahs
    public let themes: Themes
    public let tajweedLessons: TajweedLessons
    public let askAI: AskAI
    /// The per-surah outlines; loaded by default.
    public let surahSections: SurahSections
    /// The letter/tashkeel/waqf reference; loaded by default.
    public let alphabet: ArabicAlphabet
    /// Needs `loadQiraat`; with no qiraah text it reports "hafs" alone and compares nothing.
    public let qiraatComparison: QiraatComparison

    public init(quran: Quran, juzPage: JuzPage, reciters: Reciters, tajweed: Tajweed, search: Search,
                namesOfAllah: NamesOfAllah, muqattaat: Muqattaat,
                mushaf: Mushaf = Mushaf(), qiraatTajweed: QiraatTajweed = QiraatTajweed(),
                wordByWord: WordByWord = WordByWord(), similarAyahs: SimilarAyahs = SimilarAyahs(),
                themes: Themes = Themes(), tajweedLessons: TajweedLessons = TajweedLessons(),
                surahSections: SurahSections = SurahSections(),
                alphabet: ArabicAlphabet = ArabicAlphabet()) {
        self.quran = quran
        self.juzPage = juzPage
        self.reciters = reciters
        self.tajweed = tajweed
        self.search = search
        self.namesOfAllah = namesOfAllah
        self.muqattaat = muqattaat
        self.mushaf = mushaf
        self.qiraatTajweed = qiraatTajweed
        self.wordByWord = wordByWord
        self.similarAyahs = similarAyahs
        self.themes = themes
        self.tajweedLessons = tajweedLessons
        self.surahSections = surahSections
        self.alphabet = alphabet
        self.askAI = AskAI(quran: quran, search: search, themes: themes)
        self.qiraatComparison = QiraatComparison(quran: quran)
    }

    /// Load the engine from a `/data` directory.
    ///
    /// - Parameters:
    ///   - dataDirectory: explicit data dir. If `nil`, the loader tries, in order: the
    ///     `QURAN_ENGINE_DATA` environment variable, a path computed from `#filePath` walking up to
    ///     the repo root + `/data`, and `<cwd>/data` plus a few parent-relative fallbacks.
    ///   - riwayah: optional qiraah label for text/search (default Hafs).
    ///   - loadMushaf: the mushaf index, page and line tables (~2 MB). The 604-page facsimiles
    ///     themselves are never loaded by the engine - `mushaf.pdfPath(_:)` hands you the path.
    ///   - loadQiraatTajweed: the seven riwayah tajweed packs (~0.9 MB).
    ///   - loadWordByWord: the per-word gloss + transliteration pack (~1.8 MB).
    ///   - loadSimilarAyahs: the mutashabihat corpus (~3.5 MB).
    ///   - loadQiraat: the seven non-Hafs riwayat's own text (~11 MB) - what `qiraatComparison`
    ///     compares. NOT bundled in the package, so this needs a `dataDirectory`.
    public static func load(dataDirectory: URL? = nil, riwayah: String? = nil,
                            loadMushaf: Bool = false,
                            loadQiraatTajweed: Bool = false,
                            loadWordByWord: Bool = false,
                            loadSimilarAyahs: Bool = false,
                            loadQiraat: Bool = false) throws -> Engine {
        let decoder = JSONDecoder()

        // Resolve each data file from (in order): an explicit dir, the resources BUNDLED in the package
        // (so the engine works as a SwiftPM dependency with zero filesystem setup), then a discovered
        // repo /data dir (monorepo dev). `dataDirectory` is resolved lazily so a consuming app never
        // needs the repo on disk.
        let explicitDir = dataDirectory
        var discoveredDir: URL?

        /// The bytes of one data file, or nil when it is not present anywhere. `file` may be
        /// nested ("mushaf/index.json"); the bundle lookup keeps the subdirectory, because
        /// `.copy("Resources")` preserves the directory structure.
        func bytes(_ file: String) -> Data? {
            let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            let subdirectory = (file as NSString).deletingLastPathComponent
            // 1. explicit dir
            if let explicitDir, let data = try? Data(contentsOf: explicitDir.appendingPathComponent(file)) {
                return data
            }
            // 2. bundled resource (Resources/ inside the package)
            let bundled = subdirectory.isEmpty ? "Resources" : "Resources/" + subdirectory
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: bundled)
                ?? Bundle.module.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                return data
            }
            // 3. discovered repo /data (dev / monorepo)
            if discoveredDir == nil { discoveredDir = try? resolveDataDirectory(explicit: nil) }
            if let discoveredDir, let data = try? Data(contentsOf: discoveredDir.appendingPathComponent(file)) {
                return data
            }
            return nil
        }

        func decode<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
            guard let data = bytes(file) else { throw EngineError.missingFile(file) }
            return try decoder.decode(T.self, from: data)
        }

        /// For a corpus that may legitimately be absent (an app bundling only what it uses).
        func decodeIfPresent<T: Decodable>(_ type: T.Type, _ file: String) -> T? {
            guard let data = bytes(file) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }

        let surahs = try decode([Surah].self, "quran.json")
        let juzList = try decode([JuzEntry].self, "juz.json")
        let reciterList = try decode([Reciter].self, "reciters.json")
        let rules = try decode(TajweedRules.self, "tajweed-rules.json")
        let annotations = try decode([TajweedAyahRecord].self, "tajweed-annotations.json")
        let surahInfo = try decode([SurahInfo].self, "surah-info.json")
        let names = try decode([NameOfAllah].self, "names-of-allah.json")
        let muqattaat = try decode(Muqattaat.self, "muqattaat.json")
        let qiraatCounts = try decode([String: [String: Int]].self, "qiraat-counts.json")

        var qiraat: [String: [String: [Quran.QiraahVerse]]] = [:]
        if loadQiraat {
            for slug in ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"] {
                if let verses = decodeIfPresent([String: [Quran.QiraahVerse]].self,
                                                "qiraat/qiraah-\(slug).json") {
                    qiraat[slug] = verses
                }
            }
        }

        let quran = Quran(surahs: surahs, surahInfo: surahInfo, qiraat: qiraat,
                          qiraatCounts: qiraatCounts)
        let juzPage = JuzPage(quran: quran, juzList: juzList)
        let reciters = Reciters(reciterList)
        let tajweed = Tajweed(quran: quran, categories: rules.categories, records: annotations)
        let search = Search(quran: quran, riwayah: riwayah)
        let namesOfAllah = NamesOfAllah(names)

        // Themes and lessons load by default: together they are ~250 KB, and a topic list is exactly
        // the kind of thing a consumer wants without having to know it needed a flag.
        let themes = Themes(decodeIfPresent(ThemesFile.self, "themes.json"))
        let lessons = TajweedLessons(decodeIfPresent(TajweedLessonsFile.self, "tajweed-lessons.json"))
        // Sections (80 KB) and the alphabet (18 KB) join them: small, and both answer questions a
        // consumer should not have to opt into.
        let sections = SurahSections(decodeIfPresent([String: SurahSectionsEntry].self, "surah-sections.json"))
        let alphabet = ArabicAlphabet(decodeIfPresent(ArabicAlphabetFile.self, "arabic-alphabet.json"))

        var mushaf = Mushaf()
        if loadMushaf, let index = decodeIfPresent(MushafIndex.self, "mushaf/index.json") {
            var pages: [String: MushafPageTable] = [:]
            var lines: [String: MushafLineTable] = [:]
            for entry in index.riwayat {
                if let table = decodeIfPresent(MushafPageTable.self, "mushaf/\(entry.pages)") {
                    pages[entry.riwayah] = table
                }
                if let path = entry.lines,
                   let table = decodeIfPresent(MushafLineTable.self, "mushaf/\(path)") {
                    lines[entry.riwayah] = table
                }
            }
            mushaf = Mushaf(index: index, pages: pages, lines: lines)
        }

        var qiraatTajweed = QiraatTajweed()
        if loadQiraatTajweed,
           let rules = decodeIfPresent([String: QiraatRuleDescription].self, "tajweed-qiraat/rules.json") {
            var packs: [String: QiraatTajweedPack] = [:]
            for slug in ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"] {
                if let pack = decodeIfPresent(QiraatTajweedPack.self, "tajweed-qiraat/\(slug).json") {
                    packs[slug] = pack
                }
            }
            qiraatTajweed = QiraatTajweed(rules: rules, riwayat: packs)
        }

        var wordByWord = WordByWord(quran: quran)
        if loadWordByWord, let pack = decodeIfPresent(WordByWordPack.self, "word-by-word.json") {
            wordByWord = WordByWord(pack: pack, quran: quran)
        }

        var similar = SimilarAyahs()
        if loadSimilarAyahs,
           let rows = decodeIfPresent([String: [[SimilarAyahs.Field]]].self, "similar-ayahs.json") {
            similar = SimilarAyahs(rows)
        }

        return Engine(quran: quran, juzPage: juzPage, reciters: reciters, tajweed: tajweed,
                      search: search, namesOfAllah: namesOfAllah, muqattaat: muqattaat,
                      mushaf: mushaf, qiraatTajweed: qiraatTajweed, wordByWord: wordByWord,
                      similarAyahs: similar, themes: themes, tajweedLessons: lessons,
                      surahSections: sections, alphabet: alphabet)
    }

    /// Resolve the `/data` directory, trying several strategies.
    static func resolveDataDirectory(explicit: URL?) throws -> URL {
        var tried = [String]()

        func isDataDir(_ url: URL) -> Bool {
            let marker = url.appendingPathComponent("quran.json")
            tried.append(url.path)
            return FileManager.default.fileExists(atPath: marker.path)
        }

        if let explicit = explicit, isDataDir(explicit) { return explicit }

        if let env = ProcessInfo.processInfo.environment["QURAN_ENGINE_DATA"] {
            let url = URL(fileURLWithPath: env)
            if isDataDir(url) { return url }
        }

        // Path relative to the source file: <repo>/packages/quran-engine-swift/Sources/QuranEngine/Engine.swift
        // -> walk up to the repo root, then /data.
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // QuranEngine
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // quran-engine-swift
            .deletingLastPathComponent()  // packages
            .deletingLastPathComponent()  // repo root
        let fromSource = here.appendingPathComponent("data")
        if isDataDir(fromSource) { return fromSource }

        // Walk up from cwd looking for a /data dir.
        var cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = cwd.appendingPathComponent("data")
            if isDataDir(candidate) { return candidate }
            cwd = cwd.deletingLastPathComponent()
        }

        throw EngineError.dataDirectoryNotFound(tried: tried)
    }
}
