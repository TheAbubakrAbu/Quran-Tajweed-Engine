//! Root and lemma of every word of the Quran: the Quranic Arabic Corpus morphology (Kais Dukes),
//! as redistributed by the Quranic Universal Library.
//!
//! The invariant, the same one `word-by-word.json` keeps: one id per whitespace token of the
//! ayah's raw Hafs text, in the text's own token order, so nothing here matches or normalizes
//! text. Id `0` means the token has neither a root nor a lemma, which is the honest answer for
//! particles and the sajdah mark. Ids are 1-based into the root and lemma tables.
//!
//! The reverse indexes are built on first use and cached behind a `OnceLock`.
//!
//! See `../../docs/18-morphology.md`.

use std::collections::HashMap;

use serde::Deserialize;

/// A triliteral (or quadriliteral) root, in both spellings a reader might use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Root {
    /// Spaced the way a lexicon prints it: `"ر ب ب"`.
    pub letters: String,
    /// The same letters transliterated: `"rbb"`.
    pub buckwalter: String,
    /// `letters` with the spaces closed up: `"ربب"`.
    pub joined: String,
}

/// A dictionary form, marked and unmarked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lemma {
    pub text: String,
    pub clean: String,
}

/// One word of the Quran: the ayah, and the 0-based index of the token inside it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct WordLocation {
    pub surah: u32,
    pub ayah: u32,
    pub token: usize,
}

/// `data/morphology.json`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MorphologyFile {
    /// `[letters spaced, buckwalter]`, 1-based by position.
    pub roots: Vec<Vec<String>>,
    /// `[dictionary form, unmarked form]`, 1-based by position.
    pub lemmas: Vec<Vec<String>>,
    /// surah -> ayah -> token -> root id.
    pub root_ids: HashMap<String, Vec<Vec<u32>>>,
    /// surah -> ayah -> token -> lemma id.
    pub lemma_ids: HashMap<String, Vec<Vec<u32>>>,
}

/// The reverse indexes, built once.
#[derive(Debug, Default)]
pub struct MorphologyIndex {
    pub by_root: HashMap<u32, Vec<WordLocation>>,
    pub by_lemma: HashMap<u32, Vec<WordLocation>>,
}

impl MorphologyIndex {
    /// Walk the whole corpus once, in mushaf order, so the lists come out ordered for free.
    pub fn build(file: &MorphologyFile) -> MorphologyIndex {
        let mut by_root: HashMap<u32, Vec<WordLocation>> = HashMap::new();
        let mut by_lemma: HashMap<u32, Vec<WordLocation>> = HashMap::new();
        let mut surahs: Vec<u32> = file.root_ids.keys().filter_map(|k| k.parse().ok()).collect();
        surahs.sort_unstable();
        for surah in surahs {
            let key = surah.to_string();
            let roots = match file.root_ids.get(&key) {
                Some(rows) => rows,
                None => continue,
            };
            let empty = Vec::new();
            let lemmas = file.lemma_ids.get(&key).unwrap_or(&empty);
            for (a, root_row) in roots.iter().enumerate() {
                let lemma_row = lemmas.get(a);
                for (t, &root_id) in root_row.iter().enumerate() {
                    let location = WordLocation { surah, ayah: a as u32 + 1, token: t };
                    if root_id != 0 {
                        by_root.entry(root_id).or_default().push(location);
                    }
                    if let Some(&lemma_id) = lemma_row.and_then(|row| row.get(t)) {
                        if lemma_id != 0 {
                            by_lemma.entry(lemma_id).or_default().push(location);
                        }
                    }
                }
            }
        }
        MorphologyIndex { by_root, by_lemma }
    }
}

/// The fold a typed query and the tables are both compared under.
///
/// Every space is removed, not merely trimmed: a root is printed spaced (`"ر ب ب"`) and typed
/// closed up (`"ربب"`), and the two have to meet.
pub fn fold_for_morphology(text: &str) -> String {
    crate::text::clean_search(&crate::text::removing_arabic_diacritics_and_signs(text))
        .split_whitespace()
        .collect()
}

/// A root paired with its id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RootHit {
    pub id: u32,
    pub root: Root,
}

/// A dictionary form paired with its id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LemmaHit {
    pub id: u32,
    pub lemma: Lemma,
}

pub(crate) fn root_at(file: &MorphologyFile, id: u32) -> Option<Root> {
    let row = file.roots.get(id.checked_sub(1)? as usize)?;
    Some(Root {
        letters: row[0].clone(),
        buckwalter: row.get(1).cloned().unwrap_or_default(),
        joined: row[0].replace(' ', ""),
    })
}

pub(crate) fn lemma_at(file: &MorphologyFile, id: u32) -> Option<Lemma> {
    let row = file.lemmas.get(id.checked_sub(1)? as usize)?;
    Some(Lemma { text: row[0].clone(), clean: row.get(1).cloned().unwrap_or_default() })
}

/// Prefix scan shared by the root and lemma searches: Arabic folded, Latin lowercased.
pub(crate) fn prefix_hits(table: &[Vec<String>], query: &str, limit: usize) -> Vec<usize> {
    let folded = fold_for_morphology(query);
    let latin = query.trim().to_lowercase();
    if folded.is_empty() && latin.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for (i, row) in table.iter().enumerate() {
        if limit > 0 && out.len() >= limit {
            break;
        }
        let arabic = fold_for_morphology(&row[0]);
        let roman = row.get(1).map(|s| s.to_lowercase()).unwrap_or_default();
        if (!folded.is_empty() && arabic.starts_with(&folded))
            || (!latin.is_empty() && roman.starts_with(&latin))
        {
            out.push(i + 1);
        }
    }
    out
}
