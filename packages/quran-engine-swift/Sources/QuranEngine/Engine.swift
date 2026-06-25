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

    public init(quran: Quran, juzPage: JuzPage, reciters: Reciters, tajweed: Tajweed, search: Search) {
        self.quran = quran
        self.juzPage = juzPage
        self.reciters = reciters
        self.tajweed = tajweed
        self.search = search
    }

    /// Load the engine from a `/data` directory.
    ///
    /// - Parameters:
    ///   - dataDirectory: explicit data dir. If `nil`, the loader tries, in order: the
    ///     `QURAN_ENGINE_DATA` environment variable, a path computed from `#filePath` walking up to
    ///     the repo root + `/data`, and `<cwd>/data` plus a few parent-relative fallbacks.
    ///   - riwayah: optional qiraah label for text/search (default Hafs).
    public static func load(dataDirectory: URL? = nil, riwayah: String? = nil) throws -> Engine {
        let dataURL = try resolveDataDirectory(explicit: dataDirectory)
        let decoder = JSONDecoder()

        func decode<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
            let url = dataURL.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url) else { throw EngineError.missingFile(url.path) }
            return try decoder.decode(T.self, from: data)
        }

        let surahs = try decode([Surah].self, "quran.json")
        let juzList = try decode([JuzEntry].self, "juz.json")
        let reciterList = try decode([Reciter].self, "reciters.json")
        let rules = try decode(TajweedRules.self, "tajweed-rules.json")
        let annotations = try decode([TajweedAyahRecord].self, "tajweed-annotations.json")

        let quran = Quran(surahs: surahs)
        let juzPage = JuzPage(quran: quran, juzList: juzList)
        let reciters = Reciters(reciterList)
        let tajweed = Tajweed(quran: quran, categories: rules.categories, records: annotations)
        let search = Search(quran: quran, riwayah: riwayah)

        return Engine(quran: quran, juzPage: juzPage, reciters: reciters, tajweed: tajweed, search: search)
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
