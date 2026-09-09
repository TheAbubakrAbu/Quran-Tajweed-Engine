package quranengine

// Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil, the qiraat variant
// matrix and the word of the day.
//
// Mirrors the JS test/batch5.test.js and the Python tests/test_batch5.py case for case. Every
// count is pinned against the app's own verify gate, so a corpus that reaches the engine
// half-imported fails loudly rather than quietly answering less than it should.

import (
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"
)

var trees = []TopicTree{TreeThematic, TreeOntology, TreeIndex}

func batch5Engine(t *testing.T) *Engine {
	t.Helper()
	engine, err := LoadWith(LoadOptions{
		Morphology: true, Mutashabihat: true, QulTopics: true, QiraatVariants: true,
	})
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	return engine
}

func ayahTokens(e *Engine, surah, ayah int) []string {
	a := e.Ayah(surah, ayah)
	if a == nil {
		return nil
	}
	return strings.Fields(a.TextArabic)
}

// ---- morphology -------------------------------------------------------------------

func TestMorphologyCorpusSize(t *testing.T) {
	e := batch5Engine(t)
	roots, lemmas, tokens := e.MorphologyCount()
	if roots != 1642 || lemmas != 4817 || tokens != 77629 {
		t.Fatalf("got %d/%d/%d, want 1642/4817/77629", roots, lemmas, tokens)
	}
}

func TestMorphologyIDsAreOneBased(t *testing.T) {
	e := batch5Engine(t)
	if _, ok := e.Root(0); ok {
		t.Fatal("id 0 must not resolve: it means the token has no root")
	}
	if _, ok := e.Root(1); !ok {
		t.Fatal("id 1 must resolve")
	}
	if _, ok := e.Root(1643); ok {
		t.Fatal("root ids stop at the table size")
	}
	roots, lemmas, ok := e.MorphologyIDs(1, 1)
	if !ok || len(roots) != 4 || len(lemmas) != 4 {
		t.Fatalf("1:1 has four tokens, got %d/%d ok=%v", len(roots), len(lemmas), ok)
	}
}

func TestMorphologyTokenResolvesToRootAndLemma(t *testing.T) {
	e := batch5Engine(t)
	// 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
	_, root, ok := e.RootOf(1, 2, 2)
	if !ok || root.Letters != "ر ب ب" || root.Buckwalter != "rbb" || root.Joined != "ربب" {
		t.Fatalf("got %+v ok=%v", root, ok)
	}
	if _, lemma, ok := e.LemmaOf(1, 2, 2); !ok || lemma.Text == "" {
		t.Fatalf("no lemma for 1:2 token 2")
	}
}

func TestMorphologyOccurrencesAreInMushafOrder(t *testing.T) {
	e := batch5Engine(t)
	hits := e.FindRoots("ربب", 5)
	if len(hits) == 0 {
		t.Fatal("no root for ربب")
	}
	found := e.OccurrencesOfRoot(hits[0].ID)
	if len(found) != 980 {
		t.Fatalf("got %d occurrences, want 980", len(found))
	}
	if found[0] != (WordLocation{Surah: 1, Ayah: 2, Token: 2}) {
		t.Fatalf("first occurrence is %+v", found[0])
	}
	sorted := sort.SliceIsSorted(found, func(i, j int) bool {
		a, b := found[i], found[j]
		if a.Surah != b.Surah {
			return a.Surah < b.Surah
		}
		if a.Ayah != b.Ayah {
			return a.Ayah < b.Ayah
		}
		return a.Token < b.Token
	})
	if !sorted {
		t.Fatal("occurrences are not in mushaf order")
	}
}

func TestMorphologyFoldClosesTheSpaces(t *testing.T) {
	e := batch5Engine(t)
	// A lexicon prints "ر ب ب" and a reader types "ربب"; the fold has to close the spaces, not
	// merely trim them.
	if got := FoldForMorphology("ر ب ب"); got != "ربب" {
		t.Fatalf("fold gave %q", got)
	}
	for _, query := range []string{"ربب", "ر ب ب", "rbb"} {
		var seen bool
		for _, hit := range e.FindRoots(query, 5) {
			if hit.Root.Buckwalter == "rbb" {
				seen = true
			}
		}
		if !seen {
			t.Fatalf("no rbb for %q", query)
		}
	}
}

