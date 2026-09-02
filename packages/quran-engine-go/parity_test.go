package quranengine

// The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah outlines,
// alphabet reference and qiraat comparison that followed it.
//
// Mirrors the JS test/parity.test.js, the Python tests/test_parity.py, the Swift ParityTests.swift
// and the Rust tests/parity.rs case for case, so a divergence between the ports shows up as a
// failing test rather than as a surprise in an app.

import (
	"strings"
	"testing"
)

func parityEngine(t *testing.T) *Engine {
	t.Helper()
	engine, err := LoadWith(LoadOptions{
		Mushaf:        true,
		QiraatTajweed: true,
		WordByWord:    true,
		SimilarAyahs:  true,
		Qiraat:        true,
	})
	if err != nil {
		t.Fatalf("engine loads: %v", err)
	}
	return engine
}

// ---- mushaf -------------------------------------------------------------------------

func TestTwentyRiwayatEightWithText(t *testing.T) {
	e := parityEngine(t)
	if got := len(e.Riwayat()); got != 20 {
		t.Fatalf("riwayat = %d, want 20", got)
	}
	if got := len(e.RiwayatWithText()); got != 8 {
		t.Fatalf("riwayat with text = %d, want 8", got)
	}
	if got := e.MushafTotalPages(); got != 604 {
		t.Fatalf("total pages = %d, want 604", got)
	}
	if got := e.Riwayah("warsh").Imam; got != "Nafi" {
		t.Fatalf("warsh imam = %q, want Nafi", got)
	}
	if e.Riwayah("hisham").TextIncluded {
		t.Fatal("hisham's text is beta and must not be published")
	}
}

func TestEveryRiwayahHasAFacsimileAndAFullPageTable(t *testing.T) {
	e := parityEngine(t)
	for _, entry := range e.Riwayat() {
		if !strings.HasPrefix(entry.PDF, "pdfs/") || !strings.HasSuffix(entry.PDF, ".pdf.xz") {
			t.Errorf("%s: pdf = %q", entry.Riwayah, entry.PDF)
		}
		if entry.PDFBytes <= 100_000 {
			t.Errorf("%s: pdfBytes = %d", entry.Riwayah, entry.PDFBytes)
		}
		// Al-Fatihah opens page 1 and an-Nas closes page 604 in every print of the set.
		if got := e.MushafPage(1, 1, entry.Riwayah); got != 1 {
			t.Errorf("%s: 1:1 on page %d, want 1", entry.Riwayah, got)
		}
		if got := e.MushafPage(114, 6, entry.Riwayah); got != 604 {
			t.Errorf("%s: 114:6 on page %d, want 604", entry.Riwayah, got)
		}
	}
}

func TestPagesResolveBackToTheirAyahs(t *testing.T) {
	e := parityEngine(t)
	if got := e.MushafPage(2, 255, "hafs"); got != 42 {
		t.Fatalf("2:255 on page %d, want 42", got)
	}
	found := false
	for _, hit := range e.MushafAyahsOnPage(42, "hafs") {
		if hit.Surah == 2 && hit.Ayah == 255 {
			found = true
		}
	}
	if !found {
		t.Fatal("2:255 missing from page 42")
	}
	first := e.MushafFirstAyahOfPage(1, "hafs")
	if first == nil || first.Surah != 1 || first.Ayah != 1 {
		t.Fatalf("first ayah of page 1 = %+v, want 1:1", first)
	}
}

func TestLineTablesShipExactlyWhereTheTextDoes(t *testing.T) {
	e := parityEngine(t)
	for _, entry := range e.Riwayat() {
		_, ok := e.MushafLineBreaks(1, 1, entry.Riwayah)
		if ok != entry.TextIncluded {
			t.Errorf("%s: line breaks present = %v, text included = %v",
				entry.Riwayah, ok, entry.TextIncluded)
		}
	}
}

// ---- riwayah tajweed -----------------------------------------------------------------

func TestSevenVerifiedPacks(t *testing.T) {
	e := parityEngine(t)
	want := []string{"buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"}
	got := e.QiraatTajweedAvailable()
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("available = %v, want %v", got, want)
	}
}

func TestLegendCarriesItsExplanation(t *testing.T) {
	e := parityEngine(t)
	legend := e.QiraatLegend("warsh")
	if len(legend) < 3 {
		t.Fatalf("legend has %d entries", len(legend))
	}
	for _, entry := range legend {
		if len([]rune(entry.Code)) != 1 {
			t.Errorf("code %q is not one letter", entry.Code)
		}
		if entry.Rule == "" || entry.Arabic == "" || entry.English == "" {
			t.Errorf("incomplete legend entry %+v", entry)
		}
		if entry.Short == "" {
			t.Errorf("no description for %s", entry.Rule)
		}
	}
}

