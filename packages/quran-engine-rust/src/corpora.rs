//! Three curated corpora that answer questions the text alone cannot: where else the Quran says
//! this, what it says about a topic, and how to learn to recite it.
//!
//! See `../../docs/13-similar-and-themes.md`.

use serde::Deserialize;
use std::collections::HashMap;

/// One row of `data/similar-ayahs.json` (version 2) as the file stores it: exactly six fields,
/// `[surah, ayah, verifiedFlag, spans, labels, score]`. `SimilarMatch` decodes straight from it.
pub type SimilarRow = (u32, u32, u32, Vec<[usize; 2]>, Vec<String>, Option<u32>);

/// One similar-ayah match, in display order.
///
/// Decoded by position from the six-field row, so an empty `[]` at the spans slot is an empty
/// span list and an empty `[]` at the labels slot is an empty label list: nothing has to guess
/// which of the two an empty array was. A row of any other length, or a field of the wrong type,
/// fails the load rather than reading half a row.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(from = "SimilarRow")]
pub struct SimilarMatch {
    pub surah: u32,
    pub ayah: u32,
    /// True for the classical corpus, false for a generated phrase-overlap match.
    pub verified: bool,
    /// Why a generated row matched; empty for verified rows.
    pub labels: Vec<String>,
    /// The shared wording: 0-based inclusive token ranges into the MATCHED ayah's raw text.
    /// QUL's own placement where it lists the pair, else the wording the corpus recorded,
    /// located in the ayah when the data was built. Empty when no source records shared wording.
    ///
    /// The data carries no text of its own (version 2): cut the words out of `quran.json` by the
    /// span (split the matched ayah's raw text on spaces and take tokens `start..=end`), so what
    /// you show is the Quran text you already have and not a second copy of it.
    pub spans: Vec<[usize; 2]>,
    /// QUL's 0-100 similarity score, where it listed the pair. `None` for the rows that come
    /// from the other two sources: they rank, but they do not score.
    pub score: Option<u32>,
}

impl From<SimilarRow> for SimilarMatch {
    fn from((surah, ayah, verified, spans, labels, score): SimilarRow) -> Self {
        SimilarMatch { surah, ayah, verified: verified == 1, labels, spans, score }
    }
}

/// `data/similar-ayahs.json` as the file stores it: `{"v": 2, "ayahs": {"2:255": [row, ...]}}`.
///
/// Both fields default so that a version-1 file (rows keyed at the top level, the phrase as
/// text, no `v`) parses as version 0 with no `ayahs`, and `into_ayahs` then yields nothing.
#[derive(Debug, Clone, Deserialize, Default)]
pub struct SimilarAyahsFile {
    #[serde(default)]
    pub v: u32,
    #[serde(default)]
    pub ayahs: HashMap<String, Vec<SimilarMatch>>,
}

impl SimilarAyahsFile {
    /// The data version this crate reads.
    pub const VERSION: u32 = 2;

    /// The rows keyed `"surah:ayah"`, or nothing when the file is not version 2. A version-1
    /// file is not read: it would put the shared wording where a span is expected. Treated as no
    /// data rather than half a one, as the JS port does.
    pub fn into_ayahs(self) -> HashMap<String, Vec<SimilarMatch>> {
        if self.v == Self::VERSION {
            self.ayahs
        } else {
            HashMap::new()
        }
    }
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
///
/// The Arabic is in exactly one of two places. Teaching Arabic a tutor wrote - invented drill
/// syllables, single letters, the isti'adhah - is `text`. Arabic that IS Quran is `ayah`, a
/// reference into this engine's own text, and then `text` is empty: version 4 stopped copying
/// verses into the lesson pack for the same reason nothing else here copies them.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct TajweedDrill {
    pub caption: String,
    /// The fragment as written, or empty when `ayah` locates it instead.
    #[serde(default)]
    pub text: String,
    /// `[surah, ayah, first, last]`: a 0-based inclusive token range into the ayah's raw text.
    /// Cut the words out of `quran.json` by it; the pack carries no copy of them.
    #[serde(default)]
    pub ayah: Option<[usize; 4]>,
}

/// An ayah to hear the rule in: `focus` says what to listen for, `word_span` says where.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TajweedExample {
    pub surah_id: u32,
    pub ayah_number: u32,
    pub focus: String,
    /// The 0-based inclusive token range of the words to listen at, into the ayah's raw text.
    /// The data carries no copy of the words (version 3): read them out of `quran.json` by this
    /// span. `None` when the lesson names the whole ayah.
    #[serde(default)]
    pub word_span: Option<[usize; 2]>,
}

/// The memory-hook word a rule card hangs on, with what it means. Teaching Arabic chosen for the
/// rule it demonstrates, so it is written out rather than referenced.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct TajweedMnemonic {
    pub arabic: String,
    #[serde(default)]
    pub gloss: String,
}

/// The card that states the rule: when it triggers, what to do, how long to hold it, and
/// fragments to see it in.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TajweedRuleCard {
    #[serde(default)]
    pub fragments: Vec<TajweedDrill>,
    #[serde(default)]
    pub trigger: Option<String>,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub hold: Option<String>,
    #[serde(default)]
    pub mnemonic: Option<TajweedMnemonic>,
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
    pub rule_card: Option<TajweedRuleCard>,
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
        self.similar_ayahs.get(&format!("{surah}:{ayah}")).cloned().unwrap_or_default()
    }

    /// Whether the ayah has any: a map hit, cheap enough to gate a button on.
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
