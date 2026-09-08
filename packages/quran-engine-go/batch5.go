package quranengine

// The corpora added upstream in Al-Islam 4.6.4: the repeated phrases, the QUL topic indexes, the
// hizb/ruku/manzil divisions, the qiraat variant matrix and the word of the day. Morphology has
// its own file.
//
// See ../../docs/19-mutashabihat.md, 20-topics-and-metadata.md, 21-qiraat-variants.md and
// 22-word-of-day.md.

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---- mutashabihat ----------------------------------------------------------------

// Phrase is one repeated phrase and every place it occurs.
//
// A different thing from a similar ayah: that is a whole-ayah match, this is the exact run of
// words two ayahs share, which is the memoriser's question.
type Phrase struct {
	ID     int
	Source string
	// Span is the inclusive 0-based token range inside Source.
	Span [2]int
	// Count is total occurrences; AyahCount and SurahCount are how widely they spread.
	Count      int
	AyahCount  int
	SurahCount int
	// Occurrences maps an ayah key to the spans carrying the phrase in that ayah.
	Occurrences map[string][][2]int
	// WordCount is how long the phrase is, in words.
	WordCount int
}

type phraseRow struct {
	Source      string                 `json:"source"`
	Span        [2]int                 `json:"span"`
	Count       int                    `json:"count"`
	AyahCount   int                    `json:"ayahCount"`
	SurahCount  int                    `json:"surahCount"`
	Occurrences map[string][][2]int    `json:"occurrences"`
}

type mutashabihatFile struct {
	Phrases map[string]phraseRow `json:"phrases"`
	Index   map[string][]int     `json:"index"`
}

// MutashabihatPhrase returns one phrase by id.
func (e *Engine) MutashabihatPhrase(id int) (Phrase, bool) {
	row, ok := e.mutashabihat.Phrases[strconv.Itoa(id)]
	if !ok {
		return Phrase{}, false
	}
	return Phrase{ID: id, Source: row.Source, Span: row.Span, Count: row.Count,
		AyahCount: row.AyahCount, SurahCount: row.SurahCount,
		Occurrences: row.Occurrences, WordCount: row.Span[1] - row.Span[0] + 1}, true
}

// MutashabihatFor returns the phrases this ayah carries, longest first.
func (e *Engine) MutashabihatFor(surahID, ayahID int) []Phrase {
	ids := e.mutashabihat.Index[fmt.Sprintf("%d:%d", surahID, ayahID)]
	out := make([]Phrase, 0, len(ids))
	for _, id := range ids {
		if phrase, ok := e.MutashabihatPhrase(id); ok {
			out = append(out, phrase)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].WordCount != out[j].WordCount {
			return out[i].WordCount > out[j].WordCount
		}
		return out[i].ID < out[j].ID
	})
	return out
}

// HasMutashabihat reports whether the ayah carries any: a map hit, cheap enough to gate a button.
func (e *Engine) HasMutashabihat(surahID, ayahID int) bool {
	return len(e.mutashabihat.Index[fmt.Sprintf("%d:%d", surahID, ayahID)]) > 0
}

// PhraseOccurrence is one place a phrase occurs.
type PhraseOccurrence struct {
	Surah int
	Ayah  int
	Key   string
	Spans [][2]int
}

// PhraseOccurrences returns a phrase's occurrences in mushaf order, not key order.
func (e *Engine) PhraseOccurrences(id int) []PhraseOccurrence {
	phrase, ok := e.MutashabihatPhrase(id)
	if !ok {
		return nil
	}
	keys := make([]string, 0, len(phrase.Occurrences))
	for key := range phrase.Occurrences {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool { return ayahKeyLess(keys[i], keys[j]) })
	out := make([]PhraseOccurrence, 0, len(keys))
	for _, key := range keys {
		surah, ayah := splitAyahKey(key)
		out = append(out, PhraseOccurrence{Surah: surah, Ayah: ayah, Key: key,
			Spans: phrase.Occurrences[key]})
	}
	return out
}

