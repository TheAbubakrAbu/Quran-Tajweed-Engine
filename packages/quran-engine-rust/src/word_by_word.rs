//! Word by word: what each word of an ayah means, and how it is said.
//!
//! Two layers over the SAME tokens — the English gloss and a Latin transliteration — where the
//! tokens are the ayah's own whitespace-separated words. Split the ayah and index straight in; the
//! alignment against a corpus that tokenizes ~200 ayahs differently was done once, at build time.
//!
//! A token with no word of its own (the ۞ ornament, the tail of a word the corpus writes as two)
//! carries `""` in both layers — show nothing for it rather than a neighbour's meaning.
//!
//! See `../../docs/12-word-by-word.md`.

use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Deserialize, Default)]
pub struct WordByWordPack {
    /// Surah id -> ayahs in id order -> one entry per token.
    pub english: HashMap<String, Vec<Vec<String>>>,
    pub transliteration: HashMap<String, Vec<Vec<String>>>,
}

/// One word of an ayah, in reading order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GlossedWord {
    /// 1-based index of the word in the ayah.
    pub position: u32,
    /// The ayah's own token.
    pub arabic: String,
    /// The gloss, `""` when the token has none.
    pub english: String,
    pub transliteration: String,
}

/// A hit from the word-level gloss search.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GlossHit {
    pub surah: u32,
    pub ayah: u32,
    pub position: u32,
    pub english: String,
    pub transliteration: String,
}

use crate::Engine;

impl Engine {
    /// Whether a word-by-word pack is loaded at all — cheap enough to gate UI on.
    pub fn word_by_word_loaded(&self) -> bool {
        !self.word_by_word.english.is_empty()
    }

    /// Every word of an ayah, in reading order.
    pub fn words(&self, surah: u32, ayah: u32) -> Vec<GlossedWord> {
        let Some(english) = self.glosses(surah, ayah) else {
            return Vec::new();
        };
        let latin = self.transliterations(surah, ayah).unwrap_or(&[]);
        let tokens: Vec<&str> = self
            .ayah(surah, ayah)
            .map(|a| a.text_arabic.split_whitespace().collect())
            .unwrap_or_default();
        english
            .iter()
            .enumerate()
            .map(|(i, gloss)| GlossedWord {
                position: i as u32 + 1,
                arabic: tokens.get(i).copied().unwrap_or("").to_string(),
                english: gloss.clone(),
                transliteration: latin.get(i).cloned().unwrap_or_default(),
            })
            .collect()
    }

    /// One word, by its 1-based position.
    pub fn word(&self, surah: u32, ayah: u32, position: u32) -> Option<GlossedWord> {
        let words = self.words(surah, ayah);
        if position == 0 {
            return None;
        }
        words.into_iter().nth(position as usize - 1)
    }

    pub fn glosses(&self, surah: u32, ayah: u32) -> Option<&[String]> {
        layer_row(&self.word_by_word.english, surah, ayah)
    }

    pub fn transliterations(&self, surah: u32, ayah: u32) -> Option<&[String]> {
        layer_row(&self.word_by_word.transliteration, surah, ayah)
    }

    /// Ayahs containing a word whose gloss carries `term` — a word-level English search, which
    /// finds ayahs a translation search misses because no translator used that phrasing.
    pub fn find_gloss(&self, term: &str, limit: usize) -> Vec<GlossHit> {
        let needle = term.trim().to_lowercase();
        if needle.is_empty() {
            return Vec::new();
        }
        let mut out = Vec::new();
        // Mushaf order, so the result is stable across runs (HashMap iteration is not).
        for surah in &self.surahs {
            let Some(rows) = self.word_by_word.english.get(&surah.id.to_string()) else {
                continue;
            };
            for (ayah_index, glosses) in rows.iter().enumerate() {
                for (index, gloss) in glosses.iter().enumerate() {
                    if !gloss.to_lowercase().contains(&needle) {
                        continue;
                    }
                    let latin = self
                        .word_by_word
                        .transliteration
                        .get(&surah.id.to_string())
                        .and_then(|rows| rows.get(ayah_index))
                        .and_then(|row| row.get(index))
                        .cloned()
                        .unwrap_or_default();
                    out.push(GlossHit {
                        surah: surah.id,
                        ayah: ayah_index as u32 + 1,
                        position: index as u32 + 1,
                        english: gloss.clone(),
                        transliteration: latin,
                    });
                    if out.len() >= limit {
                        return out;
                    }
                }
            }
        }
        out
    }
}

fn layer_row(layer: &HashMap<String, Vec<Vec<String>>>, surah: u32, ayah: u32) -> Option<&[String]> {
    let rows = layer.get(&surah.to_string())?;
    if ayah == 0 || ayah as usize > rows.len() {
        return None;
    }
    Some(rows[ayah as usize - 1].as_slice())
}
