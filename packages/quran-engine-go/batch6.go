package quranengine

// The corpora added upstream in Al-Islam 4.6.5: the 99 Names in depth, and the chains of
// transmission of the Ten Readings. See ../../docs/23-names-depth.md and 24-isnad.md.

import (
	"sort"
	"strings"
)

// ---- the Names in depth ----------------------------------------------------------

// NameTheme is one of the nine themes the Names are grouped under.
type NameTheme struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// NameOccurrence is one ayah a Name appears in.
//
// Token is a pointer because the corpus could not place ten of them in their ayah's tokens: the
// ayah is still right, so a consumer shows the verse whole and highlights nothing.
type NameOccurrence struct {
	Surah  int  `json:"surah"`
	Ayah   int  `json:"ayah"`
	Token  *int `json:"token"`
	Tokens int  `json:"tokens"`
}

// NameDepth is the layer under names-of-allah.json: what the Name is built on and what it asks
// of a reader.
//
// The written material is Tilawa's (Jamil Hammoudeh), used with permission; the occurrences
// point into this engine's own Hafs text.
type NameDepth struct {
	Number int `json:"number"`
	// Root prints SPACED, the way a grammar book sets it ("ر ح م"). RootKey closes it up to the
	// form morphology.json stores.
	Root        string           `json:"root"`
	Theme       string           `json:"theme"`
	Explanation string           `json:"explanation"`
	Living      string           `json:"living"`
	Occurrences []NameOccurrence `json:"occurrences"`
}

type namesDepthFile struct {
	Themes []NameTheme `json:"themes"`
	Names  []NameDepth `json:"names"`
}

// RootKey returns a spaced root as morphology stores it: "ر ح م" -> "رحم".
//
// Every port strips whitespace explicitly rather than trimming, because a root is spaced in the
// middle and not only at the ends.
func RootKey(root string) string {
	return strings.Join(strings.Fields(root), "")
}

// NamesInDepth returns all 99, ordered by number.
func (e *Engine) NamesInDepth() []NameDepth { return e.namesDepth }

// NameInDepth returns one Name's depth entry, by its number (1..99).
func (e *Engine) NameInDepth(number int) (NameDepth, bool) {
	for _, name := range e.namesDepth {
		if name.Number == number {
			return name, true
		}
	}
	return NameDepth{}, false
}

// NameThemes returns the nine themes, in the corpus's own order.
func (e *Engine) NameThemes() []NameTheme { return e.nameThemes }

// NamesByTheme returns every Name under one theme, by number.
func (e *Engine) NamesByTheme(theme string) []NameDepth {
	out := []NameDepth{}
	for _, name := range e.namesDepth {
		if name.Theme == theme {
			out = append(out, name)
		}
	}
	return out
}

// NamesByRoot returns every Name built on one root. Accepts either spelling, spaced or closed up.
func (e *Engine) NamesByRoot(root string) []NameDepth {
	key := RootKey(root)
	if key == "" {
		return nil
	}
	out := []NameDepth{}
	for _, name := range e.namesDepth {
		if RootKey(name.Root) == key {
			out = append(out, name)
		}
	}
	return out
}

// NameInAyahHit is a Name and the occurrence that put it in an ayah.
type NameInAyahHit struct {
	Name       NameDepth
	Occurrence NameOccurrence
}

// NamesInAyah returns every Name appearing in an ayah, in token order. An unplaced occurrence
// (a nil Token) sorts last, so a highlighted list stays in reading order.
func (e *Engine) NamesInAyah(surahID, ayahID int) []NameInAyahHit {
	hits := []NameInAyahHit{}
	for _, name := range e.namesDepth {
		for _, occurrence := range name.Occurrences {
			if occurrence.Surah == surahID && occurrence.Ayah == ayahID {
				hits = append(hits, NameInAyahHit{Name: name, Occurrence: occurrence})
			}
		}
	}
	at := func(o NameOccurrence) int {
		if o.Token == nil {
			return int(^uint(0) >> 1)
		}
		return *o.Token
	}
	sort.SliceStable(hits, func(i, j int) bool { return at(hits[i].Occurrence) < at(hits[j].Occurrence) })
	return hits
}

