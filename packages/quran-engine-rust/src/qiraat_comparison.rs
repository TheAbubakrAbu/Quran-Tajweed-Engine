//! How far apart two readings actually are, measured word by word.
//!
//! The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which
//! says what differs but never how much. This measures it: align the two readings' words and sort
//! every pair into one of three buckets.
//!
//! * **identical** — the same word, written the same way, marks and all.
//! * **same skeleton** — the same consonantal skeleton (rasm), different vowels or spelling. This is
//!   the overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm
//!   was designed to allow: one written form, several sound readings.
//! * **different** — a different skeleton, i.e. a genuinely different word form.
//!
//! **Why alignment is not indexing.** Readings merge and split ayahs (Warsh's al-Baqarah has 285
//! ayahs to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n
//! of the other. The comparison walks the whole SURAH's word stream on both sides with a two-pointer
//! alignment and bounded lookahead rather than pairing by index.
//!
//! **What it cannot tell you.** This measures the two printed TEXTS, not the two recitations: a
//! difference that lives only in how a letter is sounded (imalah, taqlil, ishmam) shows up only
//! where the print marks it.
//!
//! Needs [`crate::LoadOptions::qiraat`]. See `../../docs/17-qiraat-comparison.md`.

use crate::text::removing_arabic_diacritics_and_signs;
use crate::Engine;

/// How far ahead to look for a resync before declaring a word added or dropped.
const LOOKAHEAD: usize = 3;

/// What happened to one word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DifferenceKind {
    /// The same consonantal skeleton, different vowels or spelling.
    SameSkeleton,
    /// A different skeleton: a genuinely different word form.
    Different,
    /// The compared reading has a word the base does not.
    Added,
    /// The base has a word the compared reading does not.
    Dropped,
}

/// One non-identical word pair.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WordDifference {
    /// 1-based word position in the BASE reading's surah.
    pub position: usize,
    /// The base reading's word (`""` when the other reading adds one).
    pub base: String,
    /// The compared reading's word (`""` when it drops one).
    pub other: String,
    pub kind: DifferenceKind,
}

/// The counts for a surah or for the whole Quran.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ComparisonTotals {
    /// Words compared, in the base reading.
    pub words: usize,
    pub identical: usize,
    pub same_skeleton: usize,
    pub different: usize,
    /// Words the compared reading has and the base does not.
    pub added: usize,
    /// Words the base has and the compared reading does not.
    pub dropped: usize,
}

impl ComparisonTotals {
    pub fn identical_percent(&self) -> f64 {
        if self.words == 0 {
            0.0
        } else {
            100.0 * self.identical as f64 / self.words as f64
        }
    }
}

/// The consonantal skeleton of a word: diacritics and recitation signs gone, the letters that are
/// written differently for the same consonant folded together.
pub fn skeleton(word: &str) -> String {
    removing_arabic_diacritics_and_signs(word)
        .chars()
        .filter_map(|ch| match ch {
            'ٱ' | 'أ' | 'إ' | 'آ' | 'ى' | 'ٰ' => Some('ا'),
            'ؤ' => Some('و'),
            'ئ' => Some('ي'),
            'ة' => Some('ه'),
            'ء' | 'ـ' => None,
            other => Some(other),
        })
        .collect()
}

impl Engine {
    /// The riwayat whose text is loaded and so can be compared, in slug order. `"hafs"` is always
    /// one of them: it is `quran.json` itself.
    pub fn comparable_riwayat(&self) -> Vec<String> {
        let mut slugs: Vec<String> =
            std::iter::once("hafs".to_string()).chain(self.qiraat.keys().cloned()).collect();
        slugs.sort_unstable();
        slugs.dedup();
        slugs
    }

    /// Every word of a surah in one reading, in order.
    pub fn qiraah_words(&self, surah: u32, riwayah: &str) -> Vec<String> {
        let Some(entry) = self.surah(surah) else {
            return Vec::new();
        };
        // The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking
        // Hafs' ayah ids and asking for each would compare different verses.
        let verses: Vec<&str> = if riwayah.eq_ignore_ascii_case("hafs") {
            entry.ayahs.iter().map(|a| a.text_arabic.as_str()).collect()
        } else {
            self.qiraah_verses(surah, riwayah).iter().map(|v| v.text.as_str()).collect()
        };
        verses.iter().flat_map(|text| text.split_whitespace()).map(str::to_string).collect()
    }

    /// Compare one surah, word by word.
    pub fn compare_surah(&self, surah: u32, riwayah: &str, against: &str) -> ComparisonTotals {
        totals(&self.align(surah, against, riwayah))
    }

