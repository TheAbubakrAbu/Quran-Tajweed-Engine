package quranengine

// Ask AI: the retrieval and the prompt behind "ask a question, get an answer grounded in the text".
//
// It is NOT a model. It is the two halves a model cannot do for you and that every app otherwise
// rebuilds badly: turning a natural-language question into the handful of passages that bear on it
// (each with the reference it must be cited by), and the instructions that keep a model from doing
// the three things that make a Quran assistant harmful — inventing verse numbers, quoting
// scripture it has half-remembered, and issuing rulings.
//
// Four lanes, interleaved round-robin so each gets a voice inside the passage budget rather than
// the first one filling it: what the question NAMES (marked as the subject), IDF-weighted
// keywords, the curated themes, and — only when a Semantic index is supplied — meaning.
//
// See ../../docs/14-ask-ai.md.

import (
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// PassageKind says what a passage is, for a consumer deciding what to link it to.
type PassageKind string

const (
	PassageAyah  PassageKind = "ayah"
	PassageSurah PassageKind = "surah"
	PassageTopic PassageKind = "topic"
)

// Passage is one passage the assistant may draw on for a turn.
type Passage struct {
	Kind PassageKind
	// Reference is how it must be cited: "2:255", "Surah Al-Kahf".
	Reference string
	Text      string
	// MaxCharacters is how much of Text to show the model.
	MaxCharacters int
	// IsSubject marks the verse or surah the question itself named.
	IsSubject bool
	Surah     int
	Ayah      int
}

// Turn is one completed turn of the conversation.
type Turn struct {
	Question string
	Answer   string
}

// QuestionWords are too common to name a topic on their own; the keyword lane never searches for
// them alone.
var QuestionWords = map[string]bool{
	"what": true, "why": true, "how": true, "when": true, "where": true, "who": true, "whom": true,
	"which": true, "does": true, "do": true, "did": true, "is": true, "are": true, "was": true,
	"were": true, "can": true, "could": true, "should": true, "would": true, "will": true,
	"shall": true, "have": true, "has": true, "had": true, "there": true, "their": true,
	"these": true, "those": true, "this": true, "that": true, "with": true, "from": true,
	"about": true, "into": true, "tell": true, "explain": true, "please": true, "mean": true,
	"means": true, "meaning": true, "say": true, "says": true, "said": true, "some": true,
	"many": true, "much": true, "islam": true, "islamic": true, "muslim": true, "muslims": true,
	"quran": true, "hadith": true, "hadiths": true, "allah": true, "prophet": true, "verse": true,
	"verses": true, "surah": true, "ayah": true, "ayat": true,
}

// How many passages a turn carries, and how much of each. See ChatPrompt.
const (
	PassageLimit          = 8
	PassageCharacterLimit = 500
	// SubjectCharacterLimit gives a subject passage more room: when the question names the verse,
	// this text IS the answer.
	SubjectCharacterLimit = 1400
)

// CHATInstructions are the system instructions. Rules 2, 3 and 5 are the ones that matter: a model
// left to itself will cite verse numbers it half-remembers, "quote" scripture it has paraphrased,
// and answer "is X halal" with a verdict. Everything else is tone.
const CHATInstructions = `You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end.`

// namedAyah is a household name for a specific verse that no pattern catches.
type namedAyah struct {
	names []string
	surah int
	ayah  int
}

var namedAyahs = []namedAyah{{
	names: []string{"ayat al-kursi", "ayatul kursi", "ayat ul kursi", "ayat al kursi",
		"ayatul-kursi", "throne verse", "verse of the throne"},
	surah: 2, ayah: 255,
}}

var surahWords = map[string]bool{"surah": true, "surat": true, "soorah": true, "sura": true, "chapter": true}
var ayahWords = map[string]bool{"ayah": true, "ayat": true, "aya": true, "verse": true}

// themeHeadings name the prose in a surah's notes that says what it is ABOUT, rather than when it
// was revealed.
var themeHeadings = []string{"theme", "subject", "subject matter", "central theme", "summary", "contents", "topics"}

// AskAIOptions carries the follow-up context. The zero value is a fresh question with the default
// passage budget.
type AskAIOptions struct {
	// PreviousQuestion is folded into the search when this is a bare follow-up.
	PreviousQuestion string
	// Carried are the passages the previous answer cited — "why?" is about those.
	Carried []Passage
	// Limit defaults to PassageLimit when zero.
	Limit int
	// Semantic enables lane 3. Optional on purpose: the other three need no model and no vectors,
	// so the feature works everywhere.
	Semantic *Semantic
	// SemanticMinScore defaults to 0.42 when zero.
	SemanticMinScore float64
}

// AskAIRetrieve returns the passages for a question, best first.
func (e *Engine) AskAIRetrieve(question string, opts AskAIOptions) []Passage {
	trimmed := strings.TrimSpace(question)
	if len([]rune(trimmed)) < 3 {
		return nil
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = PassageLimit
	}

	seen := map[string]bool{}
	claim := func(passages []Passage) []Passage {
		var out []Passage
		for _, passage := range passages {
			if seen[passage.Reference] {
				continue
			}
			seen[passage.Reference] = true
			out = append(out, passage)
		}
		return out
	}

	// Lane 0: what the question NAMES.
	named := claim(e.ReferencePassages(trimmed))

	// A bare follow-up ("why?", "what about zakat?") searches as the previous question plus this
	// one, and keeps the passages the previous answer cited in the pool.
	bare := e.IsBareFollowUp(trimmed)
	previous := strings.TrimSpace(opts.PreviousQuestion)
	searchText := trimmed
	if bare && previous != "" {
		searchText = previous + " " + trimmed
	}
	if bare {
		carried := opts.Carried
		if len(carried) > 3 {
			carried = carried[:3]
		}
		named = append(named, claim(carried)...)
	}

	keyword := claim(e.KeywordPassages(searchText, 4))
	thematic := claim(e.ThemePassages(searchText, 2))
	var meaning []Passage
	if opts.Semantic != nil {
		minScore := opts.SemanticMinScore
		if minScore == 0 {
			minScore = 0.42
		}
		meaning = claim(e.SemanticPassages(opts.Semantic, searchText, 3, minScore))
	}

	out := append([]Passage{}, named...)
	out = append(out, interleave([][]Passage{keyword, meaning, thematic})...)
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}

// ---- Lane 0: references ---------------------------------------------------------

// ReferencePassages returns the verses and surahs the question names, as subject passages.
func (e *Engine) ReferencePassages(question string) []Passage {
	lowered := strings.ToLower(question)
	var ayahs []VerseMatch
	var surahs []int

	for _, hit := range scanReferences(question) {
		if e.Ayah(hit.Surah, hit.Ayah) != nil {
			ayahs = append(ayahs, hit)
		}
	}
	for _, named := range namedAyahs {
		for _, name := range named.names {
			if strings.Contains(lowered, name) {
				ayahs = append(ayahs, VerseMatch{Surah: named.surah, Ayah: named.ayah})
				break
			}
		}
	}

	// "surah al kahf" resolves on the pair, "surah yusuf" on the single word after the keyword.
	words := strings.FieldsFunc(lowered, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '\'' && r != '-'
	})
	var looseAyahs []int
	for index, word := range words {
		switch {
		case surahWords[word]:
			var candidates []string
			if index+2 < len(words) {
				candidates = append(candidates, words[index+1]+" "+words[index+2])
			}
			if index+1 < len(words) {
				candidates = append(candidates, words[index+1])
			}
			for _, candidate := range candidates {
				if id, ok := e.resolveSurah(candidate); ok {
					surahs = append(surahs, id)
					break
				}
			}
		case ayahWords[word]:
			if index+1 < len(words) {
				if number, err := strconv.Atoi(words[index+1]); err == nil {
					looseAyahs = append(looseAyahs, number)
				}
			}
		}
	}
	// A bare ayah number belongs to the surah just named.
	if len(ayahs) == 0 && len(surahs) > 0 {
		for _, ayah := range looseAyahs {
			if e.Ayah(surahs[0], ayah) != nil {
				ayahs = append(ayahs, VerseMatch{Surah: surahs[0], Ayah: ayah})
			}
		}
	}

	var out []Passage
	for _, hit := range ayahs {
		if passage := e.AyahPassage(hit.Surah, hit.Ayah, true, SubjectCharacterLimit); passage != nil {
			out = append(out, *passage)
		}
	}
	// A surah named on its own (with no verse) is answered by its background prose.
	if len(ayahs) == 0 {
		for _, id := range surahs {
			if passage := e.SurahPassage(id); passage != nil {
				out = append(out, *passage)
			}
		}
	}
	return out
}

