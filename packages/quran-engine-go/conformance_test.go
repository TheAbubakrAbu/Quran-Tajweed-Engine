package quranengine

// Conformance test — runs the language-agnostic vectors in /conformance/vectors.json
// against the engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a
// behavior is specified ONCE in that JSON, and every language port runs the same file
// (see docs/PORTING.md → "Conformance vectors"). This mirrors the reference consumer
// packages/quran-engine-js/test/conformance.test.js.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// maddLazimMaddah is U+0653 ARABIC MADDAH ABOVE — the madd-lāzim mark whose
// presence in spelledOutArabic lets the tajweed pass colour the long vowels.
const maddLazimMaddah = "ٓ"

// conformanceVectors is the parsed shape of /conformance/vectors.json. Generic
// fields use pointers / interface{} so an absent JSON key is distinguishable from
// a zero value (mirrors the JS `v.empty`/`v.isNull`/`v.contains ?? []` checks).
type conformanceVectors struct {
	SearchVerses []struct {
		Query    string   `json:"query"`
		Empty    bool     `json:"empty"`
		Contains []string `json:"contains"`
		Excludes []string `json:"excludes"`
	} `json:"searchVerses"`
	JuzFromEnd []struct {
		N  int  `json:"n"`
		ID *int `json:"id"`
	} `json:"juzFromEnd"`
	JuzStats []struct {
		Juz         int  `json:"juz"`
		IsNull      bool `json:"isNull"`
		SurahCount  int  `json:"surahCount"`
		AyahCount   int  `json:"ayahCount"`
		WordCount   int  `json:"wordCount"`
		LetterCount int  `json:"letterCount"`
		PageCount   int  `json:"pageCount"`
	} `json:"juzStats"`
	JuzStatsInvariant struct {
		SumAyahCountAllJuz int `json:"sumAyahCountAllJuz"`
	} `json:"juzStatsInvariant"`
	Tajweed []struct {
		Surah        int    `json:"surah"`
		Ayah         int    `json:"ayah"`
		ExcludesRule string `json:"excludesRule"`
		LastSpanRule string `json:"lastSpanRule"`
	} `json:"tajweed"`
	SurahFromEnd []struct {
		N  int  `json:"n"`
		ID *int `json:"id"`
	} `json:"surahFromEnd"`
	Sajdah struct {
		Count    int      `json:"count"`
		Contains []string `json:"contains"`
		Excludes []string `json:"excludes"`
	} `json:"sajdah"`
	SurahInfo []struct {
		Surah         int    `json:"surah"`
		MinSources    *int   `json:"minSources"`
		HasSourceName string `json:"hasSourceName"`
	} `json:"surahInfo"`
	NamesOfAllah struct {
		Count    int `json:"count"`
		ByNumber []struct {
			Number          int    `json:"number"`
			Transliteration string `json:"transliteration"`
		} `json:"byNumber"`
	} `json:"namesOfAllah"`
	FilterByCounts []struct {
		Ayahs *CountFilterVec `json:"ayahs"`
		Pages *CountFilterVec `json:"pages"`
		IDs   []int           `json:"ids"`
	} `json:"filterByCounts"`
	SurahFlags []struct {
		Surah       int  `json:"surah"`
		PageChanges bool `json:"pageChanges"`
		JuzChanges  bool `json:"juzChanges"`
		PageOrJuz   bool `json:"pageOrJuz"`
	} `json:"surahFlags"`
	ExistsInQiraah []struct {
		Surah   int    `json:"surah"`
		Ayah    int    `json:"ayah"`
		Riwayah string `json:"riwayah"`
		Exists  bool   `json:"exists"`
	} `json:"existsInQiraah"`
	NumberOfAyahsInQiraah []struct {
		Surah   int    `json:"surah"`
		Riwayah string `json:"riwayah"`
		Count   int    `json:"count"`
	} `json:"numberOfAyahsInQiraah"`
	Muqattaat struct {
		Count         int `json:"count"`
		Pronunciations []struct {
			Surah                int    `json:"surah"`
			Ayah                 int    `json:"ayah"`
			Transliteration      string `json:"transliteration"`
			SpelledContainsMaddah bool   `json:"spelledContainsMaddah"`
		} `json:"pronunciations"`
		Absent []struct {
			Surah int `json:"surah"`
			Ayah  int `json:"ayah"`
		} `json:"absent"`
	} `json:"muqattaat"`
}

