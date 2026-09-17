//! # quran-engine (Rust)
//!
//! Rust port of the open-source **Quran Tajweed Engine**. The engine is *data-first*: it is a thin,
//! idiomatic wrapper over the JSON corpus in the repo's `/data` directory plus a handful of pure
//! functions. No network, database, or framework is required.
//!
//! Follows the shared contract in `../../docs/PORTING.md`. See the per-feature specs in
//! `../../docs/01-quran.md` … `../../docs/08-caching.md`.
//!
//! ```no_run
//! use quran_engine::Engine;
//! let engine = Engine::load_default().unwrap();
//! assert_eq!(engine.total_ayahs(), 6236);
//! assert_eq!(engine.global_ayah_number(2, 1), Some(8));
//! ```
//!
//! Licensed MIT. Data and algorithms are extracted from the Al-Islam | Islamic Pillars app;
//! see `../../CREDITS.md`.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

pub mod ask_ai;
pub mod audio;
pub mod batch5;
pub mod batch6;
pub mod cache;
pub mod corpora;
pub mod model;
pub mod morphology;
pub mod miracles;
pub mod mushaf;
pub mod alphabet;
pub mod qiraat_comparison;
pub mod qiraat_tajweed;
pub mod sections;
pub mod search;
pub mod semantic;
pub mod sorting;
pub mod text;
pub mod util;
pub mod word_by_word;

pub use ask_ai::{chat_prompt, Passage, PassageKind, CHAT_INSTRUCTIONS, PASSAGE_CHARACTER_LIMIT,
                 PASSAGE_LIMIT, QUESTION_WORDS, SUBJECT_CHARACTER_LIMIT};
pub use audio::{ayah_audio_url, ayah_now_playing_name, defaults_to_minshawi, surah_audio_url};
pub use corpora::{
    SimilarMatch, TajweedChapter, TajweedDrill, TajweedExample, TajweedLesson, TajweedMnemonic, TajweedRuleCard,
    Topic,
};
pub use mushaf::RiwayahEntry;
pub use alphabet::{ArabicLetter, ArabicNumeral, StoppingSign, Tashkeel};
pub use qiraat_comparison::{ComparisonTotals, DifferenceKind, WordDifference};
pub use qiraat_tajweed::{LegendEntry, RuleDescription, WordRule};
pub use sections::{OutlineNode, SurahSection};
pub use semantic::{cosine, Semantic, SemanticHit};
pub use word_by_word::{GlossHit, GlossedWord};
pub use cache::{local_surah_path, sanitize_reciter_dir, shared_audio_path};
pub use model::{
    Ayah, JuzEntry, MuqattaatPronunciation, NameOfAllah, Reciter, Surah, SurahInfoSource,
    TajweedSpan,
};
pub use search::{Reference, SearchOpts, VerseHit};
pub use sorting::{
    filter_by_counts, filter_by_revelation_type, sort_surahs, CountFilter, CountOp, SortDirection,
    SortMode,
};
pub use util::{utf16_slice, zero_pad3};

use model::{AyahAnnotations, MuqattaatData, SurahInfoEntry, TajweedRules};
use search::SearchIndex;

/// ۩ ARABIC PLACE OF SAJDAH (U+06E9), marks the 15 sajdah (prostration) ayahs.
const SAJDAH_MARK: char = '\u{06E9}';

/// A single annotation flattened to `(utf16_start, utf16_end, rule_id)`.
type AnnotationSpan = (usize, usize, String);
/// Map of `(surah, ayah)` -> the ayah's flattened annotations.
type AnnotationMap = HashMap<(u32, u32), Vec<AnnotationSpan>>;

/// Aggregate counts for a single juz. Mirrors `QuranData.JuzStats`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JuzStats {
    /// Number of distinct surahs that have at least one ayah in this juz.
    pub surah_count: u32,
    /// Number of ayahs assigned to this juz.
    pub ayah_count: u32,
    /// Total words across the juz's ayahs.
    pub word_count: u32,
    /// Total letters across the juz's ayahs.
    pub letter_count: u32,
    /// Number of distinct mushaf pages the juz spans.
    pub page_count: u32,
}

/// Errors that can occur while loading the engine.
#[derive(Debug)]
pub enum LoadError {
    /// A required data file was not found.
    NotFound(String),
    /// An I/O error reading a file.
    Io(String),
    /// A JSON parse error.
    Parse(String),
}

impl std::fmt::Display for LoadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LoadError::NotFound(s) => write!(f, "data not found: {s}"),
            LoadError::Io(s) => write!(f, "io error: {s}"),
            LoadError::Parse(s) => write!(f, "parse error: {s}"),
        }
    }
}

impl std::error::Error for LoadError {}

/// The Quran Tajweed Engine: parsed corpus + lookups.
pub struct Engine {
    surahs: Vec<Surah>,
    juz_list: Vec<JuzEntry>,
    reciters: Vec<Reciter>,
    /// Map rule/category id -> color hex, from `tajweed-rules.json`.
    rule_colors: HashMap<String, String>,
    /// Map (surah, ayah) -> annotations, from `tajweed-annotations.json`.
    annotations: AnnotationMap,
    /// Cumulative ayah offset per surah id (0-based count of ayahs in earlier surahs).
    cumulative_offset: HashMap<u32, u32>,
    /// Total ayah count across the mushaf (6236).
    total_ayahs: u32,
    /// Map surah id -> "About this surah" sources, from `surah-info.json` (empty if absent).
    surah_info: HashMap<u32, Vec<SurahInfoSource>>,
    /// The 99 Names of Allah, sorted by number, from `names-of-allah.json` (empty if absent).
    names_of_allah: Vec<NameOfAllah>,
    /// Muqaṭṭaʿāt opening ayahs, from `muqattaat.json` (empty if absent).
    muqattaat: Vec<MuqattaatPronunciation>,
    /// Map muqaṭṭaʿāt letter -> transliteration, from `muqattaat.json` (empty if absent).
    muqattaat_letter_names: HashMap<String, String>,
    /// Map riwayah -> surahId(str) -> ayah count, from `qiraat-counts.json` (empty if absent).
    qiraat_counts: HashMap<String, HashMap<String, u32>>,
    /// `data/mushaf/index.json` (absent unless `LoadOptions::mushaf`).
    mushaf_index: Option<mushaf::MushafIndex>,
    /// riwayah -> `data/mushaf/pages/<slug>.json`.
    mushaf_pages: HashMap<String, mushaf::MushafPageTable>,
    /// riwayah -> `data/mushaf/lines/<slug>.json`, for the eight whose text ships.
    mushaf_lines: HashMap<String, mushaf::MushafLineTable>,
    /// Rule key -> the shared explanation, from `data/tajweed-qiraat/rules.json`.
    qiraat_rule_descriptions: HashMap<String, RuleDescription>,
    /// riwayah -> `data/tajweed-qiraat/<slug>.json`.
    qiraat_tajweed: HashMap<String, qiraat_tajweed::QiraatTajweedPack>,
    /// riwayah -> surah id (as a string) -> that reading's own verses (empty unless
    /// `LoadOptions::qiraat`).
    qiraat: HashMap<String, HashMap<String, Vec<QiraahVerse>>>,
    /// `data/surah-sections.json`; loaded by default.
    surah_sections: sections::SurahSectionsFile,
    /// `data/arabic-alphabet.json`; loaded by default.
    alphabet: alphabet::ArabicAlphabetFile,
    /// The two aligned word-by-word layers (empty unless `LoadOptions::word_by_word`).
    word_by_word: word_by_word::WordByWordPack,
    /// The `ayahs` of `data/similar-ayahs.json`, keyed `"surah:ayah"` (empty unless
    /// `LoadOptions::similar_ayahs`, and empty when the file is not version 2).
    similar_ayahs: HashMap<String, Vec<SimilarMatch>>,
    /// The curated topics; loaded by default.
    topics: Vec<Topic>,
    /// The tajweed course; loaded by default.
    tajweed_chapters: Vec<TajweedChapter>,
    /// Batch 5. `morphology`, `mutashabihat`, `qul_topics` and the qiraat variant trio are
    /// opt-in; the metadata, passage themes and word list load by default.
    morphology: morphology::MorphologyFile,
    morphology_index: std::sync::OnceLock<morphology::MorphologyIndex>,
    mutashabihat: batch5::MutashabihatFile,
    qul_topics: Vec<batch5::QulTopic>,
    qul_topic_index: std::sync::OnceLock<batch5::QulTopicIndex>,
    ayah_themes: HashMap<String, Vec<batch5::ThemePassage>>,
    quran_metadata: batch5::QuranMetadataFile,
    qiraat_variants: batch5::QiraatVariantsFile,
    qiraat_places: batch5::QiraatPlacesFile,
    qiraat_variant_audio: batch5::QiraatVariantAudioFile,
    words_of_day: Vec<batch5::WordOfDayEntry>,
    names_depth: batch6::NamesDepthFile,
    isnad: batch6::IsnadFile,
    /// The scientific-miracles corpus; loads by default.
    miracles: miracles::MiraclesFile,
    search: SearchIndex,
}

/// Which of the heavier corpora to load. All default to `false`; `Engine::load` uses the default,
/// so the corpora that cost a few hundred kilobytes (themes, the tajweed course) always load and
/// the megabyte-scale ones are opt-in.
#[derive(Debug, Clone, Copy, Default)]
pub struct LoadOptions {
    /// The mushaf index, page and line tables (~2 MB). The 604-page facsimiles themselves are never
    /// loaded by the engine, `mushaf_pdf_path` hands you the path.
    pub mushaf: bool,
    /// The seven riwayah tajweed packs (~0.9 MB).
    pub qiraat_tajweed: bool,
    /// The per-word gloss + transliteration pack (~1.8 MB).
    pub word_by_word: bool,
    /// The mutashabihat corpus (~2.9 MB).
    pub similar_ayahs: bool,
    /// The seven non-Hafs riwayat's own text (~11 MB), what `compare_surah` compares.
    pub qiraat: bool,
    /// Root and lemma of every word (~776 KB).
    pub morphology: bool,
    /// The repeated phrases (~178 KB).
    pub mutashabihat: bool,
    /// The three QUL topic indexes (~730 KB).
    pub qul_topics: bool,
    /// The variant matrix, the place index and the paired-recording table (~1.9 MB together).
    pub qiraat_variants: bool,
}

