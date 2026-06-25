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

use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub mod audio;
pub mod cache;
pub mod model;
pub mod search;
pub mod sorting;
pub mod text;
pub mod util;

pub use audio::{ayah_audio_url, ayah_now_playing_name, defaults_to_minshawi, surah_audio_url};
pub use cache::{local_surah_path, sanitize_reciter_dir, shared_audio_path};
pub use model::{Ayah, JuzEntry, Reciter, Surah, TajweedSpan};
pub use search::{Reference, SearchOpts, VerseHit};
pub use sorting::{
    filter_by_revelation_type, sort_surahs, SortDirection, SortMode,
};
pub use util::{utf16_slice, zero_pad3};

use model::{AyahAnnotations, TajweedRules};
use search::SearchIndex;

/// A single annotation flattened to `(utf16_start, utf16_end, rule_id)`.
type AnnotationSpan = (usize, usize, String);
/// Map of `(surah, ayah)` -> the ayah's flattened annotations.
type AnnotationMap = HashMap<(u32, u32), Vec<AnnotationSpan>>;

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
    search: SearchIndex,
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

        let search = SearchIndex::build(&surahs);

        Ok(Engine {
            surahs,
            juz_list,
            reciters,
            rule_colors,
            annotations,
            cumulative_offset,
            total_ayahs,
            search,
        })
    }

    /// Load from the canonical repo `/data` directory, discovered by ascending from
    /// `CARGO_MANIFEST_DIR` (and the current working dir at runtime) until a `data/quran.json`
    /// is found.
    pub fn load_default() -> Result<Engine, LoadError> {
        let dir = find_data_dir()
            .ok_or_else(|| LoadError::NotFound("could not locate data/quran.json".into()))?;
        Engine::load(&dir)
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

    /// Iterate every `(surah, ayah)` pair in mushaf order.
    pub fn each_ayah(&self) -> impl Iterator<Item = (&Surah, &Ayah)> {
        self.surahs.iter().flat_map(|s| s.ayahs.iter().map(move |a| (s, a)))
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
}
