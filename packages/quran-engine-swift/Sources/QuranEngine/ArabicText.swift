import Foundation

/// Arabic text utilities shared across the engine. Faithful port of `text.js`.
/// Everything operates on Unicode scalar values, so behaviour is font-independent.
public enum ArabicText {

    // Tashkeel (diacritic) ranges used by the search normalizer.
    private static let tashkeelRanges: [ClosedRange<UInt32>] = [
        0x0610...0x061a, 0x064b...0x065f, 0x0670...0x0670, 0x06d6...0x06ed,
    ]

    private static func inTashkeel(_ cp: UInt32) -> Bool {
        tashkeelRanges.contains { $0.contains(cp) }
    }

    /// Canonical Arabic fold map applied before stripping marks during search normalization.
    /// Mirrors `CANONICAL_ARABIC_MAP`.
    private static let canonicalArabicMap: [Character: String] = [
        "\u{0670}": "ا", // dagger alif
        "\u{0671}": "ا", // alif wasla (ٱ)
        "أ": "ا", "إ": "ا", "آ": "ا", "\u{0672}": "ا", "\u{0673}": "ا", "\u{0675}": "ا",
        "ؤ": "و", "ئ": "ي", "ء": "", "\u{0674}": "", "\u{0676}": "و", "\u{0677}": "و", "\u{0678}": "ي",
        "\u{06e5}": "و", // small waw
        "\u{06e6}": "ي", // small yeh
        "ى": "ا", // alif maqsura -> alif
        "ة": "ه", // teh marbuta -> heh
    ]

    /// Boolean-search operators that must survive the unwanted-character strip.
    private static let keptOperators: Set<Character> = ["&", "|", "!", "#"]

    /// Remove Quranic recitation marks / diacritics (the "clean Arabic" for display + search).
    /// Mirrors `removingArabicDiacriticsAndSigns`.
    public static func removingArabicDiacriticsAndSigns(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let cp = scalar.value
            if cp == 0x0671 { out += "ا"; continue } // hamzat wasl -> alif
            if (0x064b...0x065f).contains(cp) ||
                (0x06d6...0x06ed).contains(cp) ||
                cp == 0x0670 || cp == 0x0657 || cp == 0x0674 || cp == 0x0656 {
                continue
            }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// Remove the marks the surah-name search treats as noise. Mirrors `removingArabicMarks`.
    public static func removingArabicMarks(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let cp = scalar.value
            if cp == 0x0640 ||
                (0x0610...0x061a).contains(cp) ||
                (0x064b...0x065f).contains(cp) ||
                (0x06d6...0x06ed).contains(cp) {
                continue
            }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// Convert Arabic-Indic and Eastern-Arabic digits to Western. Mirrors `arabicDigitsToWestern`.
    public static func arabicDigitsToWestern(_ text: String) -> String {
        let map: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
        ]
        return String(text.map { map[$0] ?? $0 })
    }

    /// Collapse runs of whitespace into single spaces.
    public static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The core search normalizer. Mirrors `cleanSearch`:
    /// fold Arabic carriers -> strip punctuation/symbols/combining-marks (except `& | ! #`)
    /// -> lowercase -> collapse whitespace.
    public static func cleanSearch(_ text: String, whitespace: Bool = false) -> String {
        // 1. canonical Arabic fold
        var folded = ""
        for ch in text {
            if let replacement = canonicalArabicMap[ch] { folded += replacement }
            else { folded.append(ch) }
        }
        // 2. strip punctuation, symbols, and all combining marks, keeping the four operators.
        var cleaned = ""
        for scalar in folded.unicodeScalars {
            let ch = Character(scalar)
            if keptOperators.contains(ch) { cleaned.unicodeScalars.append(scalar); continue }
            if isPunctuationOrSymbolOrMark(scalar) { continue }
            cleaned.unicodeScalars.append(scalar)
        }
        var result = collapsingWhitespace(cleaned.lowercased())
        if whitespace { result = result.trimmingCharacters(in: .whitespaces) }
        return result
    }

    /// Matches JS `\p{P}|\p{S}|\p{M}` (Unicode punctuation, symbol, or mark).
    private static func isPunctuationOrSymbolOrMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
             .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    /// Keep ONLY tashkeel scalars (inverse of cleanSearch). Mirrors `arabicTashkeelBlob`.
    public static func arabicTashkeelBlob(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars where inTashkeel(scalar.value) {
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// Lowercase + whitespace-collapse without stripping marks. Mirrors `exactPhraseBlob`.
    public static func exactPhraseBlob(_ text: String) -> String {
        collapsingWhitespace(text.lowercased())
    }

    /// Tokenize a cleaned blob on spaces. Mirrors `searchTokens`.
    public static func searchTokens(_ cleanedText: String) -> [String] {
        cleanedText.split(separator: " ").map(String.init)
    }

    private static let arabicLetterRanges: [ClosedRange<UInt32>] = [
        0x0600...0x06ff, 0x0750...0x077f, 0x08a0...0x08ff,
        0xfb50...0xfdff, 0xfe70...0xfeff, 0x1ee00...0x1eeff,
    ]

    /// True if the string contains any Arabic-script letter. Mirrors `containsArabicLetters`.
    public static func containsArabicLetters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where arabicLetterRanges.contains(where: { $0.contains(scalar.value) }) {
            return true
        }
        return false
    }

    /// Drop "silent" Arabic letters for the lenient Arabic search variant.
    /// Mirrors `removingSilentArabicLettersForSearch` (grapheme-cluster walk).
    public static func removingSilentArabicLettersForSearch(_ text: String) -> String {
        let vowels: Set<UInt32> = [0x064e, 0x064f, 0x0650, 0x064b, 0x064c, 0x064d, 0x0656, 0x0657, 0x065a]
        var out = ""
        // Swift's `Character` iteration matches extended grapheme clusters.
        for cluster in text {
            let scalars = cluster.unicodeScalars.map { $0.value }
            guard let base = scalars.first else { continue }
            func has(_ cp: UInt32) -> Bool { scalars.contains(cp) }
            let hasStdSukoon = has(0x0652) && !has(0x06e1)
            // hamzatul wasl is always silent
            if base == 0x0671 { continue }
            // alif/waw/ya/alif-maqsura with a plain sukoon
            if [0x0627, 0x0648, 0x064a, 0x0649].contains(base) && hasStdSukoon { continue }
            // lam with a plain sukoon
            if base == 0x0644 && hasStdSukoon { continue }
            // waw carrying a dagger alif with no vowel/shadda/sukoon
            if base == 0x0648 && has(0x0670) &&
                !scalars.contains(where: { vowels.contains($0) || $0 == 0x0651 || $0 == 0x0652 }) { continue }
            out.append(cluster)
        }
        return out
    }
}
