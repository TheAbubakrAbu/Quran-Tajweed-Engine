package quranengine

// The scientific-miracles corpus: 202 articles under 15 categories.
//
// A deliberate translation of packages/quran-engine-js/test/miracles.test.js: the same corpus, the
// same counts, the same shape checks, so a port that drifts fails here rather than in a consumer.

import (
	"sort"
	"strings"
	"testing"
)

func miracleSlugs(articles []MiracleArticle) []string {
	out := make([]string, len(articles))
	for i, a := range articles {
		out[i] = a.Slug
	}
	return out
}

func TestMiraclesCounts(t *testing.T) {
	e := loadTestEngine(t)
	articles, categories, ayahRefs := e.MiraclesCount()
	if articles != 202 || categories != 15 || ayahRefs != 278 {
		t.Fatalf("got (%d, %d, %d), want (202, 15, 278)", articles, categories, ayahRefs)
	}
	if len(e.Miracles()) != 202 || len(e.MiracleCategories()) != 15 {
		t.Fatalf("got %d articles and %d categories", len(e.Miracles()), len(e.MiracleCategories()))
	}
}

func TestMiracleSlugRoundTrips(t *testing.T) {
	e := loadTestEngine(t)
	article, ok := e.Miracle("big_bang_crunch")
	if !ok {
		t.Fatal("big_bang_crunch is missing")
	}
	if article.Title != "Big Bang" || article.Category != "cosmology" || article.Level != "extreme" {
		t.Fatalf("got %q / %q / %q", article.Title, article.Category, article.Level)
	}
	if _, ok := e.Miracle("no_such_article"); ok {
		t.Fatal("no_such_article resolved")
	}
	// Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
	seen := map[string]bool{}
	for _, a := range e.Miracles() {
		if seen[a.Slug] {
			t.Fatalf("slug %q appears twice", a.Slug)
		}
		seen[a.Slug] = true
	}
	if len(seen) != 202 {
		t.Fatalf("got %d distinct slugs", len(seen))
	}
}

func TestMiracleCategoriesPartition(t *testing.T) {
	e := loadTestEngine(t)
	total := 0
	for _, category := range e.MiracleCategories() {
		members := e.MiraclesByCategory(category.ID)
		if len(members) == 0 {
			t.Fatalf("category %q has no articles", category.ID)
		}
		total += len(members)
	}
	if total != 202 {
		t.Fatalf("categories cover %d articles, want 202", total)
	}
	if n := len(e.MiraclesByCategory("cosmology")); n != 18 {
		t.Fatalf("cosmology has %d articles, want 18", n)
	}
	if n := len(e.MiraclesByCategory("no_such_category")); n != 0 {
		t.Fatalf("an unknown category answered %d articles", n)
	}
}

func TestMiracleCategoryLookup(t *testing.T) {
	e := loadTestEngine(t)
	cosmology, ok := e.MiracleCategoryByID("cosmology")
	if !ok {
		t.Fatal("cosmology is missing")
	}
	if cosmology.ID != "cosmology" || cosmology.Level != "advanced" {
		t.Fatalf("got %q at %q", cosmology.ID, cosmology.Level)
	}
	if _, ok := e.MiracleCategoryByID("no_such_category"); ok {
		t.Fatal("no_such_category resolved")
	}
}

func TestMiracleArticleLevelIsItsOwn(t *testing.T) {
	// Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
	// itself is "extreme". Filtering on the category's level would put it in the wrong bucket, and
	// it is not one article out of place: most of the corpus disagrees with its category.
	e := loadTestEngine(t)
	cosmology, _ := e.MiracleCategoryByID("cosmology")
	article, _ := e.Miracle("big_bang_crunch")
	if cosmology.Level != "advanced" || article.Level != "extreme" {
		t.Fatalf("category %q vs article %q", cosmology.Level, article.Level)
	}
	catLevel := map[string]string{}
	for _, c := range e.MiracleCategories() {
		catLevel[c.ID] = c.Level
	}
	differing := 0
	for _, a := range e.Miracles() {
		if a.Level != catLevel[a.Category] {
			differing++
		}
	}
	if differing != 147 {
		t.Fatalf("%d articles differ from their category, want 147", differing)
	}
}

