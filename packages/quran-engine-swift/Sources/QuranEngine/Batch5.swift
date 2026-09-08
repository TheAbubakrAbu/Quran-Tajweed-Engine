import Foundation

// The corpora added upstream in Al-Islam 4.6.4: the repeated phrases, the QUL topic indexes, the
// hizb/ruku/manzil divisions, the qiraat variant matrix and the word of the day. Morphology has
// its own file.
//
// See docs/19-mutashabihat.md, 20-topics-and-metadata.md, 21-qiraat-variants.md and
// 22-word-of-day.md.

// MARK: - Mutashabihat

/// One repeated phrase and every place it occurs.
///
/// A different thing from a similar ayah: that is a whole-ayah match, this is the exact run of
/// words two ayahs share, which is the memoriser's question. Spans are 0-based inclusive token
/// ranges of the raw Hafs text, mapped at build time, so nothing here matches text.
public struct MutashabihatPhrase: Sendable, Equatable, Identifiable {
    public let id: Int
    /// The ayah the phrase is defined from.
    public let source: String
    /// Inclusive token range inside `source`.
    public let span: ClosedRange<Int>
    public let count: Int
    public let ayahCount: Int
    public let surahCount: Int
    /// Ayah key -> the spans carrying the phrase in that ayah.
    public let occurrences: [String: [ClosedRange<Int>]]

    /// How long the phrase is, in words.
    public var wordCount: Int { span.count }

    /// The occurrences in mushaf order.
    public var orderedKeys: [String] {
        occurrences.keys.sorted(by: ayahKeyIsOrderedBefore)
    }
}

/// One row of `data/mutashabihat.json`.
public struct MutashabihatPhraseRow: Decodable, Sendable {
    public let source: String
    public let span: [Int]
    public let count: Int
    public let ayahCount: Int
    public let surahCount: Int
    public let occurrences: [String: [[Int]]]
}

/// `data/mutashabihat.json`.
public struct MutashabihatFile: Decodable, Sendable {
    public let phrases: [String: MutashabihatPhraseRow]
    public let index: [String: [Int]]
}

public final class Mutashabihat: Sendable {
    private let file: MutashabihatFile?

    public init(_ file: MutashabihatFile? = nil) {
        self.file = file
    }

    public var isLoaded: Bool { !(file?.phrases.isEmpty ?? true) }

    /// One phrase by id.
    public func phrase(id: Int) -> MutashabihatPhrase? {
        guard let row = file?.phrases["\(id)"], row.span.count == 2,
              row.span[1] >= row.span[0] else { return nil }
        var occurrences: [String: [ClosedRange<Int>]] = [:]
        for (key, spans) in row.occurrences {
            occurrences[key] = spans.compactMap { span in
                guard span.count == 2, span[0] >= 0, span[1] >= span[0] else { return nil }
                return span[0]...span[1]
            }
        }
        return MutashabihatPhrase(id: id, source: row.source, span: row.span[0]...row.span[1],
                                  count: row.count, ayahCount: row.ayahCount,
                                  surahCount: row.surahCount, occurrences: occurrences)
    }

    /// The phrases this ayah carries, longest first so the most distinctive wording leads.
    public func phrases(surah: Int, ayah: Int) -> [MutashabihatPhrase] {
        (file?.index["\(surah):\(ayah)"] ?? [])
            .compactMap { phrase(id: $0) }
            .sorted { $0.wordCount != $1.wordCount ? $0.wordCount > $1.wordCount : $0.id < $1.id }
    }

    /// Whether the ayah carries any: a dictionary hit, cheap enough to gate a button on.
    public func has(surah: Int, ayah: Int) -> Bool {
        !(file?.index["\(surah):\(ayah)"] ?? []).isEmpty
    }

