import Foundation

/// The corpora added upstream in Al-Islam 4.6.5: the 99 Names in depth, and the chains of
/// transmission of the Ten Readings.
///
/// See docs/23-names-depth.md and 24-isnad.md.

// MARK: - The Names in depth

/// One of the nine themes the Names are grouped under.
public struct NameTheme: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
}

/// One ayah a Name appears in.
public struct NameOccurrence: Decodable, Sendable, Equatable {
    public let surah: Int
    public let ayah: Int
    /// 0-based whitespace-token index into the ayah's raw text, or nil where the corpus could not
    /// place the Name in the ayah (ten occurrences across four Names). The ayah is still right:
    /// show the verse whole and highlight nothing.
    public let token: Int?
    /// How many tokens the Name spans (0 for an unplaced occurrence).
    public let tokens: Int
}

/// The layer under `names-of-allah.json`: what the Name is built on and what it asks of a reader.
///
/// The written material is Tilawa's (Jamil Hammoudeh), used with permission; the occurrences point
/// into this engine's own Ḥafṣ text.
public struct NameDepth: Decodable, Sendable, Identifiable, Equatable {
    /// 1...99, matching `NamesOfAllah.byNumber`.
    public let number: Int
    /// Printed SPACED, the way a grammar book sets a root ("ر ح م"). `rootKey(_:)` closes it up to
    /// the form `morphology.json` stores.
    public let root: String
    public let theme: String
    public let explanation: String
    public let living: String
    public let occurrences: [NameOccurrence]

    public var id: Int { number }
}

/// `data/names-depth.json`.
public struct NamesDepthFile: Decodable, Sendable {
    public let themes: [NameTheme]
    public let names: [NameDepth]
}

/// A Name and the occurrence that put it in an ayah.
public struct NameInAyah: Sendable, Equatable {
    public let name: NameDepth
    public let occurrence: NameOccurrence
}

/// A spaced root as morphology stores it: `"ر ح م"` -> `"رحم"`.
///
/// Every port strips whitespace explicitly rather than trimming, because a root is spaced in the
/// middle and not only at the ends.
public func rootKey(_ root: String) -> String {
    root.split(whereSeparator: { $0.isWhitespace }).joined()
}

public final class NamesDepth: Sendable {
    private let names: [NameDepth]
    private let themeList: [NameTheme]
    private let byNumberMap: [Int: NameDepth]

    public init(_ file: NamesDepthFile? = nil) {
        names = file?.names ?? []
        themeList = file?.themes ?? []
        byNumberMap = Dictionary(names.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var isLoaded: Bool { !names.isEmpty }

    /// All 99, ordered by number.
    public func all() -> [NameDepth] { names }

    public func byNumber(_ number: Int) -> NameDepth? { byNumberMap[number] }

    /// The nine themes, in the corpus's own order.
    public func themes() -> [NameTheme] { themeList }

    public func theme(_ id: String) -> NameTheme? { themeList.first { $0.id == id } }

    /// Every Name under one theme, by number.
    public func byTheme(_ id: String) -> [NameDepth] { names.filter { $0.theme == id } }

    /// Every Name built on one root. Accepts either spelling, spaced or closed up.
    public func byRoot(_ root: String) -> [NameDepth] {
        let key = rootKey(root)
        guard !key.isEmpty else { return [] }
        return names.filter { rootKey($0.root) == key }
    }

    /// Every Name appearing in an ayah, in token order. An unplaced occurrence (a nil token) sorts
    /// last, so a highlighted list stays in reading order.
    public func inAyah(surah surahID: Int, ayah ayahID: Int) -> [NameInAyah] {
        names
            .flatMap { name in
                name.occurrences
                    .filter { $0.surah == surahID && $0.ayah == ayahID }
                    .map { NameInAyah(name: name, occurrence: $0) }
            }
            .sorted { ($0.occurrence.token ?? Int.max) < ($1.occurrence.token ?? Int.max) }
    }

    /// Matches the root (spaces closed on both sides), the explanation and the living line.
    public func search(_ query: String, limit: Int = 25) -> [NameDepth] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        let key = rootKey(q)
        return Array(names.filter { name in
            (!key.isEmpty && rootKey(name.root).contains(key))
                || name.explanation.lowercased().contains(lower)
                || name.living.lowercased().contains(lower)
        }.prefix(limit))
    }

    /// How many Names carry depth, how many themes, and how many occurrences they cover.
    public func count() -> (names: Int, themes: Int, occurrences: Int) {
        (names.count, themeList.count, names.reduce(0) { $0 + $1.occurrences.count })
    }
}

// MARK: - The chains of transmission

/// One person in a chain.
public struct IsnadNode: Decodable, Sendable, Equatable {
    public let name: String
    public let arabic: String
    /// The death year, e.g. "d. 117 AH".
    public let detail: String
    public let role: String

    public init(name: String, arabic: String = "", detail: String = "", role: String = "") {
        self.name = name
        self.arabic = arabic
        self.detail = detail
        self.role = role
    }
}

/// One generation of a chain, as a consumer draws it: a row, connected downward.
public struct IsnadLayer: Sendable, Equatable {
    public let title: String
    public let nodes: [IsnadNode]
}

/// An imam's side: the Successors he read on, and the Companions they read on.
public struct ImamChain: Decodable, Sendable, Equatable {
    public let teachers: [IsnadNode]
    public let companions: [IsnadNode]
}

/// A narrator's side: the links between him and the imam (empty where he read on the imam
/// himself), and the students who carried his narration on.
public struct NarratorChain: Decodable, Sendable, Equatable {
    /// The imam this narration comes from.
    public let imam: String
    public let links: [IsnadNode]
    public let students: [IsnadNode]
}

/// `data/isnad.json`.
public struct IsnadFile: Decodable, Sendable {
    public let prophet: IsnadNode?
    public let companions: [IsnadNode]
    public let imams: [String: ImamChain]
    public let narrators: [String: NarratorChain]
}

public final class Isnad: Sendable {
    private let file: IsnadFile?

