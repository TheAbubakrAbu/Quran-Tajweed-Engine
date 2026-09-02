import Foundation

/// Meaning-based ("AI") search: find the ayahs about a topic whether or not they use its words.
///
/// WHY WORD VECTORS AND MaxSim, NOT A SENTENCE EMBEDDING - measured, not assumed. Scoring an ayah
/// by the cosine between a SENTENCE embedding of the query and one of the ayah ranks this corpus
/// close to randomly: translated scripture is dense, and one vector for a whole verse washes out
/// the single idea the query is asking about. Scoring word by word fixes it - embed every word, and
/// score a text as the MEAN over the query's words of the BEST matching word in the text. On real
/// verses that separates related (0.42-0.70) from unrelated (0.27-0.41) cleanly, and it degrades
/// gracefully: a query word the model has never seen contributes nothing instead of poisoning the
/// vector.
///
/// THE EMBEDDER IS YOURS. This engine ships no model - word vectors are tens of megabytes and every
/// platform already has one worth using. On Apple platforms that is `NLEmbedding.wordEmbedding(for:)`:
///
/// ```swift
/// import NaturalLanguage
/// let embedding = NLEmbedding.wordEmbedding(for: .english)
/// let semantic = Semantic { word in embedding?.vector(for: word)?.map(Float.init) }
/// ```
///
/// Build the index once and keep it: over the 6,236 translations that is seconds and ~10-25 MB,
/// which is why any serious consumer persists it rather than rebuilding per launch.
///
/// See docs/14-ask-ai.md.
public struct SemanticHit: Sendable, Equatable {
    public let id: String
    /// Mean best-match cosine over the query's words, 0...1.
    public let score: Float
}

public final class Semantic {
    public typealias Embedder = (String) -> [Float]?

    private let embed: Embedder
    private let minWordLength: Int
    private var vectors: [String: [Float]?] = [:]
    private var documents: [(id: String, vectors: [[Float]])] = []

    public init(minWordLength: Int = 3, embed: @escaping Embedder) {
        self.embed = embed
        self.minWordLength = minWordLength
    }

    public var size: Int { documents.count }

    /// Build (or rebuild) the index. Call once per corpus.
    @discardableResult
    public func index(_ corpus: [(id: String, text: String)]) -> Semantic {
        documents = corpus.compactMap { document in
            let vectors = vectorize(document.text)
            return vectors.isEmpty ? nil : (id: document.id, vectors: vectors)
        }
        return self
    }

    /// The documents closest in meaning to `query`, best first. `minScore` is a floor on "actually
    /// related" - 0.42 is a sensible start on English translations, but calibrate it against YOUR
    /// embedder.
    public func search(_ query: String, limit: Int = 10, minScore: Float = 0) -> [SemanticHit] {
        let queryVectors = vectorize(query)
        guard !queryVectors.isEmpty else { return [] }
        var hits: [SemanticHit] = []
        for document in documents {
            var total: Float = 0
            for q in queryVectors {
                var best: Float = -1
                for w in document.vectors {
                    let score = Semantic.cosine(q, w)
                    if score > best { best = score }
                }
                total += best
            }
            let score = total / Float(queryVectors.count)
            if score >= minScore { hits.append(SemanticHit(id: document.id, score: score)) }
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
        return Array(hits.prefix(limit))
    }

    public func clear() {
        documents = []
        vectors = [:]
    }

    /// Cosine similarity of two ALREADY NORMALIZED vectors, i.e. their dot product.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) { sum += a[i] * b[i] }
        return sum
    }

    private func vectorize(_ text: String) -> [[Float]] {
        var out: [[Float]] = []
        var seen = Set<String>()
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(raw)
            guard word.count >= minWordLength, seen.insert(word).inserted else { continue }
            if let vector = vector(for: word) { out.append(vector) }
        }
        return out
    }

    private func vector(for word: String) -> [Float]? {
        if let cached = vectors[word] { return cached }
        let raw = embed(word)
        // Normalized once here, so scoring is a dot product rather than three passes per pair.
        let normalized = (raw?.isEmpty == false) ? Semantic.normalize(raw!) : nil
        vectors[word] = normalized
        return normalized
    }

    private static func normalize(_ raw: [Float]) -> [Float] {
        let magnitude = sqrt(raw.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return Array(repeating: 0, count: raw.count) }
        return raw.map { $0 / magnitude }
    }
}
