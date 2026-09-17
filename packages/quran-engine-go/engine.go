package quranengine

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

// Engine holds all parsed data and the derived lookup tables. Construct it with
// Load or LoadFrom, then call its methods. It is read-only after loading and is
// safe for concurrent reads.
type Engine struct {
	surahs     []Surah
	byID       map[int]*Surah
	cumulative map[int]int // 0-based count of ayahs in all earlier surahs
	totalAyahs int

	juzList  []JuzEntry
	reciters []Reciter

	surahInfo     map[int][]SurahInfoSource // surah id -> "About this surah" sources
	names         []NameOfAllah             // 99 Names, ordered by number
	namesByNumber map[int]*NameOfAllah      // number -> name

	ruleColors map[string]string              // category id -> colorHex
	annotByKey map[[2]int][]tajweedAnnotation // (surah,ayah) -> annotations

	muqattaat        []MuqattaatPronunciation           // 30 openings, in file order
	muqattaatByKey   map[string]*MuqattaatPronunciation // "surah:ayah" -> pronunciation
	muqattaatLetters map[string]string                  // bare letter -> transliteration

	qiraatCounts map[string]map[string]int // riwayah -> surahId(str) -> ayah count

	// The batch loaded by LoadOptions. themes.json and tajweed-lessons.json are optional but load
	// by default: together they are ~250 KB, and a topic list is the kind of thing a consumer
	// wants without a flag.
	topics          []Topic
	tajweedChapters []TajweedChapter

	mushafIndex *MushafIndex
	mushafPages map[string]*MushafPageTable
	mushafLines map[string]*MushafLineTable

	qiraatRuleDescriptions map[string]RuleDescription
	qiraatTajweed          map[string]*QiraatTajweedPack

	wordByWord WordByWordPack
	// similar-ayahs.json version 2's ayahs: "surah:ayah" -> rows, read field by field by
	// SimilarAyahs. Nil (no data) for a file of any other version.
	similarAyahs map[string][][]json.RawMessage

	// riwayah -> surah id (as a string) -> that reading's own verses (empty unless
	// LoadOptions.Qiraat).
	qiraat map[string]map[string][]QiraahVerse
	// data/surah-sections.json and data/arabic-alphabet.json; both load by default.
	surahSections map[string]surahSectionsEntry
	alphabet      arabicAlphabetFile

	// Batch 5: the corpora added upstream in Al-Islam 4.6.4.
	morphology   morphologyFile
	morphIndex   morphologyIndex
	mutashabihat mutashabihatFile
	qulTopics    []QulTopic
	qulTopicIdx  qulTopicIndex
	ayahThemes   map[string][]passageRow
	metadata     quranMetadataFile
	variants     qiraatVariantsFile
	places       qiraatPlacesFile
	variantAudio qiraatVariantAudioFile
	wordsOfDay   []WordOfDayEntry
	namesDepth   []NameDepth
	nameThemes   []NameTheme
	isnad        isnadFile
	// The scientific-miracles corpus; loads by default.
	miracles miraclesFile

	// Lazily built by TermWeights, over the translations.
	documentFrequency map[string]int
	documentCount     int

	search *searchIndex
}

// LoadOptions selects the heavier corpora. The zero value loads the core plus themes and the
// tajweed course, which is what LoadFrom and Load use.
type LoadOptions struct {
	// Mushaf loads mushaf/index.json plus every riwayah's page table (and line table, where the
	// text ships). ~9 MB.
	Mushaf bool
	// QiraatTajweed loads the shared rule catalogue and the seven verified riwayah packs.
	QiraatTajweed bool
	// WordByWord loads both aligned layers of word-by-word.json. ~9 MB.
	WordByWord bool
	// SimilarAyahs loads similar-ayahs.json.
	SimilarAyahs bool
	// Qiraat loads the seven non-Hafs riwayat's own text (~11 MB) - what CompareSurah compares.
	Qiraat bool
	// Morphology loads morphology.json (~776 KB): root and lemma of every word.
	Morphology bool
	// Mutashabihat loads mutashabihat.json (~178 KB): the repeated phrases.
	Mutashabihat bool
	// QulTopics loads quran-topics.json (~730 KB): the three QUL topic indexes.
	QulTopics bool
	// QiraatVariants loads the variant matrix, the place index and the paired-recording table
	// (~1.9 MB together).
	QiraatVariants bool
}