    public init(_ file: IsnadFile? = nil) {
        self.file = file
    }

    public var isLoaded: Bool { !(file?.imams.isEmpty ?? true) }

    /// The head of every chain.
    public func prophet() -> IsnadNode? { file?.prophet }

    /// The thirteen Companions the readings are transmitted from.
    public func companions() -> [IsnadNode] { file?.companions ?? [] }

    /// The ten imams' keys, sorted.
    public func imamKeys() -> [String] { (file?.imams.keys).map { $0.sorted() } ?? [] }

    /// The twenty riwayah tags, sorted.
    public func narratorKeys() -> [String] { (file?.narrators.keys).map { $0.sorted() } ?? [] }

    public func imam(_ imam: String) -> ImamChain? { file?.imams[imam] }

    public func narrator(_ riwayah: String) -> NarratorChain? { file?.narrators[riwayah] }

    /// Whether a narrator read on his imam himself, with nobody between them.
    public func readsDirectly(_ riwayah: String) -> Bool {
        guard let chain = file?.narrators[riwayah] else { return false }
        return chain.links.isEmpty
    }

    /// The imam a riwayah comes from.
    ///
    /// Read from the corpus, NOT parsed off the tag: four tags name the imam in the Arabic
    /// genitive ("ad-Duri an Abi Amr") while his key is the nominative ("Abu Amr"), so splitting
    /// on " an " would resolve those four to nothing.
    public func imamOf(_ riwayah: String) -> String? {
        guard let imam = file?.narrators[riwayah]?.imam, file?.imams[imam] != nil else { return nil }
        return imam
    }

    private func narratorName(_ riwayah: String) -> String {
        guard let range = riwayah.range(of: " an ") else { return riwayah }
        return String(riwayah[..<range.lowerBound])
    }

    /// The layers above any imam: the Prophet ﷺ, the Companions his teachers read on, and those
    /// teachers. Shared by both chain forms, since every chain runs through them.
    public func topLayers(imam: String) -> [IsnadLayer] {
        guard let chain = file?.imams[imam] else { return [] }
        var layers: [IsnadLayer] = []
        if let prophet = file?.prophet {
            layers.append(IsnadLayer(title: "THE PROPHET", nodes: [prophet]))
        }
        if !chain.companions.isEmpty {
            layers.append(IsnadLayer(title: "THE COMPANIONS", nodes: chain.companions))
        }
        if !chain.teachers.isEmpty {
            layers.append(IsnadLayer(title: chain.teachers.count == 1 ? "HIS TEACHER" : "HIS TEACHERS",
                                     nodes: chain.teachers))
        }
        return layers
    }

    /// A whole chain as layers: a riwayah tag for one narration's chain, or an imam key for the
    /// reading's, which ends at his two narrators.
    public func chain(_ key: String) -> [IsnadLayer] {
        let k = key.trimmingCharacters(in: .whitespaces)
        if file?.imams[k] != nil {
            var layers = topLayers(imam: k)
            guard !layers.isEmpty else { return layers }
            layers.append(IsnadLayer(title: "THE IMAM", nodes: [IsnadNode(name: k, role: "imam")]))
            let nodes = narratorKeys()
                .filter { imamOf($0) == k }
                .map { IsnadNode(name: narratorName($0), role: "narrator") }
            if !nodes.isEmpty {
                layers.append(IsnadLayer(title: "HIS TWO NARRATORS", nodes: nodes))
            }
            return layers
        }

        guard let narrator = file?.narrators[k], let imam = imamOf(k) else { return [] }
        var layers = topLayers(imam: imam)
        guard !layers.isEmpty else { return layers }
        layers.append(IsnadLayer(title: "THE IMAM", nodes: [IsnadNode(name: imam, role: "imam")]))
        if !narrator.links.isEmpty {
            layers.append(IsnadLayer(title: narrator.links.count == 1 ? "THE LINK BETWEEN" : "THE LINKS BETWEEN",
                                     nodes: narrator.links))
        }
        layers.append(IsnadLayer(title: "THE NARRATOR",
                                 nodes: [IsnadNode(name: narratorName(k), role: "narrator")]))
        if !narrator.students.isEmpty {
            layers.append(IsnadLayer(title: "HIS STUDENTS", nodes: narrator.students))
        }
        return layers
    }

    /// One sentence on how a narrator reaches his imam: directly, or through the links between.
    public func sentence(_ riwayah: String) -> String {
        guard let chain = file?.narrators[riwayah], let imam = imamOf(riwayah) else { return "" }
        let narrator = narratorName(riwayah)
        if chain.links.isEmpty {
            return "\(narrator) read on \(imam) himself, and \(imam)'s chain runs through his teachers to the Companions and to the Prophet \u{FDFA}."
        }
        let names = chain.links.map(\.name)
        let path = names.count == 1
            ? names[0]
            : names.dropLast().joined(separator: ", ") + " and then " + names[names.count - 1]
        return "\(narrator) did not meet \(imam): the reading reached him through \(path), and from \(imam) it runs through his teachers to the Companions and to the Prophet \u{FDFA}."
    }

    /// How many imams, narrators and Companions the chains cover.
    public func count() -> (imams: Int, narrators: Int, companions: Int) {
        (file?.imams.count ?? 0, file?.narrators.count ?? 0, file?.companions.count ?? 0)
    }
}
