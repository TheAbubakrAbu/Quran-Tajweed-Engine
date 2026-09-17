//! Meaning-based ("AI") search: find the ayahs about a topic whether or not they use its words.
//!
//! # Why word vectors and MaxSim, not a sentence embedding
//!
//! Measured, not assumed. Scoring an ayah by the cosine between a SENTENCE embedding of the query
//! and one of the ayah ranks this corpus close to randomly: translated scripture is dense, and one
//! vector for a whole verse washes out the single idea the query is asking about. Scoring word by
//! word fixes it, embed every word, and score a text as the MEAN over the query's words of the
//! BEST matching word in the text. On real verses that separates related (0.42–0.70) from
//! unrelated (0.27–0.41) cleanly, and it degrades gracefully: a query word the model has never seen
//! contributes nothing instead of poisoning the vector.
//!
//! # The embedder is yours
//!
//! This engine ships no model, word vectors are tens of megabytes and every platform already has
//! one worth using. Hand [`Semantic::new`] a closure from a lowercased word to its vector.
//!
//! ```
//! use quran_engine::semantic::Semantic;
//! let mut semantic = Semantic::new(|word| match word {
//!     "patience" => Some(vec![1.0, 0.0, 0.0]),
//!     "sabr" => Some(vec![0.95, 0.05, 0.0]),
//!     "dawn" => Some(vec![0.0, 1.0, 0.0]),
//!     _ => None,
//! });
//! semantic.index(vec![("sabr".to_string(), "sabr endurance".to_string()),
//!                     ("fajr".to_string(), "at dawn".to_string())]);
//! assert_eq!(semantic.search("patience", 1, 0.0)[0].id, "sabr");
//! ```
//!
//! See `../../docs/14-ask-ai.md`.

use std::collections::{HashMap, HashSet};

/// One scored document.
#[derive(Debug, Clone, PartialEq)]
pub struct SemanticHit {
    pub id: String,
    /// Mean best-match cosine over the query's words, 0..=1.
    pub score: f32,
}

/// A word-vector MaxSim index over any corpus.
pub struct Semantic {
    embed: Box<dyn Fn(&str) -> Option<Vec<f32>>>,
    min_word_length: usize,
    vectors: HashMap<String, Option<Vec<f32>>>,
    documents: Vec<(String, Vec<Vec<f32>>)>,
}

impl Semantic {
    /// A new index. `embed` maps a lowercased word to its vector, or `None` when it has none.
    pub fn new(embed: impl Fn(&str) -> Option<Vec<f32>> + 'static) -> Self {
        Semantic {
            embed: Box::new(embed),
            min_word_length: 3,
            vectors: HashMap::new(),
            documents: Vec::new(),
        }
    }

    /// Words shorter than this are skipped on both sides. Default 3.
    pub fn with_min_word_length(mut self, length: usize) -> Self {
        self.min_word_length = length;
        self
    }

    /// How many documents are indexed.
    pub fn len(&self) -> usize {
        self.documents.len()
    }

    pub fn is_empty(&self) -> bool {
        self.documents.is_empty()
    }

    /// Build (or rebuild) the index from `(id, text)` pairs. Call once per corpus.
    pub fn index(&mut self, corpus: Vec<(String, String)>) -> &mut Self {
        self.documents.clear();
        for (id, text) in corpus {
            let vectors = self.vectorize(&text);
            if !vectors.is_empty() {
                self.documents.push((id, vectors));
            }
        }
        self
    }

    /// The documents closest in meaning to `query`, best first. `min_score` is a floor on "actually
    /// related": 0.42 is a sensible start on English translations, but calibrate it against YOUR
    /// embedder.
    pub fn search(&mut self, query: &str, limit: usize, min_score: f32) -> Vec<SemanticHit> {
        let query_vectors = self.vectorize(query);
        if query_vectors.is_empty() {
            return Vec::new();
        }

        let mut hits: Vec<SemanticHit> = Vec::new();
        for (id, vectors) in &self.documents {
            let mut total = 0.0f32;
            for q in &query_vectors {
                let mut best = -1.0f32;
                for w in vectors {
                    let score = cosine(q, w);
                    if score > best {
                        best = score;
                    }
                }
                total += best;
            }
            let score = total / query_vectors.len() as f32;
            if score >= min_score {
                hits.push(SemanticHit { id: id.clone(), score });
            }
        }
        hits.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.id.cmp(&b.id))
        });
        hits.truncate(limit);
        hits
    }

    /// Drop the index and the vector cache.
    pub fn clear(&mut self) {
        self.documents.clear();
        self.vectors.clear();
    }

    fn vectorize(&mut self, text: &str) -> Vec<Vec<f32>> {
        let mut out = Vec::new();
        let mut seen = HashSet::new();
        let lowered = text.to_lowercase();
        for raw in lowered.split(|c: char| !c.is_alphanumeric()) {
            if raw.chars().count() < self.min_word_length || !seen.insert(raw.to_string()) {
                continue;
            }
            if let Some(vector) = self.vector(raw) {
                out.push(vector);
            }
        }
        out
    }

    fn vector(&mut self, word: &str) -> Option<Vec<f32>> {
        if let Some(cached) = self.vectors.get(word) {
            return cached.clone();
        }
        // Normalized once here, so scoring is a dot product rather than three passes per pair.
        let normalized = (self.embed)(word).filter(|v| !v.is_empty()).map(|v| normalize(&v));
        self.vectors.insert(word.to_string(), normalized.clone());
        normalized
    }
}

/// Cosine similarity of two ALREADY NORMALIZED vectors, i.e. their dot product.
pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
}

fn normalize(raw: &[f32]) -> Vec<f32> {
    let magnitude = raw.iter().map(|x| x * x).sum::<f32>().sqrt();
    if magnitude == 0.0 {
        return vec![0.0; raw.len()];
    }
    raw.iter().map(|x| x / magnitude).collect()
}
