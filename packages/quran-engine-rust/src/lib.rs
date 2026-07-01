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

pub mod audio;
pub mod cache;
pub mod model;
pub mod search;
pub mod sorting;
pub mod text;
pub mod util;

pub use audio::{ayah_audio_url, ayah_now_playing_name, defaults_to_minshawi, surah_audio_url};
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

/// ۩ ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs.
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

    /// Ayah count of a surah in the given riwayah — the number of Hafs ayahs that exist there
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
    pub fn surah_info(&self, id: u32) -> &[SurahInfoSource] {
        self.surah_info.get(&id).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Whether an ayah is a sajdah (prostration) ayah — its Arabic text carries the ۩ mark
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

        // Regular (non-boolean) search is a PURE SUBSTRING — mid-word match: "orld" hits 1:2.
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