// PhraseText slices the phrase's own words out of the ayah text you hand it. The engine does not
// carry the text in here: the caller already has the ayah it is displaying.
func (e *Engine) PhraseText(id int, sourceAyahText string) string {
	phrase, ok := e.MutashabihatPhrase(id)
	if !ok {
		return ""
	}
	tokens := strings.Fields(sourceAyahText)
	if phrase.Span[0] < 0 || phrase.Span[1] >= len(tokens) {
		return ""
	}
	return strings.Join(tokens[phrase.Span[0]:phrase.Span[1]+1], " ")
}

// MutashabihatCount reports how many phrases there are, and how many ayahs carry one.
func (e *Engine) MutashabihatCount() (phrases, ayahs int) {
	return len(e.mutashabihat.Phrases), len(e.mutashabihat.Index)
}

// ---- QUL topics ------------------------------------------------------------------

// TopicTree names one of the three indexes.
type TopicTree string

// The three QUL indexes. They are three trees over ONE pool of topics, not three partitions of
// it: a topic can be a node in more than one (17 are), and a tree's parent need not itself be
// listed in that tree.
const (
	TreeThematic TopicTree = "thematic"
	TreeOntology TopicTree = "ontology"
	TreeIndex    TopicTree = "index"
)

// TopicTrees are the three indexes, in the order the corpus presents them.
var TopicTrees = []TopicTree{TreeThematic, TreeOntology, TreeIndex}

// QulTopic is one topic of the Quranic Universal Library's indexes.
type QulTopic struct {
	ID     int    `json:"id"`
	Name   string `json:"name"`
	Arabic string `json:"arabic"`
	// Families are the indexes listing this topic; 17 topics are listed in two.
	Families []TopicTree `json:"families"`
	// Parents holds one parent per tree, independently. Zero where the topic is not in that
	// tree, or is one of its roots.
	Parents     map[TopicTree]int `json:"parents"`
	Description string            `json:"description"`
	Wiki        string            `json:"wiki"`
	// Ayahs are "2:255" references, in the corpus's order.
	Ayahs   []string `json:"ayahs"`
	Related []int    `json:"related"`
}

type qulTopicsFile struct {
	Topics []QulTopic `json:"topics"`
}

type qulTopicIndex struct {
	once     sync.Once
	byID     map[int]*QulTopic
	children map[TopicTree]map[int][]int
	byAyah   map[string][]int
}

func (e *Engine) buildQulTopicIndex() {
	e.qulTopicIdx.once.Do(func() {
		byID := make(map[int]*QulTopic, len(e.qulTopics))
		children := map[TopicTree]map[int][]int{}
		for _, tree := range TopicTrees {
			children[tree] = map[int][]int{}
		}
		byAyah := map[string][]int{}
		for i := range e.qulTopics {
			topic := &e.qulTopics[i]
			byID[topic.ID] = topic
			for _, tree := range TopicTrees {
				if parent := topic.Parents[tree]; parent != 0 {
					children[tree][parent] = append(children[tree][parent], topic.ID)
				}
			}
			for _, key := range topic.Ayahs {
				byAyah[key] = append(byAyah[key], topic.ID)
			}
		}
		for _, table := range children {
			for _, bucket := range table {
				sort.Ints(bucket)
			}
		}
		e.qulTopicIdx.byID = byID
		e.qulTopicIdx.children = children
		e.qulTopicIdx.byAyah = byAyah
	})
}

// QulTopics returns every topic, in corpus order.
func (e *Engine) QulTopics() []QulTopic { return e.qulTopics }

// QulTopicByID returns one topic.
func (e *Engine) QulTopicByID(id int) (QulTopic, bool) {
	e.buildQulTopicIndex()
	topic, ok := e.qulTopicIdx.byID[id]
	if !ok {
		return QulTopic{}, false
	}
	return *topic, true
}

// TopicsInTree returns the topics an index lists.
func (e *Engine) TopicsInTree(tree TopicTree) []QulTopic {
	out := []QulTopic{}
	for _, topic := range e.qulTopics {
		if topicListedIn(topic, tree) {
			out = append(out, topic)
		}
	}
	return out
}

// TopicRoots returns the topics an index lists that have no parent in that same tree.
func (e *Engine) TopicRoots(tree TopicTree) []QulTopic {
	out := []QulTopic{}
	for _, topic := range e.qulTopics {
		if topicListedIn(topic, tree) && topic.Parents[tree] == 0 {
			out = append(out, topic)
		}
	}
	return out
}