// resolveSurah picks the surah a name means. SearchSurahs is a substring match, so "al kahf" also
// reaches al-Fatihah (whose similar names include "Al..."); an exact name match wins when there is
// one, which is the difference between answering about the cave and answering about the opening.
func (e *Engine) resolveSurah(candidate string) (int, bool) {
	hits := e.SearchSurahs(candidate)
	if len(hits) == 0 {
		return 0, false
	}
	wanted := foldASCII(candidate)
	for _, surah := range hits {
		if foldASCII(surah.NameTransliteration) == wanted || foldASCII(surah.NameEnglish) == wanted {
			return surah.ID, true
		}
	}
	if len(wanted) >= 3 {
		for _, surah := range hits {
			if strings.HasSuffix(foldASCII(surah.NameTransliteration), wanted) {
				return surah.ID, true
			}
		}
	}
	return hits[0].ID, true
}

// ---- Lane 1: keywords, IDF-weighted --------------------------------------------

// KeywordPassages returns ayahs whose translation carries the question's content words, ranked by
// how INFORMATIVE those words are rather than by how often they occur.
func (e *Engine) KeywordPassages(question string, limit int) []Passage {
	terms := e.ContentWords(question)
	if len(terms) == 0 {
		return nil
	}
	weights := e.TermWeights(terms)

	scores := map[VerseMatch]float64{}
	for i, term := range terms {
		if weights[i] <= 0 {
			continue
		}
		for _, hit := range e.SearchVerses(term, SearchOptions{Limit: 400}) {
			scores[hit] += weights[i]
		}
	}
	// A verse matching two informative words beats one matching a single word twice.
	ranked := make([]VerseMatch, 0, len(scores))
	for hit := range scores {
		ranked = append(ranked, hit)
	}
	sort.Slice(ranked, func(i, j int) bool {
		if scores[ranked[i]] != scores[ranked[j]] {
			return scores[ranked[i]] > scores[ranked[j]]
		}
		if ranked[i].Surah != ranked[j].Surah {
			return ranked[i].Surah < ranked[j].Surah
		}
		return ranked[i].Ayah < ranked[j].Ayah
	})

	var out []Passage
	for _, hit := range ranked {
		if passage := e.AyahPassage(hit.Surah, hit.Ayah, false, PassageCharacterLimit); passage != nil {
			out = append(out, *passage)
		}
		if len(out) >= limit {
			break
		}
	}
	return out
}

