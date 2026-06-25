import Foundation

/// Zero-pad an integer to 3 digits ("001", "057", "114"). Mirrors `zeroPad3`.
public func zeroPad3(_ n: Int) -> String {
    String(format: "%03d", n)
}

public enum AudioError: Error, Equatable {
    case surahOutOfRange(Int)
    case noSurahFeed(String)
}

/// Full-surah recitation URL: `surahLink + zeroPad3(surah) + ".mp3"`. Mirrors `surahAudioUrl`.
public func surahAudioURL(_ reciter: Reciter, _ surahNumber: Int) throws -> String {
    guard surahNumber >= 1 && surahNumber <= 114 else { throw AudioError.surahOutOfRange(surahNumber) }
    guard !reciter.surahLink.isEmpty else { throw AudioError.noSurahFeed(reciter.name) }
    return "\(reciter.surahLink)\(zeroPad3(surahNumber)).mp3"
}

/// Ayah-by-ayah recitation URL. Requires the global ayah number (1..6236). Mirrors `ayahAudioUrl`.
public func ayahAudioURL(_ reciter: Reciter, _ globalAyahNumber: Int) -> String {
    "https://cdn.islamic.network/quran/audio/\(reciter.ayahBitrate)/\(reciter.ayahIdentifier)/\(globalAyahNumber).mp3"
}

private let minshawiFallbackName = "Muhammad Al-Minshawi (Murattal)"

/// True if this reciter falls back to Minshawi for individual-ayah audio.
public func defaultsToMinshawi(_ reciter: Reciter) -> Bool {
    reciter.ayahIdentifier.contains("minshawi") && !reciter.name.contains("Minshawi")
}

/// Display name to show while ayah audio plays (honest about the fallback).
public func ayahNowPlayingName(_ reciter: Reciter) -> String {
    if defaultsToMinshawi(reciter) { return minshawiFallbackName }
    if let q = reciter.qiraah { return "\(reciter.name) (\(q))" }
    return reciter.name
}

/// Reciter directory. Mirrors `Reciters` in `audio.js`. Sorted by name on construction.
public final class Reciters {
    public let list: [Reciter]
    private let byIdMap: [String: Reciter]

    public init(_ list: [Reciter]) {
        self.list = list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        var m = [String: Reciter]()
        for r in self.list { m[r.id] = r }
        self.byIdMap = m
    }

    public func all() -> [Reciter] { list }

    public func byId(_ id: String) -> Reciter? { byIdMap[id] }

    /// Reciters that have a full-surah feed.
    public func withSurahFeed() -> [Reciter] {
        list.filter { !$0.surahLink.isEmpty && !$0.surahLink.hasSuffix(".mp3") }
    }

    /// Reciters for a given riwayah label (`nil`/"hafs" => the default Hafs feeds).
    public func byQiraah(_ qiraah: String?) -> [Reciter] {
        guard let q = qiraah, q.lowercased() != "hafs" else { return list.filter { $0.qiraah == nil } }
        return list.filter { $0.qiraah == q }
    }

    /// Distinct riwayah labels available (excluding default Hafs).
    public func qiraat() -> [String] {
        var seen = Set<String>()
        var out = [String]()
        for r in list { if let q = r.qiraah, seen.insert(q).inserted { out.append(q) } }
        return out
    }
}
