package quranengine

// The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name and
// transliteration, and - the part that matters for tajweed - its WEIGHT.
//
// Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
// pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the
// divine name), and alif has no weight of its own at all: it inherits the letter before it. That
// single fact is behind a large share of beginner mistakes, and it is a property of the letter, not
// of any particular verse, so it lives here beside the letter and not in the annotation corpus.
//
// Also carried: the letters outside the 28, the six Persian/Urdu letters some printed mushafs use,
// the Eastern-Arabic numerals, the tashkeel marks, and the waqf (stopping) signs.
//
// See ../../docs/16-arabic-alphabet.md.

import "strings"

// ArabicLetter is one letter of the reference.
type ArabicLetter struct {
	ID int `json:"id"`
	// Letter is the isolated form.
	Letter string `json:"letter"`
	// Forms are final, medial and initial, as the source records them.
	Forms           []string `json:"forms"`
	Name            string   `json:"name"`
	Transliteration string   `json:"transliteration"`
	ShowTashkeel    bool     `json:"showTashkeel"`
	Sound           string   `json:"sound"`
	// Weight is "light", "heavy", "conditional" or "followsPrevious"; "" where none is recorded.
	Weight string `json:"weight"`
	// WeightRule says why, in one sentence.
	WeightRule string `json:"weightRule"`
}

// Tashkeel is one vowel mark.
type Tashkeel struct {
	English         string `json:"english"`
	Arabic          string `json:"arabic"`
	Mark            string `json:"mark"`
	Transliteration string `json:"transliteration"`
}

// StoppingSign is one waqf sign and what it tells the reciter to do.
type StoppingSign struct {
	Symbol string `json:"symbol"`
	Title  string `json:"title"`
}

// ArabicNumeral is one Eastern-Arabic digit.
type ArabicNumeral struct {
	Number          string `json:"number"`
	Name            string `json:"name"`
	Transliteration string `json:"transliteration"`
	EnglishNumber   string `json:"englishNumber"`
}

// arabicAlphabetFile is data/arabic-alphabet.json.
type arabicAlphabetFile struct {
	Description            string            `json:"description"`
	Weights                map[string]string `json:"weights"`
	StandardLetters        []ArabicLetter    `json:"standardLetters"`
	OtherLetters           []ArabicLetter    `json:"otherLetters"`
	NonArabicScriptLetters []ArabicLetter    `json:"nonArabicScriptLetters"`
	Numbers                []ArabicNumeral   `json:"numbers"`
	Tashkeel               []Tashkeel        `json:"tashkeel"`
	StoppingSigns          []StoppingSign    `json:"stoppingSigns"`
	StoppingSignsSource    string            `json:"stoppingSignsSource"`
}

// Letters returns the 28 letters of the alphabet, in order.
func (e *Engine) Letters() []ArabicLetter { return e.alphabet.StandardLetters }

// OtherLetters returns hamza, ta marbuta, lam-alif and the rest: forms outside the 28.
func (e *Engine) OtherLetters() []ArabicLetter { return e.alphabet.OtherLetters }

// NonArabicScriptLetters returns the Persian/Urdu letters some printed mushafs use.
func (e *Engine) NonArabicScriptLetters() []ArabicLetter { return e.alphabet.NonArabicScriptLetters }

// AllLetters returns every letter this reference knows, the 28 first.
func (e *Engine) AllLetters() []ArabicLetter {
	out := make([]ArabicLetter, 0,
		len(e.alphabet.StandardLetters)+len(e.alphabet.OtherLetters)+len(e.alphabet.NonArabicScriptLetters))
	out = append(out, e.alphabet.StandardLetters...)
	out = append(out, e.alphabet.OtherLetters...)
	out = append(out, e.alphabet.NonArabicScriptLetters...)
	return out
}

// Letter looks one up by its isolated form. Accepts any of its joining forms too, so a letter
// lifted out of a word still resolves.
func (e *Engine) Letter(letter string) *ArabicLetter {
	wanted := strings.TrimSpace(letter)
	if wanted == "" {
		return nil
	}
	all := e.AllLetters()
	for i := range all {
		if all[i].Letter == wanted {
			return &all[i]
		}
		for _, form := range all[i].Forms {
			if form == wanted {
				return &all[i]
			}
		}
	}
	return nil
}

// LetterByID looks one up by its id.
func (e *Engine) LetterByID(id int) *ArabicLetter {
	all := e.AllLetters()
	for i := range all {
		if all[i].ID == id {
			return &all[i]
		}
	}
	return nil
}

// LetterWeight is the tajweed weight of a letter, or "" when the reference records none.
func (e *Engine) LetterWeight(letter string) string {
	if entry := e.Letter(letter); entry != nil {
		return entry.Weight
	}
	return ""
}

// WeightDescriptions says what a weight name means, in one line.
func (e *Engine) WeightDescriptions() map[string]string { return e.alphabet.Weights }

// HeavyLetters are the letters pronounced full - the isti'la letters.
func (e *Engine) HeavyLetters() []ArabicLetter {
	var out []ArabicLetter
	for _, letter := range e.alphabet.StandardLetters {
		if letter.Weight == "heavy" {
			out = append(out, letter)
		}
	}
	return out
}

// Tashkeel returns the vowel marks, with the sound each one writes.
func (e *Engine) Tashkeel() []Tashkeel { return e.alphabet.Tashkeel }

// StoppingSigns returns the waqf signs.
func (e *Engine) StoppingSigns() []StoppingSign { return e.alphabet.StoppingSigns }

// StoppingSign looks one up by its symbol.
func (e *Engine) StoppingSign(symbol string) *StoppingSign {
	for i := range e.alphabet.StoppingSigns {
		if e.alphabet.StoppingSigns[i].Symbol == symbol {
			return &e.alphabet.StoppingSigns[i]
		}
	}
	return nil
}

// ArabicNumbers returns the Eastern-Arabic numerals, 0 through 10.
func (e *Engine) ArabicNumbers() []ArabicNumeral { return e.alphabet.Numbers }

// StoppingSignsSource says where the waqf sign meanings come from.
func (e *Engine) StoppingSignsSource() string { return e.alphabet.StoppingSignsSource }