// ---- mutashabihat -----------------------------------------------------------------

func TestMutashabihatCounts(t *testing.T) {
	e := batch5Engine(t)
	if phrases, ayahs := e.MutashabihatCount(); phrases != 814 || ayahs != 2232 {
		t.Fatalf("got %d/%d, want 814/2232", phrases, ayahs)
	}
}

func TestMutashabihatPhraseShape(t *testing.T) {
	e := batch5Engine(t)
	phrase, ok := e.MutashabihatPhrase(10167)
	if !ok {
		t.Fatal("phrase 10167 is missing")
	}
	if phrase.Source != "9:87" || phrase.Span != [2]int{5, 10} || phrase.WordCount != 6 {
		t.Fatalf("got %+v", phrase)
	}
	if phrase.AyahCount != 3 || phrase.SurahCount != 2 {
		t.Fatalf("spread is %d ayahs / %d surahs", phrase.AyahCount, phrase.SurahCount)
	}
	if spans := phrase.Occurrences["9:93"]; len(spans) != 1 || spans[0] != [2]int{13, 19} {
		t.Fatalf("9:93 spans are %v", spans)
	}
}

func TestMutashabihatOccurrencesAreInMushafOrderNotKeyOrder(t *testing.T) {
	e := batch5Engine(t)
	var keys []string
	for _, occurrence := range e.PhraseOccurrences(10167) {
		keys = append(keys, occurrence.Key)
	}
	want := []string{"9:87", "9:93", "63:3"}
	if strings.Join(keys, ",") != strings.Join(want, ",") {
		t.Fatalf("got %v, want %v", keys, want)
	}
}

func TestMutashabihatPhraseSlicesOutOfTheTextYouHandIt(t *testing.T) {
	e := batch5Engine(t)
	source := e.Ayah(9, 87).TextArabic
	text := e.PhraseText(10167, source)
	if len(strings.Fields(text)) != 6 {
		t.Fatalf("phrase text is %q", text)
	}
	if !strings.Contains(source, strings.Fields(text)[0]) {
		t.Fatal("the sliced phrase is not in its own source ayah")
	}
}

func TestMutashabihatHasAgreesWithLookup(t *testing.T) {
	e := batch5Engine(t)
	if !e.HasMutashabihat(9, 87) || len(e.MutashabihatFor(9, 87)) == 0 {
		t.Fatal("9:87 carries a phrase")
	}
	if e.HasMutashabihat(1, 1) != (len(e.MutashabihatFor(1, 1)) > 0) {
		t.Fatal("has() and the lookup disagree")
	}
}

// ---- QUL topics -------------------------------------------------------------------

func TestQulTopicCounts(t *testing.T) {
	e := batch5Engine(t)
	topics, thematic, ontology, index, refs := e.QulTopicCount()
	if topics != 2512 || refs != 30687 {
		t.Fatalf("got %d topics / %d refs", topics, refs)
	}
	if thematic != 695 || ontology != 284 || index != 1550 {
		t.Fatalf("families are %d/%d/%d", thematic, ontology, index)
	}
	// Deliberately sums to MORE than the topic count: the 17 topics listed in two indexes are
	// counted in both, which is what "listed in" means.
	if thematic+ontology+index != 2529 {
		t.Fatalf("family sum is %d, want 2529", thematic+ontology+index)
	}
}