// TopicParent returns the parent in one tree. Pass "" for the topic's first listed index, which
// is a convenience for a caller that does not care.
func (e *Engine) TopicParent(id int, tree TopicTree) (QulTopic, bool) {
	topic, ok := e.QulTopicByID(id)
	if !ok {
		return QulTopic{}, false
	}
	which := resolveTree(topic, tree)
	if which == "" || topic.Parents[which] == 0 {
		return QulTopic{}, false
	}
	return e.QulTopicByID(topic.Parents[which])
}

// TopicChildren returns the direct children in one tree, in id order.
func (e *Engine) TopicChildren(id int, tree TopicTree) []QulTopic {
	topic, ok := e.QulTopicByID(id)
	if !ok {
		return nil
	}
	which := resolveTree(topic, tree)
	if which == "" {
		return nil
	}
	e.buildQulTopicIndex()
	ids := e.qulTopicIdx.children[which][id]
	out := make([]QulTopic, 0, len(ids))
	for _, childID := range ids {
		if child, found := e.QulTopicByID(childID); found {
			out = append(out, child)
		}
	}
	return out
}

// TopicAncestors walks up to the root of one tree, nearest first. Cycle-safe: the corpus is
// trusted for its content, not for its shape.
func (e *Engine) TopicAncestors(id int, tree TopicTree) []QulTopic {
	topic, ok := e.QulTopicByID(id)
	if !ok {
		return nil
	}
	which := resolveTree(topic, tree)
	if which == "" {
		return nil
	}
	out := []QulTopic{}
	seen := map[int]bool{id: true}
	current, found := e.TopicParent(id, which)
	for found && !seen[current.ID] {
		seen[current.ID] = true
		out = append(out, current)
		current, found = e.TopicParent(current.ID, which)
	}
	return out
}

// QulTopicsFor returns every topic annotating this ayah, across all three indexes.
func (e *Engine) QulTopicsFor(surahID, ayahID int) []QulTopic {
	e.buildQulTopicIndex()
	ids := e.qulTopicIdx.byAyah[fmt.Sprintf("%d:%d", surahID, ayahID)]
	out := make([]QulTopic, 0, len(ids))
	for _, id := range ids {
		if topic, ok := e.QulTopicByID(id); ok {
			out = append(out, topic)
		}
	}
	return out
}

// SearchQulTopics matches names and Arabic names, exact-prefix hits first.
func (e *Engine) SearchQulTopics(query string, limit int) []QulTopic {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil
	}
	starts := []QulTopic{}
	contains := []QulTopic{}
	for _, topic := range e.qulTopics {
		name := strings.ToLower(topic.Name)
		switch {
		case strings.HasPrefix(name, q):
			starts = append(starts, topic)
		case strings.Contains(name, q) || strings.Contains(topic.Arabic, query):
			contains = append(contains, topic)
		}
		if limit > 0 && len(starts) >= limit {
			break
		}
	}
	out := append(starts, contains...)
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}

// QulTopicCount reports the corpus size. The per-index counts deliberately sum to MORE than the
// topic count: the 17 topics listed in two indexes are counted in both.
func (e *Engine) QulTopicCount() (topics, thematic, ontology, index, references int) {
	for _, topic := range e.qulTopics {
		for _, family := range topic.Families {
			switch family {
			case TreeThematic:
				thematic++
			case TreeOntology:
				ontology++
			case TreeIndex:
				index++
			}
		}
		references += len(topic.Ayahs)
	}
	return len(e.qulTopics), thematic, ontology, index, references
}

func topicListedIn(topic QulTopic, tree TopicTree) bool {
	for _, family := range topic.Families {
		if family == tree {
			return true
		}
	}
	return false
}

func resolveTree(topic QulTopic, tree TopicTree) TopicTree {
	if tree != "" {
		return tree
	}
	if len(topic.Families) > 0 {
		return topic.Families[0]
	}
	return ""
}

// ---- passage themes --------------------------------------------------------------

// ThemePassage is one short sentence describing a run of ayahs.
//
// Passages run in order through a surah and do not nest. They do not tile it either: an ayah
// between two passages has none. Named ThemePassage rather than Passage because ask_ai.go
// already uses that name for a retrieval passage, which is a different thing entirely.
type ThemePassage struct {
	Surah int
	From  int
	To    int
	Theme string
	Topic string
}

