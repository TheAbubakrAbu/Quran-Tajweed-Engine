package quranengine

import (
	"testing"
	"unicode/utf16"
)

// loadTestEngine loads from the repo's /data, found by walking up from CWD.
func loadTestEngine(t *testing.T) *Engine {
	t.Helper()
	dir, err := FindDataDir()
	if err != nil {
		t.Fatalf("locating data dir: %v", err)
	}
	e, err := LoadFrom(dir)
	if err != nil {
		t.Fatalf("LoadFrom(%q): %v", dir, err)
	}
	return e
}

// reciterByAyahIdentifier returns the first reciter with the given CDN identifier.
func reciterByAyahIdentifier(e *Engine, id string) *Reciter {
	for i := range e.reciters {
		if e.reciters[i].AyahIdentifier == id && e.reciters[i].Qiraah == "" {
			return &e.reciters[i]
		}
	}
	return nil
}

func TestTotalAyahs(t *testing.T) {
	e := loadTestEngine(t)
	if got := e.TotalAyahs(); got != 6236 {
		t.Errorf("TotalAyahs = %d, want 6236", got)
	}
}

func TestGlobalAyahNumber(t *testing.T) {
	e := loadTestEngine(t)
	cases := []struct {
		s, a, want int
	}{
		{1, 1, 1},
		{2, 1, 8},
		{114, 6, 6236},
	}
	for _, c := range cases {
		got, err := e.GlobalAyahNumber(c.s, c.a)
		if err != nil {
			t.Fatalf("GlobalAyahNumber(%d,%d): %v", c.s, c.a, err)
		}
		if got != c.want {
			t.Errorf("GlobalAyahNumber(%d,%d) = %d, want %d", c.s, c.a, got, c.want)
		}
	}
}

func TestAudioURLs(t *testing.T) {
	e := loadTestEngine(t)
	alafasy := reciterByAyahIdentifier(e, "ar.alafasy")
	if alafasy == nil {
		t.Fatal("Alafasy reciter not found")
	}

	surahURL, err := SurahAudioURL(alafasy, 1)
	if err != nil {
		t.Fatalf("SurahAudioURL: %v", err)
	}
	const wantSurah = "https://server8.mp3quran.net/afs/001.mp3"
	if surahURL != wantSurah {
		t.Errorf("SurahAudioURL(Alafasy,1) = %q, want %q", surahURL, wantSurah)
	}

	ayahURL := AyahAudioURL(alafasy, 8)
	const wantAyah = "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"
	if ayahURL != wantAyah {
		t.Errorf("AyahAudioURL(Alafasy,8) = %q, want %q", ayahURL, wantAyah)
	}
}

func TestJuzBoundaries(t *testing.T) {
	e := loadTestEngine(t)
	j1 := e.Juz(1)
	if j1 == nil || j1.StartSurah != 1 || j1.StartAyah != 1 {
		t.Errorf("juz(1) start = %+v, want startSurah=1 startAyah=1", j1)
	}
	j30 := e.Juz(30)
	if j30 == nil || j30.EndSurah != 114 || j30.EndAyah != 6 {
		t.Errorf("juz(30) end = %+v, want endSurah=114 endAyah=6", j30)
	}
}

func TestJuzFromEndAndStats(t *testing.T) {
	e := loadTestEngine(t)
	if j := e.JuzFromEnd(1); j == nil || j.ID != 30 {
		t.Errorf("JuzFromEnd(1) = %+v, want id=30", j)
	}
	if j := e.JuzFromEnd(30); j == nil || j.ID != 1 {
		t.Errorf("JuzFromEnd(30) = %+v, want id=1", j)
	}
	if e.JuzFromEnd(0) != nil || e.JuzFromEnd(31) != nil {
		t.Errorf("JuzFromEnd out of range should be nil")
	}

	stats := e.JuzStatsFor(30)
	if stats == nil {
		t.Fatal("JuzStatsFor(30) = nil")
	}
	if stats.AyahCount != len(e.AyahsInJuz(30)) {
		t.Errorf("AyahCount = %d, want %d", stats.AyahCount, len(e.AyahsInJuz(30)))
	}
	if stats.SurahCount < 1 || stats.PageCount < 1 || stats.WordCount == 0 || stats.LetterCount == 0 {
		t.Errorf("JuzStatsFor(30) has zero aggregate: %+v", stats)
	}
	if e.JuzStatsFor(99) != nil {
		t.Errorf("JuzStatsFor(99) should be nil")
	}
	sum := 0
	for i := 1; i <= 30; i++ {
		sum += e.JuzStatsFor(i).AyahCount
	}
	if sum != 6236 {
		t.Errorf("sum of juz ayah counts = %d, want 6236", sum)
	}
}

func TestSortSurahsAyahsDescending(t *testing.T) {
	e := loadTestEngine(t)
	sorted := e.SortSurahs("ayahs", "descending")
	if len(sorted) == 0 || sorted[0].ID != 2 {
		t.Errorf("SortSurahs(ayahs,descending)[0].ID = %d, want 2 (Al-Baqarah)", sorted[0].ID)
	}
}

func TestParseReference(t *testing.T) {
	e := loadTestEngine(t)
	ref := e.ParseReference("2:255")
	if ref == nil || ref.Surah != 2 || !ref.HasAyah || ref.Ayah != 255 {
		t.Errorf("ParseReference(\"2:255\") = %+v, want {Surah:2 Ayah:255}", ref)
	}
}

