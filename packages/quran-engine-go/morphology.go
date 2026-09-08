package quranengine

// Root and lemma of every word of the Quran: the Quranic Arabic Corpus morphology (Kais Dukes),
// as redistributed by the Quranic Universal Library. Mirrors src/morphology.js.
//
// The invariant, the same one word-by-word.json keeps: one id per whitespace token of the ayah's
// raw Hafs text, in the text's own token order, so nothing here matches or normalizes text. Id 0
// means the token has neither a root nor a lemma, which is the honest answer for particles and
// the sajdah mark. Ids are 1-based into the root and lemma tables.
//
// The reverse indexes are built on first use and kept.
//
// See ../../docs/18-morphology.md.

import (
	"strconv"
	"strings"
	"sync"
)

// Root is a triliteral (or quadriliteral) root, in both spellings a reader might use.
type Root struct {
	// Letters are spaced the way a lexicon prints them: "ر ب ب".
	Letters string
	// Buckwalter is the same letters transliterated: "rbb".
	Buckwalter string
	// Joined is Letters with the spaces closed up: "ربب".
	Joined string
}

// Lemma is a dictionary form, marked and unmarked.
type Lemma struct {
	Text  string
	Clean string
}

// WordLocation is one word of the Quran: the ayah and the 0-based index of the token in it.
type WordLocation struct {
	Surah int
	Ayah  int
	Token int
}

type morphologyFile struct {
	Roots    [][]string       `json:"roots"`
	Lemmas   [][]string       `json:"lemmas"`
	RootIDs  map[string][][]int `json:"rootIds"`
	LemmaIDs map[string][][]int `json:"lemmaIds"`
}

type morphologyIndex struct {
	once     sync.Once
	byRoot   map[int][]WordLocation
	byLemma  map[int][]WordLocation
}

// FoldForMorphology is the fold a typed query and the tables are both compared under.
//
// Every space is removed, not merely trimmed: a root is printed spaced ("ر ب ب") and typed
// closed up ("ربب"), and the two have to meet.
func FoldForMorphology(text string) string {
	folded := cleanSearch(removingArabicDiacriticsAndSigns(text))
	return strings.Join(strings.Fields(folded), "")
}

// HasMorphology reports whether morphology.json was loaded.
func (e *Engine) HasMorphology() bool { return len(e.morphology.Roots) > 0 }

// Root returns the root with this 1-based id.
func (e *Engine) Root(id int) (Root, bool) {
	if id < 1 || id > len(e.morphology.Roots) {
		return Root{}, false
	}
	row := e.morphology.Roots[id-1]
	return Root{Letters: row[0], Buckwalter: row[1],
		Joined: strings.ReplaceAll(row[0], " ", "")}, true
}

// Lemma returns the dictionary form with this 1-based id.
func (e *Engine) Lemma(id int) (Lemma, bool) {
	if id < 1 || id > len(e.morphology.Lemmas) {
		return Lemma{}, false
	}
	row := e.morphology.Lemmas[id-1]
	return Lemma{Text: row[0], Clean: row[1]}, true
}

// MorphologyIDs returns the root and lemma id of every token of the ayah. ok is false when the
// ayah is not covered.
func (e *Engine) MorphologyIDs(surahID, ayahID int) (roots, lemmas []int, ok bool) {
	key := strconv.Itoa(surahID)
	r := e.morphology.RootIDs[key]
	l := e.morphology.LemmaIDs[key]
	if r == nil || l == nil || ayahID < 1 || ayahID > len(r) || ayahID > len(l) {
		return nil, nil, false
	}
	return r[ayahID-1], l[ayahID-1], true
}

// RootOf returns the root of one token. ok is false when the token has none (a particle) or the
// index is out of range.
func (e *Engine) RootOf(surahID, ayahID, token int) (id int, root Root, ok bool) {
	roots, _, found := e.MorphologyIDs(surahID, ayahID)
	if !found || token < 0 || token >= len(roots) {
		return 0, Root{}, false
	}
	id = roots[token]
	root, ok = e.Root(id)
	return id, root, ok
}

