import Foundation

/// The scientific-miracles corpus: 202 short articles, each making one claim about the Quran and
/// anchoring it to the ayahs it rests on, under 15 categories.
///
/// An article is a list of BLOCKS in reading order rather than one field of prose, because the
/// layout matters: the claim is a headline, the lead sets it up, a quote carries somebody else's
/// words with the source next to them, an ayah block is a hole the consumer fills from
/// `quran.json`, and the closer asks the rhetorical question the article was built toward.
///
/// An `ayah` block carries NO text, by design: surah, ayah and endAyah only. The verse belongs to
/// this engine's own Ḥafṣ text, so duplicating it here would be a second copy to keep in step and
/// would pin the article to one riwayah.
///
/// There are NO `image` blocks and `imagesIncluded` is false: the site's illustrations are not
/// republished here for licensing reasons, and the prose is written to stand without them. A
/// consumer that leaves a gap for a picture will be waiting forever.
///
/// Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
/// science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters
/// or sorts by has to come off the ARTICLE.
///
/// See docs/25-miracles.md.

/// The four levels, easiest first.
///
/// Hard-coded because this is the app's own ordering and nothing in the file states it:
/// alphabetically "extreme" would sort second, which is precisely backwards.
public let miracleLevels: [String] = ["simple", "intermediate", "advanced", "extreme"]

/// The block kinds that carry the article's OWN prose. A quote is somebody else's words and an
/// ayah block has no text at all, so neither belongs in `Miracles.text(_:)`.
private let miracleProseKinds: Set<String> = ["claim", "lead", "text", "closer"]

/// One of the fifteen categories, with the hardest science it covers.
public struct MiracleCategory: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    /// The CATEGORY's level, which an article under it need not share.
    public let level: String
}

/// A link out of a block: either an outside page or another article in this corpus.
///
/// Exactly one of `url` and `slug` is set. Both forms occur, so a model that kept only `url` would
/// silently drop the twelve internal cross-references.
public struct MiracleLink: Decodable, Sendable, Equatable {
    public let label: String
    /// An outside page.
    public let url: String?
    /// Another article's slug: follow it with `Miracles.bySlug(_:)`.
    public let slug: String?

    public init(label: String, url: String? = nil, slug: String? = nil) {
        self.label = label
        self.url = url
        self.slug = slug
    }
}

/// One block of an article. Which fields are set follows from `kind`.
public struct MiracleBlock: Decodable, Sendable, Equatable {
    /// "claim", "lead", "text", "quote", "ayah" or "closer". Never "image".
    public let kind: String
    /// Set on every kind but `ayah`.
    public let text: String
    /// `lead` and `text` blocks only.
    public let links: [MiracleLink]
    /// `quote` only: who is being quoted.
    public let sourceLabel: String?
    public let sourceUrl: String?
    /// `ayah` only.
    public let surah: Int?
    /// `ayah` only: the first of the range.
    public let ayah: Int?
    /// `ayah` only: the last of the range, always present and equal to `ayah` for a single verse.
    public let endAyah: Int?

    private enum CodingKeys: String, CodingKey {
        case kind, text, links, sourceLabel, sourceUrl, surah, ayah, endAyah
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        links = try c.decodeIfPresent([MiracleLink].self, forKey: .links) ?? []
        sourceLabel = try c.decodeIfPresent(String.self, forKey: .sourceLabel)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        surah = try c.decodeIfPresent(Int.self, forKey: .surah)
        ayah = try c.decodeIfPresent(Int.self, forKey: .ayah)
        endAyah = try c.decodeIfPresent(Int.self, forKey: .endAyah)
    }

    /// Whether this is an `ayah` block covering one ayah. A block is a RANGE, so an article citing
    /// 21:30-33 answers to 21:31 as well.
    public func covers(_ surahID: Int, _ ayahID: Int) -> Bool {
        guard kind == "ayah", surah == surahID, let start = ayah else { return false }
        return ayahID >= start && ayahID <= (endAyah ?? start)
    }
}

/// One article.
public struct MiracleArticle: Decodable, Sendable, Identifiable, Equatable {
    public let slug: String
    public let title: String
    /// A `MiracleCategory` id.
    public let category: String
    /// This article's OWN level, not its category's.
    public let level: String
    public let blocks: [MiracleBlock]

    public var id: String { slug }
}