    /// A phrase's occurrences in mushaf order, each with the spans carrying it there.
    public func occurrences(id: Int) -> [(surah: Int, ayah: Int, key: String, spans: [ClosedRange<Int>])] {
        guard let phrase = phrase(id: id) else { return [] }
        return phrase.orderedKeys.compactMap { key in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1], key, phrase.occurrences[key] ?? [])
        }
    }

    /// The phrase's own words, sliced out of the ayah text you hand it. The engine does not carry
    /// the text in here: the caller already has the ayah it is displaying.
    public func text(id: Int, sourceAyahText: String) -> String {
        guard let phrase = phrase(id: id) else { return "" }
        let tokens = sourceAyahText.split(whereSeparator: \.isWhitespace)
        guard phrase.span.upperBound < tokens.count else { return "" }
        return tokens[phrase.span.lowerBound...phrase.span.upperBound].joined(separator: " ")
    }

    /// How many phrases there are, and how many ayahs carry one.
    public func count() -> (phrases: Int, ayahs: Int) {
        (file?.phrases.count ?? 0, file?.index.count ?? 0)
    }
}

// MARK: - QUL topics

/// One of the three QUL indexes.
///
/// They are three trees over ONE pool of topics, not three partitions of it: a topic can be a
/// node in more than one (17 are), and a tree's parent need not itself be listed in that tree.
public enum TopicTree: String, Decodable, Sendable, CaseIterable {
    case thematic
    case ontology
    case index
}

/// One topic of the Quranic Universal Library's indexes.
public struct QulTopic: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let arabic: String
    /// The indexes listing this topic; 17 topics are listed in two.
    public let families: [TopicTree]
    /// One parent per tree, independently. Nil where the topic is not in that tree, or is one of
    /// its roots.
    public let parents: [String: Int?]
    public let description: String
    public let wiki: String
    /// "2:255" references, in the corpus's order.
    public let ayahs: [String]
    public let related: [Int]

    /// The parent in one tree, if any.
    public func parent(in tree: TopicTree) -> Int? {
        parents[tree.rawValue] ?? nil
    }

    /// Whether this index lists the topic.
    public func isListed(in tree: TopicTree) -> Bool { families.contains(tree) }

    /// The tree to use when a caller does not name one: the first index listing the topic.
    public var defaultTree: TopicTree? { families.first }

    public static func == (lhs: QulTopic, rhs: QulTopic) -> Bool { lhs.id == rhs.id }
}

/// `data/quran-topics.json`.
public struct QulTopicsFile: Decodable, Sendable {
    public let topics: [QulTopic]
}

public final class QuranTopics: @unchecked Sendable {
    private let all: [QulTopic]
    private let byID: [Int: QulTopic]
    private let lock = NSLock()
    private var childCache: [TopicTree: [Int: [Int]]] = [:]
    private var ayahIndex: [String: [Int]]?

    public init(_ file: QulTopicsFile? = nil) {
        all = file?.topics ?? []
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var isLoaded: Bool { !all.isEmpty }

    /// Every topic, in corpus order.
    public func topics() -> [QulTopic] { all }

    public func topic(id: Int) -> QulTopic? { byID[id] }

    /// The topics an index lists.
    public func topics(in tree: TopicTree) -> [QulTopic] { all.filter { $0.isListed(in: tree) } }

    /// Topics an index lists that have no parent in that same tree.
    public func roots(of tree: TopicTree) -> [QulTopic] {
        all.filter { $0.isListed(in: tree) && $0.parent(in: tree) == nil }
    }

    /// The parent in one tree. Pass nil for the topic's first listed index, which is a
    /// convenience for a caller that does not care.
    public func parent(of id: Int, in tree: TopicTree? = nil) -> QulTopic? {
        guard let topic = byID[id], let which = tree ?? topic.defaultTree,
              let parentID = topic.parent(in: which) else { return nil }
        return byID[parentID]
    }

    /// Direct children in one tree, in id order.
    public func children(of id: Int, in tree: TopicTree? = nil) -> [QulTopic] {
        guard let topic = byID[id], let which = tree ?? topic.defaultTree else { return [] }
        return childIndex(for: which)[id, default: []].compactMap { byID[$0] }
    }

    /// The chain up to the root of one tree, nearest first. Cycle-safe: the corpus is trusted for
    /// its content, not for its shape.
    public func ancestors(of id: Int, in tree: TopicTree? = nil) -> [QulTopic] {
        guard let topic = byID[id], let which = tree ?? topic.defaultTree else { return [] }
        var out: [QulTopic] = []
        var seen: Set<Int> = [id]
        var current = parent(of: id, in: which)
        while let node = current, !seen.contains(node.id) {
            seen.insert(node.id)
            out.append(node)
            current = parent(of: node.id, in: which)
        }
        return out
    }

    /// Every topic annotating this ayah, across all three indexes.
    public func topics(surah: Int, ayah: Int) -> [QulTopic] {
        buildAyahIndex()
        lock.lock(); let ids = ayahIndex?["\(surah):\(ayah)"] ?? []; lock.unlock()
        return ids.compactMap { byID[$0] }
    }

    /// Name and Arabic-name substring search, exact-prefix hits first.
    public func search(_ query: String, limit: Int = 50) -> [QulTopic] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var starts: [QulTopic] = []
        var contains: [QulTopic] = []
        for topic in all {
            let name = topic.name.lowercased()
            if name.hasPrefix(q) { starts.append(topic) }
            else if name.contains(q) || topic.arabic.contains(query) { contains.append(topic) }
            if starts.count >= limit { break }
        }
        return Array((starts + contains).prefix(limit))
    }

