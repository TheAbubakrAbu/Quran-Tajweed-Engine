//! The printed mushaf: twenty riwayat as page-exact facsimiles, and the page table each one is
//! actually paginated by.
//!
//! A riwayah's pagination is NOT Hafs' pagination. Readings merge and split ayahs and spell words
//! differently, so the same ayah sits on a different page in Warsh's print than in Hafs'. The page
//! numbers on `quran.json`'s ayahs are the Madani (Hafs) ones; [`Engine::mushaf_page`] is that
//! riwayah's own. Every facsimile is exactly 604 pages on the Madani division, so PDF page N is
//! mushaf page N with no offset table.
//!
//! Twelve of the twenty ship their printed mushaf and page table but no text: their text is
//! machine-extracted and not yet proofread, so it is not published, and the line and tajweed data
//! that index into it stay out with it. [`RiwayahEntry::text_included`] says which is which.
//!
//! See `../../docs/10-mushaf.md`.

use serde::Deserialize;
use std::collections::HashMap;

/// One row of `data/mushaf/index.json`.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RiwayahEntry {
    /// Slug, e.g. `"warsh"`.
    pub riwayah: String,
    /// The tag the Al-Islam app stores for this riwayah (`""` for Hafs).
    pub tag: String,
    pub name: String,
    pub name_arabic: String,
    /// The qiraah's imam, e.g. `"Nafi"`.
    pub imam: String,
    pub imam_arabic: String,
    /// The JSON spells this `narratorDiedAH`; camelCase renaming would look for `narratorDiedAh`.
    #[serde(rename = "narratorDiedAH")]
    pub narrator_died_ah: u32,
    /// Path to the facsimile, relative to `data/mushaf/`. One solid xz stream over the PDF.
    pub pdf: String,
    pub pdf_bytes: u64,
    pub pages: String,
    /// Path to the line table, or `None` when the text is not published.
    pub lines: Option<String>,
    /// Path to the riwayah tajweed pack, or `None`.
    pub tajweed: Option<String>,
    pub text_included: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MushafIndex {
    pub total_pages: u32,
    #[serde(default)]
    pub note: Option<String>,
    pub riwayat: Vec<RiwayahEntry>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MushafPageTable {
    pub riwayah: String,
    pub total_pages: u32,
    /// Surah id -> ayah id -> page.
    pub pages: HashMap<String, HashMap<String, u32>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MushafLineTable {
    pub riwayah: String,
    pub version: u32,
    /// Surah id -> ayah id -> character offsets at which a new printed line starts.
    pub line_breaks: HashMap<String, HashMap<String, Vec<usize>>>,
}

use crate::{Engine, VerseHit};

impl Engine {
    /// Every riwayah, in the classical order of the Ten Qiraat. Empty unless
    /// [`crate::LoadOptions::mushaf`].
    pub fn riwayat(&self) -> &[RiwayahEntry] {
        self.mushaf_index.as_ref().map(|i| i.riwayat.as_slice()).unwrap_or(&[])
    }

    /// Only the riwayat whose text this engine publishes (the eight verified ones).
    pub fn riwayat_with_text(&self) -> Vec<&RiwayahEntry> {
        self.riwayat().iter().filter(|r| r.text_included).collect()
    }

    pub fn riwayah(&self, slug: &str) -> Option<&RiwayahEntry> {
        self.riwayat().iter().find(|r| r.riwayah == slug)
    }

    /// 604 for every facsimile in the set.
    pub fn mushaf_total_pages(&self) -> u32 {
        self.mushaf_index.as_ref().map(|i| i.total_pages).unwrap_or(604)
    }

    /// The facsimile's path, relative to `data/mushaf/`. It is one solid xz stream over the PDF:
    /// decompress it before handing the bytes to a PDF renderer.
    pub fn mushaf_pdf_path(&self, slug: &str) -> Option<&str> {
        self.riwayah(slug).map(|r| r.pdf.as_str())
    }

    /// The page an ayah is printed on in this riwayah's own mushaf.
    pub fn mushaf_page(&self, surah: u32, ayah: u32, riwayah: &str) -> Option<u32> {
        self.mushaf_pages
            .get(riwayah)?
            .pages
            .get(&surah.to_string())?
            .get(&ayah.to_string())
            .copied()
    }

    /// Every ayah printed on a page of this riwayah's mushaf, in mushaf order.
    pub fn mushaf_ayahs_on_page(&self, page: u32, riwayah: &str) -> Vec<VerseHit> {
        let Some(table) = self.mushaf_pages.get(riwayah) else {
            return Vec::new();
        };
        // Walked in mushaf order, so the result is ordered without a second sort.
        let mut out = Vec::new();
        for surah in &self.surahs {
            let Some(ayahs) = table.pages.get(&surah.id.to_string()) else {
                continue;
            };
            for ayah in 1..=surah.number_of_ayahs {
                if ayahs.get(&ayah.to_string()).copied() == Some(page) {
                    out.push(VerseHit { surah: surah.id, ayah });
                }
            }
        }
        out
    }

    /// What a "go to page 213" jump lands on.
    pub fn mushaf_first_ayah_of_page(&self, page: u32, riwayah: &str) -> Option<VerseHit> {
        self.mushaf_ayahs_on_page(page, riwayah).into_iter().next()
    }

    /// Character offsets into the ayah's own text at which this riwayah's print starts a new line.
  /// `None` when the riwayah's text (and so its line table) is not published.
    pub fn mushaf_line_breaks(&self, surah: u32, ayah: u32, riwayah: &str) -> Option<&[usize]> {
        self.mushaf_lines
            .get(riwayah)?
            .line_breaks
            .get(&surah.to_string())?
            .get(&ayah.to_string())
            .map(Vec::as_slice)
    }

    /// Whether `tajweed-qiraat/<slug>.json` exists for this riwayah.
    pub fn has_tajweed_pack(&self, riwayah: &str) -> bool {
        self.riwayah(riwayah).map(|r| r.tajweed.is_some()).unwrap_or(false)
    }
}