type passageRow struct {
	From  int    `json:"from"`
	To    int    `json:"to"`
	Theme string `json:"theme"`
	Topic string `json:"topic"`
}

// Passages returns a surah's passages, in order.
func (e *Engine) Passages(surahID int) []ThemePassage {
	rows := e.ayahThemes[strconv.Itoa(surahID)]
	out := make([]ThemePassage, 0, len(rows))
	for _, row := range rows {
		out = append(out, ThemePassage{Surah: surahID, From: row.From, To: row.To,
			Theme: row.Theme, Topic: row.Topic})
	}
	return out
}

// PassageFor returns the passage an ayah falls in. Passages do not overlap, so this is the one
// answer; ok is false for an ayah between two of them.
func (e *Engine) PassageFor(surahID, ayahID int) (ThemePassage, bool) {
	for _, passage := range e.Passages(surahID) {
		if ayahID >= passage.From && ayahID <= passage.To {
			return passage, true
		}
	}
	return ThemePassage{}, false
}

// SearchPassages matches the theme sentence and the topic it sits under.
func (e *Engine) SearchPassages(query string, limit int) []ThemePassage {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil
	}
	out := []ThemePassage{}
	for _, surah := range e.surahs {
		for _, passage := range e.Passages(surah.ID) {
			if strings.Contains(strings.ToLower(passage.Theme), q) ||
				strings.Contains(strings.ToLower(passage.Topic), q) {
				out = append(out, passage)
				if limit > 0 && len(out) >= limit {
					return out
				}
			}
		}
	}
	return out
}

// PassageCount reports how many surahs carry an outline and how many passages there are.
func (e *Engine) PassageCount() (surahs, passages int) {
	for _, rows := range e.ayahThemes {
		passages += len(rows)
	}
	return len(e.ayahThemes), passages
}

// ---- hizb / ruku / manzil --------------------------------------------------------

// Division is one hizb, ruku or manzil, identified by where it starts.
type Division struct {
	Number int
	Surah  int
	Ayah   int
	Key    string
}

type quranMetadataFile struct {
	Hizb   []string `json:"hizb"`
	Ruku   []string `json:"ruku"`
	Manzil []string `json:"manzil"`
}

// DivisionKind selects one of the three tables.
type DivisionKind int

// The three schedule divisions: 60 hizb (the juz halved), 558 ruku (thematic sections printed in
// the margin of South Asian mushafs), 7 manzil (the seven-day division).
const (
	Hizb DivisionKind = iota
	Ruku
	Manzil
)

func (e *Engine) divisionStarts(kind DivisionKind) []string {
	switch kind {
	case Hizb:
		return e.metadata.Hizb
	case Ruku:
		return e.metadata.Ruku
	case Manzil:
		return e.metadata.Manzil
	}
	return nil
}

// DivisionCount reports how many of a kind there are.
func (e *Engine) DivisionCount(kind DivisionKind) int { return len(e.divisionStarts(kind)) }

