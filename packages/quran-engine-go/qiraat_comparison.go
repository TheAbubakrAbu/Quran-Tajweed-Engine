package quranengine

// How far apart two readings actually are, measured word by word.
//
// The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which
// says what differs but never how much. This measures it: align the two readings' words and sort
// every pair into one of three buckets.
//
//   - identical: the same word, written the same way, marks and all.
//   - sameSkeleton: the same consonantal skeleton (rasm), different vowels or spelling. This is the
//     overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm was
//     designed to allow: one written form, several sound readings.
//   - different: a different skeleton, i.e. a genuinely different word form.
//
// WHY ALIGNMENT IS NOT INDEXING. Readings merge and split ayahs (Warsh's al-Baqarah has 285 ayahs to
// Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n of the
// other. The comparison walks the whole SURAH's word stream on both sides with a two-pointer
// alignment and bounded lookahead rather than pairing by index.
//
// WHAT IT CANNOT TELL YOU. This measures the two printed TEXTS, not the two recitations: a
// difference that lives only in how a letter is sounded (imalah, taqlil, ishmam) shows up only where
// the print marks it.
//
// Needs LoadOptions.Qiraat. See ../../docs/17-qiraat-comparison.md.

import (
	"sort"
	"strconv"
	"strings"
)

// lookahead is how far to look for a resync before declaring a word added or dropped.
const lookahead = 3

// DifferenceKind says what happened to one word.
type DifferenceKind string

const (
	// DifferenceSameSkeleton is the same consonantal skeleton, different vowels or spelling.
	DifferenceSameSkeleton DifferenceKind = "sameSkeleton"
	// DifferenceDifferent is a different skeleton: a genuinely different word form.
	DifferenceDifferent DifferenceKind = "different"
	// DifferenceAdded means the compared reading has a word the base does not.
	DifferenceAdded DifferenceKind = "added"
	// DifferenceDropped means the base has a word the compared reading does not.
	DifferenceDropped DifferenceKind = "dropped"
	differenceSame    DifferenceKind = "identical"
)

// WordDifference is one non-identical word pair.
type WordDifference struct {
	// Position is the 1-based word position in the BASE reading's surah.
	Position int
	// Base is the base reading's word ("" when the other reading adds one).
	Base string
	// Other is the compared reading's word ("" when it drops one).
	Other string
	Kind  DifferenceKind
}

// ComparisonTotals are the counts for a surah or for the whole Quran.
type ComparisonTotals struct {
	// Words compared, in the base reading.
	Words        int
	Identical    int
	SameSkeleton int
	Different    int
	// Added are words the compared reading has and the base does not.
	Added int
	// Dropped are words the base has and the compared reading does not.
	Dropped int
}

// IdenticalPercent is Identical / Words, 0..100.
func (t ComparisonTotals) IdenticalPercent() float64 {
	if t.Words == 0 {
		return 0
	}
	return 100 * float64(t.Identical) / float64(t.Words)
}

// QiraahSkeleton is the consonantal skeleton of a word: diacritics and recitation signs gone, the
// letters that are written differently for the same consonant folded together.
func QiraahSkeleton(word string) string {
	var out strings.Builder
	for _, r := range removingArabicDiacriticsAndSigns(word) {
		switch r {
		case 'ٱ', 'أ', 'إ', 'آ', 'ى', 'ٰ':
			out.WriteRune('ا')
		case 'ؤ':
			out.WriteRune('و')
		case 'ئ':
			out.WriteRune('ي')
		case 'ة':
			out.WriteRune('ه')
		case 'ء', 'ـ':
			// dropped
		default:
			out.WriteRune(r)
		}
	}
	return out.String()
}

// ComparableRiwayat lists the riwayat whose text is loaded and so can be compared, in slug order.
// "hafs" is always one of them: it is quran.json itself.
func (e *Engine) ComparableRiwayat() []string {
	slugs := []string{"hafs"}
	for slug := range e.qiraat {
		if slug != "hafs" {
			slugs = append(slugs, slug)
		}
	}
	sort.Strings(slugs)
	return slugs
}

// QiraahWords returns every word of a surah in one reading, in order.
func (e *Engine) QiraahWords(surahID int, riwayah string) []string {
	surah := e.Surah(surahID)
	if surah == nil {
		return nil
	}
	// The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking Hafs'
	// ayah ids and asking for each would compare different verses.
	var texts []string
	if strings.EqualFold(riwayah, "hafs") {
		for _, ayah := range surah.Ayahs {
			texts = append(texts, ayah.TextArabic)
		}
	} else {
		for _, verse := range e.QiraahVerses(surahID, riwayah) {
			texts = append(texts, verse.Text)
		}
	}
	var out []string
	for _, text := range texts {
		out = append(out, strings.Fields(text)...)
	}
	return out
}

