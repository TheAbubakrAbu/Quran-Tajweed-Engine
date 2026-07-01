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

/// Comparison operator for a [`CountFilter`]. Mirrors the JS `'<'|'<='|'>'|'>='|'=='`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CountOp {
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
}

impl CountOp {
    /// Parse a JS-style operator string; unknown strings fall back to `Eq` (matching the
    /// `case "==": default:` branch in `sorting.js`).
    pub fn parse(s: &str) -> CountOp {
        match s {
            "<" => CountOp::Lt,
            "<=" => CountOp::Le,
            ">" => CountOp::Gt,
            ">=" => CountOp::Ge,
            _ => CountOp::Eq,
        }
    }

    /// Apply the operator to `n` against the filter's `value`.
    fn matches(self, n: u32, value: u32) -> bool {
        match self {
            CountOp::Lt => n < value,
            CountOp::Le => n <= value,
            CountOp::Gt => n > value,
            CountOp::Ge => n >= value,
            CountOp::Eq => n == value,
        }
    }
}

/// A single count predicate, e.g. `{ op: '>', value: 200 }`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountFilter {
    pub op: CountOp,
    pub value: u32,
}

impl CountFilter {
    /// Construct a filter from an op + value.
    pub fn new(op: CountOp, value: u32) -> CountFilter {
        CountFilter { op, value }
    }
}

/// Whether `n` passes the (optional) filter. An absent filter always passes.
fn passes_count(n: u32, f: Option<CountFilter>) -> bool {
    match f {
        None => true,
        Some(f) => f.op.matches(n, f.value),
    }
}

/// Filter surahs by ayah-count and/or page-count predicates. Mirrors `filterByCounts` in
/// `sorting.js`. A surah passes when it satisfies BOTH provided filters; an omitted filter
/// (`None`) is ignored. `value` is compared against `number_of_ayahs` / `number_of_pages`
/// (the latter defaulting to 0 when absent, as in the JS `?? 0`).
pub fn filter_by_counts(
    surahs: &[Surah],
    ayahs: Option<CountFilter>,
    pages: Option<CountFilter>,
) -> Vec<&Surah> {
    surahs
        .iter()
        .filter(|s| {
            passes_count(s.number_of_ayahs, ayahs)
                && passes_count(s.number_of_pages.unwrap_or(0), pages)
        })
        .collect()
}
