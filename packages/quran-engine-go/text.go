package quranengine

import (
	"strings"
	"unicode"
)

// canonicalArabicMap folds hamza/alif/waw/yaa variants before mark stripping.
// Mirrors Settings.canonicalArabicSearchMap in the reference engine.
var canonicalArabicMap = map[rune]string{
	'ٰ': "ا", // dagger alif
	'ٱ': "ا", // alif wasla
	'أ': "ا", 'إ': "ا", 'آ': "ا", 'ٲ': "ا", 'ٳ': "ا", 'ٵ': "ا",
	'ؤ': "و", 'ئ': "ي", 'ء': "", 'ٴ': "", 'ٶ': "و", 'ٷ': "و", 'ٸ': "ي",
	'ۥ': "و", // small waw
	'ۦ': "ي", // small yeh
	'ى': "ا", // alif maqsura -> alif
	'ة': "ه", // teh marbuta -> heh
}

// keptOperators survive the unwanted-character strip in cleanSearch.
var keptOperators = map[rune]bool{'&': true, '|': true, '!': true, '#': true}

// removingArabicDiacriticsAndSigns strips Quranic recitation marks / diacritics,
// producing the "clean Arabic" used for display and search.
func removingArabicDiacriticsAndSigns(text string) string {
	var b strings.Builder
	for _, ch := range text {
		cp := int(ch)
		if cp == 0x0671 {
			b.WriteRune('ا') // hamzat wasl -> alif
			continue
		}
		if (cp >= 0x064b && cp <= 0x065f) ||
			(cp >= 0x06d6 && cp <= 0x06ed) ||
			cp == 0x0670 || cp == 0x0657 || cp == 0x0674 || cp == 0x0656 {
			continue
		}
		b.WriteRune(ch)
	}
	return b.String()
}

// removingArabicMarks strips the marks the surah-name search treats as noise.
func removingArabicMarks(text string) string {
	var b strings.Builder
	for _, ch := range text {
		cp := int(ch)
		if cp == 0x0640 ||
			(cp >= 0x0610 && cp <= 0x061a) ||
			(cp >= 0x064b && cp <= 0x065f) ||
			(cp >= 0x06d6 && cp <= 0x06ed) {
			continue
		}
		b.WriteRune(ch)
	}
	return b.String()
}

// arabicDigitsToWestern converts Arabic-Indic and Eastern-Arabic digits to Western.
func arabicDigitsToWestern(text string) string {
	var b strings.Builder
	for _, ch := range text {
		switch {
		case ch >= '٠' && ch <= '٩': // Arabic-Indic 0..9
			b.WriteRune('0' + (ch - '٠'))
		case ch >= '۰' && ch <= '۹': // Extended Arabic-Indic 0..9
			b.WriteRune('0' + (ch - '۰'))
		default:
			b.WriteRune(ch)
		}
	}
	return b.String()
}

// collapsingWhitespace collapses runs of whitespace into single spaces.
func collapsingWhitespace(text string) string {
	return strings.Join(strings.Fields(text), " ")
}

// cleanSearch is the core search normalizer: fold Arabic carriers, strip
// punctuation/symbols/combining-marks (keeping & | ! #), lowercase, collapse
// whitespace. Mirrors Settings.cleanSearch with whitespace trimming enabled.
func cleanSearch(text string) string {
	// 1. canonical Arabic fold
	var folded strings.Builder
	for _, ch := range text {
		if rep, ok := canonicalArabicMap[ch]; ok {
			folded.WriteString(rep)
		} else {
			folded.WriteRune(ch)
		}
	}
	// 2. strip unwanted chars (P, S, M) except kept operators
	var cleaned strings.Builder
	for _, ch := range folded.String() {
		if keptOperators[ch] {
			cleaned.WriteRune(ch)
			continue
		}
		if unicode.IsPunct(ch) || unicode.IsSymbol(ch) || unicode.IsMark(ch) {
			continue
		}
		cleaned.WriteRune(ch)
	}
	return strings.TrimSpace(collapsingWhitespace(strings.ToLower(cleaned.String())))
}

// searchTokens splits a cleaned blob on spaces, dropping empties.
func searchTokens(cleaned string) []string {
	return strings.Fields(cleaned)
}