func TestMiracleLevelsRunSimpleToExtreme(t *testing.T) {
	e := loadTestEngine(t)
	levels := e.MiracleLevelsPresent()
	want := []string{"simple", "intermediate", "advanced", "extreme"}
	if strings.Join(levels, ",") != strings.Join(want, ",") {
		t.Fatalf("got %v, want %v", levels, want)
	}
	if strings.Join(levels, ",") != strings.Join(MiracleLevels, ",") {
		t.Fatalf("levels() %v disagrees with MiracleLevels %v", levels, MiracleLevels)
	}
	// Sorted as strings, "extreme" would come second. That is the whole reason the rank is
	// hard-coded.
	alphabetical := append([]string{}, levels...)
	sort.Strings(alphabetical)
	if strings.Join(alphabetical, ",") == strings.Join(levels, ",") {
		t.Fatal("the level order is alphabetical, so the hard-coded rank is doing nothing")
	}
	for level, want := range map[string]int{"simple": 6, "intermediate": 103, "advanced": 37, "extreme": 56} {
		if n := len(e.MiraclesByLevel(level)); n != want {
			t.Fatalf("%s has %d articles, want %d", level, n, want)
		}
	}
	total := 0
	for _, level := range MiracleLevels {
		total += len(e.MiraclesByLevel(level))
	}
	if total != len(e.Miracles()) {
		t.Fatalf("the levels cover %d of %d articles", total, len(e.Miracles()))
	}
}

func TestMiracleArticlesNameKnownCategoryAndLevel(t *testing.T) {
	e := loadTestEngine(t)
	ids := map[string]bool{}
	for _, c := range e.MiracleCategories() {
		ids[c.ID] = true
	}
	levels := map[string]bool{}
	for _, l := range MiracleLevels {
		levels[l] = true
	}
	for _, article := range e.Miracles() {
		if article.Slug == "" || article.Title == "" || len(article.Blocks) == 0 {
			t.Fatalf("article %q is incomplete", article.Slug)
		}
		if !ids[article.Category] {
			t.Fatalf("%s is filed under %q", article.Slug, article.Category)
		}
		if !levels[article.Level] {
			t.Fatalf("%s is at %q", article.Slug, article.Level)
		}
	}
}

func TestMiraclesCiting(t *testing.T) {
	e := loadTestEngine(t)
	// 21:30 is cited by exactly two: Big Bang and Exoplanets.
	if got := miracleSlugs(e.MiraclesCiting(21, 30)); strings.Join(got, ",") != "big_bang_crunch,exoplanets" {
		t.Fatalf("21:30 -> %v", got)
	}
	// 23:14, the embryology verse, by three.
	if got := miracleSlugs(e.MiraclesCiting(23, 14)); strings.Join(got, ",") != "bones,fetal_development,human_embryo" {
		t.Fatalf("23:14 -> %v", got)
	}
	if n := len(e.MiraclesCiting(21, 999)); n != 0 {
		t.Fatalf("21:999 -> %d articles", n)
	}
	if n := len(e.MiraclesCiting(999, 1)); n != 0 {
		t.Fatalf("999:1 -> %d articles", n)
	}
}

func TestMiracleAyahBlockIsARange(t *testing.T) {
	// Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
	// one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range end
	// is what bounds the search, not the surah).
	e := loadTestEngine(t)
	refs := e.MiracleAyahRefs("abjad_numerals")
	if len(refs) != 1 || refs[0] != (MiracleAyahRef{Surah: 111, Ayah: 1, EndAyah: 5}) {
		t.Fatalf("abjad_numerals cites %v", refs)
	}
	cites := func(ayah int) bool {
		for _, a := range e.MiraclesCiting(111, ayah) {
			if a.Slug == "abjad_numerals" {
				return true
			}
		}
		return false
	}
	for ayah := 1; ayah <= 5; ayah++ {
		if !cites(ayah) {
			t.Fatalf("111:%d does not reach abjad_numerals", ayah)
		}
	}
	if cites(6) {
		t.Fatal("111:6 reaches abjad_numerals, one past the end of the range")
	}
	if n := len(e.MiracleAyahRefs("no_such_article")); n != 0 {
		t.Fatalf("an unknown slug cited %d ranges", n)
	}
}

