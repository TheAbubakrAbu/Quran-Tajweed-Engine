package quranengine

// Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one sentence
// saying what the surah as a whole is about.
//
// This answers "I am at 18:60 - what is this passage doing here", which neither the translation nor
// the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
// outline; al-Fatihah, Fussilat and ad-Dukhan do not.
//
// THE OUTLINE IS A TREE, FLATTENED. Ranges are inclusive, in mushaf order, and MAY NEST: a broad
// section is followed by the sections inside it, parent before children (Hud opens with 1-24
// "Doctrine facts", then 1-4, 5-6, 7-11, 12-17, 18-24 within it). They also do not tile the surah -
// an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
// which is what SectionsFor returns; Outline rebuilds it as a tree.
//
// See ../../docs/15-surah-sections.md.

import (
	"encoding/json"
	"sort"
	"strconv"
	"strings"
)

// SurahSection is one titled range of ayahs. From and To are inclusive.
type SurahSection struct {
	From    int
	To      int
	English string
	Arabic  string
}

// Contains reports whether the ayah falls in this section.
func (s SurahSection) Contains(ayahID int) bool { return ayahID >= s.From && ayahID <= s.To }

// OutlineNode is a section with the sections inside it.
type OutlineNode struct {
	Section  SurahSection
	Children []OutlineNode
}

// surahSectionsEntry is one surah's row of data/surah-sections.json. The section rows are
// [from, to, english, arabic] - heterogeneous, so they stay raw until Sections reads them.
type surahSectionsEntry struct {
	Overview string              `json:"overview"`
	Sections [][]json.RawMessage `json:"sections"`
}

// SurahOverview is one sentence on what the whole surah is about, "" when none is recorded.
func (e *Engine) SurahOverview(surahID int) string {
	return e.surahSections[strconv.Itoa(surahID)].Overview
}

// Sections returns the surah's sections, flat and in the order the source records them (a parent
// immediately before the sections inside it).
func (e *Engine) Sections(surahID int) []SurahSection {
	entry, ok := e.surahSections[strconv.Itoa(surahID)]
	if !ok {
		return nil
	}
	var out []SurahSection
	for _, row := range entry.Sections {
		if len(row) < 4 {
			continue
		}
		var section SurahSection
		if json.Unmarshal(row[0], &section.From) != nil ||
			json.Unmarshal(row[1], &section.To) != nil ||
			json.Unmarshal(row[2], &section.English) != nil ||
			json.Unmarshal(row[3], &section.Arabic) != nil {
			continue
		}
		out = append(out, section)
	}
	return out
}

// Outline returns the same sections as a tree: top-level passages, each with what is inside it.
func (e *Engine) Outline(surahID int) []OutlineNode {
	var roots []OutlineNode
	// The open chain, as a path of indices: appending to a slice can move it, so the path is
	// walked back down on each insert rather than held as a pointer.
	var path []int

	for _, section := range e.Sections(surahID) {
		for len(path) > 0 {
			open := nodeAt(roots, path)
			if open.Section.From <= section.From && section.To <= open.Section.To {
				break
			}
			path = path[:len(path)-1]
		}
		index := appendNode(&roots, path, OutlineNode{Section: section})
		path = append(path, index)
	}
	return roots
}

// SectionsFor lists every section covering an ayah, outermost first - the breadcrumb for "you are
// here". Empty when the surah has no outline, or when this ayah falls between sections.
func (e *Engine) SectionsFor(surahID, ayahID int) []SurahSection {
	var out []SurahSection
	for _, section := range e.Sections(surahID) {
		if section.Contains(ayahID) {
			out = append(out, section)
		}
	}
	return out
}

// SectionFor is the most specific section covering an ayah - the heading a reader wants beside it.
func (e *Engine) SectionFor(surahID, ayahID int) *SurahSection {
	chain := e.SectionsFor(surahID, ayahID)
	if len(chain) == 0 {
		return nil
	}
	return &chain[len(chain)-1]
}

// HasSections reports whether this surah has an outline at all.
func (e *Engine) HasSections(surahID int) bool {
	return len(e.surahSections[strconv.Itoa(surahID)].Sections) > 0
}

// OutlinedSurahCount is how many surahs carry an outline.
func (e *Engine) OutlinedSurahCount() int {
	count := 0
	for _, entry := range e.surahSections {
		if len(entry.Sections) > 0 {
			count++
		}
	}
	return count
}

// SectionHit pairs a section with the surah it belongs to.
type SectionHit struct {
	Surah   int
	Section SurahSection
}

// SearchSections finds sections whose title carries query, across every surah.
func (e *Engine) SearchSections(query string) []SectionHit {
	trimmed := strings.TrimSpace(query)
	needle := strings.ToLower(trimmed)
	if needle == "" {
		return nil
	}
	ids := make([]int, 0, len(e.surahSections))
	for key := range e.surahSections {
		if id, err := strconv.Atoi(key); err == nil {
			ids = append(ids, id)
		}
	}
	sort.Ints(ids)

	var out []SectionHit
	for _, id := range ids {
		for _, section := range e.Sections(id) {
			if strings.Contains(strings.ToLower(section.English), needle) ||
				strings.Contains(section.Arabic, trimmed) {
				out = append(out, SectionHit{Surah: id, Section: section})
			}
		}
	}
	return out
}

// nodeAt returns the node the path points at.
func nodeAt(roots []OutlineNode, path []int) OutlineNode {
	node := roots[path[0]]
	for _, index := range path[1:] {
		node = node.Children[index]
	}
	return node
}

// appendNode appends into the child list the path points at, returning the new node's index.
func appendNode(roots *[]OutlineNode, path []int, node OutlineNode) int {
	if len(path) == 0 {
		*roots = append(*roots, node)
		return len(*roots) - 1
	}
	return appendNode(&(*roots)[path[0]].Children, path[1:], node)
}
