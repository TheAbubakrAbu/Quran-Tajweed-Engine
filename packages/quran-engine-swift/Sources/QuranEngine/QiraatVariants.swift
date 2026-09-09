import Foundation

/// Who among the Ten reads a word differently, what they read, and what the difference means.
///
/// This is the layer the qiraah texts cannot supply. `data/qiraat/` gives each reading its own
/// words, and `qiraatComparison` will align two of them: that answers WHAT each riwayah reads. It
/// cannot say that a form is Hamzah's rather than Nafi's, that it is a passive where Hafs has an
/// active, or that al-Mahdawi held the two to mean the same thing. That is this module, from the
/// Quran.com qiraat matrix.
///
/// Readers against transmitters: a reading lists `readers` when both of an imam's transmitters
/// follow it, and `transmitters` when the two part company. Segment ranges are 0-based inclusive
/// token indices of the raw Hafs text, nil where the builder could not place the word, in which
/// case a consumer shows the word untinted rather than guessing.
///
/// Only the eight riwayat whose text this engine publishes appear in `places`. The other twelve
/// do appear as attributions, which is right: attributing a reading to Ibn Dhakwan says nothing
/// about the state of his extracted text.
///
/// See docs/21-qiraat-variants.md.

/// One of the ten imams.
public struct VariantReader: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let abbreviation: String
    public let city: String
    public let position: Int
}

/// One of the twenty riwayat.
public struct VariantTransmitter: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let reader: Int
    /// This engine's own slug, so a consumer can join to `data/qiraat` and `data/mushaf`.
    public let riwayah: String?
    /// False for the twelve riwayat whose extracted text is not published.
    public let textPublished: Bool
}

/// One form of a word, and who reads it.
public struct VariantReading: Decodable, Sendable, Equatable {
    public let text: String
    public let transliteration: String
    public let english: String
    public let explanation: String
    public let grammaticalForm: String
    public let rootLetters: String
    /// Imams whose two transmitters both read it.
    public let readers: [Int]
    /// Individual transmitters, where an imam's two differ.
    public let transmitters: [Int]
}

/// Where the word sits. `span` is nil where the builder could not place it.
public struct VariantSegment: Decodable, Sendable, Equatable {
    public let ayah: String
    public let span: [Int]?

    /// The span as a range, or nil when it is absent or malformed.
    public var range: ClosedRange<Int>? {
        guard let span, span.count == 2, span[0] >= 0, span[1] >= span[0] else { return nil }
        return span[0]...span[1]
    }
}

/// One word of an ayah that the Ten read differently.
public struct Juncture: Decodable, Sendable, Equatable {
    public let word: String
    public let category: String
    public let segments: [VariantSegment]
    public let readings: [VariantReading]
    public let note: String
}

/// `data/qiraat-variants.json`.
public struct QiraatVariantsFile: Decodable, Sendable {
    public let readers: [String: VariantReader]
    public let transmitters: [String: VariantTransmitter]
    public let ayahs: [String: [Juncture]]
}

/// One ayah where a riwayah differs from Hafs.
///
/// Two kinds, because they are found two ways and a consumer may want only the first: a `word`
/// index is a word dropped, added or spelled differently, which a text diff finds; a `letter`
/// index is a word the printed mushaf marks as read with other vowels over the SAME skeleton,
/// which no text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).
public struct QiraatPlace: Sendable, Equatable {
    public let ayah: Int
    public let word: [Int]
    public let letter: [Int]
}

/// One row of `data/qiraat-places.json`.
public struct QiraatPlaceRow: Decodable, Sendable {
    public let word: [Int]
    public let letter: [Int]
}

/// `data/qiraat-places.json`.
public struct QiraatPlacesFile: Decodable, Sendable {
    public let riwayat: [String: [String: [String: QiraatPlaceRow]]]
}

/// A reciter who published both readings, and the two feeds they live in.
public struct VariantAudioSource: Decodable, Sendable {
    /// "file" for a whole per-verse recording, "span" for a seek inside a full-surah one.
    public let kind: String
    public let reciter: String
    public let hafsBase: String
    public let riwayahBase: String
}

/// `data/qiraat-variant-audio.json`.
public struct QiraatVariantAudioFile: Decodable, Sendable {
    public let sources: [VariantAudioSource]
    public let riwayat: [String: [String: [[Int]]]]
}

/// One side of a paired recording. `startMs` and `endMs` are nil for a whole per-verse file.
public struct VariantClip: Sendable, Equatable {
    public let url: String
    public let startMs: Int?
    public let endMs: Int?
}

/// The same reciter reading a verse both ways.
public struct VariantAudioPair: Sendable, Equatable {
    public let reciter: String
    public let hafs: VariantClip
    public let riwayah: VariantClip
}

public final class QiraatVariants: Sendable {
    private let file: QiraatVariantsFile?
    private let placesFile: QiraatPlacesFile?
    private let audioFile: QiraatVariantAudioFile?

    public init(variants: QiraatVariantsFile? = nil,
                places: QiraatPlacesFile? = nil,
                audio: QiraatVariantAudioFile? = nil) {
        self.file = variants
        self.placesFile = places
        self.audioFile = audio
    }

    public var isLoaded: Bool { !(file?.ayahs.isEmpty ?? true) }

    /// The words of this ayah that the Ten read differently, in corpus order.
    public func junctures(surah: Int, ayah: Int) -> [Juncture] {
        file?.ayahs["\(surah):\(ayah)"] ?? []
    }

