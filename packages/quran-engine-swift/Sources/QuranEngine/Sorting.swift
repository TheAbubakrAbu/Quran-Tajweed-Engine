import Foundation

/// Surah sort modes. Mirrors `sorting.js`.
public enum SortMode: String, Sendable {
    case surah, revelation, ayahs, page, words, letters
}

/// Surah sort directions.
public enum SortDirection: String, Sendable {
    case surahOrder, ascending, descending
}

/// Sort modes that honour a direction. Others are intrinsically ordered.
private let directionalModes: Set<SortMode> = [.revelation, .page, .ayahs, .words, .letters]

/// Whether a mode supports a direction toggle.
public func supportsDirection(_ mode: SortMode) -> Bool { directionalModes.contains(mode) }

/// Sort surahs. Every comparator is ascending with `id` as the tiebreaker; descending is the
/// reverse of the ascending array. `mode == .surah` or `direction == .surahOrder` => natural order.
public func sortSurahs(_ surahs: [Surah], _ mode: SortMode = .surah, _ direction: SortDirection = .ascending) -> [Surah] {
    if direction == .surahOrder || mode == .surah {
        return surahs.sorted { $0.id < $1.id }
    }

    func key(_ s: Surah) -> Int {
        switch mode {
        case .revelation: return s.revelationOrder ?? Int.max
        case .ayahs: return s.numberOfAyahs
        case .page: return s.numberOfPages ?? 0
        case .words: return s.wordCount ?? 0
        case .letters: return s.letterCount ?? 0
        case .surah: return s.id
        }
    }

    let asc = surahs.sorted { a, b in
        let ka = key(a), kb = key(b)
        if ka == kb { return a.id < b.id }
        return ka < kb
    }

    if direction == .descending && directionalModes.contains(mode) { return asc.reversed() }
    return asc
}

/// Filter by revelation type (`"makkan"` / `"madinan"`).
public func filterByRevelationType(_ surahs: [Surah], _ type: String) -> [Surah] {
    surahs.filter { $0.type == type }
}
