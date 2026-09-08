import Foundation

/// Root and lemma of every word of the Quran: the Quranic Arabic Corpus morphology (Kais Dukes),
/// as redistributed by the Quranic Universal Library.
///
/// The invariant, the same one `word-by-word.json` keeps: one id per whitespace token of the
/// ayah's raw Hafs text, in the text's own token order, so nothing here matches or normalizes
/// text. Id `0` means the token has neither a root nor a lemma, which is the honest answer for
/// particles and the sajdah mark. Ids are 1-based into the root and lemma tables.
///
/// The reverse indexes are built on first use and kept: walking 77,629 tokens is quick, but a
/// caller asking about ten roots should not pay for it ten times.
///
/// See docs/18-morphology.md.

/// A triliteral (or quadriliteral) root, in both spellings a reader might use.
public struct MorphologyRoot: Sendable, Equatable {
    /// Spaced the way a lexicon prints it: "ر ب ب".
    public let letters: String
    /// The same letters transliterated: "rbb".
    public let buckwalter: String
    /// `letters` with the spaces closed up: "ربب".
    public var joined: String { letters.replacingOccurrences(of: " ", with: "") }
}

/// A dictionary form, marked and unmarked.
public struct MorphologyLemma: Sendable, Equatable {
    public let text: String
    public let clean: String
}

/// One word of the Quran: the ayah, and the 0-based index of the token inside it.
public struct WordLocation: Sendable, Equatable, Hashable {
    public let surah: Int
    public let ayah: Int
    public let token: Int

    public init(surah: Int, ayah: Int, token: Int) {
        self.surah = surah
        self.ayah = ayah
        self.token = token
    }
}

/// `data/morphology.json`.
public struct MorphologyFile: Decodable, Sendable {
    public let roots: [[String]]
    public let lemmas: [[String]]
    public let rootIds: [String: [[Int]]]
    public let lemmaIds: [String: [[Int]]]
}

public final class Morphology: @unchecked Sendable {
    private let file: MorphologyFile?
    private let lock = NSLock()
    private var byRoot: [Int: [WordLocation]]?
    private var byLemma: [Int: [WordLocation]]?

    public init(_ file: MorphologyFile? = nil) {
        self.file = file
    }

    /// Whether a corpus was supplied at all.
    public var isLoaded: Bool { !(file?.roots.isEmpty ?? true) }