func TestQulTopicsAreThreeIndependentTrees(t *testing.T) {
	e := batch5Engine(t)
	var both int
	for _, topic := range e.QulTopics() {
		if len(topic.Families) > 1 {
			both++
		}
	}
	if both != 17 {
		t.Fatalf("%d topics listed twice, want 17", both)
	}
	thematic, okT := e.TopicParent(13, TreeThematic)
	ontology, okO := e.TopicParent(13, TreeOntology)
	if !okT || !okO {
		t.Fatal("Adam is a node in both the thematic tree and the ontology")
	}
	if thematic.Name != "Prophets (25 mentioned by name)" || ontology.Name != "Prophet" {
		t.Fatalf("Adam's parents are %q / %q", thematic.Name, ontology.Name)
	}
	// A tree is not closed over its own listing either: the A-Z index hangs entries under
	// thematic topics, so asserting a parent shares its child's family would be false.
	var crossing int
	for _, topic := range e.QulTopics() {
		parentID := topic.Parents[TreeIndex]
		if parentID == 0 {
			continue
		}
		if parent, ok := e.QulTopicByID(parentID); ok && !topicListedIn(parent, TreeIndex) {
			crossing++
		}
	}
	if crossing == 0 {
		t.Fatal("expected the index tree to reach outside its own listing")
	}
}

func TestQulTopicParentsAllResolve(t *testing.T) {
	e := batch5Engine(t)
	for _, topic := range e.QulTopics() {
		for _, tree := range trees {
			parentID := topic.Parents[tree]
			if parentID == 0 {
				continue
			}
			if _, ok := e.QulTopicByID(parentID); !ok {
				t.Fatalf("topic %d (%s) has a dangling %s parent %d", topic.ID, topic.Name, tree, parentID)
			}
		}
	}
}

func TestQulTopicAncestorsTerminateInEveryTree(t *testing.T) {
	e := batch5Engine(t)
	for _, tree := range trees {
		var deep *QulTopic
		for i := range e.qulTopics {
			if len(e.TopicAncestors(e.qulTopics[i].ID, tree)) >= 2 {
				deep = &e.qulTopics[i]
				break
			}
		}
		if deep == nil {
			t.Fatalf("no topic two levels down in the %s tree", tree)
		}
		chain := e.TopicAncestors(deep.ID, tree)
		seen := map[int]bool{}
		for _, ancestor := range chain {
			if seen[ancestor.ID] {
				t.Fatalf("cycle in the %s tree", tree)
			}
			seen[ancestor.ID] = true
		}
		if chain[len(chain)-1].Parents[tree] != 0 {
			t.Fatalf("the %s chain does not end at a root", tree)
		}
	}
}

func TestQulTopicChildrenListTheirParent(t *testing.T) {
	e := batch5Engine(t)
	for _, tree := range trees {
		var child *QulTopic
		for i := range e.qulTopics {
			if e.qulTopics[i].Parents[tree] != 0 {
				child = &e.qulTopics[i]
				break
			}
		}
		if child == nil {
			t.Fatalf("no child in the %s tree", tree)
		}
		var found bool
		for _, sibling := range e.TopicChildren(child.Parents[tree], tree) {
			if sibling.ID == child.ID {
				found = true
			}
		}
		if !found {
			t.Fatalf("%s missing from its %s parent", child.Name, tree)
		}
	}
}

func TestQulTopicReferencesAreRealAyahs(t *testing.T) {
	e := batch5Engine(t)
	sample := e.QulTopics()
	if len(sample) > 200 {
		sample = sample[:200]
	}
	for _, topic := range sample {
		for _, key := range topic.Ayahs {
			surah, ayah := splitAyahKey(key)
			if e.Ayah(surah, ayah) == nil {
				t.Fatalf("%s cites %s", topic.Name, key)
			}
		}
	}
	first := sample[0]
	surah, ayah := splitAyahKey(first.Ayahs[0])
	var found bool
	for _, topic := range e.QulTopicsFor(surah, ayah) {
		if topic.ID == first.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("the reverse lookup does not agree with the forward one")
	}
}

// ---- passage themes ---------------------------------------------------------------

func TestPassageCounts(t *testing.T) {
	e := batch5Engine(t)
	if surahs, passages := e.PassageCount(); surahs != 114 || passages != 1049 {
		t.Fatalf("got %d surahs / %d passages, want 114/1049", surahs, passages)
	}
}

