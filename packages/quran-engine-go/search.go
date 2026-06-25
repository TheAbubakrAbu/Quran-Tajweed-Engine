package quranengine

import (
	"strconv"
	"strings"
)

// VerseMatch is one verse hit from SearchVerses, in mushaf order.
type VerseMatch struct {
	Surah int `json:"surah"`
	Ayah  int `json:"ayah"`
}

// verseEntry is a pre-folded index row for one ayah.
type verseEntry struct {
	surah        int
	ayah         int
	arabicBlob   string
	englishBlob  string
	arabicTokens []string
	englishTok   []string
}

// surahEntry is a pre-folded index row for one surah's searchable names.
type surahEntry struct {
	surah   *Surah
	blob    string
	compact string
	upper   string
}

// searchIndex holds the folded blobs for verse and surah search. Built at Load.
//
// This is the "core" search path described in docs/PORTING.md: folded substring
// matching plus phrase-prefix token matching, mushaf order, digit rejection on
// verse queries, and surah lookup by name / number / "2:255" reference /
// makkan-madani. The boolean grammar (& | ! # ^ % $) from the JS reference is
// intentionally omitted; document this in the README.
type searchIndex struct {
	verses []verseEntry
	surahs []surahEntry
}

func newSearchIndex(e *Engine) *searchIndex {
	si := &searchIndex{}
	e.EachAyah(func(s *Surah, a *Ayah) bool {
		raw := a.TextArabic
		clean := removingArabicDiacriticsAndSigns(raw)
		arabicBlob := cleanSearch(raw) + " " + cleanSearch(clean)
		englishBlob := strings.TrimSpace(
			cleanSearch(a.TextEnglishSaheeh) + " " +
				cleanSearch(a.TextEnglishMustafa) + " " +
				cleanSearch(a.TextTransliteration))
		si.verses = append(si.verses, verseEntry{
			surah:        s.ID,
			ayah:         a.ID,
			arabicBlob:   arabicBlob,
			englishBlob:  englishBlob,
			arabicTokens: searchTokens(arabicBlob),
			englishTok:   searchTokens(englishBlob),
		})
		return true
	})
	for i := range e.surahs {
		s := &e.surahs[i]
		names := append([]string{s.NameArabic, s.NameTransliteration, s.NameEnglish}, s.SimilarNames...)
		names = append(names, strconv.Itoa(s.ID), removingArabicMarks(s.NameArabic))
		blob := cleanSearch(strings.Join(names, " "))
		si.surahs = append(si.surahs, surahEntry{
			surah:   s,
			blob:    blob,
			compact: strings.ReplaceAll(blob, " ", ""),
			upper:   strings.ToUpper(s.NameEnglish + " " + s.NameTransliteration),
		})
	}
	return si
}

// SearchOptions controls verse-search pagination.
type SearchOptions struct {
	Offset int
	Limit  int // 0 means no limit
}

// SearchVerses matches verse text and returns hits in mushaf order (unranked).
//
// A verse matches when the whole cleaned query is a substring of the verse blob,
// OR the query tokens phrase-prefix-match the verse tokens. Arabic vs English is
// chosen by whether the query contains Arabic letters. Any query containing a
// digit is rejected (returns nil) — numeric/reference lookups go through
// SearchSurahs/ParseReference. The boolean grammar is not implemented.
func (e *Engine) SearchVerses(query string, opts SearchOptions) []VerseMatch {
	cleaned := cleanSearch(query)
	if cleaned == "" {
		return nil
	}
	if hasDigit(cleaned) {
		return nil
	}
	useArabic := containsArabicLetters(query)
	qTokens := searchTokens(cleaned)

	var hits []VerseMatch
	for i := range e.search.verses {
		v := &e.search.verses[i]
		var ok bool
		if useArabic {
			ok = strings.Contains(v.arabicBlob, cleaned) || phrasePrefixMatch(v.arabicTokens, qTokens)
		} else {
			ok = strings.Contains(v.englishBlob, cleaned) || phrasePrefixMatch(v.englishTok, qTokens)
		}
		if ok {
			hits = append(hits, VerseMatch{Surah: v.surah, Ayah: v.ayah})
		}
	}
	return paginate(hits, opts)
}

