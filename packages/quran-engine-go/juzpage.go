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