func TestPassagesAreOrderedAndNeverOverlap(t *testing.T) {
	e := batch5Engine(t)
	for _, surah := range e.Surahs() {
		previousEnd := 0
		for _, passage := range e.Passages(surah.ID) {
			if previousEnd != 0 && passage.From <= previousEnd {
				t.Fatalf("surah %d: %d overlaps %d", surah.ID, passage.From, previousEnd)
			}
			if passage.To < passage.From || passage.To > surah.NumberOfAyahs {
				t.Fatalf("surah %d: bad range %d..%d", surah.ID, passage.From, passage.To)
			}
			previousEnd = passage.To
		}
	}
}

func TestPassageForFindsTheContainingPassage(t *testing.T) {
	e := batch5Engine(t)
	passage, ok := e.PassageFor(2, 10)
	if !ok || passage.Theme != "Hypocrites and the consequences of hypocrisy" {
		t.Fatalf("got %+v ok=%v", passage, ok)
	}
	if passage.From != 8 || passage.To != 16 {
		t.Fatalf("range is %d..%d", passage.From, passage.To)
	}
}

// ---- hizb / ruku / manzil ---------------------------------------------------------

func TestDivisionCountsAndFirstStarts(t *testing.T) {
	e := batch5Engine(t)
	if e.DivisionCount(Hizb) != 60 || e.DivisionCount(Ruku) != 558 || e.DivisionCount(Manzil) != 7 {
		t.Fatalf("counts are %d/%d/%d", e.DivisionCount(Hizb), e.DivisionCount(Ruku), e.DivisionCount(Manzil))
	}
	for _, kind := range []DivisionKind{Hizb, Ruku, Manzil} {
		start, ok := e.DivisionStart(kind, 1)
		if !ok || start.Key != "1:1" {
			t.Fatalf("kind %d starts at %+v", kind, start)
		}
	}
}

func TestDivisionStartsAscendAndAreRealAyahs(t *testing.T) {
	e := batch5Engine(t)
	for _, kind := range []DivisionKind{Hizb, Ruku, Manzil} {
		all := e.Divisions(kind)
		for i := 1; i < len(all); i++ {
			a, b := all[i-1], all[i]
			if a.Surah > b.Surah || (a.Surah == b.Surah && a.Ayah >= b.Ayah) {
				t.Fatalf("kind %d out of order at %s", kind, b.Key)
			}
			if e.Ayah(b.Surah, b.Ayah) == nil {
				t.Fatalf("%s is not an ayah", b.Key)
			}
		}
	}
}

func TestDivisionLookupContainsTheAyah(t *testing.T) {
	e := batch5Engine(t)
	if h, r, m := e.DivisionsFor(1, 1); h != 1 || r != 1 || m != 1 {
		t.Fatalf("1:1 is in %d/%d/%d", h, r, m)
	}
	if h, _, m := e.DivisionsFor(114, 6); h != 60 || m != 7 {
		t.Fatalf("114:6 is in hizb %d manzil %d", h, m)
	}
	n := e.DivisionFor(Hizb, 2, 255)
	from, until, hasEnd, ok := e.DivisionRange(Hizb, n)
	if !ok {
		t.Fatal("no range for the hizb containing 2:255")
	}
	if from.Surah > 2 || (from.Surah == 2 && from.Ayah > 255) {
		t.Fatalf("the hizb starts after the ayah it contains: %s", from.Key)
	}
	if hasEnd && (until.Surah < 2 || (until.Surah == 2 && until.Ayah <= 255)) {
		t.Fatalf("the next hizb starts at or before the ayah: %s", until.Key)
	}
}

// ---- qiraat variants --------------------------------------------------------------

func TestQiraatVariantCounts(t *testing.T) {
	e := batch5Engine(t)
	ayahs, junctures, readings := e.QiraatVariantCount()
	if ayahs != 1409 || junctures != 1634 || readings != 3503 {
		t.Fatalf("got %d/%d/%d, want 1409/1634/3503", ayahs, junctures, readings)
	}
}

