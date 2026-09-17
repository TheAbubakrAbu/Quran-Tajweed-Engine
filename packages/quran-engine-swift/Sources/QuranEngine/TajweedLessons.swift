import Foundation

/// The tajweed course: eight chapters from the Arabic alphabet to the rules of stopping, each
/// lesson carrying its prose, its drills, and Quranic examples to hear the rule in.
///
/// Content, not algorithm - but it belongs in the engine for the same reason the rule catalogue
/// does: every app that teaches tajweed otherwise rewrites the same curriculum.
///
/// See docs/13-similar-and-themes.md.
/// One practice fragment: a short Arabic snippet with a caption saying what to listen for.
///
/// The Arabic is in exactly one of two places. Teaching Arabic a tutor wrote (invented drill
/// syllables, single letters, the isti'adhah) is `text`. Arabic that IS Quran is `ayah`, a
/// reference into this engine's own text, and then `text` is empty: version 4 stopped copying
/// verses into the lesson pack for the same reason nothing else here copies them.
public struct TajweedDrill: Decodable, Sendable, Equatable {
    public let caption: String
    /// The fragment as written, or empty when `ayah` locates it instead.
    public let text: String
    /// Where the words are in the Quran when this drill is a real verse: a 0-based inclusive
    /// token range into the ayah's raw text. Cut them out of `engine.quran` by it; the data
    /// carries no copy of them. Nil when `text` already holds the Arabic.
    public let ayah: TajweedAyahWords?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        ayah = try c.decodeIfPresent(TajweedAyahWords.self, forKey: .ayah)
    }

    enum CodingKeys: String, CodingKey {
        case caption, text, ayah
    }
}

/// A run of Quran words a lesson points at: the ayah, and a 0-based inclusive token range of its
/// raw text. The pack's shape is `[surah, ayah, first, last]`.
public struct TajweedAyahWords: Decodable, Sendable, Equatable {
    public let surahId: Int
    public let ayahNumber: Int
    public let span: ClosedRange<Int>

    public init(from decoder: Decoder) throws {
        let row = try decoder.singleValueContainer().decode([Int].self)
        guard row.count == 4, row[2] >= 0, row[3] >= row[2] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "expected [surah, ayah, first, last] with 0 <= first <= last"))
        }
        surahId = row[0]
        ayahNumber = row[1]
        span = row[2]...row[3]
    }
}

/// The memory-hook word a rule card hangs on, with what it means. Teaching Arabic chosen for the
/// rule it demonstrates, so it is written out rather than referenced.
public struct TajweedMnemonic: Decodable, Sendable, Equatable {
    public let arabic: String
    public let gloss: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arabic = try c.decodeIfPresent(String.self, forKey: .arabic) ?? ""
        gloss = try c.decodeIfPresent(String.self, forKey: .gloss) ?? ""
    }

    enum CodingKeys: String, CodingKey { case arabic, gloss }
}

/// An ayah to hear the rule in, with a `focus` line saying what to listen for.
public struct TajweedExample: Decodable, Sendable, Equatable {
    public let surahId: Int
    public let ayahNumber: Int
    public let focus: String
    /// The words to listen at: a 0-based inclusive token range into the ayah's raw text
    /// (`textArabic` split on spaces). The data carries no copy of the words (version 3); cut
    /// them out of `engine.quran` by this span. Nil when the lesson names the whole ayah, or
    /// when the file's pair is not `[start, end]` with `0 <= start <= end`.
    public let wordSpan: ClosedRange<Int>?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surahId = try c.decode(Int.self, forKey: .surahId)
        ayahNumber = try c.decode(Int.self, forKey: .ayahNumber)
        focus = try c.decode(String.self, forKey: .focus)
        // Absent, null, or not a list of ints at all: no span, and the lesson still loads.
        let pair = (try? c.decodeIfPresent([Int].self, forKey: .wordSpan)) ?? []
        if pair.count == 2, pair[0] >= 0, pair[1] >= pair[0] {
            wordSpan = pair[0]...pair[1]
        } else {
            wordSpan = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case surahId, ayahNumber, focus, wordSpan
    }
}

