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

// hasDigit reports whether s contains an ASCII digit.
func hasDigit(s string) bool {
	for _, ch := range s {
		if ch >= '0' && ch <= '9' {
			return true
		}
	}
	return false
}
