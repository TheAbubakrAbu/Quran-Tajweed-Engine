import Foundation

/// How far apart two readings actually are, measured word by word.
///
/// The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which
/// says what differs but never how much. This measures it: align the two readings' words and sort
/// every pair into one of three buckets.
///
/// * **identical** - the same word, written the same way, marks and all.
/// * **sameSkeleton** - the same consonantal skeleton (rasm), different vowels or spelling. This is
///   the overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm
///   was designed to allow: one written form, several sound readings.
/// * **different** - a different skeleton, i.e. a genuinely different word form.
///
/// **Why alignment is not indexing.** Readings merge and split ayahs (Warsh's al-Baqarah has 285
/// ayahs to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n
/// of the other. The comparison walks the whole SURAH's word stream on both sides with a two-pointer
/// alignment and bounded lookahead rather than pairing by index.
///
/// **What it cannot tell you.** This measures the two printed TEXTS, not the two recitations: a
/// difference that lives only in how a letter is sounded (imalah, taqlil, ishmam) shows up only
/// where the print marks it.
///
/// Needs `Engine.load(loadQiraat: true)`, or a `Quran` built with qiraah text. The Swift package
/// does not bundle the 11 MB of qiraah text, so a consumer wanting this passes a `dataDirectory`.
/// See `../../docs/17-qiraat-comparison.md`.
public struct QiraatComparison {
    /// What happened to one word.
    public enum DifferenceKind: String, Sendable {
        /// The same consonantal skeleton, different vowels or spelling.
        case sameSkeleton
        /// A different skeleton: a genuinely different word form.
        case different
        /// The compared reading has a word the base does not.
        case added
        /// The base has a word the compared reading does not.
        case dropped
    }

    /// One non-identical word pair.
    public struct WordDifference: Equatable, Sendable {
        /// 1-based word position in the BASE reading's surah.
        public let position: Int
        /// The base reading's word ("" when the other reading adds one).
        public let base: String
        /// The compared reading's word ("" when it drops one).
        public let other: String
        public let kind: DifferenceKind
    }

    /// The counts for a surah or for the whole Quran.
    public struct Totals: Equatable, Sendable {
        /// Words compared, in the base reading.
        public var words = 0
        public var identical = 0
        public var sameSkeleton = 0
        public var different = 0
        /// Words the compared reading has and the base does not.
        public var added = 0
        /// Words the base has and the compared reading does not.
        public var dropped = 0

        public var identicalPercent: Double {
            words == 0 ? 0 : 100 * Double(identical) / Double(words)
        }
    }

    /// How far ahead to look for a resync before declaring a word added or dropped.
    private static let lookahead = 3

    private let quran: Quran

    public init(quran: Quran) {
        self.quran = quran
    }

    /// The riwayat whose text is loaded and so can be compared, in slug order. "hafs" is always one
    /// of them: it is `quran.json` itself.
    public func available() -> [String] {
        Array(Set(["hafs"] + quran.loadedRiwayat)).sorted()
    }

    /// Every word of a surah in one reading, in order.
    public func words(surah surahId: Int, riwayah: String) -> [String] {
        guard let surah = quran.surah(surahId) else { return [] }
        // The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking
        // Hafs' ayah ids and asking for each would compare different verses.
        let verses: [String] = riwayah.lowercased() == "hafs"
            ? surah.ayahs.map(\.textArabic)
            : quran.qiraahVerses(surah: surahId, riwayah: riwayah).map(\.text)
        return verses.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }

    /// Compare one surah, word by word.
    public func compare(surah surahId: Int, riwayah: String, against: String = "hafs") -> Totals {
        Self.totals(align(surah: surahId, base: against, other: riwayah))
    }

    /// Compare the whole Quran. This walks every word of both readings - about 155,000 comparisons -
    /// so cache the result rather than calling it per render.
    public func compare(riwayah: String, against: String = "hafs") -> Totals {
        var sum = Totals()
        for surah in quran.all() {
            let part = compare(surah: surah.id, riwayah: riwayah, against: against)
            sum.words += part.words
            sum.identical += part.identical
            sum.sameSkeleton += part.sameSkeleton
            sum.different += part.different
            sum.added += part.added
            sum.dropped += part.dropped
        }
        return sum
    }