// QiraahVerse is one verse of a riwayah's own text, in ITS numbering.
type QiraahVerse struct {
	ID   int    `json:"id"`
	Text string `json:"text"`
}

// The seven verified non-Hafs riwayat that carry a tajweed pack. The twelve whose text is not
// published have no pack: their rules index into that text.
var qiraatTajweedSlugs = []string{"warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"}

// LoadFrom parses the JSON data files in dataDir and returns a ready Engine.
//
// Required: quran.json, juz.json, reciters.json, surah-info.json,
// names-of-allah.json, tajweed-rules.json, muqattaat.json, qiraat-counts.json.
// Optional: tajweed-annotations.json (needed for TajweedSpans).
func LoadFrom(dataDir string) (*Engine, error) {
	return LoadFromWith(dataDir, LoadOptions{})
}

// LoadFromWith is LoadFrom with the heavier corpora selected. See LoadOptions.
func LoadFromWith(dataDir string, options LoadOptions) (*Engine, error) {
	e := &Engine{}

	if err := readJSON(filepath.Join(dataDir, "quran.json"), &e.surahs); err != nil {
		return nil, err
	}
	if err := readJSON(filepath.Join(dataDir, "juz.json"), &e.juzList); err != nil {
		return nil, err
	}
	if err := readJSON(filepath.Join(dataDir, "reciters.json"), &e.reciters); err != nil {
		return nil, err
	}

	var infoEntries []surahInfoEntry
	if err := readJSON(filepath.Join(dataDir, "surah-info.json"), &infoEntries); err != nil {
		return nil, err
	}
	if err := readJSON(filepath.Join(dataDir, "names-of-allah.json"), &e.names); err != nil {
		return nil, err
	}

	var rules tajweedRulesFile
	if err := readJSON(filepath.Join(dataDir, "tajweed-rules.json"), &rules); err != nil {
		return nil, err
	}

	var muq muqattaatFile
	if err := readJSON(filepath.Join(dataDir, "muqattaat.json"), &muq); err != nil {
		return nil, err
	}

	if err := readJSON(filepath.Join(dataDir, "qiraat-counts.json"), &e.qiraatCounts); err != nil {
		return nil, err
	}

	// Build quran indexes + cumulative offsets.
	e.byID = make(map[int]*Surah, len(e.surahs))
	e.cumulative = make(map[int]int, len(e.surahs))
	acc := 0
	for i := range e.surahs {
		s := &e.surahs[i]
		e.byID[s.ID] = s
		e.cumulative[s.ID] = acc
		acc += s.NumberOfAyahs
	}
	e.totalAyahs = acc

	// Reciters: keep stable (file) order; sorting is exposed via SortReciters/All.
	// (The JS port sorts by name for display; we keep file order and offer helpers.)

	// Surah info ("About this surah") index: surah id -> sources.
	e.surahInfo = make(map[int][]SurahInfoSource, len(infoEntries))
	for _, ent := range infoEntries {
		e.surahInfo[ent.ID] = ent.Sources
	}

	// 99 Names: order by number (mirrors the JS NamesOfAllah constructor) and index.
	sort.SliceStable(e.names, func(i, j int) bool { return e.names[i].Number < e.names[j].Number })
	e.namesByNumber = make(map[int]*NameOfAllah, len(e.names))
	for i := range e.names {
		n := &e.names[i]
		e.namesByNumber[n.Number] = n
	}

	// Tajweed rule color map.
	e.ruleColors = make(map[string]string, len(rules.Categories))
	for _, c := range rules.Categories {
		e.ruleColors[c.ID] = c.ColorHex
	}

	// Muqattaʿāt: keep file order; index by "surah:ayah" and keep the letter names.
	e.muqattaat = muq.Ayahs
	e.muqattaatLetters = muq.LetterNames
	if e.muqattaatLetters == nil {
		e.muqattaatLetters = map[string]string{}
	}
	e.muqattaatByKey = make(map[string]*MuqattaatPronunciation, len(e.muqattaat))
	for i := range e.muqattaat {
		p := &e.muqattaat[i]
		e.muqattaatByKey[fmt.Sprintf("%d:%d", p.Surah, p.Ayah)] = p
	}

	// Tajweed annotations (optional).
	annPath := filepath.Join(dataDir, "tajweed-annotations.json")
	if _, err := os.Stat(annPath); err == nil {
		var entries []tajweedAnnotationEntry
		if err := readJSON(annPath, &entries); err != nil {
			return nil, err
		}
		e.annotByKey = make(map[[2]int][]tajweedAnnotation, len(entries))
		for _, ent := range entries {
			e.annotByKey[[2]int{ent.Surah, ent.Ayah}] = ent.Annotations
		}
	}

	if err := e.loadCorpora(dataDir, options); err != nil {
		return nil, err
	}

	e.search = newSearchIndex(e)
	return e, nil
}