    /// Corpus size. The per-index counts deliberately sum to MORE than the topic count: the 17
    /// topics listed in two indexes are counted in both.
    public func count() -> (topics: Int, thematic: Int, ontology: Int, index: Int, references: Int) {
        var byFamily: [TopicTree: Int] = [:]
        var references = 0
        for topic in all {
            for family in topic.families { byFamily[family, default: 0] += 1 }
            references += topic.ayahs.count
        }
        return (all.count, byFamily[.thematic] ?? 0, byFamily[.ontology] ?? 0,
                byFamily[.index] ?? 0, references)
    }

    // MARK: Internals

    private func childIndex(for tree: TopicTree) -> [Int: [Int]] {
        lock.lock(); defer { lock.unlock() }
        if let cached = childCache[tree] { return cached }
        var table: [Int: [Int]] = [:]
        for topic in all {
            if let parentID = topic.parent(in: tree) { table[parentID, default: []].append(topic.id) }
        }
        for key in table.keys { table[key]?.sort() }
        childCache[tree] = table
        return table
    }

    private func buildAyahIndex() {
        lock.lock(); defer { lock.unlock() }
        guard ayahIndex == nil else { return }
        var table: [String: [Int]] = [:]
        for topic in all {
            for key in topic.ayahs { table[key, default: []].append(topic.id) }
        }
        ayahIndex = table
    }
}

// MARK: - Passage themes

/// One short sentence describing a run of ayahs.
///
/// Passages run in order through a surah and do not nest. They do not tile it either: an ayah
/// between two passages has none.
public struct ThemePassage: Decodable, Sendable, Equatable {
    public let from: Int
    public let to: Int
    public let theme: String
    public let topic: String
}

public final class AyahThemes: Sendable {
    private let data: [String: [ThemePassage]]

    public init(_ data: [String: [ThemePassage]]? = nil) {
        self.data = data ?? [:]
    }

    public var isLoaded: Bool { !data.isEmpty }

    /// A surah's passages, in order.
    public func passages(surah: Int) -> [ThemePassage] { data["\(surah)"] ?? [] }

    /// The passage an ayah falls in. Passages do not overlap, so this is the one answer; nil for
    /// an ayah between two of them.
    public func passage(surah: Int, ayah: Int) -> ThemePassage? {
        passages(surah: surah).first { ayah >= $0.from && ayah <= $0.to }
    }

