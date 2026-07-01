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

    public init(quran: Quran, juzPage: JuzPage, reciters: Reciters, tajweed: Tajweed, search: Search, namesOfAllah: NamesOfAllah, muqattaat: Muqattaat) {
        self.quran = quran
        self.juzPage = juzPage
        self.reciters = reciters
        self.tajweed = tajweed
        self.search = search
        self.namesOfAllah = namesOfAllah
        self.muqattaat = muqattaat
    }

    /// Load the engine from a `/data` directory.
    ///
    /// - Parameters:
    ///   - dataDirectory: explicit data dir. If `nil`, the loader tries, in order: the
    ///     `QURAN_ENGINE_DATA` environment variable, a path computed from `#filePath` walking up to
    ///     the repo root + `/data`, and `<cwd>/data` plus a few parent-relative fallbacks.
    ///   - riwayah: optional qiraah label for text/search (default Hafs).
    public static func load(dataDirectory: URL? = nil, riwayah: String? = nil) throws -> Engine {
        let decoder = JSONDecoder()

        // Resolve each data file from (in order): an explicit dir, the resources BUNDLED in the package
        // (so the engine works as a SwiftPM dependency with zero filesystem setup), then a discovered
        // repo /data dir (monorepo dev). `dataDirectory` is resolved lazily so a consuming app never
        // needs the repo on disk.
        let explicitDir = dataDirectory
        var discoveredDir: URL?

        func decode<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            // 1. explicit dir
            if let explicitDir {
                let url = explicitDir.appendingPathComponent(file)
                if let data = try? Data(contentsOf: url) { return try decoder.decode(T.self, from: data) }
            }
            // 2. bundled resource (Resources/ inside the package)
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
                ?? Bundle.module.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                return try decoder.decode(T.self, from: data)
            }
            // 3. discovered repo /data (dev / monorepo)
            if discoveredDir == nil { discoveredDir = try? resolveDataDirectory(explicit: nil) }
            if let discoveredDir {
                let url = discoveredDir.appendingPathComponent(file)
                if let data = try? Data(contentsOf: url) { return try decoder.decode(T.self, from: data) }
            }
            throw EngineError.missingFile(file)
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

        let quran = Quran(surahs: surahs, surahInfo: surahInfo, qiraatCounts: qiraatCounts)
        let juzPage = JuzPage(quran: quran, juzList: juzList)
        let reciters = Reciters(reciterList)
        let tajweed = Tajweed(quran: quran, categories: rules.categories, records: annotations)
        let search = Search(quran: quran, riwayah: riwayah)
        let namesOfAllah = NamesOfAllah(names)

        return Engine(quran: quran, juzPage: juzPage, reciters: reciters, tajweed: tajweed, search: search, namesOfAllah: namesOfAllah, muqattaat: muqattaat)
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
