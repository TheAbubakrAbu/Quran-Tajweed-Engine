package quranengine

import "unicode/utf16"

// utf16Slice returns the substring of text covering the UTF-16 code-unit range
// [start, end). Go strings are UTF-8/byte indexed, while the annotation offsets
// are UTF-16, so we encode to UTF-16 units, slice, then decode back.
func utf16Slice(text string, start, end int) string {
	units := utf16.Encode([]rune(text))
	if start < 0 {
		start = 0
	}
	if end > len(units) {
		end = len(units)
	}
	if start >= end {
		return ""
	}
	return string(utf16.Decode(units[start:end]))
}

// TajweedSpans returns the colored tajweed spans for an ayah, built from the
// pre-computed annotation corpus (strategy A in docs/PORTING.md). Each span's
// Text is the reconstructed UTF-16 slice of the ayah's Arabic text and ColorHex
// is the rule's color from tajweed-rules.json. Returns nil when there are no
// annotations (or when tajweed-annotations.json was not loaded).
func (e *Engine) TajweedSpans(surahID, ayahID int) []TajweedSpan {
	if e.annotByKey == nil {
		return nil
	}
	anns := e.annotByKey[[2]int{surahID, ayahID}]
	if len(anns) == 0 {
		return nil
	}
	text := e.ArabicText(surahID, ayahID, "")
	units := utf16.Encode([]rune(text))

	out := make([]TajweedSpan, 0, len(anns))
	for _, a := range anns {
		start, end := a.Start, a.End
		if start < 0 {
			start = 0
		}
		if end > len(units) {
			end = len(units)
		}
		var sub string
		if start < end {
			sub = string(utf16.Decode(units[start:end]))
		}
		out = append(out, TajweedSpan{
			Start:    a.Start,
			End:      a.End,
			Rule:     a.Rule,
			ColorHex: e.ruleColors[a.Rule],
			Text:     sub,
		})
	}
	return out
}

// RuleColor returns the color hex registered for a tajweed rule id, or "".
func (e *Engine) RuleColor(rule string) string { return e.ruleColors[rule] }
