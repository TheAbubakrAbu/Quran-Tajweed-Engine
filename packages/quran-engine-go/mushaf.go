package quranengine

// The printed mushaf: twenty riwayat as page-exact facsimiles, and the page table each one is
// actually paginated by.
//
// A riwayah's pagination is NOT Hafs' pagination. Readings merge and split ayahs and spell words
// differently, so the same ayah sits on a different page in Warsh's print than in Hafs'. The page
// numbers on quran.json's ayahs are the Madani (Hafs) ones; MushafPage is that riwayah's own.
// Every facsimile is exactly 604 pages on the Madani division, so PDF page N is mushaf page N with
// no offset table.
//
// Twelve of the twenty ship their printed mushaf and page table but no text: their text is
// machine-extracted and not yet proofread, so it is not published, and the line and tajweed data
// that index into it stay out with it. RiwayahEntry.TextIncluded says which is which.
//
// See ../../docs/10-mushaf.md.

import "strconv"

// RiwayahEntry is one row of data/mushaf/index.json.
type RiwayahEntry struct {
	// Riwayah is the slug, e.g. "warsh".
	Riwayah string `json:"riwayah"`
	// Tag is what the Al-Islam app stores for this riwayah ("" for Hafs).
	Tag        string `json:"tag"`
	Name       string `json:"name"`
	NameArabic string `json:"nameArabic"`
	// Imam is the qiraah's imam, e.g. "Nafi".
	Imam       string `json:"imam"`
	ImamArabic string `json:"imamArabic"`
	// NarratorDiedAH is spelled with a trailing capital AH in the JSON.
	NarratorDiedAH int `json:"narratorDiedAH"`
	// PDF is the facsimile's path relative to data/mushaf/. One solid xz stream over the PDF.
	PDF      string `json:"pdf"`
	PDFBytes int64  `json:"pdfBytes"`
	Pages    string `json:"pages"`
	// Lines is "" when the riwayah's text (and so its line table) is not published.
	Lines string `json:"lines"`
	// Tajweed is "" when the riwayah has no tajweed pack.
	Tajweed      string `json:"tajweed"`
	TextIncluded bool   `json:"textIncluded"`
}

// MushafIndex is data/mushaf/index.json.
type MushafIndex struct {
	TotalPages int            `json:"totalPages"`
	Note       string         `json:"note"`
	Riwayat    []RiwayahEntry `json:"riwayat"`
}

// MushafPageTable is data/mushaf/pages/<slug>.json: surah id -> ayah id -> page.
type MushafPageTable struct {
	Riwayah    string                    `json:"riwayah"`
	TotalPages int                       `json:"totalPages"`
	Pages      map[string]map[string]int `json:"pages"`
}

// MushafLineTable is data/mushaf/lines/<slug>.json: surah id -> ayah id -> the character offsets
// into the ayah's own text at which a new printed line starts.
type MushafLineTable struct {
	Riwayah    string                      `json:"riwayah"`
	Version    int                         `json:"version"`
	LineBreaks map[string]map[string][]int `json:"lineBreaks"`
}

// Riwayat returns every riwayah, in the classical order of the Ten Qiraat. Empty unless the engine
// was loaded with LoadOptions.Mushaf.
func (e *Engine) Riwayat() []RiwayahEntry {
	if e.mushafIndex == nil {
		return nil
	}
	return e.mushafIndex.Riwayat
}

// RiwayatWithText returns only the riwayat whose text this engine publishes (the eight verified).
func (e *Engine) RiwayatWithText() []RiwayahEntry {
	var out []RiwayahEntry
	for _, entry := range e.Riwayat() {
		if entry.TextIncluded {
			out = append(out, entry)
		}
	}
	return out
}

// Riwayah looks one up by slug.
func (e *Engine) Riwayah(slug string) *RiwayahEntry {
	riwayat := e.Riwayat()
	for i := range riwayat {
		if riwayat[i].Riwayah == slug {
			return &riwayat[i]
		}
	}
	return nil
}

// MushafTotalPages is 604 for every facsimile in the set.
func (e *Engine) MushafTotalPages() int {
	if e.mushafIndex == nil {
		return 604
	}
	return e.mushafIndex.TotalPages
}

// MushafPDFPath is the facsimile's path relative to data/mushaf/. It is one solid xz stream over
// the PDF: decompress it before handing the bytes to a PDF renderer.
func (e *Engine) MushafPDFPath(slug string) string {
	if entry := e.Riwayah(slug); entry != nil {
		return entry.PDF
	}
	return ""
}

// MushafPage is the page an ayah is printed on in this riwayah's own mushaf. Zero when unknown.
func (e *Engine) MushafPage(surahID, ayahID int, riwayah string) int {
	table, ok := e.mushafPages[riwayah]
	if !ok {
		return 0
	}
	ayahs, ok := table.Pages[strconv.Itoa(surahID)]
	if !ok {
		return 0
	}
	return ayahs[strconv.Itoa(ayahID)]
}

// MushafAyahsOnPage lists every ayah printed on a page of this riwayah's mushaf, in mushaf order.
func (e *Engine) MushafAyahsOnPage(page int, riwayah string) []VerseMatch {
	table, ok := e.mushafPages[riwayah]
	if !ok {
		return nil
	}
	// Walked in mushaf order, so the result is ordered without a second sort.
	var out []VerseMatch
	for i := range e.surahs {
		surah := &e.surahs[i]
		ayahs, ok := table.Pages[strconv.Itoa(surah.ID)]
		if !ok {
			continue
		}
		for ayah := 1; ayah <= surah.NumberOfAyahs; ayah++ {
			if ayahs[strconv.Itoa(ayah)] == page {
				out = append(out, VerseMatch{Surah: surah.ID, Ayah: ayah})
			}
		}
	}
	return out
}

// MushafFirstAyahOfPage is what a "go to page 213" jump lands on.
func (e *Engine) MushafFirstAyahOfPage(page int, riwayah string) *VerseMatch {
	hits := e.MushafAyahsOnPage(page, riwayah)
	if len(hits) == 0 {
		return nil
	}
	return &hits[0]
}

// MushafLineBreaks returns the character offsets into the ayah's own text at which this riwayah's
// print starts a new line. The second result is false when the riwayah's text, and so its line
// table, is not published.
func (e *Engine) MushafLineBreaks(surahID, ayahID int, riwayah string) ([]int, bool) {
	table, ok := e.mushafLines[riwayah]
	if !ok {
		return nil, false
	}
	ayahs, ok := table.LineBreaks[strconv.Itoa(surahID)]
	if !ok {
		return nil, false
	}
	breaks, ok := ayahs[strconv.Itoa(ayahID)]
	return breaks, ok
}

// HasTajweedPack reports whether tajweed-qiraat/<slug>.json exists for this riwayah.
func (e *Engine) HasTajweedPack(riwayah string) bool {
	entry := e.Riwayah(riwayah)
	return entry != nil && entry.Tajweed != ""
}
