//! Three curated corpora that answer questions the text alone cannot: where else the Quran says
//! this, what it says about a topic, and how to learn to recite it.
//!
//! See `../../docs/13-similar-and-themes.md`.

use serde::Deserialize;

/// One row of `data/similar-ayahs.json`: `[surah, ayah, phrase, verifiedFlag, labels?]`.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum SimilarField {
    Number(u32),
    Text(String),
    Labels(Vec<String>),
}

/// One similar-ayah match, in display order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SimilarMatch {
    pub surah: u32,
    pub ayah: u32,
    /// The shared wording, `""` when none is recorded.
    pub phrase: String,
    /// True for the classical corpus, false for a generated phrase-overlap match.
    pub verified: bool,
    /// Why a generated row matched; empty for verified rows.
    pub labels: Vec<String>,
}

/// One curated topic and the ayahs that speak to it.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Topic {
    pub id: String,
    pub name: String,
    pub description: String,
    pub category: String,
    pub domain: String,
    /// `"2:255"` references, in mushaf order.
    pub ayahs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct ThemesFile {
    pub topics: Vec<Topic>,
}

/// One practice fragment: a short Arabic snippet with a caption saying what to listen for.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct TajweedDrill {
    pub caption: String,
    pub text: String,
}

/// An ayah to hear the rule in, with the phrase to focus on.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TajweedExample {
    pub surah_id: u32,
    pub ayah_number: u32,
    pub focus: String,
}

