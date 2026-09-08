//! The corpora added upstream in Al-Islam 4.6.4: the repeated phrases, the QUL topic indexes, the
//! hizb/ruku/manzil divisions, the qiraat variant matrix and the word of the day. Morphology has
//! its own module.
//!
//! See `../../docs/19-mutashabihat.md`, `20-topics-and-metadata.md`, `21-qiraat-variants.md` and
//! `22-word-of-day.md`.

use std::collections::HashMap;

use serde::Deserialize;

// ---- mutashabihat ----------------------------------------------------------------

/// One repeated phrase as the file stores it.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PhraseRow {
    pub source: String,
    pub span: [usize; 2],
    pub count: u32,
    pub ayah_count: u32,
    pub surah_count: u32,
    #[serde(default)]
    pub occurrences: HashMap<String, Vec<[usize; 2]>>,
}

/// One repeated phrase and every place it occurs.
///
/// A different thing from a similar ayah: that is a whole-ayah match, this is the exact run of
/// words two ayahs share, which is the memoriser's question.
#[derive(Debug, Clone)]
pub struct Phrase {
    pub id: u32,
    /// The ayah the phrase is defined from.
    pub source: String,
    /// Inclusive 0-based token range inside `source`.
    pub span: [usize; 2],
    pub count: u32,
    pub ayah_count: u32,
    pub surah_count: u32,
    /// Ayah key -> the spans carrying the phrase in that ayah.
    pub occurrences: HashMap<String, Vec<[usize; 2]>>,
    /// How long the phrase is, in words.
    pub word_count: usize,
}

/// `data/mutashabihat.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct MutashabihatFile {
    #[serde(default)]
    pub phrases: HashMap<String, PhraseRow>,
    #[serde(default)]
    pub index: HashMap<String, Vec<u32>>,
}

/// One place a phrase occurs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PhraseOccurrence {
    pub surah: u32,
    pub ayah: u32,
    pub key: String,
    pub spans: Vec<[usize; 2]>,
}

// ---- QUL topics ------------------------------------------------------------------

/// One of the three QUL indexes.
///
/// They are three trees over ONE pool of topics, not three partitions of it: a topic can be a
/// node in more than one (17 are), and a tree's parent need not itself be listed in that tree.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TopicTree {
    Thematic,
    Ontology,
    Index,
}

impl TopicTree {
    /// The three indexes, in the order the corpus presents them.
    pub const ALL: [TopicTree; 3] = [TopicTree::Thematic, TopicTree::Ontology, TopicTree::Index];

    pub fn as_str(self) -> &'static str {
        match self {
            TopicTree::Thematic => "thematic",
            TopicTree::Ontology => "ontology",
            TopicTree::Index => "index",
        }
    }
}

/// One topic of the Quranic Universal Library's indexes.
#[derive(Debug, Clone, Deserialize)]
pub struct QulTopic {
    pub id: u32,
    pub name: String,
    #[serde(default)]
    pub arabic: String,
    /// The indexes listing this topic; 17 topics are listed in two.
    #[serde(default)]
    pub families: Vec<TopicTree>,
    /// One parent per tree, independently. `None` where the topic is not in that tree, or is one
    /// of its roots.
    #[serde(default)]
    pub parents: HashMap<TopicTree, Option<u32>>,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub wiki: String,
    /// `"2:255"` references, in the corpus's order.
    #[serde(default)]
    pub ayahs: Vec<String>,
    #[serde(default)]
    pub related: Vec<u32>,
}

impl QulTopic {
    /// The parent in one tree, if any.
    pub fn parent_in(&self, tree: TopicTree) -> Option<u32> {
        self.parents.get(&tree).copied().flatten()
    }

    /// Whether this index lists the topic.
    pub fn listed_in(&self, tree: TopicTree) -> bool {
        self.families.contains(&tree)
    }

    /// The tree to use when a caller does not name one: the first index listing the topic.
    pub fn default_tree(&self) -> Option<TopicTree> {
        self.families.first().copied()
    }
}