func TestWordRulesNameRealLegendCodes(t *testing.T) {
	e := parityEngine(t)
	rules := e.QiraatWordRules(2, 3, "warsh")
	if len(rules) == 0 {
		t.Fatal("no word rules for 2:3 in warsh")
	}
	codes := map[string]bool{}
	for _, entry := range e.QiraatLegend("warsh") {
		codes[entry.Code] = true
	}
	for _, rule := range rules {
		if !codes[rule.Code] {
			t.Errorf("code %q is not in the legend", rule.Code)
		}
		if rule.WholeWord != (rule.FirstLetter < 0) {
			t.Errorf("wholeWord/firstLetter disagree: %+v", rule)
		}
		if rule.Word < 1 {
			t.Errorf("word index %d is not 1-based", rule.Word)
		}
	}
}

func TestKhilafMarkers(t *testing.T) {
	e := parityEngine(t)
	if !e.HasKhilaf(2, 253, "warsh") {
		t.Error("2:253 should be marked khilaf in warsh")
	}
	if e.HasKhilaf(2, 254, "warsh") {
		t.Error("2:254 should not be marked khilaf in warsh")
	}
}

// ---- word by word ---------------------------------------------------------------------

func TestBothLayersAlignedToTheAyahsOwnTokens(t *testing.T) {
	e := parityEngine(t)
	words := e.Words(112, 1)
	var latin []string
	for _, word := range words {
		latin = append(latin, word.Transliteration)
	}
	if strings.Join(latin, " ") != "qul huwa l-lahu aḥadun" {
		t.Fatalf("transliteration = %v", latin)
	}
	if words[0].English != "Say" {
		t.Fatalf("first gloss = %q", words[0].English)
	}
	firstToken := strings.Fields(e.Ayah(112, 1).TextArabic)[0]
	if words[0].Arabic != firstToken {
		t.Fatalf("first token = %q, want %q", words[0].Arabic, firstToken)
	}
}

func TestEveryAyahsArraysMatchItsTokenCount(t *testing.T) {
	e := parityEngine(t)
	for _, surah := range e.Surahs() {
		for _, ayah := range surah.Ayahs {
			tokens := len(strings.Fields(ayah.TextArabic))
			glosses, ok := e.Glosses(surah.ID, ayah.ID)
			if !ok || len(glosses) != tokens {
				t.Fatalf("%d:%d english: %d entries for %d tokens (present=%v)",
					surah.ID, ayah.ID, len(glosses), tokens, ok)
			}
			latin, ok := e.Transliterations(surah.ID, ayah.ID)
			if !ok || len(latin) != tokens {
				t.Fatalf("%d:%d transliteration: %d entries for %d tokens (present=%v)",
					surah.ID, ayah.ID, len(latin), tokens, ok)
			}
		}
	}
}

func TestGlossSearchFindsTheWord(t *testing.T) {
	e := parityEngine(t)
	hits := e.FindGloss("the Ever-Living", 5)
	found := false
	for _, hit := range hits {
		if hit.Surah == 2 && hit.Ayah == 255 {
			found = true
		}
		if hit.Transliteration == "" {
			t.Errorf("%d:%d word %d has no transliteration", hit.Surah, hit.Ayah, hit.Position)
		}
	}
	if !found {
		t.Fatal("2:255 missing from the gloss search")
	}
}

// ---- similar ayahs, themes, lessons ------------------------------------------------------

func TestSimilarAyahs(t *testing.T) {
	e := parityEngine(t)
	matches := e.SimilarAyahs(2, 255)
	found := false
	for _, match := range matches {
		if match.Surah == 3 && match.Ayah == 2 {
			found = true
			if !match.Verified {
				t.Error("3:2 is a classical match and should be verified")
			}
		}
	}
	if !found {
		t.Fatal("3:2 is not listed as similar to 2:255")
	}
	if !e.HasSimilarAyahs(2, 255) {
		t.Error("HasSimilarAyahs disagrees with SimilarAyahs")
	}
	if e.SimilarAyahCount() <= 5000 {
		t.Errorf("only %d ayahs have matches", e.SimilarAyahCount())
	}
}