    /// Whether the ayah carries any. Only 1,409 of the 6,236 do.
    public func has(surah: Int, ayah: Int) -> Bool {
        !(file?.ayahs["\(surah):\(ayah)"] ?? []).isEmpty
    }

    public func reader(id: Int) -> VariantReader? { file?.readers["\(id)"] }

    public func transmitter(id: Int) -> VariantTransmitter? { file?.transmitters["\(id)"] }

    /// Every transmitter reading a form: an imam's own pair, plus any listed individually.
    public func transmitters(following reading: VariantReading) -> [VariantTransmitter] {
        var out: [VariantTransmitter] = []
        var seen: Set<Int> = []
        for readerID in reading.readers {
            let pair = (file?.transmitters.values.filter { $0.reader == readerID } ?? [])
                .sorted { $0.id < $1.id }
            for transmitter in pair where !seen.contains(transmitter.id) {
                seen.insert(transmitter.id)
                out.append(transmitter)
            }
        }
        for id in reading.transmitters where !seen.contains(id) {
            if let transmitter = transmitter(id: id) {
                seen.insert(id)
                out.append(transmitter)
            }
        }
        return out
    }

    /// The reading a riwayah follows at a juncture, by engine slug.
    ///
    /// A reading names an imam when BOTH his transmitters follow it, and names a transmitter when
    /// the two part company, so a transmitter named on one reading overrides his imam's listing on
    /// a sibling. Look for him across the whole juncture before falling back to the imams: at
    /// 12:109 ʿĀṣim is named on نوحي while Shuʿbah is named on يوحى, and Shuʿbah recites يوحى.
    public func reading(in juncture: Juncture, followedBy riwayah: String) -> VariantReading? {
        let named = juncture.readings.first { reading in
            reading.transmitters.contains { transmitter(id: $0)?.riwayah == riwayah }
        }
        if let named { return named }
        return juncture.readings.first { reading in
            reading.readers.contains { readerID in
                file?.transmitters.values.contains {
                    $0.reader == readerID && $0.riwayah == riwayah
                } ?? false
            }
        }
    }

    /// Who reads a form, rendered the way the printed sources do: the imams first in their
    /// canonical order, then any lone transmitters with their imam named in parentheses.
    public func attribution(for reading: VariantReading) -> String {
        let readers = reading.readers.compactMap { reader(id: $0) }
            .sorted { $0.position < $1.position }
            .map(\.abbreviation)
        let transmitters = reading.transmitters.compactMap { transmitter(id: $0) }
            .sorted { a, b in
                let pa = reader(id: a.reader)?.position ?? 99
                let pb = reader(id: b.reader)?.position ?? 99
                return pa != pb ? pa < pb : a.id < b.id
            }
            .map { transmitter -> String in
                let imam = reader(id: transmitter.reader)?.abbreviation ?? ""
                return imam.isEmpty ? transmitter.name : "\(transmitter.name) (\(imam))"
            }
        var parts: [String] = []
        if !readers.isEmpty { parts.append(readers.joined(separator: ", ")) }
        if !transmitters.isEmpty { parts.append(transmitters.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Where a riwayah differs from Hafs in a surah, in ayah order.
    public func places(riwayah: String, surah: Int) -> [QiraatPlace] {
        let table = placesFile?.riwayat[riwayah]?["\(surah)"] ?? [:]
        return table.keys.compactMap(Int.init).sorted().compactMap { ayah in
            guard let row = table["\(ayah)"] else { return nil }
            return QiraatPlace(ayah: ayah, word: row.word, letter: row.letter)
        }
    }

    /// The riwayat `places` can answer for: the published ones.
    public func riwayatWithPlaces() -> [String] { (placesFile?.riwayat.keys).map { $0.sorted() } ?? [] }

    /// One reciter reading the verse both ways, for the four riwayat where such a recording
    /// exists.
    ///
    /// The rest carry none: no reciter published both sides with timings. A pair drawn from two
    /// shaykhs would differ in voice, pace and maqam as well, and teach nothing about the
    /// variant. The honest rendering is "no recording", never a button that does nothing.
    public func audio(riwayah: String, surah: Int, ayah: Int) -> VariantAudioPair? {
        guard let rows = audioFile?.riwayat[riwayah]?["\(surah)"],
              let row = rows.first(where: { $0.first == ayah }), row.count >= 6,
              let source = audioFile?.sources[safe: row[1]] else { return nil }
        let isSpan = source.kind == "span"
        let name = isSpan
            ? String(format: "%03d.mp3", surah)
            : String(format: "%03d%03d.mp3", surah, ayah)
        func clip(_ base: String, _ start: Int, _ end: Int) -> VariantClip {
            VariantClip(url: "\(base)/\(name)",
                        startMs: isSpan ? start : nil, endMs: isSpan ? end : nil)
        }
        return VariantAudioPair(reciter: source.reciter,
                                hafs: clip(source.hafsBase, row[2], row[3]),
                                riwayah: clip(source.riwayahBase, row[4], row[5]))
    }

    /// The riwayat that have any paired recordings at all.
    public func riwayatWithAudio() -> [String] { (audioFile?.riwayat.keys).map { $0.sorted() } ?? [] }

    /// Corpus size: ayahs carrying a variant, junctures, and readings.
    public func count() -> (ayahs: Int, junctures: Int, readings: Int) {
        guard let file else { return (0, 0, 0) }
        let junctures = file.ayahs.values.reduce(0) { $0 + $1.count }
        let readings = file.ayahs.values.reduce(0) { total, rows in
            total + rows.reduce(0) { $0 + $1.readings.count }
        }
        return (file.ayahs.count, junctures, readings)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