func TestTajweedSpansReconstruct(t *testing.T) {
	e := loadTestEngine(t)
	spans := e.TajweedSpans(1, 1)
	if len(spans) == 0 {
		t.Fatal("TajweedSpans(1,1) returned no spans")
	}
	text := e.ArabicText(1, 1, "")
	units := utf16.Encode([]rune(text))
	for _, sp := range spans {
		if sp.Start < 0 || sp.End > len(units) || sp.Start >= sp.End {
			t.Errorf("span %+v out of range (len=%d)", sp, len(units))
			continue
		}
		want := string(utf16.Decode(units[sp.Start:sp.End]))
		if sp.Text != want {
			t.Errorf("span %s [%d:%d] Text = %q, want %q", sp.Rule, sp.Start, sp.End, sp.Text, want)
		}
		if sp.ColorHex == "" {
			t.Errorf("span %s has no ColorHex", sp.Rule)
		}
	}
}

func TestSearchVersesAndSurahs(t *testing.T) {
	e := loadTestEngine(t)

	// Digit rejection on verse search.
	if got := e.SearchVerses("255", SearchOptions{}); got != nil {
		t.Errorf("SearchVerses with digit should return nil, got %d hits", len(got))
	}

	// English substring match returns mushaf-ordered hits.
	hits := e.SearchVerses("In the name of Allah", SearchOptions{Limit: 5})
	if len(hits) == 0 {
		t.Errorf("expected verse hits for 'In the name of Allah'")
	}

	// Surah name lookup.
	if got := e.SearchSurahs("Fatihah"); len(got) == 0 || got[0].ID != 1 {
		t.Errorf("SearchSurahs(Fatihah) first = %v, want surah 1", got)
	}

	// Reference lookup resolves to its surah.
	if got := e.SearchSurahs("2:255"); len(got) == 0 || got[0].ID != 2 {
		t.Errorf("SearchSurahs(2:255) should include surah 2, got %v", got)
	}

	// Makkan filter.
	makkan := e.SearchSurahs("makkan")
	for _, s := range makkan {
		if s.Type != "makkan" {
			t.Errorf("makkan filter returned non-makkan surah %d (%s)", s.ID, s.Type)
		}
	}
	if len(makkan) == 0 {
		t.Errorf("expected makkan surahs")
	}
}

// hasMatch reports whether hits include surah:ayah.
func hasMatch(hits []VerseMatch, surah, ayah int) bool {
	for _, h := range hits {
		if h.Surah == surah && h.Ayah == ayah {
			return true
		}
	}
	return false
}

func TestSearchVersesBehavior(t *testing.T) {
	e := loadTestEngine(t)

	// Regular search is pure substring: a mid-word fragment hits. 1:2 contains
	// "...Lord of the worlds...", so "orld" (inside "worlds") matches.
	if got := e.SearchVerses("orld", SearchOptions{}); !hasMatch(got, 1, 2) {
		t.Errorf("SearchVerses(\"orld\") should match 1:2, got %v", got)
	}

	// Whole-word operator `=` requires a full token match: `=lord` matches 1:2
	// (token "lord" exists) but `=lor` does NOT (no token "lor").
	if got := e.SearchVerses("=lord", SearchOptions{}); !hasMatch(got, 1, 2) {
		t.Errorf("SearchVerses(\"=lord\") should match 1:2, got %v", got)
	}
	if got := e.SearchVerses("=lor", SearchOptions{}); hasMatch(got, 1, 2) {
		t.Errorf("SearchVerses(\"=lor\") should NOT match 1:2 (whole-word), got %v", got)
	}
	// ...while plain (non-boolean) "lor" DOES match 1:2 as a substring of "lord".
	if got := e.SearchVerses("lor", SearchOptions{}); !hasMatch(got, 1, 2) {
		t.Errorf("SearchVerses(\"lor\") should match 1:2 as substring, got %v", got)
	}

	// A boolean query containing a digit is rejected before the boolean path.
	if got := e.SearchVerses("allah & 2", SearchOptions{}); got != nil {
		t.Errorf("SearchVerses(\"allah & 2\") should return nil (digit), got %d hits", len(got))
	}
}

func TestCachePaths(t *testing.T) {
	e := loadTestEngine(t)
	alafasy := reciterByAyahIdentifier(e, "ar.alafasy")
	if alafasy == nil {
		t.Fatal("Alafasy reciter not found")
	}
	dir := SanitizeReciterDir(alafasy.ID)
	for _, r := range dir {
		ok := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_'
		if !ok {
			t.Errorf("SanitizeReciterDir produced unsafe char %q in %q", r, dir)
		}
	}
	path := LocalSurahPath(alafasy, 1)
	if path != dir+"/001.mp3" {
		t.Errorf("LocalSurahPath = %q, want %q", path, dir+"/001.mp3")
	}
	if got := SanitizeReciterDir(""); got != "reciter" {
		t.Errorf("SanitizeReciterDir(\"\") = %q, want reciter", got)
	}
}

func TestJuzPageNavigation(t *testing.T) {
	e := loadTestEngine(t)
	if e.TotalPages() != 604 {
		t.Errorf("TotalPages = %d, want 604", e.TotalPages())
	}
	first := e.FirstAyahOfJuz(1)
	if first == nil || first.Surah.ID != 1 || first.Ayah.ID != 1 {
		t.Errorf("FirstAyahOfJuz(1) = %+v, want surah1 ayah1", first)
	}
	if got := len(e.AyahsOnPage(1)); got == 0 {
		t.Errorf("AyahsOnPage(1) returned 0 ayahs")
	}
}
