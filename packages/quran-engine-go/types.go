// Package quranengine is the Go port of the open-source Quran Tajweed Engine.
//
// It is a thin, idiomatic wrapper over the JSON data in the repository's /data
// directory plus a handful of pure functions. Nothing here needs a network call,
// a database, or a framework. The data is the engine.
//
// See ../../docs/PORTING.md for the cross-language contract this port implements,
// and ../../CREDITS.md for attribution. Licensed MIT.
package quranengine

// Ayah is a single verse. JSON keys are camelCase to match data/quran.json.
type Ayah struct {
	ID                  int    `json:"id"`
	TextArabic          string `json:"textArabic"` // Hafs Uthmani text (full diacritics)
	TextTransliteration string `json:"textTransliteration"`
	TextEnglishSaheeh   string `json:"textEnglishSaheeh"`  // Saheeh International
	TextEnglishMustafa  string `json:"textEnglishMustafa"` // Mustafa Khattab (The Clear Quran)
	Juz                 int    `json:"juz"`
	Page                int    `json:"page"`
	WordCount           int    `json:"wordCount"`
	LetterCount         int    `json:"letterCount"`
}

// Surah is one of the 114 chapters.
type Surah struct {
	ID                  int      `json:"id"`
	Type                string   `json:"type"` // "makkan" | "madinan"
	NameArabic          string   `json:"nameArabic"`
	NameTransliteration string   `json:"nameTransliteration"`
	NameEnglish         string   `json:"nameEnglish"`
	NumberOfAyahs       int      `json:"numberOfAyahs"`
	PageStart           int      `json:"pageStart"`
	PageEnd             int      `json:"pageEnd"`
	NumberOfPages       int      `json:"numberOfPages"`
	FirstJuz            int      `json:"firstJuz"`
	LastJuz             int      `json:"lastJuz"`
	Juzs                []int    `json:"juzs"`
	RevelationOrder     int      `json:"revelationOrder"`
	SimilarNames        []string `json:"similarNames"`
	WordCount           int      `json:"wordCount"`
	LetterCount         int      `json:"letterCount"`
	Ayahs               []Ayah   `json:"ayahs"`
}

// JuzEntry is a static juz (para) boundary entry from data/juz.json.
type JuzEntry struct {
	ID                  int    `json:"id"`
	NameArabic          string `json:"nameArabic"`
	NameTransliteration string `json:"nameTransliteration"`
	StartSurah          int    `json:"startSurah"`
	StartAyah           int    `json:"startAyah"`
	EndSurah            int    `json:"endSurah"`
	EndAyah             int    `json:"endAyah"`
}

// Reciter describes one recitation feed from data/reciters.json.
// Its id is "{name}|{qiraah or 'Hafs'}|{surahLink}".
type Reciter struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	AyahIdentifier string `json:"ayahIdentifier"` // e.g. "ar.alafasy"
	AyahBitrate    string `json:"ayahBitrate"`    // e.g. "128" (used verbatim)
	SurahLink      string `json:"surahLink"`      // full-surah CDN base, trailing slash
	Qiraah         string `json:"qiraah"`         // "" => Hafs; else riwayah label
	Group          string `json:"group"`
}

// TajweedSpan is a colored slice of an ayah's Arabic text produced from the
// pre-computed annotation corpus.
type TajweedSpan struct {
	Start    int    `json:"start"` // UTF-16 code-unit offset (inclusive)
	End      int    `json:"end"`   // UTF-16 code-unit offset (exclusive)
	Rule     string `json:"rule"`
	ColorHex string `json:"colorHex"` // mapped from tajweed-rules.json categories
	Text     string `json:"text"`     // reconstructed substring for [start,end)
}

// AyahRef pairs an ayah with its containing surah (returned by juz/page iteration).
type AyahRef struct {
	Surah *Surah
	Ayah  *Ayah
}

// Reference is the result of parsing "2:255" and similar.
type Reference struct {
	Surah   int
	Ayah    int  // 0 when absent
	HasAyah bool // whether an ayah component was present
}

// --- raw on-disk shapes used only during Load -------------------------------

type tajweedRule struct {
	ID       string `json:"id"`
	ColorHex string `json:"colorHex"`
}

type tajweedRulesFile struct {
	Categories []tajweedRule `json:"categories"`
}

type tajweedAnnotation struct {
	Start int    `json:"start"`
	End   int    `json:"end"`
	Rule  string `json:"rule"`
}

type tajweedAnnotationEntry struct {
	Surah       int                 `json:"surah"`
	Ayah        int                 `json:"ayah"`
	Annotations []tajweedAnnotation `json:"annotations"`
}
