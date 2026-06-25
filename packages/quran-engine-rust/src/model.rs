//! Data model: serde structs mirroring the JSON shapes in `/data`.
//!
//! All field names use `#[serde(rename_all = "camelCase")]` so they line up with the
//! JSON keys (`textArabic`, `nameEnglish`, `ayahIdentifier`, …). Optional fields are
//! `Option<T>` so the structs survive minor schema variation.

use serde::{Deserialize, Serialize};

/// A single ayah (verse) within a surah. Mirrors an element of `surah.ayahs` in `quran.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ayah {
    /// Ayah number within the surah (1-based).
    pub id: u32,
    /// Hafs Uthmani Arabic text (full diacritics).
    pub text_arabic: String,
    #[serde(default)]
    pub text_transliteration: String,
    /// Saheeh International translation.
    #[serde(default)]
    pub text_english_saheeh: String,
    /// Mustafa Khattab (The Clear Quran) translation.
    #[serde(default)]
    pub text_english_mustafa: String,
    #[serde(default)]
    pub juz: Option<u32>,
    #[serde(default)]
    pub page: Option<u32>,
    #[serde(default)]
    pub word_count: Option<u32>,
    #[serde(default)]
    pub letter_count: Option<u32>,
}

/// A surah (chapter). Top-level element of the `quran.json` array.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Surah {
    /// Surah id, 1..=114.
    pub id: u32,
    /// "makkan" | "madinan" (revelation place).
    #[serde(default)]
    pub r#type: String,
    pub name_arabic: String,
    pub name_transliteration: String,
    pub name_english: String,
    pub number_of_ayahs: u32,
    #[serde(default)]
    pub page_start: Option<u32>,
    #[serde(default)]
    pub page_end: Option<u32>,
    #[serde(default)]
    pub number_of_pages: Option<u32>,
    #[serde(default)]
    pub first_juz: Option<u32>,
    #[serde(default)]
    pub last_juz: Option<u32>,
    #[serde(default)]
    pub juzs: Vec<u32>,
    #[serde(default)]
    pub revelation_order: Option<u32>,
    #[serde(default)]
    pub similar_names: Vec<String>,
    #[serde(default)]
    pub word_count: Option<u32>,
    #[serde(default)]
    pub letter_count: Option<u32>,
    pub ayahs: Vec<Ayah>,
}

/// A juz (para) boundary entry. Top-level element of the `juz.json` array.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JuzEntry {
    pub id: u32,
    pub name_arabic: String,
    pub name_transliteration: String,
    pub start_surah: u32,
    pub start_ayah: u32,
    pub end_surah: u32,
    pub end_ayah: u32,
}

/// A reciter directory entry. Top-level element of the `reciters.json` array.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reciter {
    /// `"{name}|{qiraah??'Hafs'}|{surahLink}"`.
    pub id: String,
    pub name: String,
    /// Used by ayah-by-ayah audio, e.g. `"ar.alafasy"`.
    pub ayah_identifier: String,
    /// String, inserted verbatim into the ayah URL, e.g. `"128"`.
    pub ayah_bitrate: String,
    /// Full-surah CDN base, trailing slash.
    pub surah_link: String,
    /// `null` => Hafs; else a riwayah label.
    #[serde(default)]
    pub qiraah: Option<String>,
    #[serde(default)]
    pub group: Option<String>,
}

/// A resolved, colored tajweed span over an ayah's Arabic text.
///
/// `start`/`end` are UTF-16 code-unit offsets into the ayah text (the on-disk annotation
/// offsets, preserved verbatim). `text` is the reconstructed slice, and `color` is the
/// `colorHex` for the rule's category from `tajweed-rules.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TajweedSpan {
    /// UTF-16 start offset (inclusive).
    pub start: usize,
    /// UTF-16 end offset (exclusive).
    pub end: usize,
    /// Rule / category id, e.g. `"tafkhim"`, `"maddNatural"`.
    pub rule: String,
    /// Canonical color hex for the rule, e.g. `"#3B85C2"` (if found in the rules catalogue).
    pub color: Option<String>,
    /// The reconstructed text slice (`text == utf16_slice(ayah, start, end)`).
    pub text: String,
}

// ---- internal-only deserialization helpers ---------------------------------------

/// One ayah's pre-computed annotations (`tajweed-annotations.json` / `tajweed/NNN.json`).
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AyahAnnotations {
    pub surah: u32,
    pub ayah: u32,
    #[serde(default)]
    pub annotations: Vec<Annotation>,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct Annotation {
    pub start: usize,
    pub end: usize,
    pub rule: String,
}

/// A category from `tajweed-rules.json` (only the fields we consume).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct TajweedCategory {
    pub id: String,
    #[serde(default)]
    pub color_hex: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct TajweedRules {
    #[serde(default)]
    pub categories: Vec<TajweedCategory>,
}