    /// Compare the whole Quran. This walks every word of both readings — about 155,000 comparisons —
    /// so cache the result rather than calling it per render.
    pub fn compare_riwayah(&self, riwayah: &str, against: &str) -> ComparisonTotals {
        let mut sum = ComparisonTotals::default();
        for surah in self.surahs() {
            let part = self.compare_surah(surah.id, riwayah, against);
            sum.words += part.words;
            sum.identical += part.identical;
            sum.same_skeleton += part.same_skeleton;
            sum.different += part.different;
            sum.added += part.added;
            sum.dropped += part.dropped;
        }
        sum
    }

    /// The words that are not identical, in reading order — the rows behind a comparison view.
    /// `limit` of 0 returns them all.
    pub fn qiraat_differences(
        &self,
        surah: u32,
        riwayah: &str,
        against: &str,
        limit: usize,
    ) -> Vec<WordDifference> {
        let mut rows: Vec<WordDifference> = self
            .align(surah, against, riwayah)
            .into_iter()
            .filter_map(|row| {
                let kind = match row.kind {
                    RowKind::Identical => return None,
                    RowKind::SameSkeleton => DifferenceKind::SameSkeleton,
                    RowKind::Different => DifferenceKind::Different,
                    RowKind::Added => DifferenceKind::Added,
                    RowKind::Dropped => DifferenceKind::Dropped,
                };
                Some(WordDifference { position: row.position, base: row.base, other: row.other, kind })
            })
            .collect();
        if limit > 0 {
            rows.truncate(limit);
        }
        rows
    }

    /// Two-pointer alignment with bounded lookahead.
    fn align(&self, surah: u32, base: &str, other: &str) -> Vec<Row> {
        let left = self.qiraah_words(surah, base);
        let right = self.qiraah_words(surah, other);
        let left_skeletons: Vec<String> = left.iter().map(|w| skeleton(w)).collect();
        let right_skeletons: Vec<String> = right.iter().map(|w| skeleton(w)).collect();
        let mut rows = Vec::new();

        let (mut i, mut j) = (0usize, 0usize);
        while i < left.len() && j < right.len() {
            if left[i] == right[j] {
                rows.push(Row::new(i + 1, &left[i], &right[j], RowKind::Identical));
                i += 1;
                j += 1;
                continue;
            }
            if left_skeletons[i] == right_skeletons[j] {
                rows.push(Row::new(i + 1, &left[i], &right[j], RowKind::SameSkeleton));
                i += 1;
                j += 1;
                continue;
            }
            // Not a match. Before calling it a different word, see whether one side simply has an
            // extra word here — a merge or a split — by looking for the next place they agree.
            if let Some((ri, rj)) = find_resync(&left_skeletons, &right_skeletons, i, j) {
                for k in i..ri {
                    rows.push(Row::new(k + 1, &left[k], "", RowKind::Dropped));
                }
                for k in j..rj {
                    rows.push(Row::new(i + 1, "", &right[k], RowKind::Added));
                }
                i = ri;
                j = rj;
                continue;
            }
            rows.push(Row::new(i + 1, &left[i], &right[j], RowKind::Different));
            i += 1;
            j += 1;
        }
        while i < left.len() {
            rows.push(Row::new(i + 1, &left[i], "", RowKind::Dropped));
            i += 1;
        }
        while j < right.len() {
            rows.push(Row::new(left.len(), "", &right[j], RowKind::Added));
            j += 1;
        }
        rows
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RowKind {
    Identical,
    SameSkeleton,
    Different,
    Added,
    Dropped,
}

#[derive(Debug, Clone)]
struct Row {
    position: usize,
    base: String,
    other: String,
    kind: RowKind,
}

impl Row {
    fn new(position: usize, base: &str, other: &str, kind: RowKind) -> Row {
        Row { position, base: base.to_string(), other: other.to_string(), kind }
    }
}

/// The nearest offset within the lookahead window at which the two streams agree again by skipping
/// words on ONE side only — an insertion or a deletion.
///
/// Skipping on both sides at once is deliberately not a resync: that is a substitution, one word
/// standing where another does, which is the `Different` bucket. Allowing it here collapsed every
/// genuine word difference into a dropped+added pair and left `different` permanently at zero.
fn find_resync(left: &[String], right: &[String], i: usize, j: usize) -> Option<(usize, usize)> {
    for skip in 1..=LOOKAHEAD {
        if i + skip < left.len() && left[i + skip] == right[j] {
            return Some((i + skip, j));
        }
        if j + skip < right.len() && left[i] == right[j + skip] {
            return Some((i, j + skip));
        }
    }
    None
}

fn totals(rows: &[Row]) -> ComparisonTotals {
    let mut out = ComparisonTotals::default();
    for row in rows {
        if row.kind == RowKind::Added {
            out.added += 1;
            continue;
        }
        out.words += 1;
        match row.kind {
            RowKind::Identical => out.identical += 1,
            RowKind::SameSkeleton => out.same_skeleton += 1,
            RowKind::Dropped => out.dropped += 1,
            _ => out.different += 1,
        }
    }
    out
}