    /// The fold a typed query and the tables are both compared under.
    ///
    /// Every space is removed, not merely trimmed: a root is printed spaced ("ر ب ب") and typed
    /// closed up ("ربب"), and the two have to meet.
    public static func fold(_ text: String) -> String {
        ArabicText.cleanSearch(ArabicText.removingArabicDiacriticsAndSigns(text))
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// The root with this 1-based id.
    public func root(id: Int) -> MorphologyRoot? {
        guard let file, id >= 1, id <= file.roots.count else { return nil }
        let row = file.roots[id - 1]
        guard row.count >= 2 else { return nil }
        return MorphologyRoot(letters: row[0], buckwalter: row[1])
    }

    /// The dictionary form with this 1-based id.
    public func lemma(id: Int) -> MorphologyLemma? {
        guard let file, id >= 1, id <= file.lemmas.count else { return nil }
        let row = file.lemmas[id - 1]
        guard row.count >= 2 else { return nil }
        return MorphologyLemma(text: row[0], clean: row[1])
    }

    /// The root and lemma id of every token of the ayah, or nil when it is not covered.
    public func ids(surah: Int, ayah: Int) -> (roots: [Int], lemmas: [Int])? {
        guard let file,
              let roots = file.rootIds["\(surah)"], let lemmas = file.lemmaIds["\(surah)"],
              ayah >= 1, ayah <= roots.count, ayah <= lemmas.count else { return nil }
        return (roots[ayah - 1], lemmas[ayah - 1])
    }

    /// The root of one token; nil when it has none (a particle) or the index is out of range.
    public func root(surah: Int, ayah: Int, token: Int) -> (id: Int, root: MorphologyRoot)? {
        guard let ids = ids(surah: surah, ayah: ayah), ids.roots.indices.contains(token),
              let found = root(id: ids.roots[token]) else { return nil }
        return (ids.roots[token], found)
    }

    /// The dictionary form of one token.
    public func lemma(surah: Int, ayah: Int, token: Int) -> (id: Int, lemma: MorphologyLemma)? {
        guard let ids = ids(surah: surah, ayah: ayah), ids.lemmas.indices.contains(token),
              let found = lemma(id: ids.lemmas[token]) else { return nil }
        return (ids.lemmas[token], found)
    }

    /// Every word carrying this root, in mushaf order.
    public func occurrences(ofRoot id: Int) -> [WordLocation] {
        buildIndex()
        lock.lock(); defer { lock.unlock() }
        return byRoot?[id] ?? []
    }

    /// Every word carrying this lemma, in mushaf order.
    public func occurrences(ofLemma id: Int) -> [WordLocation] {
        buildIndex()
        lock.lock(); defer { lock.unlock() }
        return byLemma?[id] ?? []
    }

    /// Roots whose Arabic or Buckwalter spelling starts with the query.
    public func findRoots(_ query: String, limit: Int = 50) -> [(id: Int, root: MorphologyRoot)] {
        prefixHits(file?.roots ?? [], query, limit).compactMap { id in
            root(id: id).map { (id, $0) }
        }
    }

    /// Dictionary forms whose marked or unmarked spelling starts with the query.
    public func findLemmas(_ query: String, limit: Int = 50) -> [(id: Int, lemma: MorphologyLemma)] {
        prefixHits(file?.lemmas ?? [], query, limit).compactMap { id in
            lemma(id: id).map { (id, $0) }
        }
    }

    /// Corpus size: roots, lemmas, and the tokens they cover.
    public func count() -> (roots: Int, lemmas: Int, tokens: Int) {
        guard let file else { return (0, 0, 0) }
        let tokens = file.rootIds.values.reduce(0) { total, ayahs in
            total + ayahs.reduce(0) { $0 + $1.count }
        }
        return (file.roots.count, file.lemmas.count, tokens)
    }

    // MARK: - Internals

    private func prefixHits(_ table: [[String]], _ query: String, _ limit: Int) -> [Int] {
        let folded = Self.fold(query)
        let latin = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !folded.isEmpty || !latin.isEmpty else { return [] }
        var out: [Int] = []
        for (index, row) in table.enumerated() {
            if limit > 0 && out.count >= limit { break }
            guard let first = row.first else { continue }
            let arabic = Self.fold(first)
            let roman = (row.count > 1 ? row[1] : "").lowercased()
            if (!folded.isEmpty && arabic.hasPrefix(folded))
                || (!latin.isEmpty && roman.hasPrefix(latin)) {
                out.append(index + 1)
            }
        }
        return out
    }

    /// Walk the corpus once, in mushaf order, so the lists come out ordered for free.
    private func buildIndex() {
        lock.lock(); defer { lock.unlock() }
        guard byRoot == nil, let file else { return }
        var roots: [Int: [WordLocation]] = [:]
        var lemmas: [Int: [WordLocation]] = [:]
        for surah in file.rootIds.keys.compactMap(Int.init).sorted() {
            let rootRows = file.rootIds["\(surah)"] ?? []
            let lemmaRows = file.lemmaIds["\(surah)"] ?? []
            for (index, rootRow) in rootRows.enumerated() {
                let lemmaRow = index < lemmaRows.count ? lemmaRows[index] : []
                for (token, rootID) in rootRow.enumerated() {
                    let location = WordLocation(surah: surah, ayah: index + 1, token: token)
                    if rootID != 0 { roots[rootID, default: []].append(location) }
                    if token < lemmaRow.count, lemmaRow[token] != 0 {
                        lemmas[lemmaRow[token], default: []].append(location)
                    }
                }
            }
        }
        byRoot = roots
        byLemma = lemmas
    }
}
