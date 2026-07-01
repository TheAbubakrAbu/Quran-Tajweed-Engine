package quranengine

import "sort"

// directional sort modes honour a direction; others are intrinsically ordered.
var directionalModes = map[string]bool{
	"revelation": true, "page": true, "ayahs": true, "words": true, "letters": true,
}

// SortSurahs returns the surahs sorted by mode and direction.
//
// Comparators are ascending with id as the tiebreaker; descending is the reverse
// of the ascending array. mode "surah" or direction "surahOrder" yields natural
// 1..114 order. Recognized modes: "surah", "revelation", "ayahs", "page",
// "words", "letters".
func (e *Engine) SortSurahs(mode, direction string) []Surah {
	out := make([]Surah, len(e.surahs))
	copy(out, e.surahs)

	if direction == "surahOrder" || mode == "surah" {
		sort.SliceStable(out, func(i, j int) bool { return out[i].ID < out[j].ID })
		return out
	}

	key := func(s Surah) int {
		switch mode {
		case "revelation":
			if s.RevelationOrder == 0 {
				return int(^uint(0) >> 1) // max int, like JS MAX_SAFE_INTEGER sentinel
			}
			return s.RevelationOrder
		case "ayahs":
			return s.NumberOfAyahs
		case "page":
			return s.NumberOfPages
		case "words":
			return s.WordCount
		case "letters":
			return s.LetterCount
		default:
			return s.ID
		}
	}

	sort.SliceStable(out, func(i, j int) bool {
		ka, kb := key(out[i]), key(out[j])
		if ka == kb {
			return out[i].ID < out[j].ID
		}
		return ka < kb
	})

	if direction == "descending" && directionalModes[mode] {
		for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
			out[i], out[j] = out[j], out[i]
		}
	}
	return out
}

// SupportsDirection reports whether a sort mode honours a direction.
func SupportsDirection(mode string) bool { return directionalModes[mode] }

// FilterByRevelationType returns surahs whose Type matches ("makkan" | "madinan").
func (e *Engine) FilterByRevelationType(typ string) []Surah {
	var out []Surah
	for _, s := range e.surahs {
		if s.Type == typ {
			out = append(out, s)
		}
	}
	return out
}

// CountFilter is a numeric predicate for FilterByCounts. Op is one of
// "<", "<=", ">", ">=", "==" (anything else is treated as "==").
type CountFilter struct {
	Op    string
	Value int
}

// passesCount reports whether n satisfies f. A nil filter always passes.
func passesCount(n int, f *CountFilter) bool {
	if f == nil {
		return true
	}
	switch f.Op {
	case "<":
		return n < f.Value
	case "<=":
		return n <= f.Value
	case ">":
		return n > f.Value
	case ">=":
		return n >= f.Value
	default: // "==" and any unknown op
		return n == f.Value
	}
}

// FilterByCounts filters surahs by ayah-count and/or page-count predicates. Mirrors
// surahsMatchingCount in QuranData.swift (the search-bar "286 ayahs" / "<10 pages"
// filters). A surah passes when it satisfies BOTH provided filters; a nil filter is
// ignored. Values are compared against NumberOfAyahs / NumberOfPages.
func FilterByCounts(surahs []Surah, ayahs, pages *CountFilter) []Surah {
	var out []Surah
	for _, s := range surahs {
		if passesCount(s.NumberOfAyahs, ayahs) && passesCount(s.NumberOfPages, pages) {
			out = append(out, s)
		}
	}
	return out
}