/// `data/miracles.json`.
public struct MiraclesFile: Decodable, Sendable {
    public let source: String
    /// False, always: the illustrations are not republished.
    public let imagesIncluded: Bool
    public let categories: [MiracleCategory]
    public let articles: [MiracleArticle]
}

/// One ayah range an article cites.
public struct MiracleAyahRef: Sendable, Equatable {
    public let surah: Int
    public let ayah: Int
    public let endAyah: Int
}

/// Where a level sorts, or past the end for one the corpus invents later.
public func miracleLevelRank(_ level: String) -> Int {
    miracleLevels.firstIndex(of: level) ?? miracleLevels.count
}

public final class Miracles: Sendable {
    private let articles: [MiracleArticle]
    private let categoryList: [MiracleCategory]
    private let bySlugMap: [String: MiracleArticle]
    private let sourceText: String
    /// False, always: the illustrations are not republished.
    public let imagesIncluded: Bool

    public init(_ file: MiraclesFile? = nil) {
        articles = file?.articles ?? []
        categoryList = file?.categories ?? []
        bySlugMap = Dictionary(articles.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        sourceText = file?.source ?? ""
        imagesIncluded = file?.imagesIncluded ?? false
    }

    public var isLoaded: Bool { !articles.isEmpty }

    /// Where the corpus came from and when it was captured.
    public func source() -> String { sourceText }

    /// All 202, in corpus order.
    public func all() -> [MiracleArticle] { articles }

    public func bySlug(_ slug: String) -> MiracleArticle? { bySlugMap[slug] }

    /// The fifteen categories, in the corpus's own order.
    public func categories() -> [MiracleCategory] { categoryList }

    public func category(_ id: String) -> MiracleCategory? { categoryList.first { $0.id == id } }

    /// Every article filed under one category.
    public func byCategory(_ id: String) -> [MiracleArticle] { articles.filter { $0.category == id } }

    /// Every article at one level.
    ///
    /// The ARTICLE's level, not its category's: they disagree far more often than they agree, and
    /// a reader who picked "simple" means the article.
    public func byLevel(_ level: String) -> [MiracleArticle] { articles.filter { $0.level == level } }

    /// The article levels actually present, easiest first.
    public func levels() -> [String] {
        Set(articles.map(\.level)).sorted {
            let (a, b) = (miracleLevelRank($0), miracleLevelRank($1))
            return a == b ? $0 < $1 : a < b
        }
    }

    /// Every article that cites an ayah: the way into this corpus from elsewhere in the engine.
    ///
    /// An `ayah` block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An
    /// article that cites the same ayah in two blocks is still listed once.
    public func citing(_ surahID: Int, _ ayahID: Int) -> [MiracleArticle] {
        articles.filter { article in article.blocks.contains { $0.covers(surahID, ayahID) } }
    }

    /// The ayah ranges one article cites, in the order it cites them.
    public func ayahRefs(_ slug: String) -> [MiracleAyahRef] {
        guard let article = bySlugMap[slug] else { return [] }
        return article.blocks.compactMap { block in
            guard block.kind == "ayah", let surah = block.surah, let ayah = block.ayah else {
                return nil
            }
            return MiracleAyahRef(surah: surah, ayah: ayah, endAyah: block.endAyah ?? ayah)
        }
    }

    /// Articles whose title or prose matches a query, case-insensitively.
    ///
    /// Quotes are searched as well: a reader looking for a word remembers reading it, not who
    /// wrote it.
    public func search(_ query: String, limit: Int = 25) -> [MiracleArticle] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return articles.filter { article in
            article.title.lowercased().contains(q)
                || article.blocks.contains { $0.text.lowercased().contains(q) }
        }
        .prefix(limit)
        .map { $0 }
    }

    /// One article's own prose, blocks joined with a blank line in reading order.
    ///
    /// Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
    /// folding them in would put somebody else's words into the article's voice and would break a
    /// citation off from what it cites. Ayah blocks are skipped because they carry no text at all,
    /// only a reference for the consumer to resolve.
    public func text(_ slug: String) -> String {
        guard let article = bySlugMap[slug] else { return "" }
        return article.blocks
            .filter { miracleProseKinds.contains($0.kind) && !$0.text.isEmpty }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    public func count() -> (articles: Int, categories: Int, ayahRefs: Int) {
        (articles.count,
         categoryList.count,
         articles.reduce(0) { $0 + $1.blocks.filter { $0.kind == "ayah" }.count })
    }
}
