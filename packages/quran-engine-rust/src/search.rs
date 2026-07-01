//! Ayah & surah search. Faithful port of `src/search.js` — matches its behaviour byte-for-byte.
//!
//! ## What is implemented
//! - `search_verses`: unranked verse-text search in mushaf order. The regular (non-boolean) path is
//!   a **pure substring** match on the relevant (Arabic or English) folded blob, with an optional
//!   lenient "silent letters ignored" Arabic variant. Verse search rejects any query containing a
//!   Unicode decimal digit BEFORE branching into the boolean path.
//! - `_boolean_search`: the boolean grammar (`& | ! # ^ % $ =`) with per-term whole-word /
//!   starts-with / ends-with / exact / contains matching, plus tashkeel-sensitive Arabic and
//!   exact-phrase English matching.
//! - `search_surahs`: name / alias / number / `"2:255"` / makkan-madani lookup.
//! - `parse_reference`: `"2:255"`, `"2 255"`, `"baqarah 10"`, Arabic-digit forms.

use crate::model::Surah;
use crate::text::{
    arabic_digits_to_western, arabic_tashkeel_blob, clean_search, contains_arabic_letters,
    exact_phrase_blob, removing_arabic_diacritics_and_signs,
    removing_silent_arabic_letters_for_search, search_tokens,
};

/// Boolean-search operators that trigger the boolean grammar. Mirrors `BOOLEAN_CHARS`.
fn has_boolean_char(query: &str) -> bool {
    query
        .chars()
        .any(|c| matches!(c, '&' | '|' | '!' | '#' | '^' | '%' | '$' | '='))
}

/// Per-term match mode. Mirrors the JS `matchMode` string union.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MatchMode {
    Contains,
    StartsWith,
    EndsWith,
    Exact,
    WholeWord,
}

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
    pub ignore_silent_letters: bool,
}

struct VerseEntry {
    surah: u32,
    ayah: u32,
    arabic_tashkeel_blob: String,
    english_exact_blob: String,
    arabic_blob: String,
    silent_arabic_blob: String,
    english_blob: String,
    arabic_tokens: Vec<String>,
    english_tokens: Vec<String>,
}

/// A parsed boolean search term. Mirrors the object returned by `parseTerm`.
struct Term {
    value: String,
    negate: bool,
    match_mode: MatchMode,
    requires_tashkeel_match: bool,
    tashkeel_pattern: String,
    requires_exact_english_match: bool,
    exact_english_phrase: String,
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
                let silent_arabic_blob = format!(
                    "{} {}",
                    clean_search(&removing_silent_arabic_letters_for_search(raw)),
                    clean_search(&removing_silent_arabic_letters_for_search(&clean)),
                );
                let english_joined = format!(
                    "{} {} {}",
                    a.text_english_saheeh, a.text_english_mustafa, a.text_transliteration
                );
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
                    arabic_tashkeel_blob: arabic_tashkeel_blob(raw),
                    english_exact_blob: exact_phrase_blob(&english_joined),
                    arabic_blob,
                    silent_arabic_blob,
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
        // Reject any query containing a Unicode decimal digit (numeric/refs go via surah search).
        // Done BEFORE the boolean path — so even a boolean query with a digit returns []. Uses a
        // Unicode-aware check so Arabic-Indic digits are caught too.
        if cleaned.chars().any(|c| c.is_numeric()) {
            return Vec::new();
        }

        // Boolean grammar?
        if has_boolean_char(query) {
            return self.boolean_search(query, opts);
        }

        let use_arabic = contains_arabic_letters(query);
        let silent_query = if use_arabic && opts.ignore_silent_letters {
            clean_search(&removing_silent_arabic_letters_for_search(query))
        } else {
            String::new()
        };

        // Pure substring search in mushaf order — word/sentence boundaries DON'T matter (a query
        // matches anywhere it appears). Whole-word / phrase matching lives in the boolean operators.
        let hits = self.verses.iter().filter(|e| {
            if use_arabic {
                if e.arabic_blob.contains(&cleaned) {
                    return true;
                }
                if silent_query.is_empty() {
                    return false;
                }
                e.silent_arabic_blob.contains(&silent_query)
            } else {
                e.english_blob.contains(&cleaned)
            }
        });

