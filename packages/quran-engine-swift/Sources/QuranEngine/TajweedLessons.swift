import Foundation

/// The tajweed course: eight chapters from the Arabic alphabet to the rules of stopping, each
/// lesson carrying its prose, its drills, and Quranic examples to hear the rule in.
///
/// Content, not algorithm - but it belongs in the engine for the same reason the rule catalogue
/// does: every app that teaches tajweed otherwise rewrites the same curriculum.
///
/// See docs/13-similar-and-themes.md.
/// One practice fragment: a short Arabic snippet with a caption saying what to listen for.
public struct TajweedDrill: Decodable, Sendable, Equatable {
    public let caption: String
    public let text: String
}

/// An ayah to hear the rule in, with the phrase to focus on.
public struct TajweedExample: Decodable, Sendable, Equatable {
    public let surahId: Int
    public let ayahNumber: Int
    public let focus: String
}

/// The card that shows the rule as it appears in the mushaf: fragments, and the count held.
public struct TajweedMushafCard: Decodable, Sendable, Equatable {
    public let fragments: [TajweedDrill]
    public let countEn: String?
    public let countAr: String?
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
    public let mushafCard: TajweedMushafCard?
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
        mushafCard = try c.decodeIfPresent(TajweedMushafCard.self, forKey: .mushafCard)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    enum CodingKeys: String, CodingKey {
        case id, titleEn, titleAr, summary, body, drills, examples, mushafCard, color
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