// CountFilterVec is the JSON shape of a count predicate in the conformance vectors.
type CountFilterVec struct {
	Op    string `json:"op"`
	Value int    `json:"value"`
}

// toCountFilter converts the vector shape into the engine's *CountFilter.
func (c *CountFilterVec) toCountFilter() *CountFilter {
	if c == nil {
		return nil
	}
	return &CountFilter{Op: c.Op, Value: c.Value}
}

// loadConformanceVectors finds /conformance/vectors.json. The conformance file is a
// sibling of data/, i.e. <repoRoot>/conformance/vectors.json; repoRoot is the parent
// of the data dir located by the package's existing discovery walk.
func loadConformanceVectors(t *testing.T) conformanceVectors {
	t.Helper()
	dataDir, err := FindDataDir()
	if err != nil {
		t.Fatalf("locating data dir: %v", err)
	}
	repoRoot := filepath.Dir(dataDir)
	path := filepath.Join(repoRoot, "conformance", "vectors.json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	var v conformanceVectors
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatalf("parsing %s: %v", path, err)
	}
	return v
}

func TestConformanceSearchVerses(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.SearchVerses {
		hits := e.SearchVerses(v.Query, SearchOptions{})
		if v.Empty && len(hits) != 0 {
			t.Errorf("%q should be empty, got %d hits", v.Query, len(hits))
		}
		for _, id := range v.Contains {
			s, a := parseVectorID(t, id)
			if !hasMatch(hits, s, a) {
				t.Errorf("%q should contain %s", v.Query, id)
			}
		}
		for _, id := range v.Excludes {
			s, a := parseVectorID(t, id)
			if hasMatch(hits, s, a) {
				t.Errorf("%q should exclude %s", v.Query, id)
			}
		}
	}
}

func TestConformanceJuzFromEnd(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.JuzFromEnd {
		j := e.JuzFromEnd(v.N)
		if v.ID == nil {
			if j != nil {
				t.Errorf("JuzFromEnd(%d) = %+v, want nil", v.N, j)
			}
			continue
		}
		if j == nil || j.ID != *v.ID {
			t.Errorf("JuzFromEnd(%d) = %+v, want id=%d", v.N, j, *v.ID)
		}
	}
}

func TestConformanceJuzStats(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.JuzStats {
		s := e.JuzStatsFor(v.Juz)
		if v.IsNull {
			if s != nil {
				t.Errorf("JuzStatsFor(%d) should be nil, got %+v", v.Juz, s)
			}
			continue
		}
		if s == nil {
			t.Errorf("JuzStatsFor(%d) = nil, want stats", v.Juz)
			continue
		}
		if s.SurahCount != v.SurahCount {
			t.Errorf("JuzStatsFor(%d).SurahCount = %d, want %d", v.Juz, s.SurahCount, v.SurahCount)
		}
		if s.AyahCount != v.AyahCount {
			t.Errorf("JuzStatsFor(%d).AyahCount = %d, want %d", v.Juz, s.AyahCount, v.AyahCount)
		}
		if s.WordCount != v.WordCount {
			t.Errorf("JuzStatsFor(%d).WordCount = %d, want %d", v.Juz, s.WordCount, v.WordCount)
		}
		if s.LetterCount != v.LetterCount {
			t.Errorf("JuzStatsFor(%d).LetterCount = %d, want %d", v.Juz, s.LetterCount, v.LetterCount)
		}
		if s.PageCount != v.PageCount {
			t.Errorf("JuzStatsFor(%d).PageCount = %d, want %d", v.Juz, s.PageCount, v.PageCount)
		}
	}
	sum := 0
	for i := 1; i <= 30; i++ {
		s := e.JuzStatsFor(i)
		if s == nil {
			t.Fatalf("JuzStatsFor(%d) = nil", i)
		}
		sum += s.AyahCount
	}
	if sum != vectors.JuzStatsInvariant.SumAyahCountAllJuz {
		t.Errorf("sum of juz ayah counts = %d, want %d", sum, vectors.JuzStatsInvariant.SumAyahCountAllJuz)
	}
}