// ---- Lane 2: themes -------------------------------------------------------------

// ThemePassages returns ayahs from the curated topic the question matches — the lane that reaches
// verses sharing no wording with the question at all.
func (e *Engine) ThemePassages(question string, limit int) []Passage {
	words := e.ContentWords(question)
	if len(words) == 0 {
		return nil
	}
	var best *Topic
	bestScore := 0
	for i := range e.topics {
		topic := &e.topics[i]
		haystack := strings.ToLower(topic.Name + " " + topic.Description + " " + topic.Category)
		score := 0
		for _, word := range words {
			if strings.Contains(haystack, strings.ToLower(word)) {
				score += len([]rune(word))
			}
		}
		if score > bestScore {
			bestScore = score
			best = topic
		}
	}
	if best == nil {
		return nil
	}

	var out []Passage
	for _, reference := range best.Ayahs {
		surah, ayah, ok := parseReference(reference)
		if !ok {
			continue
		}
		if passage := e.AyahPassage(surah, ayah, false, PassageCharacterLimit); passage != nil {
			out = append(out, *passage)
		}
		if len(out) >= limit {
			break
		}
	}
	return out
}

// ---- Lane 3: meaning ------------------------------------------------------------

// SemanticPassages returns ayahs closest in MEANING to the question, using a semantic index you
// built and own. The other lanes need no model, which is why this one takes the index as an
// argument instead of the engine holding it.
func (e *Engine) SemanticPassages(semantic *Semantic, question string, limit int, minScore float64) []Passage {
	if semantic == nil {
		return nil
	}
	// The score is a MEAN over query words, so "what does the Quran say about" dilutes the topic:
	// the meaning query is the content words alone.
	words := e.ContentWords(question)
	query := question
	if len(words) > 0 {
		query = strings.Join(words, " ")
	}

	var out []Passage
	for _, hit := range semantic.Search(query, limit*2, minScore) {
		surah, ayah, ok := parseReference(hit.ID)
		if !ok {
			continue
		}
		if passage := e.AyahPassage(surah, ayah, false, PassageCharacterLimit); passage != nil {
			out = append(out, *passage)
		}
		if len(out) >= limit {
			break
		}
	}
	return out
}

