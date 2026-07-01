import Foundation

/// One of the 99 Names of Allah (Asmā’ ul-Ḥusnā). Mirrors a `names-of-allah.json` entry.
public struct NameOfAllah: Decodable, Equatable, Sendable {
    /// Arabic.
    public let name: String
    public let transliteration: String
    /// 1..99.
    public let number: Int
    /// Ayah references where it appears (e.g. `"(1:3) (17:110)"`).
    public let found: String
    public let meaning: String
    public let desc: String
    public let otherNames: [String]
}

/// The 99 Names of Allah (Asmā’ ul-Ḥusnā). Thin accessor over `names-of-allah.json`.
/// Mirrors `names.js`.
public final class NamesOfAllah {
    /// All names, ordered by number.
    public let list: [NameOfAllah]
    private let byNumberMap: [Int: NameOfAllah]

    /// - Parameter list: parsed `names-of-allah.json`.
    public init(_ list: [NameOfAllah] = []) {
        let sorted = list.sorted { $0.number < $1.number }
        self.list = sorted
        var map = [Int: NameOfAllah]()
        for n in sorted { map[n.number] = n }
        self.byNumberMap = map
    }

    /// All 99 names, ordered by number.
    public func all() -> [NameOfAllah] { list }

    /// - Parameter number: 1..99.
    public func byNumber(_ number: Int) -> NameOfAllah? { byNumberMap[number] }
}