// SearchNamesInDepth matches the root (spaces closed on both sides), the explanation and the
// living line.
func (e *Engine) SearchNamesInDepth(query string, limit int) []NameDepth {
	q := strings.TrimSpace(query)
	if q == "" {
		return nil
	}
	lower := strings.ToLower(q)
	key := RootKey(q)
	out := []NameDepth{}
	for _, name := range e.namesDepth {
		if (key != "" && strings.Contains(RootKey(name.Root), key)) ||
			strings.Contains(strings.ToLower(name.Explanation), lower) ||
			strings.Contains(strings.ToLower(name.Living), lower) {
			out = append(out, name)
			if limit > 0 && len(out) >= limit {
				break
			}
		}
	}
	return out
}

// NamesDepthCount reports how many Names carry depth, how many themes, and how many occurrences
// they cover.
func (e *Engine) NamesDepthCount() (names, themes, occurrences int) {
	for _, name := range e.namesDepth {
		occurrences += len(name.Occurrences)
	}
	return len(e.namesDepth), len(e.nameThemes), occurrences
}

// ---- the chains of transmission --------------------------------------------------

// IsnadNode is one person in a chain.
type IsnadNode struct {
	Name   string `json:"name"`
	Arabic string `json:"arabic"`
	// Detail is the death year, e.g. "d. 117 AH".
	Detail string `json:"detail"`
	Role   string `json:"role"`
}

// IsnadLayer is one generation of a chain, as a consumer draws it: a row, connected downward.
type IsnadLayer struct {
	Title string
	Nodes []IsnadNode
}

// ImamChain is an imam's side: the Successors he read on, and the Companions they read on.
type ImamChain struct {
	Teachers   []IsnadNode `json:"teachers"`
	Companions []IsnadNode `json:"companions"`
}

// NarratorChain is a narrator's side: the links between him and the imam (empty where he read on
// the imam himself), and the students who carried his narration on.
type NarratorChain struct {
	// Imam is the imam this narration comes from.
	Imam     string      `json:"imam"`
	Links    []IsnadNode `json:"links"`
	Students []IsnadNode `json:"students"`
}

type isnadFile struct {
	Prophet    *IsnadNode               `json:"prophet"`
	Companions []IsnadNode              `json:"companions"`
	Imams      map[string]ImamChain     `json:"imams"`
	Narrators  map[string]NarratorChain `json:"narrators"`
}

// IsnadProphet returns the head of every chain.
func (e *Engine) IsnadProphet() (IsnadNode, bool) {
	if e.isnad.Prophet == nil {
		return IsnadNode{}, false
	}
	return *e.isnad.Prophet, true
}

// IsnadCompanions returns the thirteen Companions the readings are transmitted from.
func (e *Engine) IsnadCompanions() []IsnadNode { return e.isnad.Companions }

