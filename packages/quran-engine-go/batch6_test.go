package quranengine

// Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.
//
// A deliberate translation of packages/quran-engine-js/test/batch6.test.js: the same corpora, the
// same counts, the same shape checks, so a port that drifts fails here rather than in a consumer.

import (
	"strings"
	"testing"
)

func foldBatch6(text string) string {
	var b strings.Builder
	for _, r := range text {
		switch {
		case r >= 0x064B && r <= 0x065F, r == 0x0670, r >= 0x06D6 && r <= 0x06ED, r == 0x0640:
			continue
		case r == 0x0671, r == 0x0623, r == 0x0625:
			b.WriteRune(0x0627)
		case r == 0x0624:
			b.WriteRune(0x0648)
		case r == 0x0626:
			b.WriteRune(0x064A)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func TestNamesDepthCounts(t *testing.T) {
	e := loadTestEngine(t)
	names, themes, occurrences := e.NamesDepthCount()
	if names != 99 || themes != 9 || occurrences != 194 {
		t.Fatalf("got (%d, %d, %d), want (99, 9, 194)", names, themes, occurrences)
	}
	for i, name := range e.NamesInDepth() {
		if name.Number != i+1 {
			t.Fatalf("name %d is out of order (number %d)", i, name.Number)
		}
	}
}

func TestEveryNameHasRootThemeAndProse(t *testing.T) {
	e := loadTestEngine(t)
	ids := map[string]bool{}
	for _, theme := range e.NameThemes() {
		ids[theme.ID] = true
	}
	for _, name := range e.NamesInDepth() {
		if name.Root == "" {
			t.Fatalf("name %d has no root", name.Number)
		}
		if !ids[name.Theme] {
			t.Fatalf("name %d theme %q is not in the list", name.Number, name.Theme)
		}
		if len(name.Explanation) <= 40 || len(name.Living) <= 20 {
			t.Fatalf("name %d prose is too short", name.Number)
		}
	}
}

func TestNameThemesPartition(t *testing.T) {
	e := loadTestEngine(t)
	total := 0
	for _, theme := range e.NameThemes() {
		members := e.NamesByTheme(theme.ID)
		if len(members) == 0 {
			t.Fatalf("theme %q has no Names", theme.ID)
		}
		total += len(members)
	}
	if total != 99 {
		t.Fatalf("themes cover %d Names, want 99", total)
	}
}

func TestRootIsSpacedAndClosesUp(t *testing.T) {
	e := loadTestEngine(t)
	rahman, ok := e.NameInDepth(1)
	if !ok || rahman.Root != "ر ح م" || RootKey(rahman.Root) != "رحم" {
		t.Fatalf("name 1 root is %q", rahman.Root)
	}
	for _, spelling := range []string{"رحم", "ر ح م"} {
		got := e.NamesByRoot(spelling)
		if len(got) != 2 || got[0].Number != 1 || got[1].Number != 2 {
			t.Fatalf("byRoot(%q) = %v", spelling, got)
		}
	}
}

func TestPlacedOccurrencesAreRealTokens(t *testing.T) {
	e := loadTestEngine(t)
	placed, unplaced := 0, 0
	for _, name := range e.NamesInDepth() {
		for _, o := range name.Occurrences {
			ayah := e.Ayah(o.Surah, o.Ayah)
			if ayah == nil {
				t.Fatalf("name %d points at %d:%d, which is not an ayah", name.Number, o.Surah, o.Ayah)
			}
			if o.Token == nil {
				if o.Tokens != 0 {
					t.Fatalf("name %d unplaced but spans %d", name.Number, o.Tokens)
				}
				unplaced++
				continue
			}
			tokens := strings.Fields(ayah.TextArabic)
			if *o.Token >= len(tokens) {
				t.Fatalf("name %d token %d past the end of %d:%d", name.Number, *o.Token, o.Surah, o.Ayah)
			}
			if foldBatch6(tokens[*o.Token]) == "" {
				t.Fatalf("name %d token %d folds to nothing", name.Number, *o.Token)
			}
			placed++
		}
	}
	if placed != 184 || unplaced != 10 {
		t.Fatalf("placed=%d unplaced=%d, want 184 and 10", placed, unplaced)
	}
}

func TestBasmalahCarriesTwoNames(t *testing.T) {
	e := loadTestEngine(t)
	hits := e.NamesInAyah(1, 3)
	if len(hits) != 2 {
		t.Fatalf("1:3 carries %d Names, want 2", len(hits))
	}
	for i, hit := range hits {
		if hit.Name.Number != i+1 || hit.Occurrence.Token == nil || *hit.Occurrence.Token != i {
			t.Fatalf("hit %d is name %d at %v", i, hit.Name.Number, hit.Occurrence.Token)
		}
	}
}

func TestNamesSearch(t *testing.T) {
	e := loadTestEngine(t)
	found := false
	for _, n := range e.SearchNamesInDepth("رحم", 25) {
		if n.Number == 1 {
			found = true
		}
	}
	if !found {
		t.Fatal("searching the root رحم does not find Ar-Rahman")
	}
	if len(e.SearchNamesInDepth("", 25)) != 0 {
		t.Fatal("an empty query returns results")
	}
}

func TestIsnadCounts(t *testing.T) {
	e := loadTestEngine(t)
	imams, narrators, companions := e.IsnadCount()
	if imams != 10 || narrators != 20 || companions != 13 {
		t.Fatalf("got (%d, %d, %d), want (10, 20, 13)", imams, narrators, companions)
	}
	if _, ok := e.IsnadProphet(); !ok {
		t.Fatal("no Prophet at the head of the chains")
	}
}

func TestEveryRiwayahResolvesTwoApiece(t *testing.T) {
	e := loadTestEngine(t)
	per := map[string]int{}
	for _, tag := range e.IsnadNarratorKeys() {
		imam, ok := e.IsnadImamOf(tag)
		if !ok {
			t.Fatalf("%s resolves to no imam", tag)
		}
		per[imam]++
	}
	for _, imam := range e.IsnadImamKeys() {
		if per[imam] != 2 {
			t.Fatalf("%s has %d narrators, want 2", imam, per[imam])
		}
	}
}

func TestEveryImamReachesCompanions(t *testing.T) {
	e := loadTestEngine(t)
	for _, imam := range e.IsnadImamKeys() {
		chain, _ := e.IsnadImam(imam)
		// Abu Jafar WAS a Successor and read on Companions himself, so he has no teachers layer.
		if imam != "Abu Jafar" && len(chain.Teachers) == 0 {
			t.Fatalf("%s has no teachers", imam)
		}
		if len(chain.Companions) == 0 {
			t.Fatalf("%s reaches no Companion", imam)
		}
		for _, node := range chain.Teachers {
			if node.Role != "successor" || !strings.HasPrefix(node.Detail, "d.") {
				t.Fatalf("%s teacher %q is %q / %q", imam, node.Name, node.Role, node.Detail)
			}
		}
		for _, node := range chain.Companions {
			if node.Role != "companion" {
				t.Fatalf("%s companion %q is %q", imam, node.Name, node.Role)
			}
		}
	}
}

func TestChainRunsProphetToNarrator(t *testing.T) {
	e := loadTestEngine(t)
	for _, tag := range e.IsnadNarratorKeys() {
		layers := e.IsnadChain(tag)
		if len(layers) < 4 {
			t.Fatalf("%s chain is only %d layers", tag, len(layers))
		}
		if layers[0].Title != "THE PROPHET" || layers[1].Title != "THE COMPANIONS" {
			t.Fatalf("%s starts %q, %q", tag, layers[0].Title, layers[1].Title)
		}
		imam, narrator := -1, -1
		for i, l := range layers {
			if l.Title == "THE IMAM" {
				imam = i
			}
			if l.Title == "THE NARRATOR" {
				narrator = i
			}
		}
		if imam < 0 || narrator < 0 || imam > narrator {
			t.Fatalf("%s has imam at %d and narrator at %d", tag, imam, narrator)
		}
	}
}

func TestImamChainEndsAtTwoNarrators(t *testing.T) {
	e := loadTestEngine(t)
	for _, imam := range e.IsnadImamKeys() {
		layers := e.IsnadChain(imam)
		last := layers[len(layers)-1]
		if last.Title != "HIS TWO NARRATORS" || len(last.Nodes) != 2 {
			t.Fatalf("%s ends with %q (%d nodes)", imam, last.Title, len(last.Nodes))
		}
	}
}

func TestReadsDirectlyMatchesLinks(t *testing.T) {
	e := loadTestEngine(t)
	for _, tag := range e.IsnadNarratorKeys() {
		chain, _ := e.IsnadNarrator(tag)
		if e.IsnadReadsDirectly(tag) != (len(chain.Links) == 0) {
			t.Fatalf("%s: readsDirectly disagrees with its links", tag)
		}
		sentence := e.IsnadSentence(tag)
		if sentence == "" {
			t.Fatalf("%s has no sentence", tag)
		}
		if strings.Contains(sentence, "did not meet") != (len(chain.Links) > 0) {
			t.Fatalf("%s: the sentence disagrees with its links", tag)
		}
	}
}

func TestHafsAndQunbul(t *testing.T) {
	e := loadTestEngine(t)
	if imam, _ := e.IsnadImamOf("Hafs an Asim"); imam != "Asim" {
		t.Fatalf("Hafs resolves to %q", imam)
	}
	if !e.IsnadReadsDirectly("Hafs an Asim") {
		t.Fatal("Hafs should read on Asim himself")
	}
	if !strings.HasPrefix(e.IsnadSentence("Hafs an Asim"), "Hafs read on Asim himself") {
		t.Fatal("Hafs's sentence is wrong")
	}
	if e.IsnadReadsDirectly("Qunbul an Ibn Kathir") {
		t.Fatal("Qunbul did not meet Ibn Kathir")
	}
	chain, _ := e.IsnadNarrator("Qunbul an Ibn Kathir")
	if len(chain.Links) != 3 {
		t.Fatalf("Qunbul has %d links, want 3", len(chain.Links))
	}
}

func TestUnknownIsnadKey(t *testing.T) {
	e := loadTestEngine(t)
	if len(e.IsnadChain("Nobody an Nobody")) != 0 || e.IsnadSentence("Nobody an Nobody") != "" {
		t.Fatal("an unknown key answered something")
	}
	if _, ok := e.IsnadImamOf("no separator here"); ok {
		t.Fatal("a tag with no separator resolved to an imam")
	}
}