/// The card that states the rule: when it triggers, what to do, how long to hold it, the mnemonic
/// it hangs on, and fragments to see it in.
public struct TajweedRuleCard: Decodable, Sendable, Equatable {
    public let fragments: [TajweedDrill]
    public let trigger: String?
    public let action: String?
    public let hold: String?
    public let mnemonic: TajweedMnemonic?
    public let countEn: String?
    public let countAr: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fragments = try c.decodeIfPresent([TajweedDrill].self, forKey: .fragments) ?? []
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        hold = try c.decodeIfPresent(String.self, forKey: .hold)
        mnemonic = try c.decodeIfPresent(TajweedMnemonic.self, forKey: .mnemonic)
        countEn = try c.decodeIfPresent(String.self, forKey: .countEn)
        countAr = try c.decodeIfPresent(String.self, forKey: .countAr)
    }

    enum CodingKeys: String, CodingKey {
        case fragments, trigger, action, hold, mnemonic, countEn, countAr
    }
}

public struct TajweedLesson: Decodable, Sendable, Equatable {
    public let id: String
    public let titleEn: String
    public let titleAr: String
    public let summary: String
    public let body: [String]
    /// Practice fragments. Absent on the lessons that teach through examples alone.
    public let drills: [TajweedDrill]
    public let examples: [TajweedExample]
    public let ruleCard: TajweedRuleCard?
    /// The tajweed colour this rule is painted in, where it has one.
    public let color: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        titleEn = try c.decodeIfPresent(String.self, forKey: .titleEn) ?? ""
        titleAr = try c.decodeIfPresent(String.self, forKey: .titleAr) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        body = try c.decodeIfPresent([String].self, forKey: .body) ?? []
        drills = try c.decodeIfPresent([TajweedDrill].self, forKey: .drills) ?? []
        examples = try c.decodeIfPresent([TajweedExample].self, forKey: .examples) ?? []
        ruleCard = try c.decodeIfPresent(TajweedRuleCard.self, forKey: .ruleCard)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    enum CodingKeys: String, CodingKey {
        case id, titleEn, titleAr, summary, body, drills, examples, ruleCard, color
    }
}

public struct TajweedChapter: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let lessons: [TajweedLesson]
}

public struct TajweedLessonsFile: Decodable, Sendable {
    public let chapters: [TajweedChapter]
}

public final class TajweedLessons {
    private let allChapters: [TajweedChapter]
    private let byLesson: [String: (chapter: TajweedChapter, lesson: TajweedLesson)]

    public init(_ file: TajweedLessonsFile? = nil) {
        let chapters = file?.chapters ?? []
        self.allChapters = chapters
        var index: [String: (chapter: TajweedChapter, lesson: TajweedLesson)] = [:]
        for chapter in chapters {
            for lesson in chapter.lessons { index[lesson.id] = (chapter, lesson) }
        }
        self.byLesson = index
    }

    /// Every chapter, in course order.
    public func chapters() -> [TajweedChapter] { allChapters }

    public func chapter(_ id: String) -> TajweedChapter? { allChapters.first { $0.id == id } }

    /// Every lesson across every chapter, in course order.
    public func allLessons() -> [TajweedLesson] { allChapters.flatMap(\.lessons) }

    public func lesson(_ id: String) -> TajweedLesson? { byLesson[id]?.lesson }

    /// Which chapter a lesson belongs to.
    public func chapterOf(_ id: String) -> TajweedChapter? { byLesson[id]?.chapter }

    /// The lesson after this one, walking across chapter boundaries - the "next" button's answer.
    public func next(_ id: String) -> TajweedLesson? {
        let lessons = allLessons()
        guard let at = lessons.firstIndex(where: { $0.id == id }), at + 1 < lessons.count else { return nil }
        return lessons[at + 1]
    }

    public func previous(_ id: String) -> TajweedLesson? {
        let lessons = allLessons()
        guard let at = lessons.firstIndex(where: { $0.id == id }), at > 0 else { return nil }
        return lessons[at - 1]
    }
}