// tashkeelRanges are the combining-mark ranges that count as Arabic "tashkeel"
// (diacritics) for the search normalizer. Mirrors TASHKEEL_RANGES in text.js.
var tashkeelRanges = [][2]int{
	{0x0610, 0x061a},
	{0x064b, 0x065f},
	{0x0670, 0x0670},
	{0x06d6, 0x06ed},
}

func inTashkeel(cp int) bool {
	for _, r := range tashkeelRanges {
		if cp >= r[0] && cp <= r[1] {
			return true
		}
	}
	return false
}

// arabicTashkeelBlob keeps ONLY tashkeel scalars (inverse of cleanSearch).
// Mirrors arabicTashkeelBlob() in text.js.
func arabicTashkeelBlob(text string) string {
	var b strings.Builder
	for _, ch := range text {
		if inTashkeel(int(ch)) {
			b.WriteRune(ch)
		}
	}
	return b.String()
}

// exactPhraseBlob lowercases + whitespace-collapses without stripping marks.
// Mirrors exactPhraseBlob() in text.js.
func exactPhraseBlob(text string) string {
	return collapsingWhitespace(strings.ToLower(text))
}

// silentVowels are the diacritics that keep a carrier letter "voiced" so it is
// NOT dropped by removingSilentArabicLettersForSearch.
var silentVowels = map[rune]bool{
	0x064e: true, 0x064f: true, 0x0650: true, 0x064b: true, 0x064c: true,
	0x064d: true, 0x0656: true, 0x0657: true, 0x065a: true,
}

// splitGraphemeClusters splits text into base-letter + trailing combining marks.
// Combining-mark fallback that is sufficient for Arabic Quranic text. Mirrors
// the fallback branch of splitGraphemeClusters() in text.js.
func splitGraphemeClusters(text string) []string {
	var out []string
	for _, ch := range text {
		if len(out) > 0 && unicode.IsMark(ch) {
			out[len(out)-1] += string(ch)
		} else {
			out = append(out, string(ch))
		}
	}
	return out
}

// removingSilentArabicLettersForSearch drops "silent" Arabic letters for the
// lenient Arabic search variant. Mirrors removingSilentArabicLettersForSearch().
func removingSilentArabicLettersForSearch(text string) string {
	var out strings.Builder
	for _, cluster := range splitGraphemeClusters(text) {
		runes := []rune(cluster)
		if len(runes) == 0 {
			continue
		}
		base := runes[0]
		has := func(cp rune) bool {
			for _, r := range runes {
				if r == cp {
					return true
				}
			}
			return false
		}
		hasStdSukoon := has(0x0652) && !has(0x06e1)
		// hamzatul wasl is always silent
		if base == 0x0671 {
			continue
		}
		// alif/waw/ya/alif-maqsura with a plain sukoon
		if (base == 0x0627 || base == 0x0648 || base == 0x064a || base == 0x0649) && hasStdSukoon {
			continue
		}
		// lam with a plain sukoon
		if base == 0x0644 && hasStdSukoon {
			continue
		}
		// waw carrying a dagger alif with no vowel/shadda/sukoon
		if base == 0x0648 && has(0x0670) {
			voiced := false
			for _, r := range runes {
				if silentVowels[r] || r == 0x0651 || r == 0x0652 {
					voiced = true
					break
				}
			}
			if !voiced {
				continue
			}
		}
		out.WriteString(cluster)
	}
	return out.String()
}

var arabicLetterRanges = [][2]int{
	{0x0600, 0x06ff}, {0x0750, 0x077f}, {0x08a0, 0x08ff},
	{0xfb50, 0xfdff}, {0xfe70, 0xfeff}, {0x1ee00, 0x1eeff},
}

// containsArabicLetters reports whether the string has any Arabic-script letter.
func containsArabicLetters(text string) bool {
	for _, ch := range text {
		cp := int(ch)
		for _, r := range arabicLetterRanges {
			if cp >= r[0] && cp <= r[1] {
				return true
			}
		}
	}
	return false
}

// hasDigit reports whether s contains any Unicode decimal digit (category Nd),
// which catches Arabic-Indic digits too. Mirrors the /\p{Nd}/u test in search.js.
func hasDigit(s string) bool {
	for _, ch := range s {
		if unicode.IsDigit(ch) {
			return true
		}
	}
	return false
}
