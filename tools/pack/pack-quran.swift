// pack-quran - builds the app-ready Quran packs (.qpk) from this engine's JSON.
//
//   tools/pack/build.sh                 # compile, pack, verify, write the manifest
//
// The JSON in data/ stays canonical and portable. These packs are a reproducible build
// artifact for apps that care about install size, launch time, and memory - exactly the
// split the Hadith JSON Engine uses for .hpk.
//
// Why: Al-Islam ships 16 MB of Quran JSON, decodes it once, then writes a binary-plist
// cache to Application Support and maps THAT on later launches. So the device pays twice -
// once in bundle size for the JSON, again in disk for the derived cache - and the first
// launch pays the whole decode. A pack collapses both: it IS the decoded form, mapped
// directly, with the big text left on disk until something asks for it.
//
// Three packs, one container format:
//
//   quran.qpk       114 surahs + 6,236 ayahs (arabic, transliteration, 2 translations)
//   qiraat.qpk      7 riwayat over the same ayah space
//   surahinfos.qpk  114 surahs of "about this surah" prose
//
// The format is documented once, in docs/09-qpk-format.md, which specifies it precisely
// enough to read a pack without consulting this file.

import Foundation
import Compression

// MARK: - Binary writer

struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: Int) { data.append(UInt8(truncatingIfNeeded: v)) }

    mutating func u16(_ v: Int) {
        var little = UInt16(truncatingIfNeeded: v).littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    mutating func u32(_ v: Int) {
        var little = UInt32(truncatingIfNeeded: v).littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    mutating func u64(_ v: UInt64) {
        var little = v.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    /// A length-prefixed UTF-8 string.
    mutating func string(_ v: String) {
        let bytes = Array(v.utf8)
        u32(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func raw(_ d: Data) { data.append(d) }
}

// MARK: - Compression

enum Codec: UInt8 {
    case lzfse = 1
    case lzma = 2

    var algorithm: compression_algorithm {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .lzma: return COMPRESSION_LZMA
        }
    }
}

func compress(_ data: Data, _ codec: Codec) -> Data {
    guard !data.isEmpty else { return Data() }
    let capacity = data.count + 4096
    let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { destination.deallocate() }
    let written = data.withUnsafeBytes { source in
        compression_encode_buffer(destination, capacity,
                                  source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                  nil, codec.algorithm)
    }
    guard written > 0 else {
        FileHandle.standardError.write(Data("compression failed for \(data.count) bytes\n".utf8))
        exit(1)
    }
    return Data(bytes: destination, count: written)
}

// MARK: - Container

let magic: UInt32 = 0x4B50_5251        // "QRPK" little-endian
let formatVersion = 1
let headerSize = 48
let blockEntrySize = 16

/// Target raw bytes of text per block. Same reasoning as the hadith packs: big enough that
/// the compressor gets a useful window, small enough that touching one ayah stays cheap.
let blockTargetBytes = (ProcessInfo.processInfo.environment["QPK_BLOCK"].flatMap { Int($0) } ?? 256) * 1024

let eagerCodec = Codec.lzma
/// Display text is read a block at a time and cached, so LZMA's ratio is worth its decode.
let textCodec = Codec(rawValue: UInt8(ProcessInfo.processInfo.environment["QPK_TEXT"].flatMap { Int($0) } ?? 2))!

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Assembles header + block table + eager + blocks into the final file.
func assemble(recordCount: Int, unitCount: Int, fingerprint: UInt64,
              eagerRaw: Data, blocks: [(firstRecord: Int, raw: Data)]) -> Data {
    let eager = compress(eagerRaw, eagerCodec)
    let payloads = blocks.map { (firstRecord: $0.firstRecord, blob: compress($0.raw, textCodec), rawLength: $0.raw.count) }

    var out = ByteWriter()
    out.u32(Int(magic))
    out.u16(formatVersion)
    out.u8(Int(eagerCodec.rawValue))
    out.u8(Int(textCodec.rawValue))
    out.u16(payloads.count)
    out.u16(0)                                     // reserved
    out.u32(recordCount)
    out.u32(unitCount)

    let eagerOffset = headerSize + payloads.count * blockEntrySize
    out.u32(eagerOffset)
    out.u32(eager.count)
    out.u32(eagerRaw.count)
    out.u64(fingerprint)
    out.u64(0)                                     // reserved

    var cursor = eagerOffset + eager.count
    var offsets: [Int] = []
    for p in payloads {
        offsets.append(cursor)
        cursor += p.blob.count
    }
    for (i, p) in payloads.enumerated() {
        out.u32(p.firstRecord)
        out.u32(offsets[i])
        out.u32(p.blob.count)
        out.u32(p.rawLength)
    }
    out.raw(eager)
    for p in payloads { out.raw(p.blob) }
    return out.data
}

/// FNV-1a over the source bytes. Lets a reader tell whether a pack matches the JSON it
/// claims to come from, without hashing the whole pack.
func fingerprint(_ data: Data) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* 0x1000_0000_01b3
    }
    return hash
}

func sha256Hex(_ data: Data) -> String {
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                       0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    var m = [UInt8](data)
    let bitLength = UInt64(m.count) * 8
    m.append(0x80)
    while m.count % 64 != 56 { m.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) { m.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
    for chunk in stride(from: 0, to: m.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let b = chunk + i * 4
            w[i] = (UInt32(m[b]) << 24) | (UInt32(m[b+1]) << 16) | (UInt32(m[b+2]) << 8) | UInt32(m[b+3])
        }
        for i in 16..<64 {
            let s0 = (w[i-15] >> 7 | w[i-15] << 25) ^ (w[i-15] >> 18 | w[i-15] << 14) ^ (w[i-15] >> 3)
            let s1 = (w[i-2] >> 17 | w[i-2] << 15) ^ (w[i-2] >> 19 | w[i-2] << 13) ^ (w[i-2] >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }
    return h.map { String(format: "%08x", $0) }.joined()
}

// MARK: - quran.qpk

struct PackStats {
    let name: String
    let sourceBytes: Int
    let packBytes: Int
    let records: Int
    let units: Int
    let blocks: Int
    let sha256: String
}

func packQuran(sourceURL: URL, outputURL: URL) throws -> PackStats {
    let sourceData = try Data(contentsOf: sourceURL)
    guard let surahs = try JSONSerialization.jsonObject(with: sourceData) as? [[String: Any]] else {
        throw Failure("Quran.json is not an array of surahs")
    }

    // --- Flatten to a global ayah row space, and group text into blocks by surah ---
    struct AyahText { let arabic, transliteration, saheeh, mustafa: String }
    var ayahTexts: [AyahText] = []
    var ayahScalars: [(id: Int, juz: Int, page: Int, wordCount: Int, letterCount: Int)] = []
    var surahFirstRow: [Int] = []

    for surah in surahs {
        guard let ayahs = surah["ayahs"] as? [[String: Any]] else {
            throw Failure("surah \(surah["id"] ?? "?") has no ayahs")
        }
        surahFirstRow.append(ayahTexts.count)
        for a in ayahs {
            ayahTexts.append(AyahText(
                arabic: a["textArabic"] as? String ?? "",
                transliteration: a["textTransliteration"] as? String ?? "",
                saheeh: a["textEnglishSaheeh"] as? String ?? "",
                mustafa: a["textEnglishMustafa"] as? String ?? ""))
            ayahScalars.append((a["id"] as? Int ?? 0, a["juz"] as? Int ?? 0, a["page"] as? Int ?? 0,
                                a["wordCount"] as? Int ?? 0, a["letterCount"] as? Int ?? 0))
        }
        guard let declared = surah["numberOfAyahs"] as? Int, declared == ayahs.count else {
            throw Failure("surah \(surah["id"] ?? "?") declares \(surah["numberOfAyahs"] ?? -1) ayahs "
                          + "but carries \(ayahs.count). The pack stores surahs as row ranges, and "
                          + "shipping a mismatch would show readers the wrong ayahs.")
        }
    }
    guard ayahTexts.count == 6236 else {
        throw Failure("expected 6236 ayahs, found \(ayahTexts.count)")
    }

    // Blocks never straddle a surah: a reader opening a surah then touches a contiguous run.
    var blockRanges: [Range<Int>] = []
    var start = 0, accumulated = 0
    for (index, surah) in surahs.enumerated() {
        let last = index == surahs.count - 1
        let end = last ? ayahTexts.count : surahFirstRow[index + 1]
        for row in surahFirstRow[index]..<end {
            let t = ayahTexts[row]
            accumulated += t.arabic.utf8.count + t.transliteration.utf8.count
                         + t.saheeh.utf8.count + t.mustafa.utf8.count + 16
        }
        _ = surah
        if accumulated >= blockTargetBytes || last {
            blockRanges.append(start..<end)
            start = end
            accumulated = 0
        }
    }
    if start < ayahTexts.count { blockRanges.append(start..<ayahTexts.count) }

    var blockIndexByRow = [Int](repeating: 0, count: ayahTexts.count)
    for (i, r) in blockRanges.enumerated() { for row in r { blockIndexByRow[row] = i } }

    // --- Eager: everything except ayah TEXT ---
    var eager = ByteWriter()
    eager.u32(surahs.count)
    for (index, s) in surahs.enumerated() {
        eager.u32(s["id"] as? Int ?? 0)
        eager.u8((s["type"] as? String) == "makkan" ? 1 : 0)
        eager.string(s["nameArabic"] as? String ?? "")
        eager.string(s["nameTransliteration"] as? String ?? "")
        eager.string(s["nameEnglish"] as? String ?? "")
        eager.string(s["revelationExceptions"] as? String ?? "")
        eager.u32(s["numberOfAyahs"] as? Int ?? 0)
        eager.u32(s["pageStart"] as? Int ?? 0)
        eager.u32(s["pageEnd"] as? Int ?? 0)
        eager.u32(s["numberOfPages"] as? Int ?? 0)
        eager.u32(s["firstJuz"] as? Int ?? 0)
        eager.u32(s["lastJuz"] as? Int ?? 0)
        eager.u32(s["revelationOrder"] as? Int ?? 0)
        eager.u32(s["wordCount"] as? Int ?? 0)
        eager.u32(s["letterCount"] as? Int ?? 0)
        eager.u8((s["juzChangesWithinSurah"] as? Bool) == true ? 1 : 0)
        let juzs = s["juzs"] as? [Int] ?? []
        eager.u32(juzs.count)
        for j in juzs { eager.u32(j) }
        let similar = s["similarNames"] as? [String] ?? []
        eager.u32(similar.count)
        for n in similar { eager.string(n) }
        eager.u32(surahFirstRow[index])
    }
    eager.u32(ayahTexts.count)
    for (row, a) in ayahScalars.enumerated() {
        eager.u32(a.id)
        eager.u16(a.juz)
        eager.u16(a.page)
        eager.u32(a.wordCount)
        eager.u32(a.letterCount)
        eager.u16(blockIndexByRow[row])
    }

    // --- Blocks: the four text fields per ayah, in row order ---
    let blocks: [(firstRecord: Int, raw: Data)] = blockRanges.map { range in
        var w = ByteWriter()
        for row in range {
            let t = ayahTexts[row]
            w.string(t.arabic); w.string(t.transliteration); w.string(t.saheeh); w.string(t.mustafa)
        }
        return (range.lowerBound, w.data)
    }

    let out = assemble(recordCount: surahs.count, unitCount: ayahTexts.count,
                       fingerprint: fingerprint(sourceData), eagerRaw: eager.data, blocks: blocks)
    try out.write(to: outputURL, options: .atomic)
    return PackStats(name: "quran", sourceBytes: sourceData.count, packBytes: out.count,
                     records: surahs.count, units: ayahTexts.count, blocks: blocks.count,
                     sha256: sha256Hex(out))
}

// MARK: - qiraat.qpk

/// The seven alternate readings, in the app's catalog order. Each file is
/// `{ "<surahId>": [ { "id": Int, "text": String } ] }`.
let qiraatFiles: [(file: String, key: String)] = [
    ("QiraahWarsh", "warsh"), ("QiraahQaloon", "qaloon"), ("QiraahDuri", "duri"),
    ("QiraahSusi", "susi"), ("QiraahBuzzi", "bazzi"), ("QiraahQunbul", "qunbul"),
    ("QiraahShubah", "shubah"),
]

func packQiraat(directory: URL, outputURL: URL) throws -> PackStats {
    struct Reading { let key: String; let surahs: [Int: [(id: Int, text: String)]] }
    var readings: [Reading] = []
    var sourceBytes = 0
    var combined = Data()

    for (file, key) in qiraatFiles {
        let url = directory.appendingPathComponent("\(file).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("missing qiraah source \(url.lastPathComponent)")
        }
        let data = try Data(contentsOf: url)
        sourceBytes += data.count
        combined.append(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("\(file).json is not an object keyed by surah id")
        }
        var surahs: [Int: [(id: Int, text: String)]] = [:]
        for (surahKey, value) in root {
            guard let sid = Int(surahKey), let list = value as? [[String: Any]] else { continue }
            surahs[sid] = list.map { ($0["id"] as? Int ?? 0, $0["text"] as? String ?? "") }
        }
        readings.append(Reading(key: key, surahs: surahs))
    }

    // Eager: which surahs each reading covers, and how many ayahs in each — this is what
    // `existsInQiraah` / `numberOfAyahs(for:)` need, and it answers them without any text.
    var eager = ByteWriter()
    eager.u32(readings.count)
    var blocks: [(firstRecord: Int, raw: Data)] = []
    var totalAyahs = 0

    for (index, reading) in readings.enumerated() {
        eager.string(reading.key)
        let surahIds = reading.surahs.keys.sorted()
        eager.u32(surahIds.count)
        for sid in surahIds {
            eager.u32(sid)
            eager.u32(reading.surahs[sid]!.count)
        }
        eager.u16(index)                            // one block per reading

        var w = ByteWriter()
        for sid in surahIds {
            for ayah in reading.surahs[sid]! {
                w.u32(ayah.id)
                w.string(ayah.text)
                totalAyahs += 1
            }
        }
        blocks.append((index, w.data))
    }

    let out = assemble(recordCount: readings.count, unitCount: totalAyahs,
                       fingerprint: fingerprint(combined), eagerRaw: eager.data, blocks: blocks)
    try out.write(to: outputURL, options: .atomic)
    return PackStats(name: "qiraat", sourceBytes: sourceBytes, packBytes: out.count,
                     records: readings.count, units: totalAyahs, blocks: blocks.count,
                     sha256: sha256Hex(out))
}

// MARK: - surahinfos.qpk

func packSurahInfos(sourceURL: URL, outputURL: URL) throws -> PackStats {
    let sourceData = try Data(contentsOf: sourceURL)
    guard let entries = try JSONSerialization.jsonObject(with: sourceData) as? [[String: Any]] else {
        throw Failure("SurahInfos.json is not an array")
    }

    // One block per surah: "about this surah" is opened for exactly one surah at a time, and
    // the prose is large, so a shared block would decompress 113 surahs nobody asked for.
    var eager = ByteWriter()
    eager.u32(entries.count)
    var blocks: [(firstRecord: Int, raw: Data)] = []
    var totalSources = 0

    for (index, entry) in entries.enumerated() {
        let sources = entry["sources"] as? [[String: Any]] ?? []
        eager.u32(entry["id"] as? Int ?? 0)
        eager.u32(sources.count)
        for s in sources { eager.string(s["name"] as? String ?? "") }
        eager.u16(index)

        var w = ByteWriter()
        for s in sources { w.string(s["contents"] as? String ?? "") }
        blocks.append((index, w.data))
        totalSources += sources.count
    }

    let out = assemble(recordCount: entries.count, unitCount: totalSources,
                       fingerprint: fingerprint(sourceData), eagerRaw: eager.data, blocks: blocks)
    try out.write(to: outputURL, options: .atomic)
    return PackStats(name: "surahinfos", sourceBytes: sourceData.count, packBytes: out.count,
                     records: entries.count, units: totalSources, blocks: blocks.count,
                     sha256: sha256Hex(out))
}

// MARK: - Main

func column(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
func right(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }

@main
struct PackQuran {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            print("usage: pack-quran <JSONs dir> <output dir>")
            exit(2)
        }
        let input = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var stats: [PackStats] = []
        stats.append(try packQuran(sourceURL: input.appendingPathComponent("Quran.json"),
                                   outputURL: output.appendingPathComponent("quran.qpk")))
        stats.append(try packQiraat(directory: input.appendingPathComponent("Qiraat"),
                                    outputURL: output.appendingPathComponent("qiraat.qpk")))
        stats.append(try packSurahInfos(sourceURL: input.appendingPathComponent("SurahInfos.json"),
                                        outputURL: output.appendingPathComponent("surahinfos.qpk")))

        print(column("pack", 14) + right("json", 10) + right("pack", 10) + right("ratio", 8)
              + right("records", 9) + right("units", 8) + right("blocks", 8))
        for s in stats {
            print(column(s.name, 14)
                  + right(String(format: "%.2fM", Double(s.sourceBytes) / 1e6), 10)
                  + right(String(format: "%.2fM", Double(s.packBytes) / 1e6), 10)
                  + right(String(format: "%.2fx", Double(s.sourceBytes) / Double(max(s.packBytes, 1))), 8)
                  + right("\(s.records)", 9) + right("\(s.units)", 8) + right("\(s.blocks)", 8))
        }
        let totalSource = stats.reduce(0) { $0 + $1.sourceBytes }
        let totalPack = stats.reduce(0) { $0 + $1.packBytes }
        print(column("TOTAL", 14)
              + right(String(format: "%.2fM", Double(totalSource) / 1e6), 10)
              + right(String(format: "%.2fM", Double(totalPack) / 1e6), 10)
              + right(String(format: "%.2fx", Double(totalSource) / Double(max(totalPack, 1))), 8))

        var manifest: [String: Any] = [
            "formatVersion": formatVersion,
            "blockTargetBytes": blockTargetBytes,
            "textCodec": textCodec == .lzma ? "lzma" : "lzfse",
            "totalPackBytes": totalPack,
        ]
        manifest["packs"] = stats.map {
            ["name": $0.name, "bytes": $0.packBytes, "sourceBytes": $0.sourceBytes,
             "records": $0.records, "units": $0.units, "blocks": $0.blocks, "sha256": $0.sha256] as [String: Any]
        }
        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        print("manifest: \(output.appendingPathComponent("manifest.json").path)")
    }
}