// loadCorpora reads the optional data: themes and the tajweed course always, the rest on request.
// A missing optional file is not an error (the accessors simply return nothing), but a file that
// is present and unreadable is, so a corrupt pack fails loudly instead of silently disappearing.
func (e *Engine) loadCorpora(dataDir string, options LoadOptions) error {
	var themes themesFile
	if err := readOptionalJSON(filepath.Join(dataDir, "themes.json"), &themes); err != nil {
		return err
	}
	e.topics = themes.Topics

	var lessons tajweedLessonsFile
	if err := readOptionalJSON(filepath.Join(dataDir, "tajweed-lessons.json"), &lessons); err != nil {
		return err
	}
	e.tajweedChapters = lessons.Chapters

	e.mushafPages = map[string]*MushafPageTable{}
	e.mushafLines = map[string]*MushafLineTable{}
	if options.Mushaf {
		var index MushafIndex
		if err := readJSON(filepath.Join(dataDir, "mushaf", "index.json"), &index); err != nil {
			return err
		}
		for _, entry := range index.Riwayat {
			var pages MushafPageTable
			if err := readJSON(filepath.Join(dataDir, "mushaf", entry.Pages), &pages); err != nil {
				return err
			}
			e.mushafPages[entry.Riwayah] = &pages
			if entry.Lines != "" {
				var lines MushafLineTable
				if err := readJSON(filepath.Join(dataDir, "mushaf", entry.Lines), &lines); err != nil {
					return err
				}
				e.mushafLines[entry.Riwayah] = &lines
			}
		}
		e.mushafIndex = &index
	}

	e.qiraatTajweed = map[string]*QiraatTajweedPack{}
	if options.QiraatTajweed {
		if err := readJSON(filepath.Join(dataDir, "tajweed-qiraat", "rules.json"), &e.qiraatRuleDescriptions); err != nil {
			return err
		}
		for _, slug := range qiraatTajweedSlugs {
			var pack QiraatTajweedPack
			if err := readJSON(filepath.Join(dataDir, "tajweed-qiraat", slug+".json"), &pack); err != nil {
				return err
			}
			e.qiraatTajweed[slug] = &pack
		}
	}

	if options.WordByWord {
		if err := readJSON(filepath.Join(dataDir, "word-by-word.json"), &e.wordByWord); err != nil {
			return err
		}
	}

	if options.SimilarAyahs {
		// Version 2 wraps the rows: {v: 2, ayahs: {"surah:ayah": [...]}}. A version-1 file (rows
		// keyed at the top level, the phrase as text) is not read: it would put the shared
		// wording where a span is expected. It loads as no data rather than half a one, as the
		// JS port does.
		var file similarAyahsFile
		if err := readJSON(filepath.Join(dataDir, "similar-ayahs.json"), &file); err != nil {
			return err
		}
		if file.V == 2 {
			e.similarAyahs = file.Ayahs
		}
	}

	e.qiraat = map[string]map[string][]QiraahVerse{}
	if options.Qiraat {
		for _, slug := range qiraatTajweedSlugs {
			var verses map[string][]QiraahVerse
			if err := readJSON(filepath.Join(dataDir, "qiraat", "qiraah-"+slug+".json"), &verses); err != nil {
				return err
			}
			e.qiraat[slug] = verses
		}
	}

	// surah-sections.json (80 KB) and arabic-alphabet.json (18 KB) load by default, like themes and
	// the tajweed course: small, and both answer questions a consumer should not have to opt into.
	if err := readOptionalJSON(filepath.Join(dataDir, "surah-sections.json"), &e.surahSections); err != nil {
		return err
	}
	if err := readOptionalJSON(filepath.Join(dataDir, "arabic-alphabet.json"), &e.alphabet); err != nil {
		return err
	}

	// Metadata (8 KB), the passage themes (142 KB) and the word list (128 KB) load by default on
	// the same reasoning: small, and each answers a question a consumer should not have to opt into.
	if err := readOptionalJSON(filepath.Join(dataDir, "quran-metadata.json"), &e.metadata); err != nil {
		return err
	}
	if err := readOptionalJSON(filepath.Join(dataDir, "ayah-themes.json"), &e.ayahThemes); err != nil {
		return err
	}
	var words wordOfDayFile
	if err := readOptionalJSON(filepath.Join(dataDir, "word-of-day.json"), &words); err != nil {
		return err
	}
	e.wordsOfDay = words.Words
	// The Names in depth (47 KB) and the chains (20 KB) load by default on the same footing.
	var depth namesDepthFile
	if err := readOptionalJSON(filepath.Join(dataDir, "names-depth.json"), &depth); err != nil {
		return err
	}
	e.namesDepth = depth.Names
	e.nameThemes = depth.Themes
	if err := readOptionalJSON(filepath.Join(dataDir, "isnad.json"), &e.isnad); err != nil {
		return err
	}
	// The miracles corpus (393 KB) joins them: bigger than those, but smaller than the tajweed
	// course that has always loaded by default, and a consumer cross-linking an ayah to what has
	// been written about it should not have to know a flag existed.
	if err := readOptionalJSON(filepath.Join(dataDir, "miracles.json"), &e.miracles); err != nil {
		return err
	}

	if options.Morphology {
		if err := readJSON(filepath.Join(dataDir, "morphology.json"), &e.morphology); err != nil {
			return err
		}
	}
	if options.Mutashabihat {
		if err := readJSON(filepath.Join(dataDir, "mutashabihat.json"), &e.mutashabihat); err != nil {
			return err
		}
	}
	if options.QulTopics {
		var topics qulTopicsFile
		if err := readJSON(filepath.Join(dataDir, "quran-topics.json"), &topics); err != nil {
			return err
		}
		e.qulTopics = topics.Topics
	}
	if options.QiraatVariants {
		if err := readJSON(filepath.Join(dataDir, "qiraat-variants.json"), &e.variants); err != nil {
			return err
		}
		if err := readJSON(filepath.Join(dataDir, "qiraat-places.json"), &e.places); err != nil {
			return err
		}
		if err := readJSON(filepath.Join(dataDir, "qiraat-variant-audio.json"), &e.variantAudio); err != nil {
			return err
		}
	}
	return nil
}