// ---- Passage construction --------------------------------------------------------

// AyahPassage builds the passage for one ayah, or nil when the ayah or its translation is missing.
func (e *Engine) AyahPassage(surahID, ayahID int, isSubject bool, maxCharacters int) *Passage {
	ayah := e.Ayah(surahID, ayahID)
	if ayah == nil {
		return nil
	}
	text := ayah.TextEnglishSaheeh
	if text == "" {
		text = ayah.TextEnglishMustafa
	}
	if text == "" {
		return nil
	}
	return &Passage{
		Kind:          PassageAyah,
		Reference:     fmt.Sprintf("%d:%d", surahID, ayahID),
		Text:          text,
		MaxCharacters: maxCharacters,
		IsSubject:     isSubject,
		Surah:         surahID,
		Ayah:          ayahID,
	}
}

// SurahPassage is a surah's background prose. The bundled notes open with the period of revelation,
// which answers "what is this surah about" with history — so the theme section, when a source has
// one, is what the question actually meant.
func (e *Engine) SurahPassage(surahID int) *Passage {
	surah := e.Surah(surahID)
	sources := e.SurahInfo(surahID)
	if surah == nil || len(sources) == 0 {
		return nil
	}

	text := ""
	for _, source := range sources {
		offset, ok := themeHeadingOffset(source.Contents)
		if !ok {
			continue
		}
		fromTheme := plainProse(source.Contents[offset:])
		if len([]rune(fromTheme)) >= 200 {
			text = fromTheme
			break
		}
	}
	if text == "" {
		text = plainProse(sources[0].Contents)
	}
	if text == "" {
		return nil
	}

	return &Passage{
		Kind:          PassageSurah,
		Reference:     "Surah " + surah.NameTransliteration,
		Text:          text,
		MaxCharacters: SubjectCharacterLimit,
		IsSubject:     true,
		Surah:         surahID,
	}
}

// ---- Question analysis -------------------------------------------------------------

// ContentWords are the words in a question that actually name its topic.
func (e *Engine) ContentWords(question string) []string {
	var out []string
	for _, word := range splitWords(question) {
		if len([]rune(word)) >= 3 && !QuestionWords[strings.ToLower(word)] {
			out = append(out, word)
		}
	}
	return out
}

// IsBareFollowUp reports whether a question has fewer than two content words ("why?", "and
// zakat?") and so only makes sense with the previous question beside it.
func (e *Engine) IsBareFollowUp(question string) bool {
	count := 0
	for _, word := range splitWords(question) {
		if len([]rune(word)) >= 4 && !QuestionWords[strings.ToLower(word)] {
			count++
		}
	}
	return count < 2
}