/// The card that shows the rule as it appears in the mushaf.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TajweedMushafCard {
    pub fragments: Vec<TajweedDrill>,
    #[serde(default)]
    pub count_en: Option<String>,
    #[serde(default)]
    pub count_ar: Option<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TajweedLesson {
    pub id: String,
    #[serde(default)]
    pub title_en: String,
    #[serde(default)]
    pub title_ar: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub body: Vec<String>,
    /// Absent on the lessons that teach through examples alone.
    #[serde(default)]
    pub drills: Vec<TajweedDrill>,
    #[serde(default)]
    pub examples: Vec<TajweedExample>,
    #[serde(default)]
    pub mushaf_card: Option<TajweedMushafCard>,
    /// The tajweed colour this rule is painted in, where it has one.
    #[serde(default)]
    pub color: Option<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct TajweedChapter {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub lessons: Vec<TajweedLesson>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct TajweedLessonsFile {
    pub chapters: Vec<TajweedChapter>,
}

use crate::Engine;

impl Engine {
    // ---- Similar ayahs -------------------------------------------------------------

    /// Matches for an ayah, in display order. Empty for most short ayahs.
    pub fn similar_ayahs(&self, surah: u32, ayah: u32) -> Vec<SimilarMatch> {
        let Some(rows) = self.similar_ayahs.get(&format!("{surah}:{ayah}")) else {
            return Vec::new();
        };
        rows.iter()
            .filter_map(|row| {
                if row.len() < 4 {
                    return None;
                }
                let (SimilarField::Number(surah), SimilarField::Number(ayah)) = (&row[0], &row[1])
                else {
                    return None;
                };
                let verified = matches!(&row[3], SimilarField::Number(1));
                Some(SimilarMatch {
                    surah: *surah,
                    ayah: *ayah,
                    phrase: match &row[2] {
                        SimilarField::Text(text) => text.clone(),
                        _ => String::new(),
                    },
                    verified,
                    labels: match row.get(4) {
                        Some(SimilarField::Labels(labels)) => labels.clone(),
                        _ => Vec::new(),
                    },
                })
            })
            .collect()
    }

    /// Whether the ayah has any — a map hit, cheap enough to gate a button on.
    pub fn has_similar_ayahs(&self, surah: u32, ayah: u32) -> bool {
        self.similar_ayahs
            .get(&format!("{surah}:{ayah}"))
            .map(|rows| !rows.is_empty())
            .unwrap_or(false)
    }

    /// How many ayahs have at least one match.
    pub fn similar_ayah_count(&self) -> usize {
        self.similar_ayahs.len()
    }

    // ---- Themes --------------------------------------------------------------------

    /// Every topic, in the order the corpus lists them.
    pub fn topics(&self) -> &[Topic] {
        &self.topics
    }

    pub fn topic(&self, id: &str) -> Option<&Topic> {
        self.topics.iter().find(|t| t.id == id)
    }

    /// The distinct domains, in first-seen order.
    pub fn topic_domains(&self) -> Vec<&str> {
        ordered_unique(self.topics.iter().map(|t| t.domain.as_str()))
    }

    /// The distinct categories, optionally within one domain.
    pub fn topic_categories(&self, domain: Option<&str>) -> Vec<&str> {
        ordered_unique(
            self.topics
                .iter()
                .filter(|t| domain.is_none_or(|d| t.domain == d))
                .map(|t| t.category.as_str()),
        )
    }

    pub fn topics_in_domain(&self, domain: &str) -> Vec<&Topic> {
        self.topics.iter().filter(|t| t.domain == domain).collect()
    }

    pub fn topics_in_category(&self, category: &str) -> Vec<&Topic> {
        self.topics.iter().filter(|t| t.category == category).collect()
    }

    /// The topics an ayah appears under.
    pub fn topics_for(&self, surah: u32, ayah: u32) -> Vec<&Topic> {
        let reference = format!("{surah}:{ayah}");
        self.topics.iter().filter(|t| t.ayahs.iter().any(|a| *a == reference)).collect()
    }

    /// Topics whose name, description, category or domain carries `query`.
    pub fn search_topics(&self, query: &str) -> Vec<&Topic> {
        let needle = query.trim().to_lowercase();
        if needle.is_empty() {
            return Vec::new();
        }
        self.topics
            .iter()
            .filter(|t| {
                [&t.name, &t.description, &t.category, &t.domain]
                    .iter()
                    .any(|field| field.to_lowercase().contains(&needle))
            })
            .collect()
    }

    // ---- The tajweed course ---------------------------------------------------------

    /// Every chapter, in course order.
    pub fn tajweed_chapters(&self) -> &[TajweedChapter] {
        &self.tajweed_chapters
    }

    pub fn tajweed_chapter(&self, id: &str) -> Option<&TajweedChapter> {
        self.tajweed_chapters.iter().find(|c| c.id == id)
    }

    /// Every lesson across every chapter, in course order.
    pub fn tajweed_lessons(&self) -> Vec<&TajweedLesson> {
        self.tajweed_chapters.iter().flat_map(|c| c.lessons.iter()).collect()
    }

    pub fn tajweed_lesson(&self, id: &str) -> Option<&TajweedLesson> {
        self.tajweed_lessons().into_iter().find(|l| l.id == id)
    }

    /// Which chapter a lesson belongs to.
    pub fn tajweed_chapter_of(&self, id: &str) -> Option<&TajweedChapter> {
        self.tajweed_chapters.iter().find(|c| c.lessons.iter().any(|l| l.id == id))
    }

    /// The lesson after this one, walking across chapter boundaries.
    pub fn next_tajweed_lesson(&self, id: &str) -> Option<&TajweedLesson> {
        let lessons = self.tajweed_lessons();
        let at = lessons.iter().position(|l| l.id == id)?;
        lessons.get(at + 1).copied()
    }

    pub fn previous_tajweed_lesson(&self, id: &str) -> Option<&TajweedLesson> {
        let lessons = self.tajweed_lessons();
        let at = lessons.iter().position(|l| l.id == id)?;
        if at == 0 {
            return None;
        }
        lessons.get(at - 1).copied()
    }
}

fn ordered_unique<'a>(values: impl Iterator<Item = &'a str>) -> Vec<&'a str> {
    let mut seen = std::collections::HashSet::new();
    values.filter(|value| seen.insert(*value)).collect()
}
