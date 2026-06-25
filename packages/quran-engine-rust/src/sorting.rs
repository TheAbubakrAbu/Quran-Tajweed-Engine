//! Surah sorting & filtering. Mirrors `src/sorting.js`.
//!
//! Every comparator is ascending with `id` as the tiebreaker; descending is the reverse
//! of that array (so ties stay id-ascending within a reversed block). The `surah` natural
//! order (and `surahOrder` direction) bypass sorting.

use crate::model::Surah;

/// Sort mode keys understood by [`sort_surahs`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortMode {
    Surah,
    Revelation,
    Ayahs,
    Page,
    Words,
    Letters,
}

impl SortMode {
    /// Parse a JS-style mode string; unknown strings fall back to `Surah`.
    pub fn parse(s: &str) -> SortMode {
        match s {
            "revelation" => SortMode::Revelation,
            "ayahs" => SortMode::Ayahs,
            "page" => SortMode::Page,
            "words" => SortMode::Words,
            "letters" => SortMode::Letters,
            _ => SortMode::Surah,
        }
    }

    /// Whether this mode honours an ascending/descending direction.
    pub fn supports_direction(self) -> bool {
        !matches!(self, SortMode::Surah)
    }
}

/// Sort direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortDirection {
    SurahOrder,
    Ascending,
    Descending,
}

impl SortDirection {
    /// Parse a JS-style direction string; unknown strings fall back to `Ascending`.
    pub fn parse(s: &str) -> SortDirection {
        match s {
            "surahOrder" => SortDirection::SurahOrder,
            "descending" => SortDirection::Descending,
            _ => SortDirection::Ascending,
        }
    }
}

fn sort_key(s: &Surah, mode: SortMode) -> u64 {
    match mode {
        SortMode::Revelation => s.revelation_order.unwrap_or(u32::MAX) as u64,
        SortMode::Ayahs => s.number_of_ayahs as u64,
        SortMode::Page => s.number_of_pages.unwrap_or(0) as u64,
        SortMode::Words => s.word_count.unwrap_or(0) as u64,
        SortMode::Letters => s.letter_count.unwrap_or(0) as u64,
        SortMode::Surah => s.id as u64,
    }
}

/// Return the surahs sorted by `mode`/`direction`. Borrows the input and returns references
/// in the requested order; the source slice is never mutated.
pub fn sort_surahs(
    surahs: &[Surah],
    mode: SortMode,
    direction: SortDirection,
) -> Vec<&Surah> {
    let mut out: Vec<&Surah> = surahs.iter().collect();

    if direction == SortDirection::SurahOrder || mode == SortMode::Surah {
        out.sort_by_key(|s| s.id);
        return out;
    }

    // Ascending with id as the tiebreaker.
    out.sort_by(|a, b| {
        let (ka, kb) = (sort_key(a, mode), sort_key(b, mode));
        ka.cmp(&kb).then(a.id.cmp(&b.id))
    });

    // Descending = reverse of the ascending array (only for directional modes).
    if direction == SortDirection::Descending && mode.supports_direction() {
        out.reverse();
    }
    out
}

/// Filter surahs by revelation type (`"makkan"` / `"madinan"`).
pub fn filter_by_revelation_type<'a>(surahs: &'a [Surah], r#type: &str) -> Vec<&'a Surah> {
    surahs.iter().filter(|s| s.r#type == r#type).collect()
}