func TestMiracleAyahRefsAreRealAyahs(t *testing.T) {
	e := loadTestEngine(t)
	refs, ranges := 0, 0
	for _, article := range e.Miracles() {
		for _, r := range e.MiracleAyahRefs(article.Slug) {
			if r.EndAyah < r.Ayah {
				t.Fatalf("%s cites %d:%d-%d", article.Slug, r.Surah, r.Ayah, r.EndAyah)
			}
			// Both ends resolve, which is the point of storing the reference rather than the text.
			if e.Ayah(r.Surah, r.Ayah) == nil {
				t.Fatalf("%s -> %d:%d", article.Slug, r.Surah, r.Ayah)
			}
			if e.Ayah(r.Surah, r.EndAyah) == nil {
				t.Fatalf("%s -> %d:%d", article.Slug, r.Surah, r.EndAyah)
			}
			refs++
			if r.EndAyah > r.Ayah {
				ranges++
			}
		}
	}
	if refs != 278 || ranges != 49 {
		t.Fatalf("got %d refs and %d ranges, want 278 and 49", refs, ranges)
	}
}

func TestMiraclesHaveNoImageBlocks(t *testing.T) {
	// The site's illustrations are deliberately not republished. A consumer that leaves a gap for
	// a picture would wait forever, so the corpus states it and the blocks bear it out.
	e := loadTestEngine(t)
	if e.MiraclesImagesIncluded() {
		t.Fatal("imagesIncluded is true, but no images are published")
	}
	seen := map[string]bool{}
	for _, article := range e.Miracles() {
		for _, block := range article.Blocks {
			seen[block.Kind] = true
		}
	}
	kinds := make([]string, 0, len(seen))
	for kind := range seen {
		kinds = append(kinds, kind)
	}
	sort.Strings(kinds)
	if strings.Join(kinds, ",") != "ayah,claim,closer,lead,quote,text" {
		t.Fatalf("block kinds are %v", kinds)
	}
	if !strings.Contains(e.MiraclesSource(), "miracles-of-quran.com") {
		t.Fatalf("source is %q", e.MiraclesSource())
	}
}

func TestMiracleLinksAreURLOrSlugNeverBoth(t *testing.T) {
	e := loadTestEngine(t)
	known := map[string]bool{}
	for _, a := range e.Miracles() {
		known[a.Slug] = true
	}
	urls, slugs := 0, 0
	for _, article := range e.Miracles() {
		for _, block := range article.Blocks {
			for _, link := range block.Links {
				if link.Label == "" {
					t.Fatalf("%s has an unlabelled link", article.Slug)
				}
				if (link.URL != "") == (link.Slug != "") {
					t.Fatalf("%s: link %q has url %q and slug %q", article.Slug, link.Label, link.URL, link.Slug)
				}
				if link.Slug != "" {
					// An internal cross-reference resolves, so following one is Miracle and
					// nothing more.
					if !known[link.Slug] {
						t.Fatalf("%s -> %s", article.Slug, link.Slug)
					}
					if _, ok := e.Miracle(link.Slug); !ok {
						t.Fatalf("%s -> %s does not resolve", article.Slug, link.Slug)
					}
					slugs++
				} else {
					urls++
				}
			}
		}
	}
	if urls != 73 || slugs != 12 {
		t.Fatalf("got %d url links and %d slug links, want 73 and 12", urls, slugs)
	}
	// One of each form, named, so a port that models only one of them fails here.
	bigBang, _ := e.Miracle("big_bang_crunch")
	internal := []MiracleLink{}
	for _, block := range bigBang.Blocks {
		internal = append(internal, block.Links...)
	}
	if len(internal) != 1 || internal[0].Label != "Dark Energy" || internal[0].Slug != "dark_energy" {
		t.Fatalf("big_bang_crunch links are %v", internal)
	}
	atoms, _ := e.Miracle("atoms")
	external := 0
	for _, block := range atoms.Blocks {
		for _, link := range block.Links {
			if link.URL != "" {
				if !strings.HasPrefix(link.URL, "http") {
					t.Fatalf("atoms links to %q", link.URL)
				}
				external++
			}
		}
	}
	if external == 0 {
		t.Fatal("atoms has no outside links")
	}
}

