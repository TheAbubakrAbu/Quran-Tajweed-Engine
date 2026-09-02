import Foundation

/// The printed mushaf: twenty riwayat as page-exact facsimiles, and the page table each one is
/// actually paginated by.
///
/// A riwayah's pagination is NOT Hafs' pagination. Readings merge and split ayahs and spell words
/// differently, so the same ayah sits on a different page in Warsh's print than in Hafs'. The page
/// numbers on `quran.json`'s ayahs are the Madani (Hafs) ones; `page(_:_:riwayah:)` here is that
/// riwayah's own. Every facsimile is exactly 604 pages on the Madani division, so PDF page N is
/// mushaf page N with no offset table.
///
/// Twelve of the twenty ship their printed mushaf and page table but no text: their text is
/// machine-extracted and not yet proofread, so it is not published, and the line and tajweed data
/// that index into it stay out with it. `riwayah(_:)?.textIncluded` says which is which.
///
/// See docs/10-mushaf.md.
public struct RiwayahEntry: Decodable, Sendable, Equatable {
    /// Slug, e.g. "warsh".
    public let riwayah: String
    /// The tag the Al-Islam app stores for this riwayah ("" for Hafs).
    public let tag: String
    public let name: String
    public let nameArabic: String
    /// The qiraah's imam, e.g. "Nafi".
    public let imam: String
    public let imamArabic: String
    public let narratorDiedAH: Int
    /// Path to the facsimile, relative to data/mushaf/.
    public let pdf: String
    public let pdfBytes: Int
    public let pages: String
    /// Path to the line table, when the text ships.
    public let lines: String?
    /// Path to the riwayah tajweed pack, when one exists.
    public let tajweed: String?
    public let textIncluded: Bool
}

public struct MushafIndex: Decodable, Sendable {
    public let totalPages: Int
    public let note: String?
    public let riwayat: [RiwayahEntry]
}

public struct MushafPageTable: Decodable, Sendable {
    public let riwayah: String
    public let totalPages: Int
    /// Surah id -> ayah id -> page.
    public let pages: [String: [String: Int]]
}

public struct MushafLineTable: Decodable, Sendable {
    public let riwayah: String
    public let version: Int
    /// Surah id -> ayah id -> character offsets at which a new printed line starts.
    public let lineBreaks: [String: [String: [Int]]]
}

public final class Mushaf {
    private let index: MushafIndex?
    private let byRiwayah: [String: RiwayahEntry]
    private let pageTables: [String: MushafPageTable]
    private let lineTables: [String: MushafLineTable]
    /// Inverted page -> ayahs, built the first time a riwayah is asked.
    private var onPage: [String: [Int: [(surah: Int, ayah: Int)]]] = [:]

    public init(index: MushafIndex? = nil,
                pages: [String: MushafPageTable] = [:],
                lines: [String: MushafLineTable] = [:]) {
        self.index = index
        self.byRiwayah = Dictionary(uniqueKeysWithValues: (index?.riwayat ?? []).map { ($0.riwayah, $0) })
        self.pageTables = pages
        self.lineTables = lines
    }

    /// Every riwayah, in the classical order of the Ten Qiraat.
    public func riwayat() -> [RiwayahEntry] { index?.riwayat ?? [] }

    /// Only the riwayat whose text this engine publishes (the eight verified ones).
    public func riwayatWithText() -> [RiwayahEntry] { riwayat().filter(\.textIncluded) }

    public func riwayah(_ slug: String) -> RiwayahEntry? { byRiwayah[slug] }

    /// Every facsimile has this many pages.
    public func totalPages() -> Int { index?.totalPages ?? 604 }

    /// Path to a riwayah's facsimile, relative to `data/mushaf/`. The file is one solid xz stream
    /// over the PDF; on Apple platforms `COMPRESSION_LZMA` reads that container directly.
    public func pdfPath(_ slug: String) -> String? { byRiwayah[slug]?.pdf }

    /// The page an ayah is printed on in this riwayah's own mushaf.
    public func page(_ surahId: Int, _ ayahId: Int, riwayah: String = "hafs") -> Int? {
        pageTables[riwayah]?.pages["\(surahId)"]?["\(ayahId)"]
    }

    /// Every ayah printed on a page, in mushaf order.
    public func ayahsOnPage(_ page: Int, riwayah: String = "hafs") -> [(surah: Int, ayah: Int)] {
        pageIndex(riwayah)[page] ?? []
    }

    /// The first ayah of a page - what a "go to page 213" jump lands on.
    public func firstAyahOfPage(_ page: Int, riwayah: String = "hafs") -> (surah: Int, ayah: Int)? {
        ayahsOnPage(page, riwayah: riwayah).first
    }

    /// Character offsets into the ayah's own text at which this riwayah's print starts a new line.
    /// Nil when the riwayah's text - and so its line table - is not published.
    public func lineBreaks(_ surahId: Int, _ ayahId: Int, riwayah: String = "hafs") -> [Int]? {
        lineTables[riwayah]?.lineBreaks["\(surahId)"]?["\(ayahId)"]
    }

    public func hasTajweedPack(_ riwayah: String) -> Bool { byRiwayah[riwayah]?.tajweed != nil }

    private func pageIndex(_ riwayah: String) -> [Int: [(surah: Int, ayah: Int)]] {
        if let cached = onPage[riwayah] { return cached }
        var index: [Int: [(surah: Int, ayah: Int)]] = [:]
        let table = pageTables[riwayah]?.pages ?? [:]
        for surahKey in table.keys.compactMap(Int.init).sorted() {
            let ayahs = table["\(surahKey)"] ?? [:]
            for ayahKey in ayahs.keys.compactMap(Int.init).sorted() {
                guard let page = ayahs["\(ayahKey)"] else { continue }
                index[page, default: []].append((surah: surahKey, ayah: ayahKey))
            }
        }
        onPage[riwayah] = index
        return index
    }
}
