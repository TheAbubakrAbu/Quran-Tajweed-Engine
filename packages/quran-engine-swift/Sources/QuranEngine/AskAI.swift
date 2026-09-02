import Foundation

/// Ask AI: the retrieval and the prompt behind "ask a question, get an answer grounded in the text".
///
/// It is NOT a model. It is the two halves a model cannot do for you and that every app otherwise
/// rebuilds badly: turning a natural-language question into the handful of passages that bear on it
/// (each with the reference it must be cited by), and the instructions that keep a model from doing
/// the three things that make a Quran assistant harmful - inventing verse numbers, quoting scripture
/// it has half-remembered, and issuing rulings.
///
/// Four lanes, interleaved round-robin so each gets a voice inside the passage budget rather than
/// the first one filling it:
///  * Lane 0, what the question NAMES - marked `isSubject`, because a model given eight
///    loosely-related verses will happily explain the wrong one;
///  * Lane 1, keywords weighted by inverse document frequency (plain counting ranks a question by
///    whichever verse says "the" most);
///  * Lane 2, the curated themes, which reach ayahs sharing no wording with the question;
///  * Lane 3, meaning - only when a `Semantic` index is supplied, so the feature works everywhere.
///
/// See docs/14-ask-ai.md.
public struct AskAIPassage: Sendable, Equatable {
    public enum Kind: String, Sendable { case ayah, surah, topic }

    public let kind: Kind
    /// Cite it exactly like this: "2:255", "Surah Al-Kahf".
    public let reference: String
    public let text: String
    /// How much of `text` to show the model.
    public let maxCharacters: Int
    /// The verse or surah the question itself named.
    public let isSubject: Bool
    public let surah: Int?
    public let ayah: Int?
}

public final class AskAI {
    /// Words too common to name a topic on their own; the keyword lane never searches for them alone.
    public static let questionWords: Set<String> = [
        "what", "why", "how", "when", "where", "who", "whom", "which", "does", "do", "did", "is", "are",
        "was", "were", "can", "could", "should", "would", "will", "shall", "have", "has", "had", "there",
        "their", "these", "those", "this", "that", "with", "from", "about", "into", "tell", "explain",
        "please", "mean", "means", "meaning", "say", "says", "said", "some", "many", "much", "islam",
        "islamic", "muslim", "muslims", "quran", "hadith", "hadiths", "allah", "prophet", "verse", "verses",
        "surah", "ayah", "ayat",
    ]

    /// How many passages a turn carries, and how much of each. See `chatPrompt`.
    public static let passageLimit = 8
    public static let passageCharacterLimit = 500
    /// A subject passage gets more room: when the question names the verse, this text IS the answer.
    public static let subjectCharacterLimit = 1400

    private let quran: Quran
    private let search: Search
    private let themes: Themes?
    public var semantic: Semantic?

    private var documentFrequency: [String: Int]?
    private var documentCount = 0

    public init(quran: Quran, search: Search, themes: Themes? = nil, semantic: Semantic? = nil) {
        self.quran = quran
        self.search = search
        self.themes = themes
        self.semantic = semantic
    }

    /// Index the ayah translations with your own embedder, and use it as lane 3.
    @discardableResult
    public func buildSemanticIndex(embed: @escaping Semantic.Embedder) -> Semantic {
        let corpus = quran.all().flatMap { surah in
            surah.ayahs.map { (id: "\(surah.id):\($0.id)", text: $0.textEnglishSaheeh ?? "") }
        }
        let engine = Semantic(embed: embed)
        engine.index(corpus)
        semantic = engine
        return engine
    }

    /// The passages for a question, best first. `previousQuestion` and `carried` turn a bare
    /// follow-up ("why?") into a search over both questions, with the last answer's passages kept.
    public func retrieve(_ question: String, previousQuestion: String? = nil,
                         carried: [AskAIPassage] = [],
                         limit: Int = AskAI.passageLimit) -> [AskAIPassage] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        var seen = Set<String>()
        func claim(_ passages: [AskAIPassage]) -> [AskAIPassage] {
            passages.filter { seen.insert($0.reference).inserted }
        }

        var named = claim(referencePassages(in: trimmed))

        let bare = isBareFollowUp(trimmed)
        let previous = previousQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchText = bare && !previous.isEmpty ? previous + " " + trimmed : trimmed
        if bare { named += claim(Array(carried.prefix(3))) }