func TestQiraatVariantReadersAndTransmitters(t *testing.T) {
	e := batch5Engine(t)
	if len(e.variants.Readers) != 10 || len(e.variants.Transmitters) != 20 {
		t.Fatalf("got %d readers / %d transmitters", len(e.variants.Readers), len(e.variants.Transmitters))
	}
	published := 0
	for _, transmitter := range e.variants.Transmitters {
		if _, ok := e.VariantReaderByID(transmitter.Reader); !ok {
			t.Fatalf("%s has no imam", transmitter.Name)
		}
		if transmitter.TextPublished {
			published++
		}
	}
	if published != 8 {
		t.Fatalf("%d riwayat carry published text, want 8", published)
	}
}

func TestJunctureNamesWordReadingsAndWhoReadsThem(t *testing.T) {
	e := batch5Engine(t)
	junctures := e.Junctures(102, 6)
	if len(junctures) == 0 {
		t.Fatal("102:6 carries a variant")
	}
	for _, juncture := range junctures {
		if len(juncture.Readings) < 2 {
			t.Fatal("a juncture with one reading is not a variant")
		}
		for _, reading := range juncture.Readings {
			if reading.Text == "" {
				t.Fatal("a reading with no text")
			}
			if len(reading.Readers)+len(reading.Transmitters) == 0 {
				t.Fatal("a reading nobody reads")
			}
		}
	}
}

// Every reading, not a sample: ranging over a map samples a different fifty each run, so a hole
// in the data showed up only when the iteration order happened to land on it (16:43 did, once).
func TestEveryReadingHasAnAttribution(t *testing.T) {
	e := batch5Engine(t)
	keys := make([]string, 0, len(e.variants.Ayahs))
	for key := range e.variants.Ayahs {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		surah, ayah := splitAyahKey(key)
		for _, juncture := range e.Junctures(surah, ayah) {
			for _, reading := range juncture.Readings {
				if e.VariantAttribution(reading) == "" {
					t.Errorf("%s has a reading (%q) with no attribution", key, reading.Text)
				}
			}
		}
	}
}

// A transmitter named on one reading parts from his imam, who is named on another: the imam's
// listing covers his OTHER transmitter only. Ḥafṣ and Shuʿbah split over نوحي/يوحى in all three
// places it occurs, and data/qiraat/ shows Shuʿbah reciting يوحى, so resolving him through ʿĀṣim
// would hand him the wrong form.
func TestNamedTransmitterOverridesHisImamsReading(t *testing.T) {
	e := batch5Engine(t)
	for _, place := range []struct{ surah, ayah int }{{12, 109}, {16, 43}, {21, 7}} {
		for _, juncture := range e.Junctures(place.surah, place.ayah) {
			if !strings.Contains(juncture.Word, "وح") {
				continue
			}
			// The two forms differ in their first letter: Allah's "We inspire" against the
			// passive "it is inspired". Diacritics vary between the three places, so compare
			// only that letter.
			for riwayah, want := range map[string]string{"hafs": "ن", "shubah": "ي"} {
				reading, ok := e.ReadingFor(juncture, riwayah)
				if !ok {
					t.Fatalf("%d:%d has no reading for %s", place.surah, place.ayah, riwayah)
				}
				if !strings.HasPrefix(reading.Text, want) {
					t.Errorf("%d:%d %s reads %q, want one starting %q",
						place.surah, place.ayah, riwayah, reading.Text, want)
				}
			}
		}
	}
}

func TestHafsFollowsAReadingAtJuncturesHeIsPartyTo(t *testing.T) {
	e := batch5Engine(t)
	matched, checked := 0, 0
	for key := range e.variants.Ayahs {
		if checked >= 100 {
			break
		}
		checked++
		surah, ayah := splitAyahKey(key)
		for _, juncture := range e.Junctures(surah, ayah) {
			if _, ok := e.ReadingFor(juncture, "hafs"); ok {
				matched++
			}
		}
	}
	if matched == 0 {
		t.Fatal("Hafs reads none of the sampled junctures, which cannot be right")
	}
}