// QiraahVerses returns a riwayah's own verses for a surah, in ITS numbering - which is not always
// Hafs'. Warsh's al-Baqarah has 285 verses to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as
// one; pairing the two by ayah id past that point compares different verses.
//
// Empty unless LoadOptions.Qiraat, and for "hafs", whose text is quran.json itself.
func (e *Engine) QiraahVerses(surahID int, riwayah string) []QiraahVerse {
	return e.qiraat[strings.ToLower(riwayah)][strconv.Itoa(surahID)]
}

// LoadedRiwayat lists the riwayat whose text is loaded, in slug order.
func (e *Engine) LoadedRiwayat() []string {
	slugs := make([]string, 0, len(e.qiraat))
	for slug := range e.qiraat {
		slugs = append(slugs, slug)
	}
	sort.Strings(slugs)
	return slugs
}

// CompareSurah compares one surah, word by word.
func (e *Engine) CompareSurah(surahID int, riwayah, against string) ComparisonTotals {
	return comparisonTotals(e.alignQiraat(surahID, against, riwayah))
}

// CompareRiwayah compares the whole Quran. This walks every word of both readings - about 155,000
// comparisons - so cache the result rather than calling it per render.
func (e *Engine) CompareRiwayah(riwayah, against string) ComparisonTotals {
	var sum ComparisonTotals
	for i := range e.surahs {
		part := e.CompareSurah(e.surahs[i].ID, riwayah, against)
		sum.Words += part.Words
		sum.Identical += part.Identical
		sum.SameSkeleton += part.SameSkeleton
		sum.Different += part.Different
		sum.Added += part.Added
		sum.Dropped += part.Dropped
	}
	return sum
}

// QiraatDifferences lists the words that are not identical, in reading order - the rows behind a
// comparison view. A limit of 0 returns them all.
func (e *Engine) QiraatDifferences(surahID int, riwayah, against string, limit int) []WordDifference {
	var out []WordDifference
	for _, row := range e.alignQiraat(surahID, against, riwayah) {
		if row.Kind == differenceSame {
			continue
		}
		out = append(out, row)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out
}

// alignQiraat is a two-pointer alignment with bounded lookahead.
func (e *Engine) alignQiraat(surahID int, base, other string) []WordDifference {
	left := e.QiraahWords(surahID, base)
	right := e.QiraahWords(surahID, other)
	leftSkeletons := make([]string, len(left))
	for i, word := range left {
		leftSkeletons[i] = QiraahSkeleton(word)
	}
	rightSkeletons := make([]string, len(right))
	for i, word := range right {
		rightSkeletons[i] = QiraahSkeleton(word)
	}

	var rows []WordDifference
	i, j := 0, 0
	for i < len(left) && j < len(right) {
		if left[i] == right[j] {
			rows = append(rows, WordDifference{i + 1, left[i], right[j], differenceSame})
			i++
			j++
			continue
		}
		if leftSkeletons[i] == rightSkeletons[j] {
			rows = append(rows, WordDifference{i + 1, left[i], right[j], DifferenceSameSkeleton})
			i++
			j++
			continue
		}
		// Not a match. Before calling it a different word, see whether one side simply has an extra
		// word here - a merge or a split - by looking for the next place they agree.
		if ri, rj, ok := findResync(leftSkeletons, rightSkeletons, i, j); ok {
			for k := i; k < ri; k++ {
				rows = append(rows, WordDifference{k + 1, left[k], "", DifferenceDropped})
			}
			for k := j; k < rj; k++ {
				rows = append(rows, WordDifference{i + 1, "", right[k], DifferenceAdded})
			}
			i, j = ri, rj
			continue
		}
		rows = append(rows, WordDifference{i + 1, left[i], right[j], DifferenceDifferent})
		i++
		j++
	}
	for ; i < len(left); i++ {
		rows = append(rows, WordDifference{i + 1, left[i], "", DifferenceDropped})
	}
	for ; j < len(right); j++ {
		rows = append(rows, WordDifference{len(left), "", right[j], DifferenceAdded})
	}
	return rows
}

// findResync is the nearest offset within the lookahead window at which the two streams agree again
// by skipping words on ONE side only - an insertion or a deletion.
//
// Skipping on both sides at once is deliberately not a resync: that is a substitution, one word
// standing where another does, which is the "different" bucket. Allowing it here collapsed every
// genuine word difference into a dropped+added pair and left "different" permanently at zero.
func findResync(left, right []string, i, j int) (int, int, bool) {
	for skip := 1; skip <= lookahead; skip++ {
		if i+skip < len(left) && left[i+skip] == right[j] {
			return i + skip, j, true
		}
		if j+skip < len(right) && left[i] == right[j+skip] {
			return i, j + skip, true
		}
	}
	return 0, 0, false
}

func comparisonTotals(rows []WordDifference) ComparisonTotals {
	var out ComparisonTotals
	for _, row := range rows {
		if row.Kind == DifferenceAdded {
			out.Added++
			continue
		}
		out.Words++
		switch row.Kind {
		case differenceSame:
			out.Identical++
		case DifferenceSameSkeleton:
			out.SameSkeleton++
		case DifferenceDropped:
			out.Dropped++
		default:
			out.Different++
		}
	}
	return out
}
