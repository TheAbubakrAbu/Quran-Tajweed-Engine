package quranengine

// Riwayah tajweed: where a reading differs from Hafs, and why.
//
// A different layer from tajweed.go, which reads the text and works out the universal rules. This
// carries what is SPECIFIC to a transmission and cannot be detected, because it IS the text's
// difference: Warsh's taqlil, al-Bazzi's doubled ta, the places two readings part.
//
// Two things to get right:
//
//   - The meaning of a colour is per edition. Each mushaf prints its own legend, so the same code
//     is a different rule in a different riwayah. Always read the legend. The rule KEY is stable
//     across riwayat, which is why one catalogue can explain it for all of them.
//   - Extents are base-letter indices, not character offsets: FirstLetter..LastLetter inclusive in
//     reading order with diacritics not counted, or the whole word when WholeWord.
//
// Only the seven verified non-Hafs riwayat carry a pack. See ../../docs/11-qiraat-tajweed.md.

import (
	"encoding/json"
	"sort"
	"strconv"
)

// LegendRow is one legend row as it ships, before the shared explanation is merged in.
type LegendRow struct {
	Code    string `json:"code"`
	Rule    string `json:"rule"`
	Arabic  string `json:"arabic"`
	English string `json:"english"`
}

// LegendEntry is a legend row with its shared explanation.
type LegendEntry struct {
	// Code is the single letter this riwayah's data uses for the rule.
	Code string
	// Rule is the stable rule key, e.g. "idgham" — the same across riwayat.
	Rule string
	// Arabic is the rule's name as this mushaf prints it.
	Arabic  string
	English string
	// Short is the one-line explanation, from the shared catalogue.
	Short string
	Long  string
}

// WordRule is what one word of one ayah is coloured for.
type WordRule struct {
	// Word is the 1-based word index within the ayah.
	Word    int
	Rule    string
	Code    string
	Arabic  string
	English string
	// FirstLetter is the inclusive base-letter index the rule colours, or -1 for the whole word.
	FirstLetter int
	LastLetter  int
	WholeWord   bool
}

// RuleDescription is one entry of data/tajweed-qiraat/rules.json.
type RuleDescription struct {
	Short string `json:"short"`
	Long  string `json:"long"`
}

// QiraatTajweedPack is data/tajweed-qiraat/<slug>.json.
type QiraatTajweedPack struct {
	Riwayah string      `json:"riwayah"`
	Version int         `json:"version"`
	Legend  []LegendRow `json:"legend"`
	// Rules is surah -> ayah -> word -> [code, firstLetter, lastLetter] triples. The triple is
	// heterogeneous (a string then two numbers), so it stays raw until WordRules reads it.
	Rules         map[string]map[string]map[string][][]json.RawMessage `json:"rules"`
	KhilafMarkers map[string][]int                                     `json:"khilafMarkers"`
}

// QiraatTajweedAvailable lists the riwayat that have a pack loaded, in slug order.
func (e *Engine) QiraatTajweedAvailable() []string {
	slugs := make([]string, 0, len(e.qiraatTajweed))
	for slug := range e.qiraatTajweed {
		slugs = append(slugs, slug)
	}
	sort.Strings(slugs)
	return slugs
}

// QiraatLegend is this riwayah's printed legend, each entry carrying the shared explanation of its
// rule.
func (e *Engine) QiraatLegend(riwayah string) []LegendEntry {
	pack, ok := e.qiraatTajweed[riwayah]
	if !ok {
		return nil
	}
	out := make([]LegendEntry, 0, len(pack.Legend))
	for _, row := range pack.Legend {
		description := e.qiraatRuleDescriptions[row.Rule]
		out = append(out, LegendEntry{
			Code:    row.Code,
			Rule:    row.Rule,
			Arabic:  row.Arabic,
			English: row.English,
			Short:   description.Short,
			Long:    description.Long,
		})
	}
	return out
}

// QiraatWordRules is what this riwayah colours in one ayah, word by word.
func (e *Engine) QiraatWordRules(surahID, ayahID int, riwayah string) []WordRule {
	pack, ok := e.qiraatTajweed[riwayah]
	if !ok {
		return nil
	}
	ayahs, ok := pack.Rules[strconv.Itoa(surahID)]
	if !ok {
		return nil
	}
	words, ok := ayahs[strconv.Itoa(ayahID)]
	if !ok {
		return nil
	}

	byCode := make(map[string]LegendEntry)
	for _, entry := range e.QiraatLegend(riwayah) {
		byCode[entry.Code] = entry
	}

	keys := make([]int, 0, len(words))
	for key := range words {
		if n, err := strconv.Atoi(key); err == nil {
			keys = append(keys, n)
		}
	}
	sort.Ints(keys)

	var out []WordRule
	for _, key := range keys {
		for _, triple := range words[strconv.Itoa(key)] {
			if len(triple) < 3 {
				continue
			}
			var code string
			var lo, hi int
			if json.Unmarshal(triple[0], &code) != nil ||
				json.Unmarshal(triple[1], &lo) != nil ||
				json.Unmarshal(triple[2], &hi) != nil {
				continue
			}
			entry, known := byCode[code]
			rule := code
			if known {
				rule = entry.Rule
			}
			out = append(out, WordRule{
				Word:        key,
				Rule:        rule,
				Code:        code,
				Arabic:      entry.Arabic,
				English:     entry.English,
				FirstLetter: lo,
				LastLetter:  hi,
				WholeWord:   lo < 0,
			})
		}
	}
	return out
}

// KhilafAyahs lists the ayahs of a surah this riwayah reads differently from Hafs somewhere — the
// index behind a "show me where these two readings part" list, without walking every ayah's rules.
func (e *Engine) KhilafAyahs(surahID int, riwayah string) []int {
	pack, ok := e.qiraatTajweed[riwayah]
	if !ok {
		return nil
	}
	return pack.KhilafMarkers[strconv.Itoa(surahID)]
}

// HasKhilaf reports whether this ayah is one of them.
func (e *Engine) HasKhilaf(surahID, ayahID int, riwayah string) bool {
	for _, ayah := range e.KhilafAyahs(surahID, riwayah) {
		if ayah == ayahID {
			return true
		}
	}
	return false
}

// DescribeQiraatRule says what a rule key means, in one line and in a paragraph. Shared across
// every riwayah that uses the rule, so an app writes the explanation once.
func (e *Engine) DescribeQiraatRule(rule string) *RuleDescription {
	description, ok := e.qiraatRuleDescriptions[rule]
	if !ok {
		return nil
	}
	return &description
}

// QiraatRuleKeys lists every rule key the catalogue explains.
func (e *Engine) QiraatRuleKeys() []string {
	keys := make([]string, 0, len(e.qiraatRuleDescriptions))
	for key := range e.qiraatRuleDescriptions {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