/// `data/quran-topics.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct QulTopicsFile {
    #[serde(default)]
    pub topics: Vec<QulTopic>,
}

/// The child lists and the ayah index, built once.
#[derive(Debug, Default)]
pub struct QulTopicIndex {
    pub by_id: HashMap<u32, usize>,
    pub children: HashMap<(TopicTree, u32), Vec<u32>>,
    pub by_ayah: HashMap<String, Vec<u32>>,
}

impl QulTopicIndex {
    pub fn build(topics: &[QulTopic]) -> QulTopicIndex {
        let mut by_id = HashMap::new();
        let mut children: HashMap<(TopicTree, u32), Vec<u32>> = HashMap::new();
        let mut by_ayah: HashMap<String, Vec<u32>> = HashMap::new();
        for (position, topic) in topics.iter().enumerate() {
            by_id.insert(topic.id, position);
            for tree in TopicTree::ALL {
                if let Some(parent) = topic.parent_in(tree) {
                    children.entry((tree, parent)).or_default().push(topic.id);
                }
            }
            for key in &topic.ayahs {
                by_ayah.entry(key.clone()).or_default().push(topic.id);
            }
        }
        for bucket in children.values_mut() {
            bucket.sort_unstable();
        }
        QulTopicIndex { by_id, children, by_ayah }
    }
}

// ---- passage themes --------------------------------------------------------------

/// One short sentence describing a run of ayahs.
///
/// Passages run in order through a surah and do not nest. They do not tile it either: an ayah
/// between two passages has none.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct ThemePassage {
    pub from: u32,
    pub to: u32,
    pub theme: String,
    #[serde(default)]
    pub topic: String,
}

// ---- hizb / ruku / manzil --------------------------------------------------------

/// `data/quran-metadata.json`: the start key of every division, in order.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct QuranMetadataFile {
    #[serde(default)]
    pub hizb: Vec<String>,
    #[serde(default)]
    pub ruku: Vec<String>,
    #[serde(default)]
    pub manzil: Vec<String>,
}

/// Which of the three schedule divisions.
///
/// 60 hizb (the juz halved, the unit a memorisation plan is written in), 558 ruku (thematic
/// sections printed in the margin of South Asian mushafs), 7 manzil (the seven-day division).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DivisionKind {
    Hizb,
    Ruku,
    Manzil,
}

/// One hizb, ruku or manzil, identified by where it starts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Division {
    pub number: usize,
    pub surah: u32,
    pub ayah: u32,
    pub key: String,
}

// ---- qiraat variants -------------------------------------------------------------

/// One of the ten imams.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct VariantReader {
    pub id: u32,
    pub name: String,
    #[serde(default)]
    pub abbreviation: String,
    #[serde(default)]
    pub city: String,
    #[serde(default)]
    pub position: u32,
}

/// One of the twenty riwayat.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct VariantTransmitter {
    pub id: u32,
    pub name: String,
    pub reader: u32,
    /// This engine's own slug, so a consumer can join to `data/qiraat` and `data/mushaf`.
    #[serde(default)]
    pub riwayah: Option<String>,
    /// False for the twelve riwayat whose extracted text is not published.
    #[serde(default)]
    pub text_published: bool,
}

/// One form of a word, and who reads it.
///
/// `readers` is set when both of an imam's transmitters follow the form, `transmitters` when the
/// two part company.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct VariantReading {
    pub text: String,
    #[serde(default)]
    pub transliteration: String,
    #[serde(default)]
    pub english: String,
    #[serde(default)]
    pub explanation: String,
    #[serde(default)]
    pub grammatical_form: String,
    #[serde(default)]
    pub root_letters: String,
    #[serde(default)]
    pub readers: Vec<u32>,
    #[serde(default)]
    pub transmitters: Vec<u32>,
}

/// Where the word sits. `span` is `None` where the builder could not place it, in which case a
/// consumer shows the word untinted rather than guessing.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct VariantSegment {
    pub ayah: String,
    #[serde(default)]
    pub span: Option<[usize; 2]>,
}