/// One verse of a riwayah's own text, in ITS numbering.
#[derive(Debug, Clone, serde::Deserialize, PartialEq, Eq)]
pub struct QiraahVerse {
    pub id: u32,
    pub text: String,
}

/// Like `read_json`, but a missing file yields the type's default rather than an error. Used for
/// the corpora that load by default: absent data means the accessors answer nothing, not that the
/// engine fails to start.
fn read_json_or_default<T: serde::de::DeserializeOwned + Default>(
    path: &Path,
) -> Result<T, LoadError> {
    if !path.exists() {
        return Ok(T::default());
    }
    read_json(path)
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, LoadError> {
    let bytes = std::fs::read(path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            LoadError::NotFound(path.display().to_string())
        } else {
            LoadError::Io(format!("{}: {e}", path.display()))
        }
    })?;
    serde_json::from_slice(&bytes).map_err(|e| LoadError::Parse(format!("{}: {e}", path.display())))
}

impl Engine {
    /// Load the engine from a `/data` directory. Requires `quran.json`, `juz.json`,
    /// `reciters.json`, `tajweed-rules.json`. `tajweed-annotations.json` is optional (tajweed
    /// spans are empty without it).
    pub fn load(data_dir: &Path) -> Result<Engine, LoadError> {
        Engine::load_with(data_dir, LoadOptions::default())
    }

    /// Load with the heavier corpora selected. See [`LoadOptions`].
    pub fn load_with(data_dir: &Path, options: LoadOptions) -> Result<Engine, LoadError> {
        let surahs: Vec<Surah> = read_json(&data_dir.join("quran.json"))?;
        let juz_list: Vec<JuzEntry> = read_json(&data_dir.join("juz.json"))?;
        let reciters: Vec<Reciter> = read_json(&data_dir.join("reciters.json"))?;
        let rules: TajweedRules = read_json(&data_dir.join("tajweed-rules.json"))?;

        let mut rule_colors = HashMap::new();
        for c in rules.categories {
            if let Some(color) = c.color_hex {
                rule_colors.insert(c.id, color);
            }
        }

        // tajweed-annotations.json is optional.
        let mut annotations: AnnotationMap = HashMap::new();
        let ann_path = data_dir.join("tajweed-annotations.json");
        if ann_path.exists() {
            let entries: Vec<AyahAnnotations> = read_json(&ann_path)?;
            for e in entries {
                let v = e
                    .annotations
                    .into_iter()
                    .map(|a| (a.start, a.end, a.rule))
                    .collect();
                annotations.insert((e.surah, e.ayah), v);
            }
        }

        let mut juz_list = juz_list;
        juz_list.sort_by_key(|j| j.id);

        let mut reciters = reciters;
        reciters.sort_by(|a, b| a.name.cmp(&b.name));

        let mut cumulative_offset = HashMap::new();
        let mut acc = 0u32;
        for s in &surahs {
            cumulative_offset.insert(s.id, acc);
            acc += s.number_of_ayahs;
        }
        let total_ayahs = acc;

        // surah-info.json is optional ("About this surah" write-ups).
        let mut surah_info: HashMap<u32, Vec<SurahInfoSource>> = HashMap::new();
        let info_path = data_dir.join("surah-info.json");
        if info_path.exists() {
            let entries: Vec<SurahInfoEntry> = read_json(&info_path)?;
            for e in entries {
                surah_info.insert(e.id, e.sources);
            }
        }

        // names-of-allah.json is optional (the 99 Names); sort by number to mirror the JS port.
        let mut names_of_allah: Vec<NameOfAllah> = Vec::new();
        let names_path = data_dir.join("names-of-allah.json");
        if names_path.exists() {
            names_of_allah = read_json(&names_path)?;
            names_of_allah.sort_by_key(|n| n.number);
        }

        // muqattaat.json is optional (disconnected-letter opening pronunciations).
        let mut muqattaat: Vec<MuqattaatPronunciation> = Vec::new();
        let mut muqattaat_letter_names: HashMap<String, String> = HashMap::new();
        let muqattaat_path = data_dir.join("muqattaat.json");
        if muqattaat_path.exists() {
            let data: MuqattaatData = read_json(&muqattaat_path)?;
            muqattaat = data.ayahs;
            muqattaat_letter_names = data.letter_names;
        }

        // qiraat-counts.json is optional (riwayah -> surahId -> ayah count).
        let mut qiraat_counts: HashMap<String, HashMap<String, u32>> = HashMap::new();
        let counts_path = data_dir.join("qiraat-counts.json");
        if counts_path.exists() {
            qiraat_counts = read_json(&counts_path)?;
        }

        // themes.json and tajweed-lessons.json are optional but load by default: together they are
        // ~250 KB, and a topic list is the kind of thing a consumer wants without a flag.
        let mut topics: Vec<Topic> = Vec::new();
        let themes_path = data_dir.join("themes.json");
        if themes_path.exists() {
            let file: corpora::ThemesFile = read_json(&themes_path)?;
            topics = file.topics;
        }
        let mut tajweed_chapters: Vec<TajweedChapter> = Vec::new();
        let lessons_path = data_dir.join("tajweed-lessons.json");
        if lessons_path.exists() {
            let file: corpora::TajweedLessonsFile = read_json(&lessons_path)?;
            tajweed_chapters = file.chapters;
        }

        let mut mushaf_index = None;
        let mut mushaf_pages = HashMap::new();
        let mut mushaf_lines = HashMap::new();
        if options.mushaf {
            let index: mushaf::MushafIndex = read_json(&data_dir.join("mushaf/index.json"))?;
            for entry in &index.riwayat {
                let table: mushaf::MushafPageTable =
                    read_json(&data_dir.join("mushaf").join(&entry.pages))?;
                mushaf_pages.insert(entry.riwayah.clone(), table);
                if let Some(lines) = &entry.lines {
                    let table: mushaf::MushafLineTable =
                        read_json(&data_dir.join("mushaf").join(lines))?;
                    mushaf_lines.insert(entry.riwayah.clone(), table);
                }
            }
            mushaf_index = Some(index);
        }

        let mut qiraat_rule_descriptions = HashMap::new();
        let mut qiraat_tajweed_packs = HashMap::new();
        if options.qiraat_tajweed {
            qiraat_rule_descriptions = read_json(&data_dir.join("tajweed-qiraat/rules.json"))?;
            for slug in ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"] {
                let path = data_dir.join("tajweed-qiraat").join(format!("{slug}.json"));
                let pack: qiraat_tajweed::QiraatTajweedPack = read_json(&path)?;
                qiraat_tajweed_packs.insert(slug.to_string(), pack);
            }
        }

        let word_by_word = if options.word_by_word {
            read_json(&data_dir.join("word-by-word.json"))?
        } else {
            word_by_word::WordByWordPack::default()
        };

        // surah-sections.json (80 KB) and arabic-alphabet.json (18 KB) load by default, like
        // themes and lessons: small, and both answer questions a consumer should not have to opt
        // into. A missing file is not an error; the accessors simply return nothing.
        let mut surah_sections = sections::SurahSectionsFile::new();
        let sections_path = data_dir.join("surah-sections.json");
        if sections_path.exists() {
            surah_sections = read_json(&sections_path)?;
        }
        let mut alphabet = alphabet::ArabicAlphabetFile::default();
        let alphabet_path = data_dir.join("arabic-alphabet.json");
        if alphabet_path.exists() {
            alphabet = read_json(&alphabet_path)?;
        }