        Self::paginate(hits, opts)
    }

    // ---- Boolean search -----------------------------------------------------
    fn boolean_search(&self, query: &str, opts: &SearchOpts) -> Vec<VerseHit> {
        let use_arabic = contains_arabic_letters(query);
        let normalized = query.replace("&&", "&").replace("||", "|");
        // Drop any term whose cleaned value is empty — `parseTerm` yields nil there.
        let or_groups: Vec<Vec<Term>> = normalized
            .split('|')
            .map(|g| {
                g.split('&')
                    .map(parse_term)
                    .filter(|t| !t.value.is_empty())
                    .collect::<Vec<Term>>()
            })
            .filter(|g| !g.is_empty())
            .collect();
        if or_groups.is_empty() {
            return Vec::new();
        }

        let hits = self.verses.iter().filter(|e| {
            or_groups.iter().any(|and_terms| {
                and_terms.iter().all(|term| {
                    let hit = term_match(e, term, use_arabic);
                    if term.negate {
                        !hit
                    } else {
                        hit
                    }
                })
            })
        });

        Self::paginate(hits, opts)
    }

    fn paginate<'a>(
        hits: impl Iterator<Item = &'a VerseEntry>,
        opts: &SearchOpts,
    ) -> Vec<VerseHit> {
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

/// Consecutive-token match: query tokens appear as a consecutive run of haystack tokens. Leading
/// tokens match exactly; the final token must match exactly when `last_must_be_exact`, otherwise it
/// only has to be a prefix. Mirrors `consecutiveTokenMatch`.
fn consecutive_token_match(haystack: &[String], query: &[String], last_must_be_exact: bool) -> bool {
    if query.is_empty() || haystack.len() < query.len() {
        return false;
    }
    let last = query.len() - 1;
    for start in 0..=(haystack.len() - query.len()) {
        let mut ok = true;
        for (k, term) in query.iter().enumerate() {
            let word = &haystack[start + k];
            if k == last && !last_must_be_exact {
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

/// Parse a single boolean term. Mirrors `parseTerm`: strips (in order) leading `!` (negate,
/// toggles), `#` (requires-tashkeel), `=` (whole-word), one `^` (starts-with), one trailing `%`/`$`
/// (ends-with); the leftover text becomes the value + the tashkeel/exact-phrase patterns.
fn parse_term(raw_term: &str) -> Term {
    let mut t = raw_term.trim().to_string();
    let mut negate = false;
    while t.starts_with('!') {
        negate = !negate;
        t = t[1..].trim().to_string();
    }
    let mut requires_tashkeel = false;
    while t.starts_with('#') {
        requires_tashkeel = true;
        t = t[1..].trim().to_string();
    }
    let mut whole_word = false;
    while t.starts_with('=') {
        whole_word = true;
        t = t[1..].trim().to_string();
    }
    let mut starts_with = false;
    if t.starts_with('^') {
        starts_with = true;
        t = t[1..].trim().to_string();
    }
    let mut ends_with = false;
    if t.ends_with('%') || t.ends_with('$') {
        ends_with = true;
        t = t[..t.len() - 1].trim().to_string();
    }

    let value = clean_search(&t);
    let match_mode = if whole_word {
        MatchMode::WholeWord
    } else if starts_with && ends_with {
        MatchMode::Exact
    } else if starts_with {
        MatchMode::StartsWith
    } else if ends_with {
        MatchMode::EndsWith
    } else {
        MatchMode::Contains
    };

    let is_arabic = contains_arabic_letters(&t);
    Term {
        value,
        negate,
        match_mode,
        requires_tashkeel_match: requires_tashkeel && is_arabic,
        tashkeel_pattern: arabic_tashkeel_blob(&t),
        requires_exact_english_match: requires_tashkeel && !is_arabic,
        exact_english_phrase: exact_phrase_blob(&t),
    }
}

/// Match a single term's value against a blob/token list under one of the five modes. Mirrors
/// `ayahTermMatch`.
fn ayah_term_match(haystack: &str, tokens: &[String], term: &str, mode: MatchMode) -> bool {
    match mode {
        MatchMode::StartsWith => {
            haystack.starts_with(term) || tokens.iter().any(|w| w.starts_with(term))
        }
        MatchMode::EndsWith => {
            haystack.ends_with(term) || tokens.iter().any(|w| w.ends_with(term))
        }
        MatchMode::Exact => haystack == term || tokens.iter().any(|w| w == term),
        MatchMode::WholeWord => {
            consecutive_token_match(tokens, &search_tokens(term), true)
        }
        MatchMode::Contains => haystack.contains(term),
    }
}

/// Per-term match (un-negated). Mirrors `termMatch`.
fn term_match(e: &VerseEntry, term: &Term, use_arabic: bool) -> bool {
    if use_arabic && term.requires_tashkeel_match {
        let letters_match =
            ayah_term_match(&e.arabic_blob, &e.arabic_tokens, &term.value, term.match_mode);
        let tashkeel_match = term.tashkeel_pattern.is_empty()
            || e.arabic_tashkeel_blob.contains(&term.tashkeel_pattern);
        return letters_match && tashkeel_match;
    }
    if !use_arabic && term.requires_exact_english_match {
        let exact_tokens = search_tokens(&term.exact_english_phrase);
        return !term.exact_english_phrase.is_empty()
            && ayah_term_match(
                &e.english_exact_blob,
                &exact_tokens,
                &term.exact_english_phrase,
                term.match_mode,
            );
    }
    let (haystack, tokens) = if use_arabic {
        (&e.arabic_blob, &e.arabic_tokens)
    } else {
        (&e.english_blob, &e.english_tokens)
    };
    ayah_term_match(haystack, tokens, &term.value, term.match_mode)
}

fn to_number(s: &str) -> Option<u32> {
    let t = arabic_digits_to_western(s);
    let t = t.trim();
    if t.is_empty() {
        return None;
    }
    t.parse::<u32>().ok()
}