func TestMiracleTextLeavesTheQuotesOut(t *testing.T) {
	e := loadTestEngine(t)
	abjad, _ := e.Miracle("abjad_numerals")
	var quote MiracleBlock
	for _, block := range abjad.Blocks {
		if block.Kind == "quote" {
			quote = block
			break
		}
	}
	if quote.SourceLabel != "Wikipedia, Abjad Numerals, 2021" {
		t.Fatalf("the quote is sourced to %q", quote.SourceLabel)
	}
	text := e.MiracleText("abjad_numerals")
	// The quote sits between the lead and the first text block, and none of it comes through: it
	// is somebody else's words next to a source label, not the article's voice.
	if strings.Contains(text, quote.Text[:40]) || strings.Contains(text, "Wikipedia") {
		t.Fatal("the quote leaked into the article's own prose")
	}
	// What does come through is claim, lead, text and closer, in reading order.
	if !strings.HasPrefix(text, "Alphanumeric code.") {
		t.Fatalf("text starts %q", text[:20])
	}
	if !strings.Contains(text, "We found this ancient numeral system encoded in the Quran.") {
		t.Fatal("a text block is missing from the prose")
	}
	if n := len(strings.Split(text, "\n\n")); n != 6 {
		t.Fatalf("abjad_numerals joins %d prose blocks, want 6", n)
	}
	if n := len(strings.Split(e.MiracleText("big_bang_crunch"), "\n\n")); n != 4 {
		t.Fatalf("big_bang_crunch joins %d prose blocks, want 4", n)
	}
	if e.MiracleText("no_such_article") != "" {
		t.Fatal("an unknown slug answered prose")
	}
}

func TestSearchMiracles(t *testing.T) {
	e := loadTestEngine(t)
	hits := miracleSlugs(e.SearchMiracles("big bang", 25))
	found := false
	for _, slug := range hits {
		if slug == "big_bang_crunch" {
			found = true
		}
	}
	if !found {
		t.Fatalf("\"big bang\" -> %v", hits)
	}
	if upper := miracleSlugs(e.SearchMiracles("BIG BANG", 25)); strings.Join(upper, ",") != strings.Join(hits, ",") {
		t.Fatalf("the search is case-sensitive: %v vs %v", upper, hits)
	}
	if n := len(e.SearchMiracles("cosmology", 3)); n > 3 {
		t.Fatalf("the limit was ignored: %d hits", n)
	}
	for _, query := range []string{"", "   ", "zzzznotaword"} {
		if n := len(e.SearchMiracles(query, 25)); n != 0 {
			t.Fatalf("%q -> %d hits", query, n)
		}
	}
}

func TestMiraclesEmptyCorpusAnswersNothing(t *testing.T) {
	// LoadFrom leaves this corpus at its zero value when the file is absent, and every call has to
	// survive that: a consumer without the pack sees an empty corpus, not a crash.
	empty := &Engine{}
	articles, categories, ayahRefs := empty.MiraclesCount()
	if articles != 0 || categories != 0 || ayahRefs != 0 {
		t.Fatalf("an empty corpus counted (%d, %d, %d)", articles, categories, ayahRefs)
	}
	if len(empty.Miracles()) != 0 || len(empty.MiracleCategories()) != 0 {
		t.Fatal("an empty corpus answered articles")
	}
	if _, ok := empty.Miracle("big_bang_crunch"); ok {
		t.Fatal("an empty corpus resolved a slug")
	}
	if _, ok := empty.MiracleCategoryByID("cosmology"); ok {
		t.Fatal("an empty corpus resolved a category")
	}
	if len(empty.MiracleLevelsPresent()) != 0 || len(empty.MiraclesCiting(21, 30)) != 0 {
		t.Fatal("an empty corpus answered levels or citations")
	}
	if len(empty.MiracleAyahRefs("big_bang_crunch")) != 0 || empty.MiracleText("big_bang_crunch") != "" {
		t.Fatal("an empty corpus answered refs or prose")
	}
	if len(empty.SearchMiracles("big bang", 25)) != 0 || empty.MiraclesImagesIncluded() {
		t.Fatal("an empty corpus answered a search or claimed images")
	}
	// And the loaded one is not empty, so the checks above are not vacuous.
	e := loadTestEngine(t)
	if len(e.Miracles()) == 0 {
		t.Fatal("the loaded corpus is empty")
	}
}