func TestSegmentSpansAreInclusiveOrAnHonestNil(t *testing.T) {
	e := batch5Engine(t)
	checked := 0
	for key := range e.variants.Ayahs {
		if checked >= 200 {
			break
		}
		checked++
		surah, ayah := splitAyahKey(key)
		for _, juncture := range e.Junctures(surah, ayah) {
			for _, segment := range juncture.Segments {
				if segment.Span == nil {
					continue
				}
				from, to := segment.Span[0], segment.Span[1]
				if from < 0 || to < from {
					t.Fatalf("%s: bad span %d..%d", key, from, to)
				}
				s, a := splitAyahKey(segment.Ayah)
				if to >= len(ayahTokens(e, s, a)) {
					t.Fatalf("%s: span ends past the last token", segment.Ayah)
				}
			}
		}
	}
}

// ---- qiraat places ----------------------------------------------------------------

func TestPlacesCoverOnlyThePublishedRiwayat(t *testing.T) {
	e := batch5Engine(t)
	slugs := e.RiwayatWithPlaces()
	// Hafs is the reference and indexes nothing against itself.
	want := []string{"buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"}
	if strings.Join(slugs, ",") != strings.Join(want, ",") {
		t.Fatalf("got %v, want %v", slugs, want)
	}
}

func TestPlacesPointAtTokensTheAyahHas(t *testing.T) {
	e := batch5Engine(t)
	for _, slug := range e.RiwayatWithPlaces() {
		for _, surah := range []int{1, 2, 18} {
			for _, place := range e.QiraatPlaces(slug, surah) {
				count := len(ayahTokens(e, surah, place.Ayah))
				for _, index := range append(append([]int{}, place.Word...), place.Letter...) {
					if index < 0 || index >= count {
						t.Fatalf("%s %d:%d index %d of %d", slug, surah, place.Ayah, index, count)
					}
				}
			}
		}
	}
}

func TestAlFatihahCarriesADifferenceForWarsh(t *testing.T) {
	e := batch5Engine(t)
	for _, place := range e.QiraatPlaces("warsh", 1) {
		if place.Ayah == 4 {
			if len(place.Word) == 0 && len(place.Letter) == 0 {
				t.Fatal("1:4 is listed with no differing word")
			}
			return
		}
	}
	t.Fatal("Warsh differs from Hafs at 1:4")
}

// ---- paired recordings ------------------------------------------------------------

func TestAudioCoversFourRiwayatAndHonestlyNoOthers(t *testing.T) {
	e := batch5Engine(t)
	if slugs := e.RiwayatWithAudio(); len(slugs) != 4 {
		t.Fatalf("got %v", slugs)
	}
	if _, ok := e.VariantAudio("qunbul", 1, 4); ok {
		t.Fatal("Qunbul has no reciter who published both sides with timings")
	}
}

func TestAudioPairIsOneReciterTwoUrlsAndMatchingSpanKinds(t *testing.T) {
	e := batch5Engine(t)
	mp3 := regexp.MustCompile(`^https?://.+\.mp3$`)
	found := 0
	for _, slug := range e.RiwayatWithAudio() {
		for surah := 1; surah <= 114 && found < 8; surah++ {
			for ayah := 1; ayah <= 10; ayah++ {
				pair, ok := e.VariantAudio(slug, surah, ayah)
				if !ok {
					continue
				}
				found++
				if pair.Reciter == "" {
					t.Fatal("a pair with no reciter")
				}
				if !mp3.MatchString(pair.Hafs.URL) || !mp3.MatchString(pair.Riwayah.URL) {
					t.Fatalf("bad urls %q / %q", pair.Hafs.URL, pair.Riwayah.URL)
				}
				if pair.Hafs.URL == pair.Riwayah.URL {
					t.Fatal("a pair must differ in the reading")
				}
				if (pair.Hafs.StartMs == nil) != (pair.Riwayah.StartMs == nil) {
					t.Fatal("one side is a seek and the other a whole file")
				}
				if pair.Hafs.StartMs != nil && *pair.Hafs.EndMs <= *pair.Hafs.StartMs {
					t.Fatal("a clip that ends before it starts")
				}
				break
			}
		}
	}
	if found < 4 {
		t.Fatalf("only found %d pairs", found)
	}
}