func TestThemesIndexBothWays(t *testing.T) {
	e := parityEngine(t)
	if len(e.Topics()) < 300 {
		t.Fatalf("%d topics", len(e.Topics()))
	}
	tawheed := e.Topic("tawheed")
	if tawheed == nil {
		t.Fatal("no tawheed topic")
	}
	listed := false
	for _, ayah := range tawheed.Ayahs {
		if ayah == "2:255" {
			listed = true
		}
	}
	if !listed {
		t.Error("2:255 is not listed under tawheed")
	}
	back := false
	for _, topic := range e.TopicsFor(2, 255) {
		if topic.ID == "tawheed" {
			back = true
		}
	}
	if !back {
		t.Error("TopicsFor does not invert the topic lists")
	}
	if len(e.TopicDomains()) < 2 {
		t.Error("expected several domains")
	}
}

func TestLessonsWalkInCourseOrder(t *testing.T) {
	e := parityEngine(t)
	lessons := e.TajweedLessons()
	if len(lessons) < 30 {
		t.Fatalf("%d lessons", len(lessons))
	}
	if e.PreviousTajweedLesson(lessons[0].ID) != nil {
		t.Error("the first lesson has no predecessor")
	}
	next := e.NextTajweedLesson(lessons[0].ID)
	if next == nil || next.ID != lessons[1].ID {
		t.Errorf("next after %s = %+v", lessons[0].ID, next)
	}
	if e.TajweedChapterOf(lessons[0].ID) == nil {
		t.Error("every lesson belongs to a chapter")
	}
}

// ---- meaning search ---------------------------------------------------------------------

func TestMaxSimRanksByMeaning(t *testing.T) {
	// A toy embedder: enough to prove the scoring, without shipping a model.
	vectors := map[string][]float64{
		"patience":  {1.0, 0.0, 0.0},
		"hardship":  {0.9, 0.1, 0.0},
		"sabr":      {0.95, 0.05, 0.0},
		"steadfast": {0.9, 0.05, 0.0},
		"dawn":      {0.0, 1.0, 0.0},
		"prayer":    {0.0, 0.95, 0.0},
	}
	semantic := NewSemantic(func(word string) []float64 { return vectors[word] })
	semantic.Index([]SemanticDocument{
		{ID: "sabr", Text: "sabr and steadfast endurance"},
		{ID: "fajr", Text: "prayer at dawn"},
	})
	hits := semantic.Search("patience hardship", 10, 0)
	if len(hits) < 2 || hits[0].ID != "sabr" {
		t.Fatalf("hits = %+v", hits)
	}
	if hits[0].Score <= hits[1].Score {
		t.Fatalf("scores do not separate: %+v", hits)
	}
}

// ---- ask AI ------------------------------------------------------------------------------

func TestNamedVerseIsTheSubject(t *testing.T) {
	e := parityEngine(t)
	passages := e.AskAIRetrieve("explain ayat al-kursi", AskAIOptions{})
	if len(passages) == 0 || passages[0].Reference != "2:255" || !passages[0].IsSubject {
		t.Fatalf("passages[0] = %+v", passages)
	}
}

func TestNamedSurahAnswersWithItsBackground(t *testing.T) {
	e := parityEngine(t)
	passages := e.AskAIRetrieve("what is surah al-kahf about", AskAIOptions{})
	if len(passages) == 0 || passages[0].Reference != "Surah Al-Kahf" || passages[0].Kind != PassageSurah {
		t.Fatalf("passages[0] = %+v", passages)
	}
}

func TestKeywordLaneIsWeighted(t *testing.T) {
	e := parityEngine(t)
	passages := e.AskAIRetrieve("what does the Quran say about patience in hardship", AskAIOptions{})
	found := false
	for _, passage := range passages {
		if passage.Reference == "2:153" {
			found = true
		}
		if passage.Kind == PassageAyah && e.Ayah(passage.Surah, passage.Ayah) == nil {
			t.Errorf("passage %s names an ayah that does not exist", passage.Reference)
		}
	}
	if !found {
		t.Fatalf("2:153 missing from %d passages", len(passages))
	}
}

func TestBareFollowUpUsesThePreviousQuestion(t *testing.T) {
	e := parityEngine(t)
	carried := e.AskAIRetrieve("tell me about 2:153", AskAIOptions{})
	if len(e.AskAIRetrieve("why?", AskAIOptions{})) != 0 {
		t.Error("a bare follow-up with no context retrieves nothing")
	}
	withContext := e.AskAIRetrieve("why?", AskAIOptions{
		PreviousQuestion: "tell me about 2:153",
		Carried:          carried,
	})
	found := false
	for _, passage := range withContext {
		if passage.Reference == "2:153" {
			found = true
		}
	}
	if !found {
		t.Fatalf("the carried passage was dropped: %+v", withContext)
	}
}