// DivisionFor returns the 1-based number containing an ayah, or 0 when there is no table.
func (e *Engine) DivisionFor(kind DivisionKind, surahID, ayahID int) int {
	starts := e.divisionStarts(kind)
	target := surahID*1000 + ayahID
	found := -1
	lo, hi := 0, len(starts)-1
	for lo <= hi {
		mid := (lo + hi) / 2
		s, a := splitAyahKey(starts[mid])
		if s*1000+a <= target {
			found = mid
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return found + 1
}

// DivisionStart returns where a division begins.
func (e *Engine) DivisionStart(kind DivisionKind, number int) (Division, bool) {
	starts := e.divisionStarts(kind)
	if number < 1 || number > len(starts) {
		return Division{}, false
	}
	surah, ayah := splitAyahKey(starts[number-1])
	return Division{Number: number, Surah: surah, Ayah: ayah, Key: starts[number-1]}, true
}

// Divisions returns every start of a kind, in order.
func (e *Engine) Divisions(kind DivisionKind) []Division {
	starts := e.divisionStarts(kind)
	out := make([]Division, 0, len(starts))
	for i := range starts {
		if division, ok := e.DivisionStart(kind, i+1); ok {
			out = append(out, division)
		}
	}
	return out
}

// DivisionRange returns a division's start and the start of the next one, which is where it
// ends. hasEnd is false for the last, which runs to the end of the Quran: no start key says so,
// and pretending otherwise would be an invented boundary.
func (e *Engine) DivisionRange(kind DivisionKind, number int) (from, until Division, hasEnd, ok bool) {
	from, ok = e.DivisionStart(kind, number)
	if !ok {
		return Division{}, Division{}, false, false
	}
	until, hasEnd = e.DivisionStart(kind, number+1)
	return from, until, hasEnd, true
}

// DivisionsFor returns all three at once, which is what a "where am I" line under an ayah wants.
func (e *Engine) DivisionsFor(surahID, ayahID int) (hizb, ruku, manzil int) {
	return e.DivisionFor(Hizb, surahID, ayahID),
		e.DivisionFor(Ruku, surahID, ayahID),
		e.DivisionFor(Manzil, surahID, ayahID)
}

// ---- qiraat variants -------------------------------------------------------------

// VariantReader is one of the ten imams.
type VariantReader struct {
	ID           int    `json:"id"`
	Name         string `json:"name"`
	Abbreviation string `json:"abbreviation"`
	City         string `json:"city"`
	Position     int    `json:"position"`
}

// VariantTransmitter is one of the twenty riwayat.
type VariantTransmitter struct {
	ID     int    `json:"id"`
	Name   string `json:"name"`
	Reader int    `json:"reader"`
	// Riwayah is this engine's own slug, so a consumer can join to data/qiraat and data/mushaf.
	Riwayah string `json:"riwayah"`
	// TextPublished is false for the twelve riwayat whose extracted text is not published.
	TextPublished bool `json:"textPublished"`
}

// VariantReading is one form of a word, and who reads it.
//
// Readers against transmitters: Readers is set when both of an imam's transmitters follow the
// form, Transmitters when the two part company.
type VariantReading struct {
	Text            string `json:"text"`
	Transliteration string `json:"transliteration"`
	English         string `json:"english"`
	Explanation     string `json:"explanation"`
	GrammaticalForm string `json:"grammaticalForm"`
	RootLetters     string `json:"rootLetters"`
	Readers         []int  `json:"readers"`
	Transmitters    []int  `json:"transmitters"`
}

// VariantSegment locates the word in an ayah. Span is nil where the builder could not place it,
// in which case a consumer shows the word untinted rather than guessing.
type VariantSegment struct {
	Ayah string  `json:"ayah"`
	Span *[2]int `json:"span"`
}

// Juncture is one word of an ayah that the Ten read differently.
type Juncture struct {
	ID       int
	Word     string           `json:"word"`
	Category string           `json:"category"`
	Segments []VariantSegment `json:"segments"`
	Readings []VariantReading `json:"readings"`
	Note     string           `json:"note"`
}

type qiraatVariantsFile struct {
	Readers      map[string]VariantReader      `json:"readers"`
	Transmitters map[string]VariantTransmitter `json:"transmitters"`
	Ayahs        map[string][]Juncture         `json:"ayahs"`
}

type placeRow struct {
	Word   []int `json:"word"`
	Letter []int `json:"letter"`
}

type qiraatPlacesFile struct {
	Riwayat map[string]map[string]map[string]placeRow `json:"riwayat"`
}

type audioSource struct {
	Kind        string `json:"kind"`
	Reciter     string `json:"reciter"`
	HafsBase    string `json:"hafsBase"`
	RiwayahBase string `json:"riwayahBase"`
}

type qiraatVariantAudioFile struct {
	Sources []audioSource                `json:"sources"`
	Riwayat map[string]map[string][][]int `json:"riwayat"`
}

// Junctures returns the words of this ayah that the Ten read differently, in corpus order.
func (e *Engine) Junctures(surahID, ayahID int) []Juncture {
	rows := e.variants.Ayahs[fmt.Sprintf("%d:%d", surahID, ayahID)]
	out := make([]Juncture, len(rows))
	for i, row := range rows {
		row.ID = i
		out[i] = row
	}
	return out
}

// HasQiraatVariants reports whether the ayah carries any. Only 1,409 of the 6,236 do.
func (e *Engine) HasQiraatVariants(surahID, ayahID int) bool {
	return len(e.variants.Ayahs[fmt.Sprintf("%d:%d", surahID, ayahID)]) > 0
}

// VariantReaderByID returns one of the ten imams.
func (e *Engine) VariantReaderByID(id int) (VariantReader, bool) {
	reader, ok := e.variants.Readers[strconv.Itoa(id)]
	return reader, ok
}

// VariantTransmitterByID returns one of the twenty transmitters.
func (e *Engine) VariantTransmitterByID(id int) (VariantTransmitter, bool) {
	transmitter, ok := e.variants.Transmitters[strconv.Itoa(id)]
	return transmitter, ok
}

// TransmittersFollowing returns every transmitter reading a form: an imam's own pair, plus any
// listed individually.
func (e *Engine) TransmittersFollowing(reading VariantReading) []VariantTransmitter {
	out := []VariantTransmitter{}
	seen := map[int]bool{}
	for _, readerID := range reading.Readers {
		ids := make([]int, 0, 2)
		for key := range e.variants.Transmitters {
			if e.variants.Transmitters[key].Reader == readerID {
				ids = append(ids, e.variants.Transmitters[key].ID)
			}
		}
		sort.Ints(ids)
		for _, id := range ids {
			if !seen[id] {
				seen[id] = true
				transmitter, _ := e.VariantTransmitterByID(id)
				out = append(out, transmitter)
			}
		}
	}
	for _, id := range reading.Transmitters {
		if seen[id] {
			continue
		}
		if transmitter, ok := e.VariantTransmitterByID(id); ok {
			seen[id] = true
			out = append(out, transmitter)
		}
	}
	return out
}

// ReadingFor returns the reading a riwayah follows at a juncture, by engine slug.
func (e *Engine) ReadingFor(juncture Juncture, riwayah string) (VariantReading, bool) {
	for _, reading := range juncture.Readings {
		for _, transmitter := range e.TransmittersFollowing(reading) {
			if transmitter.Riwayah == riwayah {
				return reading, true
			}
		}
	}
	return VariantReading{}, false
}

// VariantAttribution renders who reads a form the way the printed sources do: the imams first in
// their canonical order, then any lone transmitters with their imam named in parentheses.
func (e *Engine) VariantAttribution(reading VariantReading) string {
	readers := []VariantReader{}
	for _, id := range reading.Readers {
		if reader, ok := e.VariantReaderByID(id); ok {
			readers = append(readers, reader)
		}
	}
	sort.SliceStable(readers, func(i, j int) bool { return readers[i].Position < readers[j].Position })

	transmitters := []VariantTransmitter{}
	for _, id := range reading.Transmitters {
		if transmitter, ok := e.VariantTransmitterByID(id); ok {
			transmitters = append(transmitters, transmitter)
		}
	}
	sort.SliceStable(transmitters, func(i, j int) bool {
		a, _ := e.VariantReaderByID(transmitters[i].Reader)
		b, _ := e.VariantReaderByID(transmitters[j].Reader)
		pa, pb := 99, 99
		if a.Position != 0 {
			pa = a.Position
		}
		if b.Position != 0 {
			pb = b.Position
		}
		if pa != pb {
			return pa < pb
		}
		return transmitters[i].ID < transmitters[j].ID
	})

	parts := []string{}
	if len(readers) > 0 {
		names := make([]string, len(readers))
		for i, reader := range readers {
			names[i] = reader.Abbreviation
		}
		parts = append(parts, strings.Join(names, ", "))
	}
	if len(transmitters) > 0 {
		names := make([]string, len(transmitters))
		for i, transmitter := range transmitters {
			imam, _ := e.VariantReaderByID(transmitter.Reader)
			if imam.Abbreviation != "" {
				names[i] = transmitter.Name + " (" + imam.Abbreviation + ")"
			} else {
				names[i] = transmitter.Name
			}
		}
		parts = append(parts, strings.Join(names, ", "))
	}
	return strings.Join(parts, " · ")
}

// QiraatPlace is one ayah where a riwayah differs from Hafs.
//
// Two kinds, because they are found two ways and a consumer may want only the first: a Word
// index is a word dropped, added or spelled differently, which a text diff finds; a Letter index
// is a word the printed mushaf marks as read with other vowels over the SAME skeleton, which no
// text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).
type QiraatPlace struct {
	Ayah   int
	Word   []int
	Letter []int
}

// QiraatPlaces returns where a riwayah differs from Hafs in a surah, in ayah order.
func (e *Engine) QiraatPlaces(riwayah string, surahID int) []QiraatPlace {
	table := e.places.Riwayat[riwayah][strconv.Itoa(surahID)]
	ayahs := make([]int, 0, len(table))
	for key := range table {
		if n, err := strconv.Atoi(key); err == nil {
			ayahs = append(ayahs, n)
		}
	}
	sort.Ints(ayahs)
	out := make([]QiraatPlace, 0, len(ayahs))
	for _, ayah := range ayahs {
		row := table[strconv.Itoa(ayah)]
		out = append(out, QiraatPlace{Ayah: ayah, Word: row.Word, Letter: row.Letter})
	}
	return out
}

// RiwayatWithPlaces returns the riwayat QiraatPlaces can answer for: the published ones.
func (e *Engine) RiwayatWithPlaces() []string {
	out := make([]string, 0, len(e.places.Riwayat))
	for slug := range e.places.Riwayat {
		out = append(out, slug)
	}
	sort.Strings(out)
	return out
}

// VariantClip is one side of a paired recording. StartMs and EndMs are nil for a whole per-verse
// file and set for a seek inside a full-surah one.
type VariantClip struct {
	URL     string
	StartMs *int
	EndMs   *int
}

// VariantAudioPair is the same reciter reading a verse both ways.
type VariantAudioPair struct {
	Reciter string
	Hafs    VariantClip
	Riwayah VariantClip
}

// VariantAudio returns the paired recording for an ayah, for the four riwayat where one exists.
//
// The rest carry none: no reciter published both sides with timings. A pair drawn from two
// shaykhs would differ in voice, pace and maqam as well, and teach nothing about the variant.
// That is a fact about the world, and the honest rendering of it is "no recording", never a
// button that does nothing.
func (e *Engine) VariantAudio(riwayah string, surahID, ayahID int) (VariantAudioPair, bool) {
	rows := e.variantAudio.Riwayat[riwayah][strconv.Itoa(surahID)]
	for _, row := range rows {
		if len(row) < 6 || row[0] != ayahID {
			continue
		}
		if row[1] < 0 || row[1] >= len(e.variantAudio.Sources) {
			return VariantAudioPair{}, false
		}
		source := e.variantAudio.Sources[row[1]]
		isSpan := source.Kind == "span"
		name := fmt.Sprintf("%03d%03d.mp3", surahID, ayahID)
		if isSpan {
			name = fmt.Sprintf("%03d.mp3", surahID)
		}
		clip := func(base string, start, end int) VariantClip {
			if !isSpan {
				return VariantClip{URL: base + "/" + name}
			}
			s, e2 := start, end
			return VariantClip{URL: base + "/" + name, StartMs: &s, EndMs: &e2}
		}
		return VariantAudioPair{
			Reciter: source.Reciter,
			Hafs:    clip(source.HafsBase, row[2], row[3]),
			Riwayah: clip(source.RiwayahBase, row[4], row[5]),
		}, true
	}
	return VariantAudioPair{}, false
}

// RiwayatWithAudio returns the riwayat that have any paired recordings at all.
func (e *Engine) RiwayatWithAudio() []string {
	out := make([]string, 0, len(e.variantAudio.Riwayat))
	for slug := range e.variantAudio.Riwayat {
		out = append(out, slug)
	}
	sort.Strings(out)
	return out
}

// QiraatVariantCount reports the corpus size.
func (e *Engine) QiraatVariantCount() (ayahs, junctures, readings int) {
	for _, rows := range e.variants.Ayahs {
		junctures += len(rows)
		for _, row := range rows {
			readings += len(row.Readings)
		}
	}
	return len(e.variants.Ayahs), junctures, readings
}

// ---- word of the day -------------------------------------------------------------

// WordOccurrence is one ayah carrying a curated form. Tokens is plural because a form can repeat
// inside a single ayah.
type WordOccurrence struct {
	Surah  int   `json:"surah"`
	Ayah   int   `json:"ayah"`
	Tokens []int `json:"tokens"`
}

// WordOfDayEntry is one curated word of Quranic vocabulary, with every ayah the same written
// form appears in.
//
// Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission;
// the occurrences are derived from the Hafs text, so the count and the list are one derivation.
type WordOfDayEntry struct {
	ID              string `json:"id"`
	Arabic          string `json:"arabic"`
	Transliteration string `json:"transliteration"`
	Meaning         string `json:"meaning"`
	// Surah, Ayah and Token are the anchor: where the form first appears.
	Surah int `json:"surah"`
	Ayah  int `json:"ayah"`
	Token int `json:"token"`
	// Count is hits across the whole Quran.
	Count       int              `json:"count"`
	Occurrences []WordOccurrence `json:"occurrences"`
}

type wordOfDayFile struct {
	Words []WordOfDayEntry `json:"words"`
}

// WordsOfDay returns the whole corpus, in curation order. The order is deliberate: the themes
// are interleaved so consecutive days feel varied, which is why the day mapping below is a walk
// and not a hash.
func (e *Engine) WordsOfDay() []WordOfDayEntry { return e.wordsOfDay }

// WordOfDayByID returns one curated word.
func (e *Engine) WordOfDayByID(id string) (WordOfDayEntry, bool) {
	for _, word := range e.wordsOfDay {
		if word.ID == id {
			return word, true
		}
	}
	return WordOfDayEntry{}, false
}

// WordOfDayForIndex returns the word for a day number: the corpus walked in order, wrapping.
//
// Take this rather than WordOfDayForDate if your app has its own idea of when a day turns over
// (the upstream app rolls at Fajr, not midnight): hand it your own day number and the mapping is
// identical.
func (e *Engine) WordOfDayForIndex(dayIndex int) (WordOfDayEntry, bool) {
	n := len(e.wordsOfDay)
	if n == 0 {
		return WordOfDayEntry{}, false
	}
	return e.wordsOfDay[((dayIndex%n)+n)%n], true
}

// WordOfDayForDate returns the word for a calendar day, by the time's own location.
func (e *Engine) WordOfDayForDate(when time.Time) (WordOfDayEntry, bool) {
	midnight := time.Date(when.Year(), when.Month(), when.Day(), 0, 0, 0, 0, time.UTC)
	return e.WordOfDayForIndex(int(midnight.Unix() / 86400))
}

// SearchWordsOfDay matches the written form, the transliteration and the gloss.
func (e *Engine) SearchWordsOfDay(query string, limit int) []WordOfDayEntry {
	q := strings.TrimSpace(query)
	if q == "" {
		return nil
	}
	lower := strings.ToLower(q)
	out := []WordOfDayEntry{}
	for _, word := range e.wordsOfDay {
		if strings.Contains(word.Arabic, q) ||
			strings.Contains(strings.ToLower(word.Transliteration), lower) ||
			strings.Contains(strings.ToLower(word.Meaning), lower) {
			out = append(out, word)
			if limit > 0 && len(out) >= limit {
				break
			}
		}
	}
	return out
}

// WordsOfDayIn returns every curated word appearing in an ayah.
func (e *Engine) WordsOfDayIn(surahID, ayahID int) []WordOfDayEntry {
	out := []WordOfDayEntry{}
	for _, word := range e.wordsOfDay {
		for _, occurrence := range word.Occurrences {
			if occurrence.Surah == surahID && occurrence.Ayah == ayahID {
				out = append(out, word)
				break
			}
		}
	}
	return out
}

// WordOfDayCount reports how many words there are and how many occurrences they cover.
func (e *Engine) WordOfDayCount() (words, occurrences int) {
	for _, word := range e.wordsOfDay {
		occurrences += word.Count
	}
	return len(e.wordsOfDay), occurrences
}

// ---- shared helpers --------------------------------------------------------------

func splitAyahKey(key string) (surah, ayah int) {
	parts := strings.SplitN(key, ":", 2)
	if len(parts) != 2 {
		return 0, 0
	}
	surah, _ = strconv.Atoi(parts[0])
	ayah, _ = strconv.Atoi(parts[1])
	return surah, ayah
}

func ayahKeyLess(a, b string) bool {
	sa, aa := splitAyahKey(a)
	sb, ab := splitAyahKey(b)
	if sa != sb {
		return sa < sb
	}
	return aa < ab
}
