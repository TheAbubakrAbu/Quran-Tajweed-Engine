import Foundation

/// Riwayah tajweed: where a reading differs from Hafs, and why.
///
/// A different layer from `Tajweed`, which detects the universal recitation rules from the text.
/// This carries what is SPECIFIC to a transmission and cannot be detected, because it IS the text's
/// difference: Warsh's taqlil, al-Bazzi's doubled ta, the places two readings part.
///
/// Two things to get right:
///  * **The meaning of a colour is per edition.** Each mushaf prints its own legend, so the same
///    code is a different rule in a different riwayah. Always read `legend(_:)`. The `rule` KEY is
///    stable across riwayat, which is why `describe(_:)` can explain it once for all of them.
///  * **Extents are base-letter indices, not character offsets** - `firstLetter`...`lastLetter`
///    inclusive in reading order, diacritics not counted, or the whole word when `wholeWord`.
///
/// Only the seven verified non-Hafs riwayat carry a pack; the twelve whose text is not published
/// have none, because their rules index into that text. See docs/11-qiraat-tajweed.md.
public struct QiraatLegendEntry: Sendable, Equatable {
    /// The single letter this riwayah's data uses for the rule.
    public let code: String
    /// Stable rule key, e.g. "idgham" - the same across riwayat.
    public let rule: String
    /// The rule's name as this mushaf prints it.
    public let arabic: String
    public let english: String
    /// One-line explanation, from the shared catalogue.
    public let short: String
    public let long: String
}

public struct QiraatWordRule: Sendable, Equatable {
    /// 1-based word index within the ayah.
    public let word: Int
    public let rule: String
    public let code: String
    public let arabic: String
    public let english: String
    /// Inclusive base-letter index the rule colours, or -1 for the whole word.
    public let firstLetter: Int
    public let lastLetter: Int
    public let wholeWord: Bool
}

public struct QiraatRuleDescription: Decodable, Sendable, Equatable {
    public let short: String
    public let long: String
}

public struct QiraatTajweedPack: Decodable, Sendable {
    public struct Legend: Decodable, Sendable {
        public let code: String
        public let rule: String
        public let arabic: String
        public let english: String
    }
    public let riwayah: String
    public let version: Int
    public let legend: [Legend]
    /// Surah -> ayah -> word -> [code, firstLetter, lastLetter].
    public let rules: [String: [String: [String: [[TajweedRuleExtent]]]]]
    public let khilafMarkers: [String: [Int]]
}

/// One field of a word-rule triple: the code is a string, the two extents are ints.
public enum TajweedRuleExtent: Decodable, Sendable, Equatable {
    case code(String)
    case index(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) { self = .index(value) }
        else { self = .code(try container.decode(String.self)) }
    }

    var stringValue: String? { if case .code(let value) = self { return value } else { return nil } }
    var intValue: Int? { if case .index(let value) = self { return value } else { return nil } }
}

public final class QiraatTajweed {
    private let descriptions: [String: QiraatRuleDescription]
    private let packs: [String: QiraatTajweedPack]
    private var legendByCode: [String: [String: QiraatLegendEntry]] = [:]

    public init(rules: [String: QiraatRuleDescription] = [:], riwayat: [String: QiraatTajweedPack] = [:]) {
        self.descriptions = rules
        self.packs = riwayat
    }

    /// The riwayat that have a pack loaded, in slug order.
    public func available() -> [String] { packs.keys.sorted() }

    /// This riwayah's printed legend, each entry carrying the shared explanation of its rule.
    public func legend(_ riwayah: String) -> [QiraatLegendEntry] {
        guard let pack = packs[riwayah] else { return [] }
        return pack.legend.map { entry in
            let description = descriptions[entry.rule]
            return QiraatLegendEntry(code: entry.code, rule: entry.rule, arabic: entry.arabic,
                                     english: entry.english,
                                     short: description?.short ?? "", long: description?.long ?? "")
        }
    }

    /// What this riwayah colours in one ayah, word by word.
    public func wordRules(_ surahId: Int, _ ayahId: Int, riwayah: String) -> [QiraatWordRule] {
        guard let words = packs[riwayah]?.rules["\(surahId)"]?["\(ayahId)"] else { return [] }
        let byCode = codes(riwayah)
        var out: [QiraatWordRule] = []
        for key in words.keys.compactMap(Int.init).sorted() {
            for triple in words["\(key)"] ?? [] {
                guard triple.count == 3,
                      let code = triple[0].stringValue,
                      let lo = triple[1].intValue,
                      let hi = triple[2].intValue else { continue }
                let entry = byCode[code]
                out.append(QiraatWordRule(word: key, rule: entry?.rule ?? code, code: code,
                                          arabic: entry?.arabic ?? "", english: entry?.english ?? "",
                                          firstLetter: lo, lastLetter: hi, wholeWord: lo < 0))
            }
        }
        return out
    }

    /// The ayahs of a surah this riwayah reads differently from Hafs somewhere - the index behind a
    /// "show me where these two readings part" list, without walking every ayah's rules.
    public func khilafAyahs(_ surahId: Int, riwayah: String) -> [Int] {
        packs[riwayah]?.khilafMarkers["\(surahId)"] ?? []
    }

    public func hasKhilaf(_ surahId: Int, _ ayahId: Int, riwayah: String) -> Bool {
        khilafAyahs(surahId, riwayah: riwayah).contains(ayahId)
    }

    /// What a rule key means, in one line and in a paragraph. Shared across every riwayah that uses it.
    public func describe(_ rule: String) -> QiraatRuleDescription? { descriptions[rule] }

    public func ruleKeys() -> [String] { descriptions.keys.sorted() }

    private func codes(_ riwayah: String) -> [String: QiraatLegendEntry] {
        if let cached = legendByCode[riwayah] { return cached }
        let map = Dictionary(uniqueKeysWithValues: legend(riwayah).map { ($0.code, $0) })
        legendByCode[riwayah] = map
        return map
    }
}