// SearchSurahs finds surahs by name, number, "2:255" reference, or makkan/madani.
// An empty query returns all surahs in mushaf order.
func (e *Engine) SearchSurahs(query string) []Surah {
	trimmed := strings.TrimSpace(query)
	if trimmed == "" {
		return e.Surahs()
	}

	norm := strings.ReplaceAll(cleanSearch(trimmed), " ", "")
	makkan := []string{"makkah", "makkan", "makki"}
	madinan := []string{"madinah", "madinan", "madina", "madani"}
	aliasHit := func(aliases []string) bool {
		for _, a := range aliases {
			if strings.HasPrefix(a, norm) || strings.HasPrefix(norm, a) {
				return true
			}
		}
		return false
	}
	if norm != "" && aliasHit(makkan) {
		return e.FilterByRevelationType("makkan")
	}
	if norm != "" && aliasHit(madinan) {
		return e.FilterByRevelationType("madinan")
	}

	ref := e.ParseReference(trimmed)
	cleaned := cleanSearch(strings.ReplaceAll(trimmed, ":", ""))
	compact := strings.ReplaceAll(cleaned, " ", "")
	upper := strings.ToUpper(trimmed)
	numeric := 0
	if ref != nil {
		numeric = ref.Surah
	} else if n, ok := toNumber(cleaned); ok {
		numeric = n
	}

	var out []Surah
	for i := range e.search.surahs {
		se := &e.search.surahs[i]
		match := (numeric != 0 && numeric == se.surah.ID) ||
			(se.upper != "" && strings.Contains(upper, se.upper)) ||
			(cleaned != "" && strings.Contains(se.blob, cleaned)) ||
			(compact != "" && strings.Contains(se.compact, compact))
		if match {
			out = append(out, *se.surah)
		}
	}
	return out
}

// ParseReference parses an ayah reference like "2:255", "2 255", or Arabic-digit
// forms (also resolving a surah name in the first component). Returns nil when no
// surah can be resolved. Ayah is 0 / HasAyah=false when absent.
func (e *Engine) ParseReference(query string) *Reference {
	parts := strings.FieldsFunc(arabicDigitsToWestern(query), func(r rune) bool {
		return r == ':' || r == ' ' || r == '\t' || r == '\n' || r == '\r'
	})
	if len(parts) == 0 {
		return nil
	}

	surah, ok := toNumber(parts[0])
	if !ok {
		cleaned := cleanSearch(parts[0])
		compact := strings.ReplaceAll(cleaned, " ", "")
		resolved := 0
		for i := range e.search.surahs {
			se := &e.search.surahs[i]
			if containsToken(se.blob, cleaned) || (compact != "" && strings.Contains(se.compact, compact)) {
				resolved = se.surah.ID
				break
			}
		}
		if resolved == 0 {
			return nil
		}
		surah = resolved
	}

	ref := &Reference{Surah: surah}
	if len(parts) >= 2 {
		if a, ok := toNumber(parts[1]); ok {
			ref.Ayah = a
			ref.HasAyah = true
		}
	}
	return ref
}

// --- helpers ---------------------------------------------------------------

// phrasePrefixMatch reports whether query tokens match a consecutive run of
// haystack tokens, all-but-last exact and the last a prefix.
func phrasePrefixMatch(haystack, query []string) bool {
	if len(query) == 0 || len(haystack) < len(query) {
		return false
	}
	for start := 0; start <= len(haystack)-len(query); start++ {
		ok := true
		for k := 0; k < len(query); k++ {
			word, term := haystack[start+k], query[k]
			if k == len(query)-1 {
				if !strings.HasPrefix(word, term) {
					ok = false
					break
				}
			} else if word != term {
				ok = false
				break
			}
		}
		if ok {
			return true
		}
	}
	return false
}

func paginate(arr []VerseMatch, opts SearchOptions) []VerseMatch {
	off := opts.Offset
	if off < 0 {
		off = 0
	}
	if off >= len(arr) {
		return nil
	}
	arr = arr[off:]
	if opts.Limit > 0 && opts.Limit < len(arr) {
		arr = arr[:opts.Limit]
	}
	return arr
}

func toNumber(s string) (int, bool) {
	t := strings.TrimSpace(arabicDigitsToWestern(s))
	if t == "" {
		return 0, false
	}
	n, err := strconv.Atoi(t)
	if err != nil {
		return 0, false
	}
	return n, true
}

// containsToken reports whether the space-separated blob contains target as a token.
func containsToken(blob, target string) bool {
	if target == "" {
		return false
	}
	for _, tok := range strings.Fields(blob) {
		if tok == target {
			return true
		}
	}
	return false
}