/// One word of an ayah that the Ten read differently.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Juncture {
    #[serde(default)]
    pub word: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub segments: Vec<VariantSegment>,
    #[serde(default)]
    pub readings: Vec<VariantReading>,
    #[serde(default)]
    pub note: String,
}

/// `data/qiraat-variants.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct QiraatVariantsFile {
    #[serde(default)]
    pub readers: HashMap<String, VariantReader>,
    #[serde(default)]
    pub transmitters: HashMap<String, VariantTransmitter>,
    #[serde(default)]
    pub ayahs: HashMap<String, Vec<Juncture>>,
}

/// One ayah where a riwayah differs from Hafs.
///
/// Two kinds, because they are found two ways and a consumer may want only the first: a `word`
/// index is a word dropped, added or spelled differently, which a text diff finds; a `letter`
/// index is a word the printed mushaf marks as read with other vowels over the SAME skeleton,
/// which no text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).
#[derive(Debug, Clone, Default, Deserialize, PartialEq, Eq)]
pub struct PlaceRow {
    #[serde(default)]
    pub word: Vec<usize>,
    #[serde(default)]
    pub letter: Vec<usize>,
}

/// `data/qiraat-places.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct QiraatPlacesFile {
    #[serde(default)]
    pub riwayat: HashMap<String, HashMap<String, HashMap<String, PlaceRow>>>,
}

/// One ayah's differing words, with the ayah number attached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QiraatPlace {
    pub ayah: u32,
    pub word: Vec<usize>,
    pub letter: Vec<usize>,
}

/// A reciter who published both readings, and the two feeds they live in.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AudioSource {
    /// `"file"` for a whole per-verse recording, `"span"` for a seek inside a full-surah one.
    pub kind: String,
    pub reciter: String,
    pub hafs_base: String,
    pub riwayah_base: String,
}

/// `data/qiraat-variant-audio.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct QiraatVariantAudioFile {
    #[serde(default)]
    pub sources: Vec<AudioSource>,
    #[serde(default)]
    pub riwayat: HashMap<String, HashMap<String, Vec<Vec<i64>>>>,
}

/// One side of a paired recording.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VariantClip {
    pub url: String,
    /// `None` for a whole per-verse file.
    pub start_ms: Option<i64>,
    pub end_ms: Option<i64>,
}

/// The same reciter reading a verse both ways.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VariantAudioPair {
    pub reciter: String,
    pub hafs: VariantClip,
    pub riwayah: VariantClip,
}

// ---- word of the day -------------------------------------------------------------

/// One ayah carrying a curated form. `tokens` is plural because a form can repeat inside one
/// ayah.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct WordOccurrence {
    pub surah: u32,
    pub ayah: u32,
    pub tokens: Vec<usize>,
}

/// One curated word of Quranic vocabulary, with every ayah the same written form appears in.
///
/// Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission;
/// the occurrences are derived from the Hafs text, so the count and the list are one derivation.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct WordOfDayEntry {
    pub id: String,
    pub arabic: String,
    #[serde(default)]
    pub transliteration: String,
    #[serde(default)]
    pub meaning: String,
    /// The anchor: where the form first appears.
    pub surah: u32,
    pub ayah: u32,
    pub token: usize,
    /// Hits across the whole Quran.
    pub count: u32,
    pub occurrences: Vec<WordOccurrence>,
}

/// `data/word-of-day.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct WordOfDayFile {
    #[serde(default)]
    pub words: Vec<WordOfDayEntry>,
}

// ---- shared helpers --------------------------------------------------------------

/// Split a `"surah:ayah"` key. Returns `(0, 0)` for anything malformed, which sorts first and
/// never masquerades as a real ayah.
pub fn split_ayah_key(key: &str) -> (u32, u32) {
    let mut parts = key.splitn(2, ':');
    let surah = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let ayah = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    (surah, ayah)
}