        let mut qiraat = HashMap::new();
        if options.qiraat {
            for slug in ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"] {
                let path = data_dir.join("qiraat").join(format!("qiraah-{slug}.json"));
                let verses: HashMap<String, Vec<QiraahVerse>> = read_json(&path)?;
                qiraat.insert(slug.to_string(), verses);
            }
        }

        let similar_ayahs = if options.similar_ayahs {
            let file: corpora::SimilarAyahsFile = read_json(&data_dir.join("similar-ayahs.json"))?;
            file.into_ayahs()
        } else {
            HashMap::new()
        };

        // Metadata (8 KB), the passage themes (142 KB) and the word list (128 KB) load by
        // default like the sections and the alphabet: small, and each answers a question a
        // consumer should not have to opt into. A missing file is not an error.
        let quran_metadata: batch5::QuranMetadataFile =
            read_json_or_default(&data_dir.join("quran-metadata.json"))?;
        let ayah_themes: HashMap<String, Vec<batch5::ThemePassage>> =
            read_json_or_default(&data_dir.join("ayah-themes.json"))?;
        let word_file: batch5::WordOfDayFile =
            read_json_or_default(&data_dir.join("word-of-day.json"))?;
        // The Names in depth (47 KB) and the chains (20 KB) load by default on the same footing.
        let names_depth: batch6::NamesDepthFile =
            read_json_or_default(&data_dir.join("names-depth.json"))?;
        let isnad: batch6::IsnadFile = read_json_or_default(&data_dir.join("isnad.json"))?;
        // The miracles corpus (393 KB) joins them: bigger than those, but smaller than the tajweed
        // course that has always loaded by default, and a consumer cross-linking an ayah to what
        // has been written about it should not have to know a flag existed.
        let miracles: miracles::MiraclesFile = read_json_or_default(&data_dir.join("miracles.json"))?;

        let morphology = if options.morphology {
            read_json(&data_dir.join("morphology.json"))?
        } else {
            morphology::MorphologyFile::default()
        };
        let mutashabihat = if options.mutashabihat {
            read_json(&data_dir.join("mutashabihat.json"))?
        } else {
            batch5::MutashabihatFile::default()
        };
        let qul_topics = if options.qul_topics {
            let file: batch5::QulTopicsFile = read_json(&data_dir.join("quran-topics.json"))?;
            file.topics
        } else {
            Vec::new()
        };
        let (qiraat_variants, qiraat_places, qiraat_variant_audio) = if options.qiraat_variants {
            (
                read_json(&data_dir.join("qiraat-variants.json"))?,
                read_json(&data_dir.join("qiraat-places.json"))?,
                read_json(&data_dir.join("qiraat-variant-audio.json"))?,
            )
        } else {
            Default::default()
        };

        let search = SearchIndex::build(&surahs);

        Ok(Engine {
            surahs,
            juz_list,
            reciters,
            rule_colors,
            annotations,
            cumulative_offset,
            total_ayahs,
            surah_info,
            names_of_allah,
            muqattaat,
            muqattaat_letter_names,
            qiraat_counts,
            mushaf_index,
            mushaf_pages,
            mushaf_lines,
            qiraat_rule_descriptions,
            qiraat_tajweed: qiraat_tajweed_packs,
            qiraat,
            surah_sections,
            alphabet,
            word_by_word,
            similar_ayahs,
            topics,
            tajweed_chapters,
            morphology,
            morphology_index: std::sync::OnceLock::new(),
            mutashabihat,
            qul_topics,
            qul_topic_index: std::sync::OnceLock::new(),
            ayah_themes,
            quran_metadata,
            qiraat_variants,
            qiraat_places,
            qiraat_variant_audio,
            words_of_day: word_file.words,
            names_depth,
            isnad,
            miracles,
            search,
        })
    }

    /// Load from the canonical repo `/data` directory, discovered by ascending from
    /// `CARGO_MANIFEST_DIR` (and the current working dir at runtime) until a `data/quran.json`
    /// is found.
    pub fn load_default() -> Result<Engine, LoadError> {
        Engine::load_default_with(LoadOptions::default())
    }

    /// [`Engine::load_default`] with the heavier corpora selected.
    pub fn load_default_with(options: LoadOptions) -> Result<Engine, LoadError> {
        let dir = find_data_dir()
            .ok_or_else(|| LoadError::NotFound("could not locate data/quran.json".into()))?;
        Engine::load_with(&dir, options)
    }

    // ---- Quran -----------------------------------------------------------------

    /// All surahs in mushaf order (1..=114).
    pub fn surahs(&self) -> &[Surah] {
        &self.surahs
    }

    /// A surah by id (1..=114).
    pub fn surah(&self, id: u32) -> Option<&Surah> {
        self.surahs.iter().find(|s| s.id == id)
    }

    /// An ayah by surah id + ayah id.
    pub fn ayah(&self, surah: u32, ayah: u32) -> Option<&Ayah> {
        self.surah(surah)?.ayahs.iter().find(|a| a.id == ayah)
    }

    /// Global ayah number (1..=6236): `(Σ numberOfAyahs of surahs before `surah`) + ayah`.
    pub fn global_ayah_number(&self, surah: u32, ayah: u32) -> Option<u32> {
        self.cumulative_offset.get(&surah).map(|off| off + ayah)
    }

    /// Total ayah count across the mushaf (6236 for the standard Hafs count).
    pub fn total_ayahs(&self) -> u32 {
        self.total_ayahs
    }

    /// The default Hafs Arabic text of an ayah.
    pub fn arabic_text(&self, surah: u32, ayah: u32) -> Option<&str> {
        self.ayah(surah, ayah).map(|a| a.text_arabic.as_str())
    }

    /// Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs every ayah
    /// exists; other riwayat merge/split some ayahs, so a Hafs ayah "exists" iff the riwayah's
    /// feed carries an ayah with that id (feeds are numbered contiguously 1..=count, so this is
    /// `ayah <= count`). Mirrors `Quran.existsInQiraah`. `riwayah` `""`/`"hafs"` (case-insensitive)
    /// and an unknown/unloaded riwayah fall back to Hafs (exists).
    pub fn exists_in_qiraah(&self, surah: u32, ayah: u32, riwayah: &str) -> bool {
        if self.ayah(surah, ayah).is_none() {
            return false;
        }
        let r = riwayah.to_lowercase();
        if r.is_empty() || r == "hafs" {
            return true;
        }
        match self
            .qiraat_counts
            .get(&r)
            .and_then(|m| m.get(&surah.to_string()))
        {
            None => true,
            Some(&count) => ayah <= count,
        }
    }

    /// Ayah count of a surah in the given riwayah, the number of Hafs ayahs that exist there
    /// (e.g. Baqarah is 286 in Hafs but 285 in Warsh). Mirrors `Quran.numberOfAyahsInQiraah`.
    /// Returns 0 for an unknown surah. `riwayah` `""`/`"hafs"` and a missing count fall back to
    /// the surah's Hafs `number_of_ayahs`.
    pub fn number_of_ayahs_in_qiraah(&self, surah: u32, riwayah: &str) -> u32 {
        let s = match self.surah(surah) {
            Some(s) => s,
            None => return 0,
        };
        let r = riwayah.to_lowercase();
        if r.is_empty() || r == "hafs" {
            return s.number_of_ayahs;
        }
        match self
            .qiraat_counts
            .get(&r)
            .and_then(|m| m.get(&surah.to_string()))
        {
            None => s.number_of_ayahs,
            Some(&count) => s.number_of_ayahs.min(count),
        }
    }

    /// Iterate every `(surah, ayah)` pair in mushaf order.
    pub fn each_ayah(&self) -> impl Iterator<Item = (&Surah, &Ayah)> {
        self.surahs.iter().flat_map(|s| s.ayahs.iter().map(move |a| (s, a)))
    }

    /// Resolve a surah counted from the END of the mushaf: 1 → An-Nās (114), 2 → Al-Falaq …
    /// 114 → Al-Fātiḥah. Mirrors `Quran.surahFromEnd`. Returns `None` for n outside 1..=114.
    pub fn surah_from_end(&self, n: u32) -> Option<&Surah> {
        let len = self.surahs.len() as u32;
        if n < 1 || n > len {
            return None;
        }
        self.surah(len + 1 - n)
    }

    /// "About this surah" write-ups (Maududi / Ibn Ashur) for a surah id; empty slice if none.
    /// Mirrors `Quran.info`.
    /// A riwayah's own verses for a surah, in ITS numbering: which is not always Hafs'.
    ///
    /// Warsh's al-Baqarah has 285 verses to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as
    /// one; pairing the two by ayah id past that point compares different verses. Empty unless
    /// [`LoadOptions::qiraat`], and for `"hafs"`, whose text is `quran.json` itself.
    pub fn qiraah_verses(&self, surah: u32, riwayah: &str) -> &[QiraahVerse] {
        self.qiraat
            .get(&riwayah.to_lowercase())
            .and_then(|s| s.get(&surah.to_string()))
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    /// The riwayat whose text is loaded, in slug order.
    pub fn loaded_riwayat(&self) -> Vec<&str> {
        let mut slugs: Vec<&str> = self.qiraat.keys().map(String::as_str).collect();
        slugs.sort_unstable();
        slugs
    }

    pub fn surah_info(&self, id: u32) -> &[SurahInfoSource] {
        self.surah_info.get(&id).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Whether an ayah is a sajdah (prostration) ayah: its Arabic text carries the ۩ mark
    /// (U+06E9). Mirrors `Quran.isSajdahAyah`.
    pub fn is_sajdah_ayah(&self, surah: u32, ayah: u32) -> bool {
        self.ayah(surah, ayah)
            .is_some_and(|a| a.text_arabic.contains(SAJDAH_MARK))
    }

    /// The 15 sajdah (prostration) ayahs, in mushaf order, detected by the ۩ mark in the
    /// Arabic text. Mirrors `Quran.sajdahAyahs`.
    pub fn sajdah_ayahs(&self) -> Vec<(&Surah, &Ayah)> {
        self.each_ayah()
            .filter(|(_, a)| a.text_arabic.contains(SAJDAH_MARK))
            .collect()
    }

    /// Whether a mushaf page boundary falls inside this surah. Mirrors
    /// `Quran.pageChangesWithinSurah`.
    pub fn page_changes_within_surah(&self, surah: u32) -> bool {
        let s = match self.surah(surah) {
            Some(s) => s,
            None => return false,
        };
        if s.number_of_pages.unwrap_or(1) > 1 {
            return true;
        }
        let pages: HashSet<u32> = s.ayahs.iter().filter_map(|a| a.page).collect();
        pages.len() > 1
    }

    /// Whether a juz boundary falls inside this surah. Mirrors `Quran.juzChangesWithinSurah`.
    pub fn juz_changes_within_surah(&self, surah: u32) -> bool {
        let s = match self.surah(surah) {
            Some(s) => s,
            None => return false,
        };
        if s.juzs.len() > 1 {
            return true;
        }
        if let (Some(first), Some(last)) = (s.first_juz, s.last_juz) {
            if first != last {
                return true;
            }
        }
        let juzs: HashSet<u32> = s.ayahs.iter().filter_map(|a| a.juz).collect();
        juzs.len() > 1
    }

    /// Whether a page OR juz boundary falls inside this surah. Mirrors
    /// `Quran.pageOrJuzChangesWithinSurah`.
    pub fn page_or_juz_changes_within_surah(&self, surah: u32) -> bool {
        self.page_changes_within_surah(surah) || self.juz_changes_within_surah(surah)
    }

    // ---- Names of Allah --------------------------------------------------------

    /// All 99 Names of Allah, ordered by number. Mirrors `NamesOfAllah.all`.
    pub fn names_of_allah(&self) -> &[NameOfAllah] {
        &self.names_of_allah
    }

    /// A Name of Allah by number (1..=99). Mirrors `NamesOfAllah.byNumber`.
    pub fn name_of_allah(&self, number: u32) -> Option<&NameOfAllah> {
        self.names_of_allah.iter().find(|n| n.number == number)
    }

    // ---- Muqaṭṭaʿāt ------------------------------------------------------------

    /// Every muqaṭṭaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd ayah).
    /// Mirrors `Muqattaat.all`.
    pub fn muqattaat(&self) -> &[MuqattaatPronunciation] {
        &self.muqattaat
    }

    /// Pronunciation for a muqaṭṭaʿāt ayah, or `None` if that ayah doesn't open with them.
    /// Mirrors `Muqattaat.pronunciation`.
    pub fn muqattaat_pronunciation(&self, surah: u32, ayah: u32) -> Option<&MuqattaatPronunciation> {
        self.muqattaat
            .iter()
            .find(|p| p.surah == surah && p.ayah == ayah)
    }

    /// Transliteration of a single muqaṭṭaʿāt letter, e.g. `"ا"` → `"Alif"`. Mirrors
    /// `Muqattaat.letterName`.
    pub fn muqattaat_letter_name(&self, letter: &str) -> Option<&str> {
        self.muqattaat_letter_names.get(letter).map(String::as_str)
    }

    // ---- Juz / Page ------------------------------------------------------------

    /// All 30 juz boundary entries (sorted by id).
    pub fn juzes(&self) -> &[JuzEntry] {
        &self.juz_list
    }

    /// A juz boundary entry by id (1..=30).
    pub fn juz(&self, id: u32) -> Option<&JuzEntry> {
        self.juz_list.iter().find(|j| j.id == id)
    }

    /// Every `(surah, ayah)` in a juz, in mushaf order.
    pub fn ayahs_in_juz(&self, juz: u32) -> Vec<(&Surah, &Ayah)> {
        self.each_ayah().filter(|(_, a)| a.juz == Some(juz)).collect()
    }

    /// Every `(surah, ayah)` on a mushaf page, in mushaf order.
    pub fn ayahs_on_page(&self, page: u32) -> Vec<(&Surah, &Ayah)> {
        self.each_ayah().filter(|(_, a)| a.page == Some(page)).collect()
    }

    /// First `(surah, ayah)` of a juz (jump target).
    pub fn first_ayah_of_juz(&self, juz: u32) -> Option<(&Surah, &Ayah)> {
        self.each_ayah().find(|(_, a)| a.juz == Some(juz))
    }

    /// First `(surah, ayah)` of a mushaf page (jump target).
    pub fn first_ayah_of_page(&self, page: u32) -> Option<(&Surah, &Ayah)> {
        self.each_ayah().find(|(_, a)| a.page == Some(page))
    }

    /// The juz number an ayah belongs to.
    pub fn juz_for_ayah(&self, surah: u32, ayah: u32) -> Option<u32> {
        self.ayah(surah, ayah).and_then(|a| a.juz)
    }

    /// The mushaf page an ayah is on.
    pub fn page_for_ayah(&self, surah: u32, ayah: u32) -> Option<u32> {
        self.ayah(surah, ayah).and_then(|a| a.page)
    }

    /// Total page count of the bundled mushaf (max page seen).
    pub fn total_pages(&self) -> u32 {
        self.each_ayah().filter_map(|(_, a)| a.page).max().unwrap_or(0)
    }

    /// Surah ids contained in a juz (by boundary range).
    pub fn surahs_in_juz(&self, juz: u32) -> Vec<u32> {
        match self.juz(juz) {
            None => Vec::new(),
            Some(j) => self
                .surahs
                .iter()
                .filter(|s| s.id >= j.start_surah && s.id <= j.end_surah)
                .map(|s| s.id)
                .collect(),
        }
    }

    /// Resolve a juz counted from the end of the Quran: 1 → juz 30, 2 → juz 29 … 30 → juz 1.
    /// Mirrors the search-bar `-N` shorthand in QuranView.swift. Returns `None` for n outside 1..=30.
    pub fn juz_from_end(&self, n: u32) -> Option<&JuzEntry> {
        if !(1..=30).contains(&n) {
            return None;
        }
        self.juz(31 - n)
    }

    /// Aggregate counts for a single juz, computed from the ayahs actually assigned to it
    /// (`ayah.juz == Some(juz)`) so surahs that straddle a juz boundary are split correctly.
    /// Mirrors `QuranData.juzStats(for:)`. Returns `None` for an unknown juz id.
    pub fn juz_stats(&self, juz: u32) -> Option<JuzStats> {
        self.juz(juz)?;
        let mut surah_ids: HashSet<u32> = HashSet::new();
        let mut pages: HashSet<u32> = HashSet::new();
        let mut ayah_count = 0u32;
        let mut word_count = 0u32;
        let mut letter_count = 0u32;
        for (s, a) in self.each_ayah() {
            if a.juz != Some(juz) {
                continue;
            }
            surah_ids.insert(s.id);
            ayah_count += 1;
            word_count += a.word_count.unwrap_or(0);
            letter_count += a.letter_count.unwrap_or(0);
            if let Some(p) = a.page {
                pages.insert(p);
            }
        }
        Some(JuzStats {
            surah_count: surah_ids.len() as u32,
            ayah_count,
            word_count,
            letter_count,
            page_count: pages.len() as u32,
        })
    }

    // ---- Reciters / audio ------------------------------------------------------

    /// All reciters (sorted by name).
    pub fn reciters(&self) -> &[Reciter] {
        &self.reciters
    }

    /// A reciter by exact id.
    pub fn reciter_by_id(&self, id: &str) -> Option<&Reciter> {
        self.reciters.iter().find(|r| r.id == id)
    }

    /// Reciters that have a full-surah feed (a `surahLink` directory not ending in `.mp3`).
    pub fn reciters_with_surah_feed(&self) -> Vec<&Reciter> {
        self.reciters
            .iter()
            .filter(|r| !r.surah_link.is_empty() && !r.surah_link.ends_with(".mp3"))
            .collect()
    }

    /// Full-surah recitation URL for a reciter + surah number.
    pub fn surah_audio_url(&self, reciter: &Reciter, surah: u32) -> Result<String, String> {
        audio::surah_audio_url(reciter, surah)
    }

    /// Ayah-by-ayah recitation URL for a reciter + global ayah number (1..=6236).
    pub fn ayah_audio_url(&self, reciter: &Reciter, global_ayah: u32) -> String {
        audio::ayah_audio_url(reciter, global_ayah)
    }

    // ---- Sorting ---------------------------------------------------------------

    /// Sort surahs by `mode` ("surah"|"revelation"|"ayahs"|"page"|"words"|"letters") and
    /// `direction` ("surahOrder"|"ascending"|"descending"). Returns references in order.
    pub fn sort_surahs(&self, mode: &str, direction: &str) -> Vec<&Surah> {
        sorting::sort_surahs(
            &self.surahs,
            SortMode::parse(mode),
            SortDirection::parse(direction),
        )
    }

    /// Filter surahs by revelation type (`"makkan"` / `"madinan"`).
    pub fn filter_by_revelation_type(&self, r#type: &str) -> Vec<&Surah> {
        sorting::filter_by_revelation_type(&self.surahs, r#type)
    }

    /// Filter surahs by ayah-count and/or page-count predicates. A surah passes when it
    /// satisfies BOTH provided filters; an omitted (`None`) filter is ignored. Mirrors
    /// `filterByCounts` in `sorting.js`.
    pub fn filter_by_counts(
        &self,
        ayahs: Option<CountFilter>,
        pages: Option<CountFilter>,
    ) -> Vec<&Surah> {
        sorting::filter_by_counts(&self.surahs, ayahs, pages)
    }

    // ---- Search ----------------------------------------------------------------

    /// Verse-text search (unranked, mushaf order). Core path; boolean grammar omitted.
    pub fn search_verses(&self, query: &str, opts: &SearchOpts) -> Vec<VerseHit> {
        self.search.search_verses(query, opts)
    }

    /// Surah search by name / alias / number / `"2:255"` / makkan-madani. Returns surah ids.
    pub fn search_surahs(&self, query: &str) -> Vec<u32> {
        // Makkan/madani filter takes precedence, matching the JS port.
        if let Some(kind) = self.search.revelation_filter(query) {
            return self
                .surahs
                .iter()
                .filter(|s| s.r#type == kind)
                .map(|s| s.id)
                .collect();
        }
        self.search.search_surahs(query)
    }

    /// Parse an ayah reference like `"2:255"`.
    pub fn parse_reference(&self, query: &str) -> Option<Reference> {
        self.search.parse_reference(query)
    }

    // ---- Tajweed (strategy A: pre-computed annotations) ------------------------

    /// Colored tajweed spans for an ayah, from the pre-computed annotation corpus.
    ///
    /// Each span's `start`/`end` are UTF-16 offsets; `text` is the reconstructed UTF-16 slice of
    /// the ayah's Arabic text, and `color` is the rule's `colorHex` from `tajweed-rules.json`.
    /// Returns an empty vec if the ayah has no annotations (or the annotation file is absent).
    pub fn tajweed(&self, surah: u32, ayah: u32) -> Vec<TajweedSpan> {
        let text = match self.arabic_text(surah, ayah) {
            Some(t) => t,
            None => return Vec::new(),
        };
        let anns = match self.annotations.get(&(surah, ayah)) {
            Some(a) => a,
            None => return Vec::new(),
        };
        anns.iter()
            .map(|(start, end, rule)| TajweedSpan {
                start: *start,
                end: *end,
                color: self.rule_colors.get(rule).cloned(),
                text: utf16_slice(text, *start, *end),
                rule: rule.clone(),
            })
            .collect()
    }
}

/// Ascend from `CARGO_MANIFEST_DIR` and the current working directory looking for `data/quran.json`.
fn find_data_dir() -> Option<PathBuf> {
    let mut starts: Vec<PathBuf> = Vec::new();
    if let Some(manifest) = option_env!("CARGO_MANIFEST_DIR") {
        starts.push(PathBuf::from(manifest));
    }
    if let Ok(cwd) = std::env::current_dir() {
        starts.push(cwd);
    }

    for start in starts {
        let mut dir: Option<&Path> = Some(start.as_path());
        while let Some(d) = dir {
            let candidate = d.join("data");
            if candidate.join("quran.json").is_file() {
                return Some(candidate);
            }
            dir = d.parent();
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> Engine {
        Engine::load_default().expect("load_default should find the repo data dir")
    }

    #[test]
    fn total_ayahs_is_6236() {
        assert_eq!(engine().total_ayahs(), 6236);
    }

    #[test]
    fn global_ayah_numbers() {
        let e = engine();
        assert_eq!(e.global_ayah_number(1, 1), Some(1));
        assert_eq!(e.global_ayah_number(2, 1), Some(8));
        assert_eq!(e.global_ayah_number(114, 6), Some(6236));
    }

    #[test]
    fn audio_urls() {
        let e = engine();
        let alafasy = e
            .reciters()
            .iter()
            .find(|r| r.ayah_identifier == "ar.alafasy")
            .expect("alafasy reciter present");
        assert_eq!(
            e.surah_audio_url(alafasy, 1).unwrap(),
            "https://server8.mp3quran.net/afs/001.mp3"
        );
        assert_eq!(
            e.ayah_audio_url(alafasy, 8),
            "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"
        );
    }

    #[test]
    fn juz_boundaries() {
        let e = engine();
        let j1 = e.juz(1).unwrap();
        assert_eq!(j1.start_surah, 1);
        assert_eq!(j1.start_ayah, 1);
        let j30 = e.juz(30).unwrap();
        assert_eq!(j30.end_surah, 114);
        assert_eq!(j30.end_ayah, 6);
    }

    #[test]
    fn juz_from_end_and_stats() {
        let e = engine();
        assert_eq!(e.juz_from_end(1).unwrap().id, 30);
        assert_eq!(e.juz_from_end(30).unwrap().id, 1);
        assert!(e.juz_from_end(0).is_none());
        assert!(e.juz_from_end(31).is_none());

        let stats = e.juz_stats(30).unwrap();
        assert_eq!(stats.ayah_count as usize, e.ayahs_in_juz(30).len());
        assert!(stats.surah_count >= 1 && stats.page_count >= 1);
        assert!(stats.word_count > 0 && stats.letter_count > 0);
        assert!(e.juz_stats(99).is_none());

        let sum: u32 = (1..=30).map(|i| e.juz_stats(i).unwrap().ayah_count).sum();
        assert_eq!(sum, 6236);
    }

    #[test]
    fn sort_surahs_ayahs_descending() {
        let e = engine();
        let sorted = e.sort_surahs("ayahs", "descending");
        assert_eq!(sorted[0].id, 2); // Al-Baqarah, 286 ayahs (longest)
    }

    #[test]
    fn parse_reference_2_255() {
        let e = engine();
        let r = e.parse_reference("2:255").unwrap();
        assert_eq!(r.surah, 2);
        assert_eq!(r.ayah, Some(255));
    }

    #[test]
    fn tajweed_spans_reconstruct_utf16_slices() {
        let e = engine();
        let spans = e.tajweed(1, 1);
        assert!(!spans.is_empty(), "al-Fatiha 1:1 should have annotations");
        let text = e.arabic_text(1, 1).unwrap();
        for s in &spans {
            // The reconstructed UTF-16 slice must equal the span's recorded text.
            assert_eq!(s.text, utf16_slice(text, s.start, s.end));
            assert!(s.color.is_some(), "rule {} should map to a color", s.rule);
        }
    }

    #[test]
    fn first_ayah_of_juz_and_page() {
        let e = engine();
        let (s, a) = e.first_ayah_of_juz(1).unwrap();
        assert_eq!((s.id, a.id), (1, 1));
        let (s, a) = e.first_ayah_of_page(1).unwrap();
        assert_eq!((s.id, a.id), (1, 1));
        assert!(e.total_pages() >= 604);
    }

    #[test]
    fn cache_paths() {
        assert_eq!(
            local_surah_path("Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/", 57),
            "Mishary_Alafasy_Hafs_https___server8_mp3quran_net_afs_/057.mp3"
        );
        assert_eq!(sanitize_reciter_dir(""), "reciter");
    }

    #[test]
    fn surah_from_end_and_sajdah() {
        let e = engine();
        assert_eq!(e.surah_from_end(1).unwrap().id, 114);
        assert_eq!(e.surah_from_end(2).unwrap().id, 113);
        assert_eq!(e.surah_from_end(114).unwrap().id, 1);
        assert!(e.surah_from_end(0).is_none());
        assert!(e.surah_from_end(115).is_none());

        assert_eq!(e.sajdah_ayahs().len(), 15);
        assert!(e.is_sajdah_ayah(32, 15));
        assert!(!e.is_sajdah_ayah(1, 1));
    }

    #[test]
    fn surah_info_and_names() {
        let e = engine();
        assert!(!e.surah_info(1).is_empty());
        assert!(e.surah_info(1).iter().any(|s| s.name == "Maududi"));

        assert_eq!(e.names_of_allah().len(), 99);
        assert_eq!(e.name_of_allah(1).unwrap().transliteration, "Ar-Rahman");
        assert!(e.name_of_allah(0).is_none());
        assert!(e.name_of_allah(100).is_none());
    }

    #[test]
    fn filter_by_counts_matches_js() {
        let e = engine();
        let only_baqarah = e.filter_by_counts(Some(CountFilter::new(CountOp::Eq, 286)), None);
        assert_eq!(only_baqarah.iter().map(|s| s.id).collect::<Vec<_>>(), vec![2]);

        let mut over200: Vec<u32> = e
            .filter_by_counts(Some(CountFilter::new(CountOp::Gt, 200)), None)
            .iter()
            .map(|s| s.id)
            .collect();
        over200.sort_unstable();
        assert_eq!(over200, vec![2, 7, 26]);
    }

    #[test]
    fn search_core_paths() {
        let e = engine();
        // English substring search.
        let hits = e.search_verses("lord of the worlds", &SearchOpts::default());
        assert!(hits.iter().any(|h| h.surah == 1 && h.ayah == 2));
        // Digit queries are rejected by verse search.
        assert!(e.search_verses("2 255", &SearchOpts::default()).is_empty());
        // Surah search by name + reference.
        assert!(e.search_surahs("fatihah").contains(&1));
        assert!(e.search_surahs("baqarah").contains(&2));
    }

    #[test]
    fn search_behavior_matches_js() {
        let e = engine();
        let opts = SearchOpts::default();
        let hits_1_2 = |hits: &[VerseHit]| hits.iter().any(|h| h.surah == 1 && h.ayah == 2);

        // Regular (non-boolean) search is a PURE SUBSTRING, mid-word match: "orld" hits 1:2.
        assert!(hits_1_2(&e.search_verses("orld", &opts)));

        // `=lord` (whole-word) hits 1:2; `=lor` does NOT (no whole word "lor")...
        assert!(hits_1_2(&e.search_verses("=lord", &opts)));
        assert!(!hits_1_2(&e.search_verses("=lor", &opts)));
        // ...while a plain `lor` substring DOES hit 1:2.
        assert!(hits_1_2(&e.search_verses("lor", &opts)));

        // Digit rejection happens BEFORE the boolean branch: `allah & 2` returns 0.
        assert!(e.search_verses("allah & 2", &opts).is_empty());
    }
}

// ---- batch 5 accessors -------------------------------------------------------------
//
// Kept here with the other accessors rather than in `batch5.rs`, which holds the shapes: the
// engine owns the data, and an accessor that borrows from it belongs on the type that owns it.

impl Engine {
    // -- morphology ------------------------------------------------------------------

    /// Whether `morphology.json` was loaded.
    pub fn has_morphology(&self) -> bool {
        !self.morphology.roots.is_empty()
    }

    /// The root with this 1-based id. Id `0` means the token has no root and never resolves.
    pub fn root(&self, id: u32) -> Option<morphology::Root> {
        morphology::root_at(&self.morphology, id)
    }

    /// The dictionary form with this 1-based id.
    pub fn lemma(&self, id: u32) -> Option<morphology::Lemma> {
        morphology::lemma_at(&self.morphology, id)
    }

    /// The root and lemma id of every token of the ayah, or `None` when it is not covered.
    pub fn morphology_ids(&self, surah_id: u32, ayah_id: u32) -> Option<(&[u32], &[u32])> {
        let key = surah_id.to_string();
        let roots = self.morphology.root_ids.get(&key)?;
        let lemmas = self.morphology.lemma_ids.get(&key)?;
        let index = (ayah_id as usize).checked_sub(1)?;
        Some((roots.get(index)?.as_slice(), lemmas.get(index)?.as_slice()))
    }

    /// The root of one token, `None` when it has none (a particle) or the index is out of range.
    pub fn root_of(&self, surah_id: u32, ayah_id: u32, token: usize) -> Option<(u32, morphology::Root)> {
        let (roots, _) = self.morphology_ids(surah_id, ayah_id)?;
        let id = *roots.get(token)?;
        Some((id, self.root(id)?))
    }

    /// The dictionary form of one token.
    pub fn lemma_of(&self, surah_id: u32, ayah_id: u32, token: usize) -> Option<(u32, morphology::Lemma)> {
        let (_, lemmas) = self.morphology_ids(surah_id, ayah_id)?;
        let id = *lemmas.get(token)?;
        Some((id, self.lemma(id)?))
    }

    fn morphology_index(&self) -> &morphology::MorphologyIndex {
        self.morphology_index
            .get_or_init(|| morphology::MorphologyIndex::build(&self.morphology))
    }

    /// Every word carrying this root, in mushaf order.
    pub fn occurrences_of_root(&self, id: u32) -> &[morphology::WordLocation] {
        self.morphology_index().by_root.get(&id).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Every word carrying this lemma, in mushaf order.
    pub fn occurrences_of_lemma(&self, id: u32) -> &[morphology::WordLocation] {
        self.morphology_index().by_lemma.get(&id).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Roots whose Arabic or Buckwalter spelling starts with the query.
    pub fn find_roots(&self, query: &str, limit: usize) -> Vec<morphology::RootHit> {
        morphology::prefix_hits(&self.morphology.roots, query, limit)
            .into_iter()
            .filter_map(|id| Some(morphology::RootHit { id: id as u32, root: self.root(id as u32)? }))
            .collect()
    }

    /// Dictionary forms whose marked or unmarked spelling starts with the query.
    pub fn find_lemmas(&self, query: &str, limit: usize) -> Vec<morphology::LemmaHit> {
        morphology::prefix_hits(&self.morphology.lemmas, query, limit)
            .into_iter()
            .filter_map(|id| Some(morphology::LemmaHit { id: id as u32, lemma: self.lemma(id as u32)? }))
            .collect()
    }

    /// Corpus size: roots, lemmas, and the tokens they cover.
    pub fn morphology_count(&self) -> (usize, usize, usize) {
        let tokens = self
            .morphology
            .root_ids
            .values()
            .flat_map(|ayahs| ayahs.iter())
            .map(Vec::len)
            .sum();
        (self.morphology.roots.len(), self.morphology.lemmas.len(), tokens)
    }

    // -- mutashabihat ----------------------------------------------------------------

    /// One repeated phrase by id.
    pub fn mutashabihat_phrase(&self, id: u32) -> Option<batch5::Phrase> {
        let row = self.mutashabihat.phrases.get(&id.to_string())?;
        Some(batch5::Phrase {
            id,
            source: row.source.clone(),
            span: row.span,
            count: row.count,
            ayah_count: row.ayah_count,
            surah_count: row.surah_count,
            occurrences: row.occurrences.clone(),
            word_count: row.span[1] - row.span[0] + 1,
        })
    }

    /// The phrases this ayah carries, longest first so the most distinctive wording leads.
    pub fn mutashabihat_for(&self, surah_id: u32, ayah_id: u32) -> Vec<batch5::Phrase> {
        let key = format!("{surah_id}:{ayah_id}");
        let mut out: Vec<batch5::Phrase> = self
            .mutashabihat
            .index
            .get(&key)
            .map(Vec::as_slice)
            .unwrap_or(&[])
            .iter()
            .filter_map(|&id| self.mutashabihat_phrase(id))
            .collect();
        out.sort_by(|a, b| b.word_count.cmp(&a.word_count).then(a.id.cmp(&b.id)));
        out
    }

    /// Whether the ayah carries any: a map hit, cheap enough to gate a button on.
    pub fn has_mutashabihat(&self, surah_id: u32, ayah_id: u32) -> bool {
        self.mutashabihat
            .index
            .get(&format!("{surah_id}:{ayah_id}"))
            .is_some_and(|ids| !ids.is_empty())
    }

    /// A phrase's occurrences in mushaf order, not key order.
    pub fn phrase_occurrences(&self, id: u32) -> Vec<batch5::PhraseOccurrence> {
        let Some(phrase) = self.mutashabihat_phrase(id) else {
            return Vec::new();
        };
        let mut keys: Vec<&String> = phrase.occurrences.keys().collect();
        keys.sort_by_key(|key| batch5::split_ayah_key(key));
        keys.into_iter()
            .map(|key| {
                let (surah, ayah) = batch5::split_ayah_key(key);
                batch5::PhraseOccurrence {
                    surah,
                    ayah,
                    key: key.clone(),
                    spans: phrase.occurrences[key].clone(),
                }
            })
            .collect()
    }

    /// The phrase's own words, sliced out of the ayah text you hand it. The engine does not carry
    /// the text in here: the caller already has the ayah it is displaying.
    pub fn phrase_text(&self, id: u32, source_ayah_text: &str) -> String {
        let Some(phrase) = self.mutashabihat_phrase(id) else {
            return String::new();
        };
        let tokens: Vec<&str> = source_ayah_text.split_whitespace().collect();
        if phrase.span[1] >= tokens.len() {
            return String::new();
        }
        tokens[phrase.span[0]..=phrase.span[1]].join(" ")
    }

    /// How many phrases there are, and how many ayahs carry one.
    pub fn mutashabihat_count(&self) -> (usize, usize) {
        (self.mutashabihat.phrases.len(), self.mutashabihat.index.len())
    }

    // -- QUL topics ------------------------------------------------------------------

    fn qul_topic_index(&self) -> &batch5::QulTopicIndex {
        self.qul_topic_index
            .get_or_init(|| batch5::QulTopicIndex::build(&self.qul_topics))
    }

    /// Every topic, in corpus order.
    pub fn qul_topics(&self) -> &[batch5::QulTopic] {
        &self.qul_topics
    }

    /// One topic.
    pub fn qul_topic(&self, id: u32) -> Option<&batch5::QulTopic> {
        let position = *self.qul_topic_index().by_id.get(&id)?;
        self.qul_topics.get(position)
    }

    /// The topics an index lists.
    pub fn topics_in_tree(&self, tree: batch5::TopicTree) -> Vec<&batch5::QulTopic> {
        self.qul_topics.iter().filter(|topic| topic.listed_in(tree)).collect()
    }

    /// Topics an index lists that have no parent in that same tree.
    pub fn topic_roots(&self, tree: batch5::TopicTree) -> Vec<&batch5::QulTopic> {
        self.qul_topics
            .iter()
            .filter(|topic| topic.listed_in(tree) && topic.parent_in(tree).is_none())
            .collect()
    }

    /// The parent in one tree. `None` for the tree means the topic's first listed index, which is
    /// a convenience for a caller that does not care.
    pub fn topic_parent(&self, id: u32, tree: Option<batch5::TopicTree>) -> Option<&batch5::QulTopic> {
        let topic = self.qul_topic(id)?;
        let which = tree.or_else(|| topic.default_tree())?;
        self.qul_topic(topic.parent_in(which)?)
    }

    /// Direct children in one tree, in id order.
    pub fn topic_children(&self, id: u32, tree: Option<batch5::TopicTree>) -> Vec<&batch5::QulTopic> {
        let Some(topic) = self.qul_topic(id) else {
            return Vec::new();
        };
        let Some(which) = tree.or_else(|| topic.default_tree()) else {
            return Vec::new();
        };
        self.qul_topic_index()
            .children
            .get(&(which, id))
            .map(Vec::as_slice)
            .unwrap_or(&[])
            .iter()
            .filter_map(|&child| self.qul_topic(child))
            .collect()
    }

    /// The chain up to the root of one tree, nearest first. Cycle-safe: the corpus is trusted for
    /// its content, not for its shape.
    pub fn topic_ancestors(&self, id: u32, tree: Option<batch5::TopicTree>) -> Vec<&batch5::QulTopic> {
        let Some(topic) = self.qul_topic(id) else {
            return Vec::new();
        };
        let Some(which) = tree.or_else(|| topic.default_tree()) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        let mut seen = std::collections::HashSet::from([id]);
        let mut current = self.topic_parent(id, Some(which));
        while let Some(parent) = current {
            if !seen.insert(parent.id) {
                break;
            }
            out.push(parent);
            current = self.topic_parent(parent.id, Some(which));
        }
        out
    }

    /// Every topic annotating this ayah, across all three indexes.
    pub fn qul_topics_for(&self, surah_id: u32, ayah_id: u32) -> Vec<&batch5::QulTopic> {
        self.qul_topic_index()
            .by_ayah
            .get(&format!("{surah_id}:{ayah_id}"))
            .map(Vec::as_slice)
            .unwrap_or(&[])
            .iter()
            .filter_map(|&id| self.qul_topic(id))
            .collect()
    }

    /// Name and Arabic-name substring search, exact-prefix hits first.
    pub fn search_qul_topics(&self, query: &str, limit: usize) -> Vec<&batch5::QulTopic> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }
        let mut starts = Vec::new();
        let mut contains = Vec::new();
        for topic in &self.qul_topics {
            let name = topic.name.to_lowercase();
            if name.starts_with(&q) {
                starts.push(topic);
            } else if name.contains(&q) || topic.arabic.contains(query) {
                contains.push(topic);
            }
            if limit > 0 && starts.len() >= limit {
                break;
            }
        }
        starts.extend(contains);
        if limit > 0 {
            starts.truncate(limit);
        }
        starts
    }

    /// Corpus size. The per-index counts deliberately sum to MORE than the topic count: the 17
    /// topics listed in two indexes are counted in both.
    pub fn qul_topic_count(&self) -> (usize, usize, usize, usize, usize) {
        let mut thematic = 0;
        let mut ontology = 0;
        let mut index = 0;
        let mut references = 0;
        for topic in &self.qul_topics {
            for family in &topic.families {
                match family {
                    batch5::TopicTree::Thematic => thematic += 1,
                    batch5::TopicTree::Ontology => ontology += 1,
                    batch5::TopicTree::Index => index += 1,
                }
            }
            references += topic.ayahs.len();
        }
        (self.qul_topics.len(), thematic, ontology, index, references)
    }

    // -- passage themes --------------------------------------------------------------

    /// A surah's passages, in order.
    pub fn passages(&self, surah_id: u32) -> &[batch5::ThemePassage] {
        self.ayah_themes.get(&surah_id.to_string()).map(Vec::as_slice).unwrap_or(&[])
    }

    /// The passage an ayah falls in. Passages do not overlap, so this is the one answer; `None`
    /// for an ayah between two of them.
    pub fn passage_for(&self, surah_id: u32, ayah_id: u32) -> Option<&batch5::ThemePassage> {
        self.passages(surah_id)
            .iter()
            .find(|passage| ayah_id >= passage.from && ayah_id <= passage.to)
    }

    /// Matches the theme sentence and the topic it sits under.
    pub fn search_passages(&self, query: &str, limit: usize) -> Vec<(u32, &batch5::ThemePassage)> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }
        let mut out = Vec::new();
        for surah in &self.surahs {
            for passage in self.passages(surah.id) {
                if passage.theme.to_lowercase().contains(&q)
                    || passage.topic.to_lowercase().contains(&q)
                {
                    out.push((surah.id, passage));
                    if limit > 0 && out.len() >= limit {
                        return out;
                    }
                }
            }
        }
        out
    }

    /// How many surahs carry an outline, and how many passages there are.
    pub fn passage_count(&self) -> (usize, usize) {
        (self.ayah_themes.len(), self.ayah_themes.values().map(Vec::len).sum())
    }

    // -- hizb / ruku / manzil --------------------------------------------------------

    fn division_starts(&self, kind: batch5::DivisionKind) -> &[String] {
        match kind {
            batch5::DivisionKind::Hizb => &self.quran_metadata.hizb,
            batch5::DivisionKind::Ruku => &self.quran_metadata.ruku,
            batch5::DivisionKind::Manzil => &self.quran_metadata.manzil,
        }
    }

    /// How many of a kind there are.
    pub fn division_count(&self, kind: batch5::DivisionKind) -> usize {
        self.division_starts(kind).len()
    }

    /// The 1-based number containing an ayah, or 0 when there is no table.
    pub fn division_for(&self, kind: batch5::DivisionKind, surah_id: u32, ayah_id: u32) -> usize {
        let starts = self.division_starts(kind);
        let target = surah_id * 1000 + ayah_id;
        starts.partition_point(|key| {
            let (surah, ayah) = batch5::split_ayah_key(key);
            surah * 1000 + ayah <= target
        })
    }

    /// Where a division begins.
    pub fn division_start(&self, kind: batch5::DivisionKind, number: usize) -> Option<batch5::Division> {
        let key = self.division_starts(kind).get(number.checked_sub(1)?)?;
        let (surah, ayah) = batch5::split_ayah_key(key);
        Some(batch5::Division { number, surah, ayah, key: key.clone() })
    }

    /// Every start of a kind, in order.
    pub fn divisions(&self, kind: batch5::DivisionKind) -> Vec<batch5::Division> {
        (1..=self.division_count(kind))
            .filter_map(|n| self.division_start(kind, n))
            .collect()
    }

    /// A division's start, and the start of the next one, which is where it ends. The second is
    /// `None` for the last, which runs to the end of the Quran: no start key says so, and
    /// pretending otherwise would be an invented boundary.
    pub fn division_range(
        &self,
        kind: batch5::DivisionKind,
        number: usize,
    ) -> Option<(batch5::Division, Option<batch5::Division>)> {
        let from = self.division_start(kind, number)?;
        Some((from, self.division_start(kind, number + 1)))
    }

    /// All three at once, which is what a "where am I" line under an ayah wants.
    pub fn divisions_for(&self, surah_id: u32, ayah_id: u32) -> (usize, usize, usize) {
        (
            self.division_for(batch5::DivisionKind::Hizb, surah_id, ayah_id),
            self.division_for(batch5::DivisionKind::Ruku, surah_id, ayah_id),
            self.division_for(batch5::DivisionKind::Manzil, surah_id, ayah_id),
        )
    }

    // -- qiraat variants -------------------------------------------------------------

    /// The words of this ayah that the Ten read differently, in corpus order.
    pub fn junctures(&self, surah_id: u32, ayah_id: u32) -> &[batch5::Juncture] {
        self.qiraat_variants
            .ayahs
            .get(&format!("{surah_id}:{ayah_id}"))
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    /// Whether the ayah carries any. Only 1,409 of the 6,236 do.
    pub fn has_qiraat_variants(&self, surah_id: u32, ayah_id: u32) -> bool {
        !self.junctures(surah_id, ayah_id).is_empty()
    }

    /// One of the ten imams.
    pub fn variant_reader(&self, id: u32) -> Option<&batch5::VariantReader> {
        self.qiraat_variants.readers.get(&id.to_string())
    }

    /// One of the twenty transmitters.
    pub fn variant_transmitter(&self, id: u32) -> Option<&batch5::VariantTransmitter> {
        self.qiraat_variants.transmitters.get(&id.to_string())
    }

    /// Every transmitter reading a form: an imam's own pair, plus any listed individually.
    pub fn transmitters_following(
        &self,
        reading: &batch5::VariantReading,
    ) -> Vec<&batch5::VariantTransmitter> {
        let mut out = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for &reader_id in &reading.readers {
            let mut ids: Vec<u32> = self
                .qiraat_variants
                .transmitters
                .values()
                .filter(|t| t.reader == reader_id)
                .map(|t| t.id)
                .collect();
            ids.sort_unstable();
            for id in ids {
                if seen.insert(id) {
                    if let Some(t) = self.variant_transmitter(id) {
                        out.push(t);
                    }
                }
            }
        }
        for &id in &reading.transmitters {
            if seen.insert(id) {
                if let Some(t) = self.variant_transmitter(id) {
                    out.push(t);
                }
            }
        }
        out
    }

    /// The reading a riwayah follows at a juncture, by engine slug.
    ///
    /// A reading names an imam when BOTH his transmitters follow it, and names a transmitter when
    /// the two part company, so a transmitter named on one reading overrides his imam's listing on
    /// a sibling. Look for him across the whole juncture before falling back to the imams: at
    /// 12:109 ʿĀṣim is named on نوحي while Shuʿbah is named on يوحى, and Shuʿbah recites يوحى.
    pub fn reading_for<'a>(
        &'a self,
        juncture: &'a batch5::Juncture,
        riwayah: &str,
    ) -> Option<&'a batch5::VariantReading> {
        let named = juncture.readings.iter().find(|reading| {
            reading.transmitters.iter().any(|&id| {
                self.variant_transmitter(id).map(|t| t.riwayah.as_deref() == Some(riwayah))
                    == Some(true)
            })
        });
        if named.is_some() {
            return named;
        }
        juncture.readings.iter().find(|reading| {
            reading.readers.iter().any(|&reader_id| {
                self.qiraat_variants
                    .transmitters
                    .values()
                    .any(|t| t.reader == reader_id && t.riwayah.as_deref() == Some(riwayah))
            })
        })
    }

    /// Who reads a form, rendered the way the printed sources do: the imams first in their
    /// canonical order, then any lone transmitters with their imam named in parentheses.
    pub fn variant_attribution(&self, reading: &batch5::VariantReading) -> String {
        let mut readers: Vec<&batch5::VariantReader> =
            reading.readers.iter().filter_map(|&id| self.variant_reader(id)).collect();
        readers.sort_by_key(|reader| reader.position);

        let mut transmitters: Vec<&batch5::VariantTransmitter> =
            reading.transmitters.iter().filter_map(|&id| self.variant_transmitter(id)).collect();
        transmitters.sort_by_key(|t| {
            (self.variant_reader(t.reader).map_or(99, |r| r.position), t.id)
        });

        let mut parts = Vec::new();
        if !readers.is_empty() {
            parts.push(
                readers.iter().map(|r| r.abbreviation.as_str()).collect::<Vec<_>>().join(", "),
            );
        }
        if !transmitters.is_empty() {
            parts.push(
                transmitters
                    .iter()
                    .map(|t| match self.variant_reader(t.reader) {
                        Some(imam) if !imam.abbreviation.is_empty() => {
                            format!("{} ({})", t.name, imam.abbreviation)
                        }
                        _ => t.name.clone(),
                    })
                    .collect::<Vec<_>>()
                    .join(", "),
            );
        }
        parts.join(" · ")
    }

    /// Where a riwayah differs from Hafs in a surah, in ayah order.
    pub fn qiraat_places(&self, riwayah: &str, surah_id: u32) -> Vec<batch5::QiraatPlace> {
        let Some(table) = self
            .qiraat_places
            .riwayat
            .get(riwayah)
            .and_then(|surahs| surahs.get(&surah_id.to_string()))
        else {
            return Vec::new();
        };
        let mut ayahs: Vec<u32> = table.keys().filter_map(|k| k.parse().ok()).collect();
        ayahs.sort_unstable();
        ayahs
            .into_iter()
            .filter_map(|ayah| {
                let row = table.get(&ayah.to_string())?;
                Some(batch5::QiraatPlace {
                    ayah,
                    word: row.word.clone(),
                    letter: row.letter.clone(),
                })
            })
            .collect()
    }

    /// The riwayat `qiraat_places` can answer for: the published ones.
    pub fn riwayat_with_places(&self) -> Vec<String> {
        let mut out: Vec<String> = self.qiraat_places.riwayat.keys().cloned().collect();
        out.sort();
        out
    }

    /// One reciter reading the verse both ways, for the four riwayat where such a recording
    /// exists.
    ///
    /// The rest carry none: no reciter published both sides with timings. A pair drawn from two
    /// shaykhs would differ in voice, pace and maqam as well, and teach nothing about the
    /// variant. The honest rendering is "no recording", never a button that does nothing.
    pub fn variant_audio(
        &self,
        riwayah: &str,
        surah_id: u32,
        ayah_id: u32,
    ) -> Option<batch5::VariantAudioPair> {
        let rows = self
            .qiraat_variant_audio
            .riwayat
            .get(riwayah)?
            .get(&surah_id.to_string())?;
        let row = rows.iter().find(|row| row.first() == Some(&(ayah_id as i64)))?;
        if row.len() < 6 {
            return None;
        }
        let source = self.qiraat_variant_audio.sources.get(usize::try_from(row[1]).ok()?)?;
        let is_span = source.kind == "span";
        let name = if is_span {
            format!("{surah_id:03}.mp3")
        } else {
            format!("{surah_id:03}{ayah_id:03}.mp3")
        };
        let clip = |base: &str, start: i64, end: i64| batch5::VariantClip {
            url: format!("{base}/{name}"),
            start_ms: is_span.then_some(start),
            end_ms: is_span.then_some(end),
        };
        Some(batch5::VariantAudioPair {
            reciter: source.reciter.clone(),
            hafs: clip(&source.hafs_base, row[2], row[3]),
            riwayah: clip(&source.riwayah_base, row[4], row[5]),
        })
    }

    /// The riwayat that have any paired recordings at all.
    pub fn riwayat_with_audio(&self) -> Vec<String> {
        let mut out: Vec<String> = self.qiraat_variant_audio.riwayat.keys().cloned().collect();
        out.sort();
        out
    }

    /// Corpus size: ayahs carrying a variant, junctures, and readings.
    pub fn qiraat_variant_count(&self) -> (usize, usize, usize) {
        let junctures: usize = self.qiraat_variants.ayahs.values().map(Vec::len).sum();
        let readings: usize = self
            .qiraat_variants
            .ayahs
            .values()
            .flat_map(|rows| rows.iter())
            .map(|row| row.readings.len())
            .sum();
        (self.qiraat_variants.ayahs.len(), junctures, readings)
    }

    // -- word of the day -------------------------------------------------------------

    /// The whole corpus, in curation order. The order is deliberate: the themes are interleaved
    /// so consecutive days feel varied, which is why the day mapping is a walk and not a hash.
    pub fn words_of_day(&self) -> &[batch5::WordOfDayEntry] {
        &self.words_of_day
    }

    /// One curated word.
    pub fn word_of_day(&self, id: &str) -> Option<&batch5::WordOfDayEntry> {
        self.words_of_day.iter().find(|word| word.id == id)
    }

    /// The word for a day number: the corpus walked in order, wrapping.
    ///
    /// Take this rather than a date if your app has its own idea of when a day turns over (the
    /// upstream app rolls at Fajr, not midnight): hand it your own day number and the mapping is
    /// identical.
    pub fn word_of_day_for_index(&self, day_index: i64) -> Option<&batch5::WordOfDayEntry> {
        let n = self.words_of_day.len();
        if n == 0 {
            return None;
        }
        let n = n as i64;
        self.words_of_day.get((((day_index % n) + n) % n) as usize)
    }

    /// Matches the written form, the transliteration and the gloss.
    pub fn search_words_of_day(&self, query: &str, limit: usize) -> Vec<&batch5::WordOfDayEntry> {
        let q = query.trim();
        if q.is_empty() {
            return Vec::new();
        }
        let lower = q.to_lowercase();
        self.words_of_day
            .iter()
            .filter(|word| {
                word.arabic.contains(q)
                    || word.transliteration.to_lowercase().contains(&lower)
                    || word.meaning.to_lowercase().contains(&lower)
            })
            .take(if limit == 0 { usize::MAX } else { limit })
            .collect()
    }

    /// Every curated word appearing in an ayah.
    pub fn words_of_day_in(&self, surah_id: u32, ayah_id: u32) -> Vec<&batch5::WordOfDayEntry> {
        self.words_of_day
            .iter()
            .filter(|word| {
                word.occurrences
                    .iter()
                    .any(|o| o.surah == surah_id && o.ayah == ayah_id)
            })
            .collect()
    }

    /// How many words there are, and how many occurrences they cover.
    pub fn word_of_day_count(&self) -> (usize, usize) {
        (
            self.words_of_day.len(),
            self.words_of_day.iter().map(|word| word.count as usize).sum(),
        )
    }

    // -- the Names in depth ----------------------------------------------------------

    /// All 99, ordered by number.
    pub fn names_in_depth(&self) -> &[batch6::NameDepth] {
        &self.names_depth.names
    }

    /// One Name's depth entry, by its number (1..=99).
    pub fn name_in_depth(&self, number: u32) -> Option<&batch6::NameDepth> {
        self.names_depth.names.iter().find(|name| name.number == number)
    }

    /// The nine themes, in the corpus's own order.
    pub fn name_themes(&self) -> &[batch6::NameTheme] {
        &self.names_depth.themes
    }

    /// Every Name under one theme, by number.
    pub fn names_by_theme(&self, theme: &str) -> Vec<&batch6::NameDepth> {
        self.names_depth.names.iter().filter(|name| name.theme == theme).collect()
    }

    /// Every Name built on one root. Accepts either spelling, spaced or closed up.
    pub fn names_by_root(&self, root: &str) -> Vec<&batch6::NameDepth> {
        let key = batch6::root_key(root);
        if key.is_empty() {
            return Vec::new();
        }
        self.names_depth
            .names
            .iter()
            .filter(|name| batch6::root_key(&name.root) == key)
            .collect()
    }

    /// Every Name appearing in an ayah, with the occurrence that put it there, in token order.
    pub fn names_in_ayah(&self, surah_id: u32, ayah_id: u32) -> Vec<(&batch6::NameDepth, &batch6::NameOccurrence)> {
        let mut hits: Vec<(&batch6::NameDepth, &batch6::NameOccurrence)> = self
            .names_depth
            .names
            .iter()
            .flat_map(|name| {
                name.occurrences
                    .iter()
                    .filter(move |o| o.surah == surah_id && o.ayah == ayah_id)
                    .map(move |o| (name, o))
            })
            .collect();
        // Unplaced occurrences (a `None` token) sort last, so a highlighted list stays in
        // reading order.
        hits.sort_by_key(|(_, o)| o.token.unwrap_or(usize::MAX));
        hits
    }

    /// Matches the root (spaces closed on both sides), the explanation and the living line.
    pub fn search_names_in_depth(&self, query: &str, limit: usize) -> Vec<&batch6::NameDepth> {
        let q = query.trim();
        if q.is_empty() {
            return Vec::new();
        }
        let lower = q.to_lowercase();
        let key = batch6::root_key(q);
        self.names_depth
            .names
            .iter()
            .filter(|name| {
                (!key.is_empty() && batch6::root_key(&name.root).contains(&key))
                    || name.explanation.to_lowercase().contains(&lower)
                    || name.living.to_lowercase().contains(&lower)
            })
            .take(if limit == 0 { usize::MAX } else { limit })
            .collect()
    }

    /// How many Names carry depth, how many themes, and how many occurrences they cover.
    pub fn names_depth_count(&self) -> (usize, usize, usize) {
        (
            self.names_depth.names.len(),
            self.names_depth.themes.len(),
            self.names_depth.names.iter().map(|n| n.occurrences.len()).sum(),
        )
    }

    // -- the chains of transmission --------------------------------------------------

    /// The Prophet, the head of every chain.
    pub fn isnad_prophet(&self) -> Option<&batch6::IsnadNode> {
        self.isnad.prophet.as_ref()
    }

    /// The thirteen Companions the readings are transmitted from.
    pub fn isnad_companions(&self) -> &[batch6::IsnadNode] {
        &self.isnad.companions
    }

    /// The ten imams' keys, sorted.
    pub fn isnad_imam_keys(&self) -> Vec<&str> {
        let mut keys: Vec<&str> = self.isnad.imams.keys().map(String::as_str).collect();
        keys.sort_unstable();
        keys
    }

    /// The twenty riwayah tags, sorted.
    pub fn isnad_narrator_keys(&self) -> Vec<&str> {
        let mut keys: Vec<&str> = self.isnad.narrators.keys().map(String::as_str).collect();
        keys.sort_unstable();
        keys
    }

    /// One imam's side of the chain.
    pub fn isnad_imam(&self, imam: &str) -> Option<&batch6::ImamChain> {
        self.isnad.imams.get(imam)
    }

    /// One narrator's side of the chain.
    pub fn isnad_narrator(&self, riwayah: &str) -> Option<&batch6::NarratorChain> {
        self.isnad.narrators.get(riwayah)
    }

    /// Whether a narrator read on his imam himself, with nobody between them.
    pub fn isnad_reads_directly(&self, riwayah: &str) -> bool {
        self.isnad.narrators.get(riwayah).is_some_and(|c| c.links.is_empty())
    }

    /// The imam a riwayah tag belongs to ("Warsh an Nafi" -> "Nafi").
    pub fn isnad_imam_of(&self, riwayah: &str) -> Option<String> {
        batch6::imam_of(&self.isnad, riwayah)
    }

    /// A whole chain as layers: a riwayah tag for one narration, an imam key for a reading.
    pub fn isnad_chain(&self, key: &str) -> Vec<batch6::IsnadLayer> {
        batch6::chain(&self.isnad, key)
    }

    /// One sentence on how a narrator reaches his imam.
    pub fn isnad_sentence(&self, riwayah: &str) -> String {
        batch6::sentence(&self.isnad, riwayah)
    }

    /// How many imams, narrators and Companions the chains cover.
    pub fn isnad_count(&self) -> (usize, usize, usize) {
        (
            self.isnad.imams.len(),
            self.isnad.narrators.len(),
            self.isnad.companions.len(),
        )
    }

    // -- the scientific-miracles corpus ----------------------------------------------

    /// All 202 articles, in corpus order.
    pub fn miracles(&self) -> &[miracles::MiracleArticle] {
        &self.miracles.articles
    }

    /// One article, by its slug.
    pub fn miracle(&self, slug: &str) -> Option<&miracles::MiracleArticle> {
        self.miracles.articles.iter().find(|a| a.slug == slug)
    }

    /// The fifteen categories, in the corpus's own order.
    pub fn miracle_categories(&self) -> &[miracles::MiracleCategory] {
        &self.miracles.categories
    }

    /// One category, by its id.
    pub fn miracle_category(&self, id: &str) -> Option<&miracles::MiracleCategory> {
        self.miracles.categories.iter().find(|c| c.id == id)
    }

    /// Every article filed under one category.
    pub fn miracles_by_category(&self, id: &str) -> Vec<&miracles::MiracleArticle> {
        self.miracles.articles.iter().filter(|a| a.category == id).collect()
    }

    /// Every article at one level.
    ///
    /// The ARTICLE's level, not its category's: they disagree far more often than they agree, and
    /// a reader who picked "simple" means the article.
    pub fn miracles_by_level(&self, level: &str) -> Vec<&miracles::MiracleArticle> {
        self.miracles.articles.iter().filter(|a| a.level == level).collect()
    }

    /// The article levels actually present, easiest first.
    pub fn miracle_levels(&self) -> Vec<&str> {
        let mut present: Vec<&str> =
            self.miracles.articles.iter().map(|a| a.level.as_str()).collect();
        present.sort_unstable_by_key(|level| (miracles::level_rank(level), *level));
        present.dedup();
        present
    }

    /// Every article that cites an ayah: the way into this corpus from elsewhere in the engine.
    ///
    /// An `ayah` block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An
    /// article that cites the same ayah in two blocks is still listed once.
    pub fn miracles_citing(&self, surah_id: u32, ayah_id: u32) -> Vec<&miracles::MiracleArticle> {
        self.miracles
            .articles
            .iter()
            .filter(|a| miracles::article_cites(a, surah_id, ayah_id))
            .collect()
    }

    /// The ayah ranges one article cites, in the order it cites them.
    pub fn miracle_ayah_refs(&self, slug: &str) -> Vec<miracles::MiracleAyahRef> {
        self.miracle(slug).map(miracles::article_ayah_refs).unwrap_or_default()
    }

    /// Articles whose title or prose matches a query, case-insensitively.
    ///
    /// Quotes are searched as well: a reader looking for a word remembers reading it, not who
    /// wrote it.
    pub fn search_miracles(&self, query: &str, limit: usize) -> Vec<&miracles::MiracleArticle> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }
        self.miracles
            .articles
            .iter()
            .filter(|a| {
                a.title.to_lowercase().contains(&q)
                    || a.blocks.iter().any(|b| b.text.to_lowercase().contains(&q))
            })
            .take(limit)
            .collect()
    }

    /// One article's own prose, quotes and ayah blocks left out. See [`miracles::article_text`].
    pub fn miracle_text(&self, slug: &str) -> String {
        self.miracle(slug).map(miracles::article_text).unwrap_or_default()
    }

    /// Where the corpus came from and when it was captured.
    pub fn miracles_source(&self) -> &str {
        &self.miracles.source
    }

    /// False, always: the illustrations are not republished.
    pub fn miracles_images_included(&self) -> bool {
        self.miracles.images_included
    }

    /// How many articles, categories and ayah refs the corpus carries.
    pub fn miracles_count(&self) -> (usize, usize, usize) {
        (
            self.miracles.articles.len(),
            self.miracles.categories.len(),
            self.miracles
                .articles
                .iter()
                .map(|a| a.blocks.iter().filter(|b| b.kind == "ayah").count())
                .sum(),
        )
    }
}

