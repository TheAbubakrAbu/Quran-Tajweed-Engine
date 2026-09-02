import Foundation

/// Browse the Quran by theme: curated topics, each grouped under a category and a domain, each
/// listing the ayahs that speak to it.
///
/// The ayah lists are curated, not derived, so a topic is a real reading path rather than a keyword
/// hit list. `topicsFor` inverts them. See docs/13-similar-and-themes.md.
public struct Topic: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let category: String
    public let domain: String
    /// "2:255" references, in mushaf order.
    public let ayahs: [String]
}

public struct ThemesFile: Decodable, Sendable {
    public let topics: [Topic]
}

public final class Themes {
    private let topics: [Topic]
    private let byId: [String: Topic]
    private var byAyah: [String: [Topic]]?

    public init(_ file: ThemesFile? = nil) {
        self.topics = file?.topics ?? []
        self.byId = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every topic, in the order the corpus lists them.
    public func all() -> [Topic] { topics }

    public func topic(_ id: String) -> Topic? { byId[id] }

    /// The distinct domains, in first-seen order.
    public func domains() -> [String] { orderedUnique(topics.map(\.domain)) }

    public func categories(domain: String? = nil) -> [String] {
        let scope = domain.map { d in topics.filter { $0.domain == d } } ?? topics
        return orderedUnique(scope.map(\.category))
    }

    public func inDomain(_ domain: String) -> [Topic] { topics.filter { $0.domain == domain } }

    public func inCategory(_ category: String) -> [Topic] { topics.filter { $0.category == category } }

    /// The topics an ayah appears under.
    public func topicsFor(_ surahId: Int, _ ayahId: Int) -> [Topic] {
        if byAyah == nil {
            var index: [String: [Topic]] = [:]
            for topic in topics {
                for ref in topic.ayahs { index[ref, default: []].append(topic) }
            }
            byAyah = index
        }
        return byAyah?["\(surahId):\(ayahId)"] ?? []
    }

    /// Topics whose name, description, category or domain carries `query`.
    public func search(_ query: String) -> [Topic] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return topics.filter { topic in
            [topic.name, topic.description, topic.category, topic.domain]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