func TestPromptShape(t *testing.T) {
	e := parityEngine(t)
	passages := e.AskAIRetrieve("explain 2:153", AskAIOptions{})
	instructions, prompt := ChatPrompt("explain 2:153", passages, nil)
	if !strings.Contains(instructions, "Never issue a religious ruling") {
		t.Error("the instructions lost the no-fatwa rule")
	}
	if !strings.Contains(prompt, "SUBJECT OF THE QUESTION [2:153]") {
		t.Errorf("prompt does not mark the subject:\n%s", prompt)
	}
	if !strings.HasSuffix(strings.TrimRight(prompt, "\n"), "QUESTION: explain 2:153") {
		t.Errorf("prompt does not end with the question:\n%s", prompt)
	}
	if !QuestionWords["what"] {
		t.Error("QuestionWords lost a stopword")
	}
}

// ---- surah sections -------------------------------------------------------------------

func TestSections111SurahsAndAChain(t *testing.T) {
	e := parityEngine(t)
	if got := e.OutlinedSurahCount(); got != 111 {
		t.Fatalf("outlined surahs = %d, want 111", got)
	}
	if len(e.SurahOverview(1)) <= 20 {
		t.Errorf("al-Fatihah has no overview")
	}
	if e.HasSections(1) {
		t.Errorf("al-Fatihah is one of the three surahs with no outline")
	}
	// Hud opens with a broad passage and the sections inside it - an ayah has a chain, not a row.
	var chain []string
	for _, section := range e.SectionsFor(11, 3) {
		chain = append(chain, section.English)
	}
	if strings.Join(chain, "|") != "Doctrine facts|Calling to Allah" {
		t.Fatalf("chain = %v", chain)
	}
	if got := e.SectionFor(11, 3); got == nil || got.English != "Calling to Allah" {
		t.Fatalf("innermost section = %+v", got)
	}
}

func TestOutlineRebuildsTheNesting(t *testing.T) {
	e := parityEngine(t)
	roots := e.Outline(11)
	if len(roots) < 2 {
		t.Fatalf("%d roots", len(roots))
	}
	if roots[0].Section.English != "Doctrine facts" {
		t.Fatalf("first root = %q", roots[0].Section.English)
	}
	if len(roots[0].Children) != 5 {
		t.Fatalf("%d children", len(roots[0].Children))
	}
	for _, child := range roots[0].Children {
		if child.Section.From < roots[0].Section.From || child.Section.To > roots[0].Section.To {
			t.Errorf("child %d-%d escapes its parent", child.Section.From, child.Section.To)
		}
	}
}

func TestSectionRangesAreInsideTheirSurah(t *testing.T) {
	e := parityEngine(t)
	for _, surah := range e.Surahs() {
		for _, section := range e.Sections(surah.ID) {
			if section.From < 1 || section.To > surah.NumberOfAyahs || section.From > section.To {
				t.Errorf("%d: %d-%d outside 1-%d", surah.ID, section.From, section.To, surah.NumberOfAyahs)
			}
			if section.English == "" || section.Arabic == "" {
				t.Errorf("%d: untitled section %d-%d", surah.ID, section.From, section.To)
			}
		}
	}
	nuh := e.SearchSections("Story of Nuh")
	if len(nuh) < 2 {
		t.Fatalf("%d hits for the story of Nuh", len(nuh))
	}
	found := false
	for _, hit := range nuh {
		if hit.Surah == 11 {
			found = true
		}
	}
	if !found {
		t.Error("Hud tells the story of Nuh")
	}
}

// ---- arabic alphabet ------------------------------------------------------------------

func TestAlphabet28LettersEachWithAWeight(t *testing.T) {
	e := parityEngine(t)
	letters := e.Letters()
	if len(letters) != 28 {
		t.Fatalf("%d letters", len(letters))
	}
	weights := e.WeightDescriptions()
	for _, letter := range letters {
		if letter.Letter == "" || letter.Name == "" {
			t.Errorf("incomplete letter %+v", letter)
		}
		if letter.Weight == "" {
			t.Errorf("%s has no weight", letter.Letter)
			continue
		}
		if weights[letter.Weight] == "" {
			t.Errorf("no description for weight %s", letter.Weight)
		}
	}
	// Alif is the one letter with no weight of its own - the fact the whole field exists for.
	if got := e.LetterWeight("ا"); got != "followsPrevious" {
		t.Errorf("alif weight = %q", got)
	}
	if got := e.LetterWeight("ص"); got != "heavy" {
		t.Errorf("saad weight = %q", got)
	}
	if got := e.LetterWeight("س"); got != "light" {
		t.Errorf("seen weight = %q", got)
	}
}

