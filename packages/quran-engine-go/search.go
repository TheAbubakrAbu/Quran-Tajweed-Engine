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
	surah              int
	ayah               int
	arabicTashkeelBlob string
	englishExactBlob   string
	arabicBlob         string
	silentArabicBlob   string
	englishBlob        string
	arabicTokens       []string
	silentArabicTokens []string
	englishTok         []string
}

// matchMode is one of the five boolean per-term matching modes.
type matchMode int

const (
	modeContains matchMode = iota
	modeStartsWith
	modeEndsWith
	modeExact
	modeWholeWord
)

// surahEntry is a pre-folded index row for one surah's searchable names.
type surahEntry struct {
	surah   *Surah
	blob    string
	compact string
	upper   string
}

// searchIndex holds the folded blobs for verse and surah search. Built at Load.
//
// This is the search path described in docs/PORTING.md: regular verse search is
// pure substring matching in mushaf order; digit-bearing queries are rejected;
// surah lookup is by name / number / "2:255" reference / makkan-madani. The
// boolean grammar (& | ! # ^ % $ =) from the JS reference is also implemented.
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
		silentArabicBlob := cleanSearch(removingSilentArabicLettersForSearch(raw)) + " " +
			cleanSearch(removingSilentArabicLettersForSearch(clean))
		englishBlob := strings.TrimSpace(
			cleanSearch(a.TextEnglishSaheeh) + " " +
				cleanSearch(a.TextEnglishMustafa) + " " +
				cleanSearch(a.TextTransliteration))
		englishExactBlob := exactPhraseBlob(
			a.TextEnglishSaheeh + " " + a.TextEnglishMustafa + " " + a.TextTransliteration)
		si.verses = append(si.verses, verseEntry{
			surah:              s.ID,
			ayah:               a.ID,
			arabicTashkeelBlob: arabicTashkeelBlob(raw),
			englishExactBlob:   englishExactBlob,
			arabicBlob:         arabicBlob,
			silentArabicBlob:   silentArabicBlob,
			englishBlob:        englishBlob,
			arabicTokens:       searchTokens(arabicBlob),
			silentArabicTokens: searchTokens(silentArabicBlob),
			englishTok:         searchTokens(englishBlob),
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

// SearchOptions controls verse-search pagination and the lenient Arabic variant.
type SearchOptions struct {
	Offset int
	Limit  int // 0 means no limit
	// IgnoreSilentLetters enables the lenient Arabic search variant: silent
	// Arabic letters are dropped from both query and verse text before matching.
	IgnoreSilentLetters bool
}

// SearchVerses matches verse text and returns hits in mushaf order (unranked).
//
// Regular (non-boolean) search is PURE SUBSTRING: a verse matches when the whole
// cleaned query is a substring of the verse blob. Arabic vs English is chosen by
// whether the query contains Arabic letters. Any query containing a digit is
// rejected (returns nil) before the boolean branch is even considered — so even a
// boolean query with a digit returns nil. The boolean grammar (& | ! # ^ % $ =)
// goes through booleanSearch.
func (e *Engine) SearchVerses(query string, opts SearchOptions) []VerseMatch {
	cleaned := cleanSearch(query)
	if cleaned == "" {
		return nil
	}
	// Reject any query containing a digit (numeric/refs go via surah search). Done
	// BEFORE the boolean path so even a boolean query with a digit returns nil.
	if hasDigit(cleaned) {
		return nil
	}

	// Boolean grammar?
	if strings.ContainsAny(query, "&|!#^%$=") {
		return e.booleanSearch(query, opts)
	}

	useArabic := containsArabicLetters(query)
	silentQuery := ""
	if useArabic && opts.IgnoreSilentLetters {
		silentQuery = cleanSearch(removingSilentArabicLettersForSearch(query))
	}

	var hits []VerseMatch
	for i := range e.search.verses {
		v := &e.search.verses[i]
		var ok bool
		if useArabic {
			ok = strings.Contains(v.arabicBlob, cleaned)
			if !ok && silentQuery != "" {
				ok = strings.Contains(v.silentArabicBlob, silentQuery)
			}
		} else {
			ok = strings.Contains(v.englishBlob, cleaned)
		}
		if ok {
			hits = append(hits, VerseMatch{Surah: v.surah, Ayah: v.ayah})
		}
	}
	return paginate(hits, opts)
}

// booleanTerm is one parsed term of a boolean query.
type booleanTerm struct {
	value                     string
	negate                    bool
	mode                      matchMode
	requiresTashkeelMatch     bool
	tashkeelPattern           string
	requiresExactEnglishMatch bool
	exactEnglishPhrase        string
}

// booleanSearch evaluates the boolean grammar (OR of AND-groups). Mirrors
// _booleanSearch in search.js.
func (e *Engine) booleanSearch(query string, opts SearchOptions) []VerseMatch {
	useArabic := containsArabicLetters(query)
	normalized := strings.ReplaceAll(query, "&&", "&")
	normalized = strings.ReplaceAll(normalized, "||", "|")

	// OR groups of AND terms; drop terms whose cleaned value is empty, then drop
	// empty groups.
	var orGroups [][]booleanTerm
	for _, group := range strings.Split(normalized, "|") {
		var andTerms []booleanTerm
		for _, t := range strings.Split(group, "&") {
			term := parseTerm(t)
			if term.value != "" {
				andTerms = append(andTerms, term)
			}
		}
		if len(andTerms) > 0 {
			orGroups = append(orGroups, andTerms)
		}
	}
	if len(orGroups) == 0 {
		return nil
	}

	var hits []VerseMatch
	for i := range e.search.verses {
		v := &e.search.verses[i]
		matched := false
		for _, andTerms := range orGroups {
			all := true
			for j := range andTerms {
				hit := termMatch(v, &andTerms[j], useArabic)
				if andTerms[j].negate {
					hit = !hit
				}
				if !hit {
					all = false
					break
				}
			}
			if all {
				matched = true
				break
			}
		}
		if matched {
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

// consecutiveTokenMatch reports whether query tokens appear as a consecutive run
// of haystack tokens. Leading tokens must match exactly; the final token must
// match exactly when lastMustBeExact, otherwise it only has to be a prefix.
// Mirrors consecutiveTokenMatch() in search.js.
func consecutiveTokenMatch(haystack, query []string, lastMustBeExact bool) bool {
	if len(query) == 0 || len(haystack) < len(query) {
		return false
	}
	for start := 0; start <= len(haystack)-len(query); start++ {
		ok := true
		for k := 0; k < len(query); k++ {
			word, term := haystack[start+k], query[k]
			if k == len(query)-1 && !lastMustBeExact {
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

// parseTerm parses a single boolean term. Strips (in order) leading `!` (negate,
// toggles), `#` (requiresTashkeel), `=` (wholeWord), one `^` (startsWith), one
// trailing `%`/`$` (endsWith); the leftover text becomes the value plus the
// tashkeel / exact-phrase patterns. Mirrors parseTerm() in search.js.
func parseTerm(rawTerm string) booleanTerm {
	t := strings.TrimSpace(rawTerm)
	negate := false
	for strings.HasPrefix(t, "!") {
		negate = !negate
		t = strings.TrimSpace(t[1:])
	}
	requiresTashkeel := false
	for strings.HasPrefix(t, "#") {
		requiresTashkeel = true
		t = strings.TrimSpace(t[1:])
	}
	wholeWord := false
	for strings.HasPrefix(t, "=") {
		wholeWord = true
		t = strings.TrimSpace(t[1:])
	}
	startsWith := false
	if strings.HasPrefix(t, "^") {
		startsWith = true
		t = strings.TrimSpace(t[1:])
	}
	endsWith := false
	if strings.HasSuffix(t, "%") || strings.HasSuffix(t, "$") {
		endsWith = true
		t = strings.TrimSpace(t[:len(t)-1])
	}

	value := cleanSearch(t)
	var mode matchMode
	switch {
	case wholeWord:
		mode = modeWholeWord
	case startsWith && endsWith:
		mode = modeExact
	case startsWith:
		mode = modeStartsWith
	case endsWith:
		mode = modeEndsWith
	default:
		mode = modeContains
	}

	isArabic := containsArabicLetters(t)
	return booleanTerm{
		value:                     value,
		negate:                    negate,
		mode:                      mode,
		requiresTashkeelMatch:     requiresTashkeel && isArabic,
		tashkeelPattern:           arabicTashkeelBlob(t),
		requiresExactEnglishMatch: requiresTashkeel && !isArabic,
		exactEnglishPhrase:        exactPhraseBlob(t),
	}
}

// anyTokenHasPrefix reports whether any token starts with term.
func anyTokenHasPrefix(tokens []string, term string) bool {
	for _, w := range tokens {
		if strings.HasPrefix(w, term) {
			return true
		}
	}
	return false
}

// anyTokenHasSuffix reports whether any token ends with term.
func anyTokenHasSuffix(tokens []string, term string) bool {
	for _, w := range tokens {
		if strings.HasSuffix(w, term) {
			return true
		}
	}
	return false
}

// anyTokenEquals reports whether any token equals term.
func anyTokenEquals(tokens []string, term string) bool {
	for _, w := range tokens {
		if w == term {
			return true
		}
	}
	return false
}

// ayahTermMatch matches a single term's value against a blob/token list under one
// of the five modes. Mirrors ayahTermMatch() in search.js.
func ayahTermMatch(haystack string, tokens []string, term string, mode matchMode) bool {
	switch mode {
	case modeStartsWith:
		return strings.HasPrefix(haystack, term) || anyTokenHasPrefix(tokens, term)
	case modeEndsWith:
		return strings.HasSuffix(haystack, term) || anyTokenHasSuffix(tokens, term)
	case modeExact:
		return haystack == term || anyTokenEquals(tokens, term)
	case modeWholeWord:
		return consecutiveTokenMatch(tokens, searchTokens(term), true)
	default: // modeContains
		return strings.Contains(haystack, term)
	}
}

// termMatch is the per-term (un-negated) match. Mirrors termMatch() in search.js.
func termMatch(v *verseEntry, term *booleanTerm, useArabic bool) bool {
	if useArabic && term.requiresTashkeelMatch {
		lettersMatch := ayahTermMatch(v.arabicBlob, v.arabicTokens, term.value, term.mode)
		tashkeelMatch := term.tashkeelPattern == "" || strings.Contains(v.arabicTashkeelBlob, term.tashkeelPattern)
		return lettersMatch && tashkeelMatch
	}
	if !useArabic && term.requiresExactEnglishMatch {
		if term.exactEnglishPhrase == "" {
			return false
		}
		exactTokens := searchTokens(term.exactEnglishPhrase)
		return ayahTermMatch(v.englishExactBlob, exactTokens, term.exactEnglishPhrase, term.mode)
	}
	if useArabic {
		return ayahTermMatch(v.arabicBlob, v.arabicTokens, term.value, term.mode)
	}
	return ayahTermMatch(v.englishBlob, v.englishTok, term.value, term.mode)
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