    /// The words that are not identical, in reading order - the rows behind a comparison view.
    /// `limit` of 0 returns them all.
    public func differences(surah surahId: Int, riwayah: String, against: String = "hafs",
                            limit: Int = 0) -> [WordDifference] {
        let rows = align(surah: surahId, base: against, other: riwayah).compactMap { row -> WordDifference? in
            guard let kind = DifferenceKind(rawValue: row.kind), row.kind != "identical" else { return nil }
            return WordDifference(position: row.position, base: row.base, other: row.other, kind: kind)
        }
        return limit > 0 ? Array(rows.prefix(limit)) : rows
    }

    /// The consonantal skeleton of a word: diacritics and recitation signs gone, the letters that
    /// are written differently for the same consonant folded together.
    public static func skeleton(_ word: String) -> String {
        var out = ""
        for character in ArabicText.removingArabicDiacriticsAndSigns(word) {
            switch character {
            case "ٱ", "أ", "إ", "آ", "ى", "ٰ": out.append("ا")
            case "ؤ": out.append("و")
            case "ئ": out.append("ي")
            case "ة": out.append("ه")
            case "ء", "ـ": continue
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: - Alignment

    private struct Row {
        let position: Int
        let base: String
        let other: String
        let kind: String
    }

    /// Two-pointer alignment with bounded lookahead.
    private func align(surah surahId: Int, base: String, other: String) -> [Row] {
        let left = words(surah: surahId, riwayah: base)
        let right = words(surah: surahId, riwayah: other)
        let leftSkeletons = left.map(Self.skeleton)
        let rightSkeletons = right.map(Self.skeleton)
        var rows: [Row] = []

        var i = 0, j = 0
        while i < left.count && j < right.count {
            if left[i] == right[j] {
                rows.append(Row(position: i + 1, base: left[i], other: right[j], kind: "identical"))
                i += 1; j += 1
                continue
            }
            if leftSkeletons[i] == rightSkeletons[j] {
                rows.append(Row(position: i + 1, base: left[i], other: right[j], kind: "sameSkeleton"))
                i += 1; j += 1
                continue
            }
            // Not a match. Before calling it a different word, see whether one side simply has an
            // extra word here - a merge or a split - by looking for the next place they agree.
            if let resync = Self.findResync(leftSkeletons, rightSkeletons, i, j) {
                for k in i..<resync.i {
                    rows.append(Row(position: k + 1, base: left[k], other: "", kind: "dropped"))
                }
                for k in j..<resync.j {
                    rows.append(Row(position: i + 1, base: "", other: right[k], kind: "added"))
                }
                i = resync.i; j = resync.j
                continue
            }
            rows.append(Row(position: i + 1, base: left[i], other: right[j], kind: "different"))
            i += 1; j += 1
        }
        while i < left.count {
            rows.append(Row(position: i + 1, base: left[i], other: "", kind: "dropped"))
            i += 1
        }
        while j < right.count {
            rows.append(Row(position: left.count, base: "", other: right[j], kind: "added"))
            j += 1
        }
        return rows
    }

    /// The nearest offset within the lookahead window at which the two streams agree again by
    /// skipping words on ONE side only - an insertion or a deletion.
    ///
    /// Skipping on both sides at once is deliberately not a resync: that is a substitution, one word
    /// standing where another does, which is the `different` bucket. Allowing it here collapsed
    /// every genuine word difference into a dropped+added pair and left `different` at zero.
    private static func findResync(_ left: [String], _ right: [String],
                                   _ i: Int, _ j: Int) -> (i: Int, j: Int)? {
        for skip in 1...lookahead {
            if i + skip < left.count && left[i + skip] == right[j] { return (i + skip, j) }
            if j + skip < right.count && left[i] == right[j + skip] { return (i, j + skip) }
        }
        return nil
    }

    private static func totals(_ rows: [Row]) -> Totals {
        var out = Totals()
        for row in rows {
            if row.kind == "added" { out.added += 1; continue }
            out.words += 1
            switch row.kind {
            case "identical": out.identical += 1
            case "sameSkeleton": out.sameSkeleton += 1
            case "dropped": out.dropped += 1
            default: out.different += 1
            }
        }
        return out
    }
}
