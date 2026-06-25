package quranengine

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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

	ruleColors map[string]string              // category id -> colorHex
	annotByKey map[[2]int][]tajweedAnnotation // (surah,ayah) -> annotations

	search *searchIndex
}

// LoadFrom parses the JSON data files in dataDir and returns a ready Engine.
//
// Required: quran.json, juz.json, reciters.json, tajweed-rules.json.
// Optional: tajweed-annotations.json (needed for TajweedSpans).
func LoadFrom(dataDir string) (*Engine, error) {
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

	var rules tajweedRulesFile
	if err := readJSON(filepath.Join(dataDir, "tajweed-rules.json"), &rules); err != nil {
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

	// Tajweed rule color map.
	e.ruleColors = make(map[string]string, len(rules.Categories))
	for _, c := range rules.Categories {
		e.ruleColors[c.ID] = c.ColorHex
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

	e.search = newSearchIndex(e)
	return e, nil
}

// Load locates the data directory automatically and calls LoadFrom.
//
// Resolution order:
//  1. the QURAN_ENGINE_DATA environment variable, if set;
//  2. walking up from the current working directory until a data/quran.json is found.
func Load() (*Engine, error) {
	if dir := os.Getenv("QURAN_ENGINE_DATA"); dir != "" {
		return LoadFrom(dir)
	}
	dir, err := FindDataDir()
	if err != nil {
		return nil, err
	}
	return LoadFrom(dir)
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
