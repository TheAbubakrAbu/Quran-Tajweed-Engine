import Foundation

/// Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one sentence
/// saying what the surah as a whole is about.
///
/// This answers "I am at 18:60 - what is this passage doing here", which neither the translation nor
/// the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
/// outline; al-Fatihah, Fussilat and ad-Dukhan do not.
///
/// **The outline is a tree, flattened.** Ranges are inclusive, in mushaf order, and MAY NEST: a
/// broad section is followed by the sections inside it, parent before children (Hud opens with 1-24
/// "Doctrine facts", then 1-4, 5-6, 7-11, 12-17, 18-24 within it). They also do not tile the surah -
/// an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
/// which is what `sections(for:ayah:)` returns; `outline(_:)` rebuilds it as a tree.
///
/// See `../../docs/15-surah-sections.md`.
public struct SurahSection: Equatable, Sendable {
    /// First ayah, inclusive.
    public let from: Int
    /// Last ayah, inclusive.
    public let to: Int
    public let english: String
    public let arabic: String

    public func contains(_ ayah: Int) -> Bool { ayah >= from && ayah <= to }
}

/// A section with the sections inside it.
public struct OutlineNode: Equatable, Sendable {
    public let section: SurahSection
    public var children: [OutlineNode]
}

/// One surah's entry in `data/surah-sections.json`.
public struct SurahSectionsEntry: Decodable, Sendable {
    public let overview: String
    /// `[from, to, english, arabic]` - heterogeneous, so decoded field by field.
    public let sections: [SurahSection]

    private enum CodingKeys: String, CodingKey { case overview, sections }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = (try? container.decode(String.self, forKey: .overview)) ?? ""

        var rows: [SurahSection] = []
        if var list = try? container.nestedUnkeyedContainer(forKey: .sections) {
            while !list.isAtEnd {
                var row = try list.nestedUnkeyedContainer()
                guard let from = try? row.decode(Int.self),
                      let to = try? row.decode(Int.self),
                      let english = try? row.decode(String.self),
                      let arabic = try? row.decode(String.self) else { continue }
                rows.append(SurahSection(from: from, to: to, english: english, arabic: arabic))
            }
        }
        sections = rows
    }
}

public struct SurahSections: Sendable {
    private let data: [String: SurahSectionsEntry]

    public init(_ data: [String: SurahSectionsEntry]? = nil) {
        self.data = data ?? [:]
    }

    /// One sentence on what the whole surah is about, "" when none is recorded.
    public func overview(_ surahId: Int) -> String {
        data[String(surahId)]?.overview ?? ""
    }

    /// The surah's sections, flat and in the order the source records them (a parent immediately
    /// before the sections inside it).
    public func sections(_ surahId: Int) -> [SurahSection] {
        data[String(surahId)]?.sections ?? []
    }

    /// The same sections as a tree: top-level passages, each with what is inside it.
    public func outline(_ surahId: Int) -> [OutlineNode] {
        var roots: [OutlineNode] = []
        // The open chain, as a path of indices: a value-type tree cannot hold a reference to the
        // node currently being filled, so the path is walked back down on each insert.
        var path: [Int] = []

        for section in sections(surahId) {
            while let open = node(in: roots, at: path), !(open.section.from <= section.from && section.to <= open.section.to) {
                path.removeLast()
            }
            let node = OutlineNode(section: section, children: [])
            let index = append(node, in: &roots, at: path)
            path.append(index)
        }
        return roots
    }

    /// Every section covering an ayah, outermost first - the breadcrumb for "you are here". Empty
    /// when the surah has no outline, or when this ayah falls between sections.
    public func sections(for surahId: Int, ayah ayahId: Int) -> [SurahSection] {
        sections(surahId).filter { $0.contains(ayahId) }
    }

    /// The most specific section covering an ayah - the heading a reader wants beside the verse.
    public func section(for surahId: Int, ayah ayahId: Int) -> SurahSection? {
        sections(for: surahId, ayah: ayahId).last
    }

    /// Whether this surah has an outline at all.
    public func hasSections(_ surahId: Int) -> Bool {
        !(data[String(surahId)]?.sections.isEmpty ?? true)
    }

    /// How many surahs carry an outline.
    public var count: Int {
        data.values.filter { !$0.sections.isEmpty }.count
    }

    /// Sections whose title carries `query`, across every surah.
    public func search(_ query: String) -> [(surah: Int, section: SurahSection)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [(surah: Int, section: SurahSection)] = []
        for id in data.keys.compactMap(Int.init).sorted() {
            for section in sections(id) where
                section.english.lowercased().contains(needle) || section.arabic.contains(trimmed) {
                out.append((id, section))
            }
        }
        return out
    }

    private func node(in roots: [OutlineNode], at path: [Int]) -> OutlineNode? {
        guard let first = path.first, roots.indices.contains(first) else { return nil }
        var current = roots[first]
        for index in path.dropFirst() {
            guard current.children.indices.contains(index) else { return nil }
            current = current.children[index]
        }
        return current
    }

    /// Appends into the child list the path points at, returning the new node's index.
    private func append(_ node: OutlineNode, in roots: inout [OutlineNode], at path: [Int]) -> Int {
        guard let first = path.first else {
            roots.append(node)
            return roots.count - 1
        }
        var rest = path
        rest.removeFirst()
        return append(node, in: &roots[first].children, at: rest)
    }
}