    /// Matches the theme sentence and the topic it sits under.
    public func search(_ query: String, limit: Int = 50) -> [(surah: Int, passage: ThemePassage)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [(surah: Int, passage: ThemePassage)] = []
        for surah in data.keys.compactMap(Int.init).sorted() {
            for passage in passages(surah: surah)
            where passage.theme.lowercased().contains(q) || passage.topic.lowercased().contains(q) {
                out.append((surah, passage))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    public func count() -> (surahs: Int, passages: Int) {
        (data.count, data.values.reduce(0) { $0 + $1.count })
    }
}

// MARK: - Hizb, ruku and manzil

/// One hizb, ruku or manzil, identified by where it starts.
public struct Division: Sendable, Equatable {
    public let number: Int
    public let surah: Int
    public let ayah: Int
    public let key: String
}

/// `data/quran-metadata.json`.
public struct QuranMetadataFile: Decodable, Sendable {
    public let hizb: [String]
    public let ruku: [String]
    public let manzil: [String]
}

/// One of the three schedule divisions, stored as its start keys in order so a lookup is a
/// binary search rather than a table with one row per ayah.
public struct DivisionTable: Sendable {
    private let starts: [String]
    private let ranks: [Int]

    init(_ starts: [String]) {
        self.starts = starts
        self.ranks = starts.map { key in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 1000 + parts[1] : 0
        }
    }

    public var count: Int { starts.count }

    /// The 1-based number containing an ayah, or 0 when there is no table.
    public func number(surah: Int, ayah: Int) -> Int {
        let target = surah * 1000 + ayah
        var low = 0, high = ranks.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if ranks[mid] <= target { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found + 1
    }

    /// Where a division begins.
    public func start(_ number: Int) -> Division? {
        guard number >= 1, number <= starts.count else { return nil }
        let key = starts[number - 1]
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Division(number: number, surah: parts[0], ayah: parts[1], key: key)
    }

    /// Every start, in order.
    public func all() -> [Division] { (1...max(starts.count, 1)).compactMap { start($0) } }

    /// A division's start and the start of the next one, which is where it ends. The second is
    /// nil for the last, which runs to the end of the Quran: no start key says so, and pretending
    /// otherwise would be an invented boundary.
    public func range(_ number: Int) -> (from: Division, until: Division?)? {
        guard let from = start(number) else { return nil }
        return (from, start(number + 1))
    }
}

/// 60 hizb (the juz halved, the unit a memorisation plan is written in), 558 ruku (thematic
/// sections printed in the margin of South Asian mushafs), 7 manzil (the seven-day division).
public struct QuranMetadata: Sendable {
    public let hizb: DivisionTable
    public let ruku: DivisionTable
    public let manzil: DivisionTable

    public init(_ file: QuranMetadataFile? = nil) {
        hizb = DivisionTable(file?.hizb ?? [])
        ruku = DivisionTable(file?.ruku ?? [])
        manzil = DivisionTable(file?.manzil ?? [])
    }

    public var isLoaded: Bool { hizb.count > 0 }

    /// All three at once, which is what a "where am I" line under an ayah wants.
    public func divisions(surah: Int, ayah: Int) -> (hizb: Int, ruku: Int, manzil: Int) {
        (hizb.number(surah: surah, ayah: ayah),
         ruku.number(surah: surah, ayah: ayah),
         manzil.number(surah: surah, ayah: ayah))
    }

    public func count() -> (hizb: Int, ruku: Int, manzil: Int) {
        (hizb.count, ruku.count, manzil.count)
    }
}

// MARK: - Shared helpers

/// Mushaf order for "surah:ayah" keys.
func ayahKeyIsOrderedBefore(_ a: String, _ b: String) -> Bool {
    let pa = a.split(separator: ":").compactMap { Int($0) }
    let pb = b.split(separator: ":").compactMap { Int($0) }
    guard pa.count == 2, pb.count == 2 else { return a < b }
    return pa[0] != pb[0] ? pa[0] < pb[0] : pa[1] < pb[1]
}

/// Split a "surah:ayah" key; (0, 0) for anything malformed, which never masquerades as an ayah.
func splitAyahKey(_ key: String) -> (surah: Int, ayah: Int) {
    let parts = key.split(separator: ":").compactMap { Int($0) }
    return parts.count == 2 ? (parts[0], parts[1]) : (0, 0)
}