func TestConformanceTajweed(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.Tajweed {
		spans := e.TajweedSpans(v.Surah, v.Ayah)
		if v.ExcludesRule != "" {
			for _, sp := range spans {
				if sp.Rule == v.ExcludesRule {
					t.Errorf("%d:%d should NOT have rule %q", v.Surah, v.Ayah, v.ExcludesRule)
					break
				}
			}
		}
		if v.LastSpanRule != "" {
			if len(spans) == 0 {
				t.Errorf("%d:%d has no spans, want last span rule %q", v.Surah, v.Ayah, v.LastSpanRule)
				continue
			}
			last := spans[0]
			for _, sp := range spans[1:] {
				if sp.Start > last.Start {
					last = sp
				}
			}
			if last.Rule != v.LastSpanRule {
				t.Errorf("%d:%d last span rule = %q, want %q", v.Surah, v.Ayah, last.Rule, v.LastSpanRule)
			}
		}
	}
}

func TestConformanceSurahFromEnd(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.SurahFromEnd {
		s := e.SurahFromEnd(v.N)
		if v.ID == nil {
			if s != nil {
				t.Errorf("SurahFromEnd(%d) = %+v, want nil", v.N, s)
			}
			continue
		}
		if s == nil || s.ID != *v.ID {
			t.Errorf("SurahFromEnd(%d) = %+v, want id=%d", v.N, s, *v.ID)
		}
	}
}

func TestConformanceSajdah(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	sj := vectors.Sajdah
	refs := e.SajdahAyahs()
	if len(refs) != sj.Count {
		t.Errorf("SajdahAyahs() count = %d, want %d", len(refs), sj.Count)
	}
	has := func(surah, ayah int) bool {
		for _, r := range refs {
			if r.Surah.ID == surah && r.Ayah.ID == ayah {
				return true
			}
		}
		return false
	}
	for _, id := range sj.Contains {
		s, a := parseVectorID(t, id)
		if !has(s, a) {
			t.Errorf("sajdah should contain %s", id)
		}
		if !e.IsSajdahAyah(s, a) {
			t.Errorf("IsSajdahAyah(%s) = false, want true", id)
		}
	}
	for _, id := range sj.Excludes {
		s, a := parseVectorID(t, id)
		if e.IsSajdahAyah(s, a) {
			t.Errorf("IsSajdahAyah(%s) = true, want false", id)
		}
	}
}

