//! Ayah & surah search — **core path only**. Mirrors the non-boolean path of `src/search.js`.
//!
//! ## What is implemented
//! - `search_verses`: unranked verse-text search in mushaf order. A verse matches when the whole
//!   cleaned query is a substring of the relevant (Arabic or English) blob, OR the query tokens
//!   phrase-prefix-match the verse tokens (all-but-last exact, last is a prefix). Verse search
//!   rejects any query containing a digit.
//! - `search_surahs`: name / alias / number / `"2:255"` / makkan-madani lookup.
//! - `parse_reference`: `"2:255"`, `"2 255"`, `"baqarah 10"`, Arabic-digit forms.
//!
//! ## What is intentionally omitted (documented divergence)
//! The **boolean grammar** (`& | ! # ^ % $`) and its dedicated tashkeel / exact-phrase /
//! silent-letter blobs are **not** ported. A query containing a boolean operator is treated as
//! plain text here. This matches the "minimal port" allowance in `docs/06-ayah-search.md` /
//! `docs/PORTING.md` ("A minimal port may implement substring matching on the folded blobs and
//! skip the boolean grammar; document what you skipped.").

use crate::model::Surah;
use crate::text::{
    arabic_digits_to_western, clean_search, contains_arabic_letters,
    removing_arabic_diacritics_and_signs, search_tokens,
};

/// A verse search result (mushaf order).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerseHit {
    pub surah: u32,
    pub ayah: u32,
}

/// A parsed `"2:255"`-style reference.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reference {
    pub surah: u32,
    pub ayah: Option<u32>,
}

/// Options for [`SearchIndex::search_verses`].
#[derive(Debug, Clone, Default)]
pub struct SearchOpts {
    pub offset: Option<usize>,
    pub limit: Option<usize>,
}

struct VerseEntry {
    surah: u32,
    ayah: u32,
    arabic_blob: String,
    english_blob: String,
    arabic_tokens: Vec<String>,
    english_tokens: Vec<String>,
}

struct SurahEntry {
    id: u32,
    blob: String,
    compact: String,
    upper: String,
}

/// Precomputed search index over the parsed surahs.
pub struct SearchIndex {
    verses: Vec<VerseEntry>,
    surahs: Vec<SurahEntry>,
}

impl SearchIndex {
    /// Build the verse + surah indexes from the parsed surahs (mushaf order).
    pub fn build(surahs: &[Surah]) -> SearchIndex {
        let mut verses = Vec::new();
        for s in surahs {
            for a in &s.ayahs {
                let raw = &a.text_arabic;
                let clean = removing_arabic_diacritics_and_signs(raw);
                let arabic_blob = format!("{} {}", clean_search(raw), clean_search(&clean));
                let english_blob = format!(
                    "{} {} {}",
                    clean_search(&a.text_english_saheeh),
                    clean_search(&a.text_english_mustafa),
                    clean_search(&a.text_transliteration),
                );
                let arabic_tokens = search_tokens(&arabic_blob);
                let english_tokens = search_tokens(&english_blob);
                verses.push(VerseEntry {
                    surah: s.id,
                    ayah: a.id,
                    arabic_blob,
                    english_blob,
                    arabic_tokens,
                    english_tokens,
                });
            }
        }

        let surah_idx = surahs
            .iter()
            .map(|s| {
                let mut names: Vec<String> = vec![
                    s.name_arabic.clone(),
                    s.name_transliteration.clone(),
                    s.name_english.clone(),
                ];
                names.extend(s.similar_names.iter().cloned());
                names.push(s.id.to_string());
                let blob = clean_search(&names.join(" "));
                let compact = blob.replace(' ', "");
                let upper = format!("{} {}", s.name_english, s.name_transliteration).to_uppercase();
                SurahEntry { id: s.id, blob, compact, upper }
            })
            .collect();

        SearchIndex { verses, surahs: surah_idx }
    }

    /// Verse-text search (unranked, mushaf order). See module docs for the matching rules.
    pub fn search_verses(&self, query: &str, opts: &SearchOpts) -> Vec<VerseHit> {
        let cleaned = clean_search(query);
        if cleaned.is_empty() {
            return Vec::new();
        }
        // Verse-text search rejects any query containing a digit.
        if cleaned.chars().any(|c| c.is_ascii_digit()) {
            return Vec::new();
        }

        let use_arabic = contains_arabic_letters(query);
        let q_tokens = search_tokens(&cleaned);

        let hits = self.verses.iter().filter(|e| {
            if use_arabic {
                e.arabic_blob.contains(&cleaned)
                    || phrase_prefix_match(&e.arabic_tokens, &q_tokens)
            } else {
                e.english_blob.contains(&cleaned)
                    || phrase_prefix_match(&e.english_tokens, &q_tokens)
            }
        });

        let offset = opts.offset.unwrap_or(0);
        let mut out: Vec<VerseHit> = hits
            .skip(offset)
            .map(|e| VerseHit { surah: e.surah, ayah: e.ayah })
            .collect();
        if let Some(limit) = opts.limit {
            out.truncate(limit);
        }
        out
    }