func TestAlphabetResolvesAJoiningForm(t *testing.T) {
	e := parityEngine(t)
	if got := e.Letter("ـصـ"); got == nil || got.Transliteration != "Saad" {
		t.Fatalf("medial saad = %+v", got)
	}
	if got := e.LetterByID(1); got == nil || got.Letter != "ا" {
		t.Fatalf("letter 1 = %+v", got)
	}
	if e.Letter("nope") != nil {
		t.Error("a non-letter resolved")
	}
}

func TestAlphabetTashkeelNumeralsAndWaqf(t *testing.T) {
	e := parityEngine(t)
	if len(e.Tashkeel()) < 8 {
		t.Errorf("%d tashkeel marks", len(e.Tashkeel()))
	}
	if len(e.ArabicNumbers()) != 11 {
		t.Errorf("%d numerals", len(e.ArabicNumbers()))
	}
	if got := e.StoppingSign("۩"); got == nil || got.Title != "Make Sujood" {
		t.Fatalf("sajdah sign = %+v", got)
	}
	if len(e.HeavyLetters()) < 7 {
		t.Errorf("%d heavy letters", len(e.HeavyLetters()))
	}
}

// ---- qiraat comparison ----------------------------------------------------------------

func TestComparisonListsOnlyPublishedReadings(t *testing.T) {
	e := parityEngine(t)
	want := "buzzi,duri,hafs,qaloon,qunbul,shubah,susi,warsh"
	if got := strings.Join(e.ComparableRiwayat(), ","); got != want {
		t.Fatalf("available = %s", got)
	}
}

func TestAReadingAgainstItselfIsIdentical(t *testing.T) {
	e := parityEngine(t)
	same := e.CompareSurah(2, "hafs", "hafs")
	if same.Identical != same.Words || same.SameSkeleton != 0 || same.Different != 0 ||
		same.Added != 0 || same.Dropped != 0 || same.IdenticalPercent() != 100 {
		t.Fatalf("hafs vs hafs = %+v", same)
	}
}

func TestBucketsAddUpAndShubahIsNearerThanWarsh(t *testing.T) {
	e := parityEngine(t)
	warsh := e.CompareSurah(2, "warsh", "hafs")
	shubah := e.CompareSurah(2, "shubah", "hafs")
	for _, totals := range []ComparisonTotals{warsh, shubah} {
		if totals.Identical+totals.SameSkeleton+totals.Different+totals.Dropped != totals.Words {
			t.Errorf("buckets do not add up: %+v", totals)
		}
	}
	// Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
	if shubah.IdenticalPercent() <= warsh.IdenticalPercent() {
		t.Errorf("shubah %.1f%% is not nearer than warsh %.1f%%",
			shubah.IdenticalPercent(), warsh.IdenticalPercent())
	}
	if shubah.IdenticalPercent() <= 95 {
		t.Errorf("shubah is only %.1f%% identical", shubah.IdenticalPercent())
	}
}

func TestDifferencesAreInReadingOrder(t *testing.T) {
	e := parityEngine(t)
	rows := e.QiraatDifferences(2, "warsh", "hafs", 20)
	if len(rows) == 0 {
		t.Fatal("no differences")
	}
	last := 0
	for _, row := range rows {
		if row.Base == row.Other {
			t.Errorf("identical row in the differences: %+v", row)
		}
		if row.Position < last {
			t.Errorf("out of order: %d after %d", row.Position, last)
		}
		last = row.Position
	}
}

func TestWordStreamsFollowTheReadingsOwnVerseCount(t *testing.T) {
	e := parityEngine(t)
	// Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
	// different verses from that point on; the comparison walks the surah's words instead.
	if got := e.NumberOfAyahsInQiraah(2, "warsh"); got != 285 {
		t.Fatalf("warsh al-Baqarah = %d ayahs", got)
	}
	if got := len(e.QiraahVerses(2, "warsh")); got != 285 {
		t.Fatalf("warsh al-Baqarah = %d verses", got)
	}
	if got := len(e.QiraahWords(2, "warsh")); got <= 6000 {
		t.Fatalf("warsh al-Baqarah = %d words", got)
	}
}