// Load locates the data directory automatically and calls LoadFrom.
//
// Resolution order:
//  1. the QURAN_ENGINE_DATA environment variable, if set;
//  2. walking up from the current working directory until a data/quran.json is found.
func Load() (*Engine, error) {
	return LoadWith(LoadOptions{})
}

// LoadWith is Load with the heavier corpora selected. See LoadOptions.
func LoadWith(options LoadOptions) (*Engine, error) {
	if dir := os.Getenv("QURAN_ENGINE_DATA"); dir != "" {
		return LoadFromWith(dir, options)
	}
	dir, err := FindDataDir()
	if err != nil {
		return nil, err
	}
	return LoadFromWith(dir, options)
}

// FindDataDir walks up from the current working directory looking for a sibling
// data/quran.json (the repository's /data). Returns the absolute data dir path.
func FindDataDir() (string, error) {
	start, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return findDataDirFrom(start)
}

func findDataDirFrom(start string) (string, error) {
	dir := start
	for {
		candidate := filepath.Join(dir, "data", "quran.json")
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Join(dir, "data"), nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("could not locate data/quran.json walking up from %s; set QURAN_ENGINE_DATA", start)
		}
		dir = parent
	}
}

// readOptionalJSON is readJSON that treats an absent file as "nothing to load".
func readOptionalJSON(path string, v any) error {
	if _, err := os.Stat(path); err != nil {
		return nil
	}
	return readJSON(path, v)
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("reading %s: %w", path, err)
	}
	if err := json.Unmarshal(b, v); err != nil {
		return fmt.Errorf("parsing %s: %w", path, err)
	}
	return nil
}