    /// Search surahs by name, alias, number, `"2:255"` reference, or makkan/madani.
    /// Returns matched surah ids in natural (index) order.
    pub fn search_surahs(&self, query: &str) -> Vec<u32> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return self.surahs.iter().map(|s| s.id).collect();
        }

        // NOTE: the makkan/madani revelation filter (which short-circuits in the JS port) is
        // handled by `Engine::search_surahs`, which has access to each surah's revelation type.

        let reference = self.parse_reference(trimmed);
        let cleaned = clean_search(&trimmed.replace(':', ""));
        let compact = cleaned.replace(' ', "");
        let upper = trimmed.to_uppercase();
        let numeric: Option<u32> = reference
            .as_ref()
            .map(|r| r.surah)
            .or_else(|| to_number(&cleaned));

        self.surahs
            .iter()
            .filter(|s| {
                numeric == Some(s.id)
                    || (!s.upper.is_empty() && upper.contains(&s.upper))
                    || (!cleaned.is_empty() && s.blob.contains(&cleaned))
                    || (!compact.is_empty() && s.compact.contains(&compact))
            })
            .map(|s| s.id)
            .collect()
    }

    /// Parse an ayah reference like `"2:255"`, `"2 255"`, `"baqarah 10"`, or Arabic-digit forms.
    pub fn parse_reference(&self, query: &str) -> Option<Reference> {
        let western = arabic_digits_to_western(query);
        let parts: Vec<&str> = western
            .split(|c: char| c == ':' || c.is_whitespace())
            .filter(|p| !p.is_empty())
            .collect();
        if parts.is_empty() {
            return None;
        }

        let surah = match to_number(parts[0]) {
            Some(n) => Some(n),
            None => {
                let cleaned = clean_search(parts[0]);
                let cleaned_compact = cleaned.replace(' ', "");
                self.surahs
                    .iter()
                    .find(|x| {
                        x.blob.split(' ').any(|w| w == cleaned)
                            || x.compact.contains(&cleaned_compact)
                    })
                    .map(|x| x.id)
            }
        }?;

        let ayah = if parts.len() >= 2 { to_number(parts[1]) } else { None };
        Some(Reference { surah, ayah })
    }

    /// True if `query` resolves to a makkan/madani filter request (used by the Engine wrapper).
    pub(crate) fn revelation_filter(&self, query: &str) -> Option<&'static str> {
        let norm = clean_search(query.trim()).replace(' ', "");
        if norm.is_empty() {
            return None;
        }
        const MAKKAN: [&str; 3] = ["makkah", "makkan", "makki"];
        const MADINAN: [&str; 4] = ["madinah", "madinan", "madina", "madani"];
        let alias_hit = |aliases: &[&str]| {
            aliases.iter().any(|a| a.starts_with(&norm) || norm.starts_with(a))
        };
        if alias_hit(&MAKKAN) {
            Some("makkan")
        } else if alias_hit(&MADINAN) {
            Some("madinan")
        } else {
            None
        }
    }
}

/// Phrase-prefix match: query tokens match a consecutive run of haystack tokens, all-but-last
/// exact-equal, last is a prefix. Mirrors `phrasePrefixMatch`.
fn phrase_prefix_match(haystack: &[String], query: &[String]) -> bool {
    if query.is_empty() || haystack.len() < query.len() {
        return false;
    }
    let last = query.len() - 1;
    for start in 0..=(haystack.len() - query.len()) {
        let mut ok = true;
        for (k, term) in query.iter().enumerate() {
            let word = &haystack[start + k];
            if k == last {
                if !word.starts_with(term) {
                    ok = false;
                    break;
                }
            } else if word != term {
                ok = false;
                break;
            }
        }
        if ok {
            return true;
        }
    }
    false
}

fn to_number(s: &str) -> Option<u32> {
    let t = arabic_digits_to_western(s);
    let t = t.trim();
    if t.is_empty() {
        return None;
    }
    t.parse::<u32>().ok()
}