// TermWeights is the inverse document frequency per term: log(N / (1 + df)), floored at 0. A word
// in half the Quran weighs almost nothing; a word in ten ayahs weighs a lot.
func (e *Engine) TermWeights(terms []string) []float64 {
	if e.documentFrequency == nil {
		frequency := map[string]int{}
		documents := 0
		for i := range e.surahs {
			for _, ayah := range e.surahs[i].Ayahs {
				documents++
				seen := map[string]bool{}
				for _, word := range splitWords(strings.ToLower(ayah.TextEnglishSaheeh)) {
					if len([]rune(word)) < 3 || seen[word] {
						continue
					}
					seen[word] = true
					frequency[word]++
				}
			}
		}
		e.documentFrequency = frequency
		e.documentCount = documents
	}
	out := make([]float64, len(terms))
	for i, term := range terms {
		df := e.documentFrequency[strings.ToLower(term)]
		out[i] = math.Max(0, math.Log(float64(e.documentCount)/float64(1+df)))
	}
	return out
}

// ---- The prompt --------------------------------------------------------------------

// ChatPrompt returns the instructions and the user-side prompt for one turn: the passages, the
// recent conversation, the question.
//
// Eight passages of 500 characters is roughly a thousand tokens — sized for a ~4k on-device window
// with room for the instructions, the conversation, and a full answer. Raise both for a larger
// model; the shape does not change.
func ChatPrompt(question string, passages []Passage, transcript []Turn) (instructions, prompt string) {
	if len(passages) > PassageLimit {
		passages = passages[:PassageLimit]
	}
	rendered := make([]string, 0, len(passages))
	for _, passage := range passages {
		marker := ""
		if passage.IsSubject {
			marker = "SUBJECT OF THE QUESTION "
		}
		rendered = append(rendered, fmt.Sprintf("%s[%s] %s", marker, passage.Reference,
			clip(passage.Text, passage.MaxCharacters)))
	}
	recent := transcript
	if len(recent) > 3 {
		recent = recent[len(recent)-3:]
	}
	turns := make([]string, 0, len(recent))
	for _, turn := range recent {
		turns = append(turns, fmt.Sprintf("Earlier question: %s\nEarlier answer: %s",
			clip(turn.Question, 300), clip(turn.Answer, 500)))
	}

	var out strings.Builder
	if len(rendered) > 0 {
		out.WriteString("PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n")
		out.WriteString(strings.Join(rendered, "\n"))
		out.WriteString("\n\n")
	}
	if len(turns) > 0 {
		out.WriteString("CONVERSATION SO FAR:\n")
		out.WriteString(strings.Join(turns, "\n"))
		out.WriteString("\n\n")
	}
	out.WriteString("QUESTION: ")
	out.WriteString(question)

	return CHATInstructions, out.String()
}

// ---- helpers -------------------------------------------------------------------------

// clip truncates on a rune boundary, the way every other port's prefix/slice does.
func clip(text string, max int) string {
	runes := []rune(text)
	if len(runes) <= max {
		return text
	}
	return string(runes[:max])
}

// interleave round-robins the lanes so each gets a voice inside the budget.
func interleave(lanes [][]Passage) []Passage {
	depth := 0
	for _, lane := range lanes {
		if len(lane) > depth {
			depth = len(lane)
		}
	}
	var out []Passage
	for i := 0; i < depth; i++ {
		for _, lane := range lanes {
			if i < len(lane) {
				out = append(out, lane[i])
			}
		}
	}
	return out
}

