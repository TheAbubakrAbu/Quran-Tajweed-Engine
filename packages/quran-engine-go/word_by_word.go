package quranengine

// Word by word: what each word of an ayah means, and how it is said.
//
// Two layers over the SAME tokens — the English gloss and a Latin transliteration — where the
// tokens are the ayah's own whitespace-separated words. Split the ayah and index straight in; the
// alignment against a corpus that tokenizes ~200 ayahs differently was done once, at build time.
//
// A token with no word of its own (the ۞ ornament, the tail of a word the corpus writes as two)
// carries "" in both layers — show nothing for it rather than a neighbour's meaning.
//
// See ../../docs/12-word-by-word.md.

import (
	"strconv"
	"strings"
)

// WordByWordPack is data/word-by-word.json: surah id -> ayahs in id order -> one entry per token.
type WordByWordPack struct {
	English         map[string][][]string `json:"english"`
	Transliteration map[string][][]string `json:"transliteration"`
}

// GlossedWord is one word of an ayah, in reading order.
type GlossedWord struct {
	// Position is the 1-based index of the word in the ayah.
	Position int
	// Arabic is the ayah's own token.
	Arabic string
	// English is the gloss, "" when the token has none.
	English         string
	Transliteration string
}

// GlossHit is a hit from the word-level gloss search.
type GlossHit struct {
	Surah           int
	Ayah            int
	Position        int
	English         string
	Transliteration string
}

// WordByWordLoaded reports whether a pack is loaded at all — cheap enough to gate UI on.
func (e *Engine) WordByWordLoaded() bool {
	return len(e.wordByWord.English) > 0
}

// Words returns every word of an ayah, in reading order.
func (e *Engine) Words(surahID, ayahID int) []GlossedWord {
	english, ok := e.Glosses(surahID, ayahID)
	if !ok {
		return nil
	}
	latin, _ := e.Transliterations(surahID, ayahID)
	var tokens []string
	if ayah := e.Ayah(surahID, ayahID); ayah != nil {
		tokens = strings.Fields(ayah.TextArabic)
	}

	out := make([]GlossedWord, 0, len(english))
	for i, gloss := range english {
		word := GlossedWord{Position: i + 1, English: gloss}
		if i < len(tokens) {
			word.Arabic = tokens[i]
		}
		if i < len(latin) {
			word.Transliteration = latin[i]
		}
		out = append(out, word)
	}
	return out
}

// Word returns one word by its 1-based position.
func (e *Engine) Word(surahID, ayahID, position int) *GlossedWord {
	words := e.Words(surahID, ayahID)
	if position < 1 || position > len(words) {
		return nil
	}
	return &words[position-1]
}

// Glosses returns the English layer for an ayah. The second result is false when the pack has no
// row for it, which is not the same as an ayah every one of whose tokens is unglossed.
func (e *Engine) Glosses(surahID, ayahID int) ([]string, bool) {
	return layerRow(e.wordByWord.English, surahID, ayahID)
}

// Transliterations returns the Latin layer, aligned token for token with Glosses.
func (e *Engine) Transliterations(surahID, ayahID int) ([]string, bool) {
	return layerRow(e.wordByWord.Transliteration, surahID, ayahID)
}

// FindGloss lists ayahs containing a word whose gloss carries term — a word-level English search,
// which finds ayahs a translation search misses because no translator used that phrasing.
func (e *Engine) FindGloss(term string, limit int) []GlossHit {
	needle := strings.ToLower(strings.TrimSpace(term))
	if needle == "" {
		return nil
	}
	var out []GlossHit
	// Mushaf order, so the result is stable across runs (map iteration is not).
	for i := range e.surahs {
		surah := &e.surahs[i]
		rows, ok := e.wordByWord.English[strconv.Itoa(surah.ID)]
		if !ok {
			continue
		}
		for ayahIndex, glosses := range rows {
			for index, gloss := range glosses {
				if !strings.Contains(strings.ToLower(gloss), needle) {
					continue
				}
				latin := ""
				if latinRows, ok := e.wordByWord.Transliteration[strconv.Itoa(surah.ID)]; ok &&
					ayahIndex < len(latinRows) && index < len(latinRows[ayahIndex]) {
					latin = latinRows[ayahIndex][index]
				}
				out = append(out, GlossHit{
					Surah:           surah.ID,
					Ayah:            ayahIndex + 1,
					Position:        index + 1,
					English:         gloss,
					Transliteration: latin,
				})
				if limit > 0 && len(out) >= limit {
					return out
				}
			}
		}
	}
	return out
}

func layerRow(layer map[string][][]string, surahID, ayahID int) ([]string, bool) {
	rows, ok := layer[strconv.Itoa(surahID)]
	if !ok || ayahID < 1 || ayahID > len(rows) {
		return nil, false
	}
	return rows[ayahID-1], true
}