        let keyword = claim(keywordPassages(searchText))
        let thematic = claim(themePassages(searchText))
        let meaning = claim(semanticPassages(searchText))

        return Array((named + AskAI.interleave([keyword, meaning, thematic])).prefix(limit))
    }

    // MARK: Lane 0 - references

    /// The verses and surahs the question names, as subject passages.
    public func referencePassages(in question: String) -> [AskAIPassage] {
        let lowered = question.lowercased()
        var ayahs: [(surah: Int, ayah: Int)] = []
        var surahs: [Int] = []

        for match in AskAI.ayahReference.matches(in: question, range: NSRange(question.startIndex..., in: question)) {
            guard let surah = Int(AskAI.substring(question, match.range(at: 1))),
                  let ayah = Int(AskAI.substring(question, match.range(at: 2))),
                  quran.ayah(surah, ayah) != nil else { continue }
            ayahs.append((surah, ayah))
        }
        for named in AskAI.namedAyahs where named.names.contains(where: { lowered.contains($0) }) {
            ayahs.append((named.surah, named.ayah))
        }
        for match in AskAI.surahMention.matches(in: question, range: NSRange(question.startIndex..., in: question)) {
            let first = AskAI.substring(question, match.range(at: 1))
            let second = AskAI.substring(question, match.range(at: 2))
            // Two words then one: "surah al kahf" resolves on the pair, "surah yusuf" on the single.
            let candidates = [second.isEmpty ? "" : "\(first) \(second)", first].filter { !$0.isEmpty }
            for candidate in candidates {
                if let hit = resolveSurah(candidate) { surahs.append(hit); break }
            }
        }
        // "surah al-kahf verse 10" - a bare ayah number belongs to the surah just named.
        let loose = AskAI.ayahMention.matches(in: question, range: NSRange(question.startIndex..., in: question))
            .compactMap { Int(AskAI.substring(question, $0.range(at: 1))) }
        if !loose.isEmpty, let surah = surahs.first, ayahs.isEmpty {
            ayahs += loose.filter { quran.ayah(surah, $0) != nil }.map { (surah, $0) }
        }

        var out: [AskAIPassage] = []
        for (surah, ayah) in ayahs {
            if let passage = ayahPassage(surah, ayah, isSubject: true,
                                         maxCharacters: AskAI.subjectCharacterLimit) {
                out.append(passage)
            }
        }
        // A surah named on its own (with no verse) is answered by its background prose.
        if ayahs.isEmpty {
            for surah in surahs { if let passage = surahPassage(surah) { out.append(passage) } }
        }
        return out
    }

    /// `searchSurahs` is a substring match, so "al kahf" also reaches al-Fatihah; an exact name match
    /// wins when there is one, which is the difference between answering about the cave and
    /// answering about the opening.
    private func resolveSurah(_ candidate: String) -> Int? {
        let hits = search.searchSurahs(candidate)
        guard !hits.isEmpty else { return nil }
        func fold(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter && $0.isASCII }
        }
        let wanted = fold(candidate)
        if let exact = hits.first(where: { fold($0.nameTransliteration) == wanted || fold($0.nameEnglish) == wanted }) {
            return exact.id
        }
        if wanted.count >= 3,
           let suffix = hits.first(where: { fold($0.nameTransliteration).hasSuffix(wanted) }) {
            return suffix.id
        }
        return hits[0].id
    }

    // MARK: Lane 1 - keywords, IDF-weighted

    /// Ayahs whose translation carries the question's content words, ranked by how INFORMATIVE those
    /// words are rather than by how often they occur.
    public func keywordPassages(_ question: String, limit: Int = 4) -> [AskAIPassage] {
        let terms = contentWords(question)
        guard !terms.isEmpty else { return [] }
        let weights = termWeights(terms)

        var scores: [String: Double] = [:]
        for (term, weight) in zip(terms, weights) where weight > 0 {
            for hit in search.searchVerses(term, limit: 400) {
                scores[hit.id, default: 0] += weight
            }
        }
        let ranked = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }

        var out: [AskAIPassage] = []
        for (id, _) in ranked {
            let parts = id.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, let passage = ayahPassage(parts[0], parts[1]) else { continue }
            out.append(passage)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: Lane 2 - themes

    /// Ayahs from the curated topic the question matches - the lane that reaches verses sharing no
    /// wording with the question at all.
    public func themePassages(_ question: String, limit: Int = 2) -> [AskAIPassage] {
        guard let themes else { return [] }
        let words = contentWords(question)
        guard !words.isEmpty else { return [] }

        var best: Topic?
        var bestScore = 0
        for topic in themes.all() {
            let haystack = "\(topic.name) \(topic.description) \(topic.category)".lowercased()
            let score = words.reduce(0) { $0 + (haystack.contains($1.lowercased()) ? $1.count : 0) }
            if score > bestScore { bestScore = score; best = topic }
        }
        guard let topic = best else { return [] }

        var out: [AskAIPassage] = []
        for ref in topic.ayahs {
            let parts = ref.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, let passage = ayahPassage(parts[0], parts[1]) else { continue }
            out.append(passage)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: Lane 3 - meaning

    /// Ayahs closest in MEANING to the question. Empty unless a semantic index was supplied.
    public func semanticPassages(_ question: String, limit: Int = 3, minScore: Float = 0.42) -> [AskAIPassage] {
        guard let semantic else { return [] }
        // The score is a MEAN over query words, so "what does the Quran say about" dilutes the topic.
        let words = contentWords(question)
        let query = words.isEmpty ? question : words.joined(separator: " ")

        var out: [AskAIPassage] = []
        for hit in semantic.search(query, limit: limit * 2, minScore: minScore) {
            let parts = hit.id.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, let passage = ayahPassage(parts[0], parts[1]) else { continue }
            out.append(passage)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: Passage construction

    public func ayahPassage(_ surahId: Int, _ ayahId: Int, isSubject: Bool = false,
                            maxCharacters: Int = AskAI.passageCharacterLimit) -> AskAIPassage? {
        guard let ayah = quran.ayah(surahId, ayahId) else { return nil }
        let text = ayah.textEnglishSaheeh ?? ayah.textEnglishMustafa ?? ""
        guard !text.isEmpty else { return nil }
        return AskAIPassage(kind: .ayah, reference: "\(surahId):\(ayahId)", text: text,
                            maxCharacters: maxCharacters, isSubject: isSubject,
                            surah: surahId, ayah: ayahId)
    }

    /// A surah's background prose. The bundled notes open with the period of revelation, which
    /// answers "what is this surah about" with history - so the theme section, when a source has
    /// one, is what the question actually meant.
    public func surahPassage(_ surahId: Int) -> AskAIPassage? {
        guard let surah = quran.surah(surahId) else { return nil }
        let sources = quran.info(surahId)
        guard !sources.isEmpty else { return nil }

        var text = ""
        for source in sources {
            let range = NSRange(source.contents.startIndex..., in: source.contents)
            guard let match = AskAI.themeHeading.firstMatch(in: source.contents, range: range),
                  let start = Range(NSRange(location: match.range.location,
                                            length: (source.contents as NSString).length - match.range.location),
                                    in: source.contents) else { continue }
            let fromTheme = AskAI.plainProse(String(source.contents[start]))
            if fromTheme.count >= 200 { text = fromTheme; break }
        }
        if text.isEmpty { text = AskAI.plainProse(sources[0].contents) }
        guard !text.isEmpty else { return nil }

        return AskAIPassage(kind: .surah, reference: "Surah \(surah.nameTransliteration)", text: text,
                            maxCharacters: AskAI.subjectCharacterLimit, isSubject: true,
                            surah: surahId, ayah: nil)
    }

    // MARK: Question analysis

    /// The words in a question that actually name its topic.
    public func contentWords(_ question: String) -> [String] {
        question.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !AskAI.questionWords.contains($0.lowercased()) }
    }

    /// A question with fewer than two content words ("why?", "and zakat?") only makes sense with the
    /// previous question beside it.
    public func isBareFollowUp(_ question: String) -> Bool {
        question.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 && !AskAI.questionWords.contains($0.lowercased()) }
            .count < 2
    }

    /// Inverse document frequency per term: log(N / (1 + df)), floored at 0. A word in half the
    /// Quran weighs almost nothing; a word in ten ayahs weighs a lot. Built once, over the
    /// translations.
    public func termWeights(_ terms: [String]) -> [Double] {
        if documentFrequency == nil {
            var frequency: [String: Int] = [:]
            var documents = 0
            for surah in quran.all() {
                for ayah in surah.ayahs {
                    documents += 1
                    let text = (ayah.textEnglishSaheeh ?? "").lowercased()
                    let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        .map(String.init).filter { $0.count >= 3 })
                    for word in words { frequency[word, default: 0] += 1 }
                }
            }
            documentFrequency = frequency
            documentCount = documents
        }
        return terms.map { term in
            let df = documentFrequency?[term.lowercased()] ?? 0
            return max(0, log(Double(documentCount) / Double(1 + df)))
        }
    }

    // MARK: Internals

    private static let ayahReference = try! NSRegularExpression(pattern: #"(?<![\d:])(\d{1,3})\s*:\s*(\d{1,3})(?![\d:])"#)
    private static let surahMention = try! NSRegularExpression(
        pattern: #"(?i)\b(?:surah|surat|soorah|sura|chapter)\s+([\p{L}'’\-]+)(?:\s+([\p{L}'’\-]+))?"#)
    private static let ayahMention = try! NSRegularExpression(pattern: #"(?i)\b(?:ayah|ayat|aya|verse)\s+(\d{1,3})\b"#)
    private static let themeHeading = try! NSRegularExpression(
        pattern: #"(?im)^\s*#*\s*(?:theme|subject|subject matter|central theme|summary|contents|topics)\b[^\n]*$"#)

    /// Household names for specific verses that no pattern catches.
    private static let namedAyahs: [(names: [String], surah: Int, ayah: Int)] = [
        (["ayat al-kursi", "ayatul kursi", "ayat ul kursi", "ayat al kursi", "ayatul-kursi",
          "throne verse", "verse of the throne"], 2, 255),
    ]

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return "" }
        return String(text[swift])
    }

    /// Round-robin the lanes so each gets a voice inside the budget.
    private static func interleave(_ lanes: [[AskAIPassage]]) -> [AskAIPassage] {
        var out: [AskAIPassage] = []
        let depth = lanes.map(\.count).max() ?? 0
        for i in 0..<depth {
            for lane in lanes where i < lane.count { out.append(lane[i]) }
        }
        return out
    }

    /// Strip the light markdown the surah notes carry, so a passage reads as prose.
    static func plainProse(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"(?m)^\s*#+\s*"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\r", with: "")
        out = out.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - The prompt

public enum AskAIPrompt {
    /// The system instructions. Rules 2, 3 and 5 are the ones that matter: a model left to itself
    /// will cite verse numbers it half-remembers, "quote" scripture it has paraphrased, and answer
    /// "is X halal" with a verdict. Everything else is tone.
    public static let chatInstructions = """
    You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

    You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
    1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
    2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
    3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
    4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
    5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
    6. Keep the conversation's thread: a follow-up refers to what was discussed before.
    7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
    8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end.
    """

    public struct Turn: Sendable, Equatable {
        public let question: String
        public let answer: String
        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// The user-side prompt for one turn: the passages, the recent conversation, the question.
    ///
    /// Eight passages of 500 characters is roughly a thousand tokens - sized for a ~4k on-device
    /// window with room for the instructions, the conversation, and a full answer. Raise both for a
    /// larger model; the shape does not change.
    public static func chatPrompt(question: String, passages: [AskAIPassage],
                                  transcript: [Turn] = [],
                                  passageLimit: Int = AskAI.passageLimit)
        -> (instructions: String, prompt: String) {
        let rendered = passages.prefix(passageLimit).map { passage in
            "\(passage.isSubject ? "SUBJECT OF THE QUESTION " : "")[\(passage.reference)] \(String(passage.text.prefix(passage.maxCharacters)))"
        }.joined(separator: "\n")
        let recent = transcript.suffix(3).map { turn in
            "Earlier question: \(String(turn.question.prefix(300)))\nEarlier answer: \(String(turn.answer.prefix(500)))"
        }.joined(separator: "\n")

        var prompt = ""
        if !rendered.isEmpty {
            prompt += "PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n\(rendered)\n\n"
        }
        if !recent.isEmpty { prompt += "CONVERSATION SO FAR:\n\(recent)\n\n" }
        prompt += "QUESTION: \(question)"
        return (chatInstructions, prompt)
    }
}
