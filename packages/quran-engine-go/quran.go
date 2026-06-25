package quranengine

import "fmt"

// TotalAyahs returns the total ayah count across the mushaf (6236 for Hafs).
func (e *Engine) TotalAyahs() int { return e.totalAyahs }

// Surahs returns all surahs in mushaf order (1..114).
func (e *Engine) Surahs() []Surah { return e.surahs }

// Surah returns the surah with the given id, or nil if not found.
func (e *Engine) Surah(id int) *Surah { return e.byID[id] }

// Ayah returns the ayah (surahID, ayahID), or nil if not found.
func (e *Engine) Ayah(surahID, ayahID int) *Ayah {
	s := e.byID[surahID]
	if s == nil {
		return nil
	}
	for i := range s.Ayahs {
		if s.Ayahs[i].ID == ayahID {
			return &s.Ayahs[i]
		}
	}
	return nil
}

// GlobalAyahNumber returns the 1-based global ayah number (1..6236) used by the
// ayah-audio CDN and as a stable verse key. It errors on an unknown surah.
func (e *Engine) GlobalAyahNumber(surahID, ayahID int) (int, error) {
	off, ok := e.cumulative[surahID]
	if !ok {
		return 0, fmt.Errorf("unknown surah %d", surahID)
	}
	return off + ayahID, nil
}

// ArabicText returns the Arabic text of an ayah. The riwayah parameter is
// accepted for parity with other ports; this core build bundles only the Hafs
// text, so any value falls back to TextArabic. Returns "" if the ayah is missing.
func (e *Engine) ArabicText(surahID, ayahID int, riwayah string) string {
	a := e.Ayah(surahID, ayahID)
	if a == nil {
		return ""
	}
	return a.TextArabic
}

// CleanArabicText returns the Arabic text with diacritics/recitation marks stripped.
func (e *Engine) CleanArabicText(surahID, ayahID int, riwayah string) string {
	return removingArabicDiacriticsAndSigns(e.ArabicText(surahID, ayahID, riwayah))
}

// EachAyah calls fn for every ayah in mushaf order. Return false from fn to stop.
func (e *Engine) EachAyah(fn func(s *Surah, a *Ayah) bool) {
	for i := range e.surahs {
		s := &e.surahs[i]
		for j := range s.Ayahs {
			if !fn(s, &s.Ayahs[j]) {
				return
			}
		}
	}
}
