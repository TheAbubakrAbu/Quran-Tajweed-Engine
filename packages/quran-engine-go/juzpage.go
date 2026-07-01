package quranengine

import "sort"

// Juzes returns all 30 juz boundary entries, sorted by id.
func (e *Engine) Juzes() []JuzEntry {
	out := make([]JuzEntry, len(e.juzList))
	copy(out, e.juzList)
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// Juz returns the boundary entry with the given id, or nil if not found.
func (e *Engine) Juz(id int) *JuzEntry {
	for i := range e.juzList {
		if e.juzList[i].ID == id {
			return &e.juzList[i]
		}
	}
	return nil
}

// AyahsInJuz returns every ayah whose per-ayah juz field equals juz, in mushaf order.
func (e *Engine) AyahsInJuz(juz int) []AyahRef {
	var out []AyahRef
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Juz == juz {
			out = append(out, AyahRef{Surah: s, Ayah: a})
		}
		return true
	})
	return out
}

// AyahsOnPage returns every ayah on a mushaf page, in mushaf order.
func (e *Engine) AyahsOnPage(page int) []AyahRef {
	var out []AyahRef
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Page == page {
			out = append(out, AyahRef{Surah: s, Ayah: a})
		}
		return true
	})
	return out
}

// FirstAyahOfJuz returns the first ayah of a juz, or nil if none.
func (e *Engine) FirstAyahOfJuz(juz int) *AyahRef {
	var ref *AyahRef
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Juz == juz {
			ref = &AyahRef{Surah: s, Ayah: a}
			return false
		}
		return true
	})
	return ref
}

// FirstAyahOfPage returns the first ayah of a mushaf page, or nil if none.
func (e *Engine) FirstAyahOfPage(page int) *AyahRef {
	var ref *AyahRef
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Page == page {
			ref = &AyahRef{Surah: s, Ayah: a}
			return false
		}
		return true
	})
	return ref
}

// JuzForAyah returns the juz number an ayah belongs to (0 if unknown).
func (e *Engine) JuzForAyah(surahID, ayahID int) int {
	if a := e.Ayah(surahID, ayahID); a != nil {
		return a.Juz
	}
	return 0
}

// PageForAyah returns the mushaf page an ayah is on (0 if unknown).
func (e *Engine) PageForAyah(surahID, ayahID int) int {
	if a := e.Ayah(surahID, ayahID); a != nil {
		return a.Page
	}
	return 0
}

// TotalPages returns the page count of the bundled mushaf (max page seen).
func (e *Engine) TotalPages() int {
	max := 0
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Page > max {
			max = a.Page
		}
		return true
	})
	return max
}

// JuzFromEnd resolves a juz counted from the end of the Quran: 1 -> juz 30, 2 -> juz 29 ... 30 -> juz 1.
// Mirrors the search-bar "-N" shorthand in QuranView.swift. Returns nil for n outside 1..30.
func (e *Engine) JuzFromEnd(n int) *JuzEntry {
	if n < 1 || n > 30 {
		return nil
	}
	return e.Juz(31 - n)
}

// JuzStats holds aggregate counts for a single juz. Mirrors QuranData.JuzStats.
type JuzStats struct {
	SurahCount  int
	AyahCount   int
	WordCount   int
	LetterCount int
	PageCount   int
}

// JuzStatsFor returns aggregate counts for a single juz, computed from the ayahs actually
// assigned to it (ayah.Juz == juz) so surahs that straddle a juz boundary are split correctly.
// Mirrors QuranData.juzStats(for:). Returns nil for an unknown juz id.
func (e *Engine) JuzStatsFor(juz int) *JuzStats {
	if e.Juz(juz) == nil {
		return nil
	}
	surahIDs := map[int]bool{}
	pages := map[int]bool{}
	stats := JuzStats{}
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		if a.Juz != juz {
			return true
		}
		surahIDs[s.ID] = true
		stats.AyahCount++
		stats.WordCount += a.WordCount
		stats.LetterCount += a.LetterCount
		if a.Page != 0 {
			pages[a.Page] = true
		}
		return true
	})
	stats.SurahCount = len(surahIDs)
	stats.PageCount = len(pages)
	return &stats
}