// ---- word of the day --------------------------------------------------------------

func TestWordOfDayCount(t *testing.T) {
	e := batch5Engine(t)
	if words, _ := e.WordOfDayCount(); words != 149 {
		t.Fatalf("got %d words, want 149", words)
	}
}

func TestWordOfDayWalkWrapsAndHandlesANegativeIndex(t *testing.T) {
	e := batch5Engine(t)
	all := e.WordsOfDay()
	n := len(all)
	first, _ := e.WordOfDayForIndex(0)
	wrapped, _ := e.WordOfDayForIndex(n)
	back, _ := e.WordOfDayForIndex(-1)
	if first.ID != all[0].ID || wrapped.ID != all[0].ID || back.ID != all[n-1].ID {
		t.Fatalf("walk gave %s / %s / %s", first.ID, wrapped.ID, back.ID)
	}
	noon, _ := e.WordOfDayForDate(time.Date(2026, 9, 8, 12, 0, 0, 0, time.UTC))
	night, _ := e.WordOfDayForDate(time.Date(2026, 9, 8, 23, 0, 0, 0, time.UTC))
	if noon.ID != night.ID {
		t.Fatal("the word changed inside one calendar day")
	}
}

func TestWordOfDayCountIsTheLengthOfTheListBehindIt(t *testing.T) {
	e := batch5Engine(t)
	for _, word := range e.WordsOfDay() {
		total := 0
		for _, occurrence := range word.Occurrences {
			total += len(occurrence.Tokens)
		}
		if word.Count != total {
			t.Fatalf("%s says %d, the list has %d", word.ID, word.Count, total)
		}
	}
}

func TestWordOfDayAnchorAndFoldedTokens(t *testing.T) {
	e := batch5Engine(t)
	// Occurrences were matched FOLDED upstream, so ٱلۡحَمۡدُۖ at 64:1 is the same form as
	// ٱلۡحَمۡدُ; comparing written tokens literally would call a pause mark a mismatch.
	marks := regexp.MustCompile("[ً-ٰٟۖ-ۭـ]")
	fold := func(s string) string {
		s = marks.ReplaceAllString(s, "")
		r := strings.NewReplacer("ٱ", "ا", "أ", "ا", "إ", "ا",
			"ؤ", "و", "ئ", "ي")
		return r.Replace(s)
	}
	for _, word := range e.WordsOfDay() {
		first := word.Occurrences[0]
		if first.Surah != word.Surah || first.Ayah != word.Ayah || first.Tokens[0] != word.Token {
			t.Fatalf("%s: the anchor is not the first appearance", word.ID)
		}
		target := fold(word.Arabic)
		for _, occurrence := range word.Occurrences {
			tokens := ayahTokens(e, occurrence.Surah, occurrence.Ayah)
			for _, index := range occurrence.Tokens {
				if index >= len(tokens) || fold(tokens[index]) != target {
					t.Fatalf("%s at %d:%d token %d", word.ID, occurrence.Surah, occurrence.Ayah, index)
				}
			}
		}
	}
}

func TestWordOfDaySearchAndReverseLookup(t *testing.T) {
	e := batch5Engine(t)
	first := e.WordsOfDay()[0]
	var bySearch, byAyah bool
	for _, word := range e.SearchWordsOfDay(first.Arabic, 25) {
		if word.ID == first.ID {
			bySearch = true
		}
	}
	for _, word := range e.WordsOfDayIn(first.Surah, first.Ayah) {
		if word.ID == first.ID {
			byAyah = true
		}
	}
	if !bySearch || !byAyah {
		t.Fatalf("search=%v ayah=%v", bySearch, byAyah)
	}
}
