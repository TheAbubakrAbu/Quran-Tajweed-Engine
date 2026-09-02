import Foundation

/// The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name and
/// transliteration, and - the part that matters for tajweed - its WEIGHT.
///
/// Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
/// pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the
/// divine name), and alif has no weight of its own at all: it inherits the letter before it. That
/// single fact is behind a large share of beginner mistakes, and it is a property of the letter, not
/// of any particular verse, so it lives here beside the letter and not in the annotation corpus.
///
/// Also carried: the letters outside the 28, the six Persian/Urdu letters some printed mushafs use,
/// the Eastern-Arabic numerals, the tashkeel marks, and the waqf (stopping) signs.
///
/// See `../../docs/16-arabic-alphabet.md`.
public struct ArabicLetter: Decodable, Equatable, Sendable {
    public let id: Int
    /// The isolated form.
    public let letter: String
    /// Final, medial and initial, as the source records them.
    public let forms: [String]
    public let name: String
    public let transliteration: String
    public let showTashkeel: Bool
    public let sound: String
    /// "light", "heavy", "conditional", "followsPrevious" - or nil where none is recorded.
    public let weight: String?
    /// Why, in one sentence.
    public let weightRule: String?

    private enum CodingKeys: String, CodingKey {
        case id, letter, forms, name, transliteration, showTashkeel, sound, weight, weightRule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        letter = (try? c.decode(String.self, forKey: .letter)) ?? ""
        forms = (try? c.decode([String].self, forKey: .forms)) ?? []
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        transliteration = (try? c.decode(String.self, forKey: .transliteration)) ?? ""
        showTashkeel = (try? c.decode(Bool.self, forKey: .showTashkeel)) ?? false
        sound = (try? c.decode(String.self, forKey: .sound)) ?? ""
        weight = try? c.decode(String.self, forKey: .weight)
        weightRule = try? c.decode(String.self, forKey: .weightRule)
    }
}

public struct Tashkeel: Decodable, Equatable, Sendable {
    public let english: String
    public let arabic: String
    public let mark: String
    public let transliteration: String
}

public struct StoppingSign: Decodable, Equatable, Sendable {
    public let symbol: String
    public let title: String
}

public struct ArabicNumeral: Decodable, Equatable, Sendable {
    public let number: String
    public let name: String
    public let transliteration: String
    public let englishNumber: String
}

/// `data/arabic-alphabet.json`.
public struct ArabicAlphabetFile: Decodable, Sendable {
    public let description: String
    public let weights: [String: String]
    public let standardLetters: [ArabicLetter]
    public let otherLetters: [ArabicLetter]
    public let nonArabicScriptLetters: [ArabicLetter]
    public let numbers: [ArabicNumeral]
    public let tashkeel: [Tashkeel]
    public let stoppingSigns: [StoppingSign]
    public let stoppingSignsSource: String

    private enum CodingKeys: String, CodingKey {
        case description, weights, standardLetters, otherLetters, nonArabicScriptLetters
        case numbers, tashkeel, stoppingSigns, stoppingSignsSource
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        weights = (try? c.decode([String: String].self, forKey: .weights)) ?? [:]
        standardLetters = (try? c.decode([ArabicLetter].self, forKey: .standardLetters)) ?? []
        otherLetters = (try? c.decode([ArabicLetter].self, forKey: .otherLetters)) ?? []
        nonArabicScriptLetters = (try? c.decode([ArabicLetter].self, forKey: .nonArabicScriptLetters)) ?? []
        numbers = (try? c.decode([ArabicNumeral].self, forKey: .numbers)) ?? []
        tashkeel = (try? c.decode([Tashkeel].self, forKey: .tashkeel)) ?? []
        stoppingSigns = (try? c.decode([StoppingSign].self, forKey: .stoppingSigns)) ?? []
        stoppingSignsSource = (try? c.decode(String.self, forKey: .stoppingSignsSource)) ?? ""
    }
}

public struct ArabicAlphabet: Sendable {
    private let file: ArabicAlphabetFile?

    public init(_ file: ArabicAlphabetFile? = nil) {
        self.file = file
    }

    /// The 28 letters of the alphabet, in order.
    public var letters: [ArabicLetter] { file?.standardLetters ?? [] }

    /// Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28.
    public var otherLetters: [ArabicLetter] { file?.otherLetters ?? [] }

    /// The Persian/Urdu letters some printed mushafs use for non-Arabic sounds.
    public var nonArabicScriptLetters: [ArabicLetter] { file?.nonArabicScriptLetters ?? [] }

    /// Every letter this reference knows, the 28 first.
    public var allLetters: [ArabicLetter] { letters + otherLetters + nonArabicScriptLetters }

    /// One letter by its isolated form. Accepts any of its joining forms too, so a letter lifted out
    /// of a word still resolves.
    public func letter(_ letter: String) -> ArabicLetter? {
        let wanted = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        return allLetters.first { $0.letter == wanted || $0.forms.contains(wanted) }
    }

    public func letter(id: Int) -> ArabicLetter? {
        allLetters.first { $0.id == id }
    }

    /// The tajweed weight of a letter, or nil when the reference records none.
    public func weight(_ letter: String) -> String? {
        self.letter(letter)?.weight
    }

    /// What a weight name means, in one line.
    public var weightDescriptions: [String: String] { file?.weights ?? [:] }

    /// The letters pronounced full - the isti'la letters.
    public var heavyLetters: [ArabicLetter] { letters.filter { $0.weight == "heavy" } }

    public var tashkeel: [Tashkeel] { file?.tashkeel ?? [] }

    /// The waqf signs, with what each one tells the reciter to do.
    public var stoppingSigns: [StoppingSign] { file?.stoppingSigns ?? [] }

    public func stoppingSign(_ symbol: String) -> StoppingSign? {
        stoppingSigns.first { $0.symbol == symbol }
    }

    /// The Eastern-Arabic numerals, 0 through 10.
    public var numbers: [ArabicNumeral] { file?.numbers ?? [] }

    public var stoppingSignsSource: String { file?.stoppingSignsSource ?? "" }
}