func TestConformanceSurahInfo(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.SurahInfo {
		sources := e.SurahInfo(v.Surah)
		min := 1
		if v.MinSources != nil {
			min = *v.MinSources
		}
		if len(sources) < min {
			t.Errorf("SurahInfo(%d) has %d sources, want >= %d", v.Surah, len(sources), min)
		}
		if v.HasSourceName != "" {
			found := false
			for _, s := range sources {
				if s.Name == v.HasSourceName {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("SurahInfo(%d) should have source %q", v.Surah, v.HasSourceName)
			}
		}
	}
}

func TestConformanceNamesOfAllah(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	if got := len(e.NamesOfAllah()); got != vectors.NamesOfAllah.Count {
		t.Errorf("NamesOfAllah() count = %d, want %d", got, vectors.NamesOfAllah.Count)
	}
	for _, v := range vectors.NamesOfAllah.ByNumber {
		n := e.NameOfAllah(v.Number)
		if n == nil {
			t.Errorf("NameOfAllah(%d) = nil, want %q", v.Number, v.Transliteration)
			continue
		}
		if n.Transliteration != v.Transliteration {
			t.Errorf("NameOfAllah(%d).Transliteration = %q, want %q", v.Number, n.Transliteration, v.Transliteration)
		}
	}
}

func TestConformanceFilterByCounts(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.FilterByCounts {
		got := FilterByCounts(e.Surahs(), v.Ayahs.toCountFilter(), v.Pages.toCountFilter())
		gotIDs := make([]int, 0, len(got))
		for _, s := range got {
			gotIDs = append(gotIDs, s.ID)
		}
		sort.Ints(gotIDs)
		wantIDs := append([]int(nil), v.IDs...)
		sort.Ints(wantIDs)
		if len(gotIDs) != len(wantIDs) {
			t.Errorf("FilterByCounts %+v: got ids %v, want %v", v, gotIDs, wantIDs)
			continue
		}
		for i := range gotIDs {
			if gotIDs[i] != wantIDs[i] {
				t.Errorf("FilterByCounts %+v: got ids %v, want %v", v, gotIDs, wantIDs)
				break
			}
		}
	}
}

func TestConformanceSurahFlags(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.SurahFlags {
		if got := e.PageChangesWithinSurah(v.Surah); got != v.PageChanges {
			t.Errorf("PageChangesWithinSurah(%d) = %v, want %v", v.Surah, got, v.PageChanges)
		}
		if got := e.JuzChangesWithinSurah(v.Surah); got != v.JuzChanges {
			t.Errorf("JuzChangesWithinSurah(%d) = %v, want %v", v.Surah, got, v.JuzChanges)
		}
		if got := e.PageOrJuzChangesWithinSurah(v.Surah); got != v.PageOrJuz {
			t.Errorf("PageOrJuzChangesWithinSurah(%d) = %v, want %v", v.Surah, got, v.PageOrJuz)
		}
	}
}

func TestConformanceExistsInQiraah(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.ExistsInQiraah {
		if got := e.ExistsInQiraah(v.Surah, v.Ayah, v.Riwayah); got != v.Exists {
			t.Errorf("ExistsInQiraah(%d, %d, %q) = %v, want %v", v.Surah, v.Ayah, v.Riwayah, got, v.Exists)
		}
	}
}

func TestConformanceNumberOfAyahsInQiraah(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	for _, v := range vectors.NumberOfAyahsInQiraah {
		if got := e.NumberOfAyahsInQiraah(v.Surah, v.Riwayah); got != v.Count {
			t.Errorf("NumberOfAyahsInQiraah(%d, %q) = %d, want %d", v.Surah, v.Riwayah, got, v.Count)
		}
	}
}

func TestConformanceMuqattaat(t *testing.T) {
	e := loadTestEngine(t)
	vectors := loadConformanceVectors(t)
	m := vectors.Muqattaat
	if got := len(e.Muqattaat()); got != m.Count {
		t.Errorf("Muqattaat() count = %d, want %d", got, m.Count)
	}
	for _, p := range m.Pronunciations {
		got := e.MuqattaatFor(p.Surah, p.Ayah)
		if got == nil {
			t.Errorf("MuqattaatFor(%d:%d) = nil, want present", p.Surah, p.Ayah)
			continue
		}
		if got.Transliteration != p.Transliteration {
			t.Errorf("MuqattaatFor(%d:%d).Transliteration = %q, want %q", p.Surah, p.Ayah, got.Transliteration, p.Transliteration)
		}
		if p.SpelledContainsMaddah && !strings.Contains(got.SpelledOutArabic, maddLazimMaddah) {
			t.Errorf("MuqattaatFor(%d:%d) spelledOutArabic should keep madd-lāzim maddah", p.Surah, p.Ayah)
		}
	}
	for _, a := range m.Absent {
		if got := e.MuqattaatFor(a.Surah, a.Ayah); got != nil {
			t.Errorf("MuqattaatFor(%d:%d) = %+v, want nil", a.Surah, a.Ayah, got)
		}
	}
}

// parseVectorID splits a "surah:ayah" vector id into its two integer components.
func parseVectorID(t *testing.T, id string) (int, int) {
	t.Helper()
	colon := -1
	for i := 0; i < len(id); i++ {
		if id[i] == ':' {
			colon = i
			break
		}
	}
	if colon < 0 {
		t.Fatalf("malformed vector id %q (want surah:ayah)", id)
	}
	surah := atoiOrFail(t, id[:colon], id)
	ayah := atoiOrFail(t, id[colon+1:], id)
	return surah, ayah
}

func atoiOrFail(t *testing.T, s, id string) int {
	t.Helper()
	n := 0
	if len(s) == 0 {
		t.Fatalf("malformed vector id %q", id)
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			t.Fatalf("malformed vector id %q", id)
		}
		n = n*10 + int(r-'0')
	}
	return n
}