// IsnadImamKeys returns the ten imams' keys, sorted.
func (e *Engine) IsnadImamKeys() []string {
	keys := make([]string, 0, len(e.isnad.Imams))
	for key := range e.isnad.Imams {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// IsnadNarratorKeys returns the twenty riwayah tags, sorted.
func (e *Engine) IsnadNarratorKeys() []string {
	keys := make([]string, 0, len(e.isnad.Narrators))
	for key := range e.isnad.Narrators {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// IsnadImam returns one imam's side of the chain.
func (e *Engine) IsnadImam(imam string) (ImamChain, bool) {
	chain, ok := e.isnad.Imams[imam]
	return chain, ok
}

// IsnadNarrator returns one narrator's side of the chain.
func (e *Engine) IsnadNarrator(riwayah string) (NarratorChain, bool) {
	chain, ok := e.isnad.Narrators[riwayah]
	return chain, ok
}

// IsnadReadsDirectly reports whether a narrator read on his imam himself, with nobody between.
func (e *Engine) IsnadReadsDirectly(riwayah string) bool {
	chain, ok := e.isnad.Narrators[riwayah]
	return ok && len(chain.Links) == 0
}

// IsnadImamOf returns the imam a riwayah comes from.
//
// Read from the corpus, NOT parsed off the tag: four tags name the imam in the Arabic genitive
// ("ad-Duri an Abi Amr") while his key is the nominative ("Abu Amr"), so splitting on " an "
// would resolve those four to nothing.
func (e *Engine) IsnadImamOf(riwayah string) (string, bool) {
	chain, ok := e.isnad.Narrators[riwayah]
	if !ok {
		return "", false
	}
	if _, known := e.isnad.Imams[chain.Imam]; !known {
		return "", false
	}
	return chain.Imam, true
}

func isnadNarratorName(riwayah string) string {
	if i := strings.Index(riwayah, " an "); i >= 0 {
		return riwayah[:i]
	}
	return riwayah
}

func isnadPlain(name, role string) IsnadNode {
	return IsnadNode{Name: name, Role: role}
}

// IsnadTopLayers returns the layers above any imam: the Prophet, the Companions his teachers read
// on, and those teachers. Shared by both chain forms, since every chain runs through them.
func (e *Engine) IsnadTopLayers(imam string) []IsnadLayer {
	chain, ok := e.isnad.Imams[imam]
	if !ok {
		return nil
	}
	layers := []IsnadLayer{}
	if e.isnad.Prophet != nil {
		layers = append(layers, IsnadLayer{Title: "THE PROPHET", Nodes: []IsnadNode{*e.isnad.Prophet}})
	}
	if len(chain.Companions) > 0 {
		layers = append(layers, IsnadLayer{Title: "THE COMPANIONS", Nodes: chain.Companions})
	}
	if len(chain.Teachers) > 0 {
		title := "HIS TEACHERS"
		if len(chain.Teachers) == 1 {
			title = "HIS TEACHER"
		}
		layers = append(layers, IsnadLayer{Title: title, Nodes: chain.Teachers})
	}
	return layers
}

// IsnadChain returns a whole chain as layers: a riwayah tag for one narration's chain, or an imam
// key for the reading's, which ends at his two narrators.
func (e *Engine) IsnadChain(key string) []IsnadLayer {
	key = strings.TrimSpace(key)
	if _, ok := e.isnad.Imams[key]; ok {
		layers := e.IsnadTopLayers(key)
		if len(layers) == 0 {
			return layers
		}
		layers = append(layers, IsnadLayer{Title: "THE IMAM", Nodes: []IsnadNode{isnadPlain(key, "imam")}})
		nodes := []IsnadNode{}
		for _, tag := range e.IsnadNarratorKeys() {
			if imam, ok := e.IsnadImamOf(tag); ok && imam == key {
				nodes = append(nodes, isnadPlain(isnadNarratorName(tag), "narrator"))
			}
		}
		if len(nodes) > 0 {
			layers = append(layers, IsnadLayer{Title: "HIS TWO NARRATORS", Nodes: nodes})
		}
		return layers
	}

	narrator, ok := e.isnad.Narrators[key]
	if !ok {
		return nil
	}
	imam, ok := e.IsnadImamOf(key)
	if !ok {
		return nil
	}
	layers := e.IsnadTopLayers(imam)
	if len(layers) == 0 {
		return layers
	}
	layers = append(layers, IsnadLayer{Title: "THE IMAM", Nodes: []IsnadNode{isnadPlain(imam, "imam")}})
	if len(narrator.Links) > 0 {
		title := "THE LINKS BETWEEN"
		if len(narrator.Links) == 1 {
			title = "THE LINK BETWEEN"
		}
		layers = append(layers, IsnadLayer{Title: title, Nodes: narrator.Links})
	}
	layers = append(layers, IsnadLayer{Title: "THE NARRATOR", Nodes: []IsnadNode{isnadPlain(isnadNarratorName(key), "narrator")}})
	if len(narrator.Students) > 0 {
		layers = append(layers, IsnadLayer{Title: "HIS STUDENTS", Nodes: narrator.Students})
	}
	return layers
}

// IsnadSentence returns one sentence on how a narrator reaches his imam: directly, or through the
// links between.
func (e *Engine) IsnadSentence(riwayah string) string {
	chain, ok := e.isnad.Narrators[riwayah]
	if !ok {
		return ""
	}
	imam, ok := e.IsnadImamOf(riwayah)
	if !ok {
		return ""
	}
	narrator := isnadNarratorName(riwayah)
	if len(chain.Links) == 0 {
		return narrator + " read on " + imam + " himself, and " + imam +
			"'s chain runs through his teachers to the Companions and to the Prophet ﷺ."
	}
	names := make([]string, 0, len(chain.Links))
	for _, node := range chain.Links {
		names = append(names, node.Name)
	}
	path := names[0]
	if len(names) > 1 {
		path = strings.Join(names[:len(names)-1], ", ") + " and then " + names[len(names)-1]
	}
	return narrator + " did not meet " + imam + ": the reading reached him through " + path +
		", and from " + imam + " it runs through his teachers to the Companions and to the Prophet ﷺ."
}

// IsnadCount reports how many imams, narrators and Companions the chains cover.
func (e *Engine) IsnadCount() (imams, narrators, companions int) {
	return len(e.isnad.Imams), len(e.isnad.Narrators), len(e.isnad.Companions)
}