// LemmaOf returns the dictionary form of one token.
func (e *Engine) LemmaOf(surahID, ayahID, token int) (id int, lemma Lemma, ok bool) {
	_, lemmas, found := e.MorphologyIDs(surahID, ayahID)
	if !found || token < 0 || token >= len(lemmas) {
		return 0, Lemma{}, false
	}
	id = lemmas[token]
	lemma, ok = e.Lemma(id)
	return id, lemma, ok
}

// OccurrencesOfRoot returns every word carrying this root, in mushaf order.
func (e *Engine) OccurrencesOfRoot(id int) []WordLocation {
	e.buildMorphologyIndex()
	return e.morphIndex.byRoot[id]
}

// OccurrencesOfLemma returns every word carrying this lemma, in mushaf order.
func (e *Engine) OccurrencesOfLemma(id int) []WordLocation {
	e.buildMorphologyIndex()
	return e.morphIndex.byLemma[id]
}

// RootHit pairs a root with its id.
type RootHit struct {
	ID   int
	Root Root
}

// LemmaHit pairs a dictionary form with its id.
type LemmaHit struct {
	ID    int
	Lemma Lemma
}

// FindRoots returns roots whose Arabic or Buckwalter spelling starts with the query.
func (e *Engine) FindRoots(query string, limit int) []RootHit {
	out := []RootHit{}
	e.prefixScan(e.morphology.Roots, query, limit, func(id int, row []string) {
		out = append(out, RootHit{ID: id, Root: Root{Letters: row[0], Buckwalter: row[1],
			Joined: strings.ReplaceAll(row[0], " ", "")}})
	})
	return out
}

// FindLemmas returns dictionary forms whose marked or unmarked spelling starts with the query.
func (e *Engine) FindLemmas(query string, limit int) []LemmaHit {
	out := []LemmaHit{}
	e.prefixScan(e.morphology.Lemmas, query, limit, func(id int, row []string) {
		out = append(out, LemmaHit{ID: id, Lemma: Lemma{Text: row[0], Clean: row[1]}})
	})
	return out
}

// MorphologyCount reports the corpus size: roots, lemmas, and the tokens they cover.
func (e *Engine) MorphologyCount() (roots, lemmas, tokens int) {
	for _, ayahs := range e.morphology.RootIDs {
		for _, row := range ayahs {
			tokens += len(row)
		}
	}
	return len(e.morphology.Roots), len(e.morphology.Lemmas), tokens
}

func (e *Engine) prefixScan(table [][]string, query string, limit int, emit func(int, []string)) {
	folded := FoldForMorphology(query)
	latin := strings.ToLower(strings.TrimSpace(query))
	if folded == "" && latin == "" {
		return
	}
	found := 0
	for i, row := range table {
		if limit > 0 && found >= limit {
			return
		}
		arabic := FoldForMorphology(row[0])
		roman := strings.ToLower(row[1])
		if (folded != "" && strings.HasPrefix(arabic, folded)) ||
			(latin != "" && strings.HasPrefix(roman, latin)) {
			emit(i+1, row)
			found++
		}
	}
}

func (e *Engine) buildMorphologyIndex() {
	e.morphIndex.once.Do(func() {
		byRoot := map[int][]WordLocation{}
		byLemma := map[int][]WordLocation{}
		for _, surah := range e.surahs {
			key := strconv.Itoa(surah.ID)
			roots := e.morphology.RootIDs[key]
			lemmas := e.morphology.LemmaIDs[key]
			for a, rootRow := range roots {
				var lemmaRow []int
				if a < len(lemmas) {
					lemmaRow = lemmas[a]
				}
				for t, rootID := range rootRow {
					location := WordLocation{Surah: surah.ID, Ayah: a + 1, Token: t}
					if rootID != 0 {
						byRoot[rootID] = append(byRoot[rootID], location)
					}
					if t < len(lemmaRow) && lemmaRow[t] != 0 {
						byLemma[lemmaRow[t]] = append(byLemma[lemmaRow[t]], location)
					}
				}
			}
		}
		e.morphIndex.byRoot = byRoot
		e.morphIndex.byLemma = byLemma
	})
}