// plainProse strips the light markdown the surah notes carry, so a passage reads as prose.
func plainProse(text string) string {
	var out strings.Builder
	for _, line := range strings.Split(strings.ReplaceAll(text, "\r", ""), "\n") {
		cleaned := strings.TrimLeft(strings.TrimLeft(line, " \t"), "#")
		cleaned = strings.TrimLeft(cleaned, " \t")
		cleaned = strings.Map(func(r rune) rune {
			if r == '*' || r == '_' || r == '`' {
				return -1
			}
			return r
		}, cleaned)
		// Collapse runs of blank lines: the notes separate paragraphs with two, and a passage the
		// model reads is better as one paragraph per line.
		if strings.TrimSpace(cleaned) == "" {
			existing := out.String()
			if existing == "" || strings.HasSuffix(existing, "\n") {
				continue
			}
		}
		out.WriteString(strings.TrimRight(cleaned, " \t"))
		out.WriteString("\n")
	}
	return strings.TrimSpace(out.String())
}

// splitWords cuts on everything that is not a letter or a digit, like the other ports' \W split.
func splitWords(text string) []string {
	return strings.FieldsFunc(text, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
}

func foldASCII(text string) string {
	var out strings.Builder
	for _, r := range strings.ToLower(text) {
		if r >= 'a' && r <= 'z' {
			out.WriteRune(r)
		}
	}
	return out.String()
}

func parseReference(text string) (surah, ayah int, ok bool) {
	parts := strings.SplitN(text, ":", 2)
	if len(parts) != 2 {
		return 0, 0, false
	}
	surah, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, 0, false
	}
	ayah, err = strconv.Atoi(parts[1])
	if err != nil {
		return 0, 0, false
	}
	return surah, ayah, true
}

// scanReferences finds every "N:M" in the text, ignoring anything glued to more digits or another
// colon. Written out rather than as a regexp because Go's RE2 has no lookbehind.
func scanReferences(text string) []VerseMatch {
	runes := []rune(text)
	var out []VerseMatch
	for i := 0; i < len(runes); {
		if !isASCIIDigit(runes[i]) {
			i++
			continue
		}
		// A digit or a colon immediately before makes this the tail of something else.
		if i > 0 && (isASCIIDigit(runes[i-1]) || runes[i-1] == ':') {
			for i < len(runes) && isASCIIDigit(runes[i]) {
				i++
			}
			continue
		}
		start := i
		for i < len(runes) && isASCIIDigit(runes[i]) {
			i++
		}
		surahText := string(runes[start:i])

		j := i
		for j < len(runes) && runes[j] == ' ' {
			j++
		}
		if j >= len(runes) || runes[j] != ':' {
			continue
		}
		j++
		for j < len(runes) && runes[j] == ' ' {
			j++
		}
		ayahStart := j
		for j < len(runes) && isASCIIDigit(runes[j]) {
			j++
		}
		if ayahStart == j {
			continue
		}
		// A trailing colon means this was part of a longer token.
		if j < len(runes) && runes[j] == ':' {
			continue
		}
		ayahText := string(runes[ayahStart:j])
		if len(surahText) <= 3 && len(ayahText) <= 3 {
			surah, _ := strconv.Atoi(surahText)
			ayah, _ := strconv.Atoi(ayahText)
			out = append(out, VerseMatch{Surah: surah, Ayah: ayah})
		}
		i = j
	}
	return out
}

func isASCIIDigit(r rune) bool { return r >= '0' && r <= '9' }

// themeHeadingOffset is the byte offset of the first line that opens with a theme-ish heading.
func themeHeadingOffset(text string) (int, bool) {
	offset := 0
	for _, line := range strings.SplitAfter(text, "\n") {
		stripped := strings.TrimLeft(strings.TrimLeft(strings.TrimLeft(line, " \t"), "#"), " \t")
		lowered := strings.ToLower(stripped)
		for _, heading := range themeHeadings {
			if !strings.HasPrefix(lowered, heading) {
				continue
			}
			rest := []rune(lowered[len(heading):])
			if len(rest) == 0 || (!unicode.IsLetter(rest[0]) && !unicode.IsDigit(rest[0])) {
				return offset, true
			}
		}
		offset += len(line)
	}
	return 0, false
}
