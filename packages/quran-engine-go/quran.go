package quranengine

import (
	"fmt"
	"strconv"
	"strings"
)

// sajdahMark is ۩ ARABIC PLACE OF SAJDAH (U+06E9), which marks the 15 sajdah
// (prostration) ayahs in the Arabic text.
const sajdahMark = "۩"

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

// ExistsInQiraah reports whether a Hafs ayah exists as its own verse in the given
// riwayah. In Hafs every ayah exists; other riwayat merge/split some ayahs, so a Hafs
// ayah "exists" iff the riwayah's feed carries an ayah with that id (its feeds are
// numbered contiguously 1..count, so this is ayahID <= count). Mirrors
// Quran.existsInQiraah. An unknown/unloaded riwayah falls back to Hafs (exists).
func (e *Engine) ExistsInQiraah(surahID, ayahID int, riwayah string) bool {
	if e.Ayah(surahID, ayahID) == nil {
		return false
	}
	r := strings.ToLower(riwayah)
	if r == "" || r == "hafs" {
		return true
	}
	counts, ok := e.qiraatCounts[r]
	if !ok {
		return true
	}
	count, ok := counts[strconv.Itoa(surahID)]
	if !ok {
		return true
	}
	return ayahID <= count
}

// NumberOfAyahsInQiraah returns the ayah count of a surah in the given riwayah — the
// number of Hafs ayahs that exist there (e.g. Baqarah is 286 in Hafs but 285 in Warsh).
// Mirrors Quran.numberOfAyahsInQiraah. Returns 0 for an unknown surah; an unknown/unloaded
// riwayah falls back to the Hafs count.
func (e *Engine) NumberOfAyahsInQiraah(surahID int, riwayah string) int {
	s := e.byID[surahID]
	if s == nil {
		return 0
	}
	r := strings.ToLower(riwayah)
	if r == "" || r == "hafs" {
		return s.NumberOfAyahs
	}
	counts, ok := e.qiraatCounts[r]
	if !ok {
		return s.NumberOfAyahs
	}
	count, ok := counts[strconv.Itoa(surahID)]
	if !ok {
		return s.NumberOfAyahs
	}
	if count < s.NumberOfAyahs {
		return count
	}
	return s.NumberOfAyahs
}

// SurahFromEnd resolves a surah counted from the END of the mushaf: 1 -> An-Nas
// (114), 2 -> Al-Falaq ... 114 -> Al-Fatihah. Mirrors the search-bar "-N" shorthand
// (companion to JuzFromEnd). Returns nil for n outside 1..114.
func (e *Engine) SurahFromEnd(n int) *Surah {
	if n < 1 || n > len(e.surahs) {
		return nil
	}
	return e.byID[len(e.surahs)+1-n]
}

// IsSajdahAyah reports whether the ayah is a sajdah (prostration) ayah — it carries
// the ۩ mark (U+06E9) in its Arabic text.
func (e *Engine) IsSajdahAyah(surahID, ayahID int) bool {
	a := e.Ayah(surahID, ayahID)
	if a == nil {
		return false
	}
	return strings.Contains(a.TextArabic, sajdahMark)
}

// SajdahAyahs returns the 15 sajdah (prostration) ayahs, in mushaf order, detected
// by the ۩ mark in the Arabic text.
func (e *Engine) SajdahAyahs() []AyahRef {
	var out []AyahRef
	for i := range e.surahs {
		s := &e.surahs[i]
		for j := range s.Ayahs {
			if strings.Contains(s.Ayahs[j].TextArabic, sajdahMark) {
				out = append(out, AyahRef{Surah: s, Ayah: &s.Ayahs[j]})
			}
		}
	}
	return out
}

// SurahInfo returns the "About this surah" write-ups (e.g. Maududi, Ibn Ashur) for
// the given surah id, or nil if none exist.
func (e *Engine) SurahInfo(id int) []SurahInfoSource {
	return e.surahInfo[id]
}

// NamesOfAllah returns all 99 Names of Allah (Asma' ul-Husna), ordered by number.
func (e *Engine) NamesOfAllah() []NameOfAllah {
	return e.names
}

// NameOfAllah returns the Name with the given number (1..99), or nil if not found.
func (e *Engine) NameOfAllah(number int) *NameOfAllah {
	return e.namesByNumber[number]
}

// PageChangesWithinSurah reports whether a mushaf page boundary falls inside this
// surah. Mirrors Quran.pageChangesWithinSurah. Returns false for an unknown surah.
func (e *Engine) PageChangesWithinSurah(surahID int) bool {
	s := e.byID[surahID]
	if s == nil {
		return false
	}
	// NumberOfPages is 0 for "none" in the Go data; treat that like the JS `?? 1`.
	if s.NumberOfPages > 1 {
		return true
	}
	pages := map[int]struct{}{}
	for i := range s.Ayahs {
		if p := s.Ayahs[i].Page; p != 0 {
			pages[p] = struct{}{}
		}
	}
	return len(pages) > 1
}

// JuzChangesWithinSurah reports whether a juz boundary falls inside this surah.
// Mirrors Quran.juzChangesWithinSurah. Returns false for an unknown surah.
func (e *Engine) JuzChangesWithinSurah(surahID int) bool {
	s := e.byID[surahID]
	if s == nil {
		return false
	}
	if len(s.Juzs) > 1 {
		return true
	}
	// FirstJuz/LastJuz are 0 for "none" in the Go data; only compare when both set.
	if s.FirstJuz != 0 && s.LastJuz != 0 && s.FirstJuz != s.LastJuz {
		return true
	}
	juzs := map[int]struct{}{}
	for i := range s.Ayahs {
		if j := s.Ayahs[i].Juz; j != 0 {
			juzs[j] = struct{}{}
		}
	}
	return len(juzs) > 1
}

// PageOrJuzChangesWithinSurah reports whether a page OR juz boundary falls inside
// this surah. Mirrors Quran.pageOrJuzChangesWithinSurah.
func (e *Engine) PageOrJuzChangesWithinSurah(surahID int) bool {
	return e.PageChangesWithinSurah(surahID) || e.JuzChangesWithinSurah(surahID)
}

// Muqattaat returns every muqattaʿāt opening (30 entries: one per surah, plus
// Ash-Shūra's 2nd ayah), in file order. Mirrors Muqattaat.all().
func (e *Engine) Muqattaat() []MuqattaatPronunciation { return e.muqattaat }

// MuqattaatFor returns the pronunciation for a muqattaʿāt ayah, or nil if that
// ayah doesn't open with them. Mirrors Muqattaat.pronunciation.
func (e *Engine) MuqattaatFor(surahID, ayahID int) *MuqattaatPronunciation {
	return e.muqattaatByKey[fmt.Sprintf("%d:%d", surahID, ayahID)]
}

// MuqattaatLetterName returns the transliteration of a single muqattaʿāt letter
// (e.g. "ا" -> "Alif"), or "" if the letter has no name. Mirrors Muqattaat.letterName.
func (e *Engine) MuqattaatLetterName(letter string) string {
	return e.muqattaatLetters[letter]
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
