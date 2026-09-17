//! The scientific-miracles corpus: 202 short articles, each making one claim about the Quran and
//! anchoring it to the ayahs it rests on, under 15 categories.
//!
//! An article is a list of BLOCKS in reading order rather than one field of prose, because the
//! layout matters: the claim is a headline, the lead sets it up, a quote carries somebody else's
//! words with the source next to them, an ayah block is a hole the consumer fills from
//! `quran.json`, and the closer asks the rhetorical question the article was built toward.
//!
//! An `ayah` block carries NO text, by design: surah, ayah and `end_ayah` only. The verse belongs
//! to this engine's own Ḥafṣ text, so duplicating it here would be a second copy to keep in step
//! and would pin the article to one riwayah.
//!
//! There are NO `image` blocks and `imagesIncluded` is false: the site's illustrations are not
//! republished here for licensing reasons, and the prose is written to stand without them. A
//! consumer that leaves a gap for a picture will be waiting forever.
//!
//! Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
//! science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters
//! or sorts by has to come off the ARTICLE.
//!
//! See `../../docs/25-miracles.md`.

use serde::Deserialize;

/// The four levels, easiest first.
///
/// Hard-coded because this is the app's own ordering and nothing in the file states it:
/// alphabetically "extreme" would sort second, which is precisely backwards.
pub const MIRACLE_LEVELS: [&str; 4] = ["simple", "intermediate", "advanced", "extreme"];

/// The block kinds that carry the article's OWN prose. A quote is somebody else's words and an
/// ayah block has no text at all, so neither belongs in [`article_text`].
const PROSE_KINDS: [&str; 4] = ["claim", "lead", "text", "closer"];

/// One of the fifteen categories, with the hardest science it covers.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct MiracleCategory {
    pub id: String,
    /// The CATEGORY's level, which an article under it need not share.
    #[serde(default)]
    pub level: String,
}

/// A link out of a block: either an outside page or another article in this corpus.
///
/// Exactly one of the two is set. Both forms occur, so a model that kept only `url` would silently
/// drop the twelve internal cross-references.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct MiracleLink {
    #[serde(default)]
    pub label: String,
    /// An outside page.
    #[serde(default)]
    pub url: Option<String>,
    /// Another article's slug: follow it with `Engine::miracle`.
    #[serde(default)]
    pub slug: Option<String>,
}

/// One block of an article. Which fields are set follows from `kind`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MiracleBlock {
    /// "claim", "lead", "text", "quote", "ayah" or "closer". Never "image".
    pub kind: String,
    /// Set on every kind but `ayah`.
    #[serde(default)]
    pub text: String,
    /// `lead` and `text` only.
    #[serde(default)]
    pub links: Vec<MiracleLink>,
    /// `quote` only: who is being quoted.
    #[serde(default)]
    pub source_label: Option<String>,
    /// `quote` only.
    #[serde(default)]
    pub source_url: Option<String>,
    /// `ayah` only.
    #[serde(default)]
    pub surah: Option<u32>,
    /// `ayah` only: the first of the range.
    #[serde(default)]
    pub ayah: Option<u32>,
    /// `ayah` only: the last of the range, always present and equal to `ayah` for a single verse.
    #[serde(default)]
    pub end_ayah: Option<u32>,
}

/// One article.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct MiracleArticle {
    pub slug: String,
    #[serde(default)]
    pub title: String,
    /// A [`MiracleCategory`] id.
    #[serde(default)]
    pub category: String,
    /// This article's OWN level, not its category's.
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub blocks: Vec<MiracleBlock>,
}

/// One ayah range an article cites.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MiracleAyahRef {
    pub surah: u32,
    pub ayah: u32,
    pub end_ayah: u32,
}

/// `data/miracles.json`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MiraclesFile {
    #[serde(default)]
    pub source: String,
    /// False, always: the illustrations are not republished.
    #[serde(default)]
    pub images_included: bool,
    #[serde(default)]
    pub categories: Vec<MiracleCategory>,
    #[serde(default)]
    pub articles: Vec<MiracleArticle>,
}

/// Where a level sorts, or past the end for one the corpus invents later.
pub fn level_rank(level: &str) -> usize {
    MIRACLE_LEVELS.iter().position(|l| *l == level).unwrap_or(MIRACLE_LEVELS.len())
}

/// Whether a block is an `ayah` block covering one ayah. A block is a RANGE, so an article citing
/// 21:30-33 answers to 21:31 as well.
fn block_covers(block: &MiracleBlock, surah_id: u32, ayah_id: u32) -> bool {
    block.kind == "ayah"
        && block.surah == Some(surah_id)
        && match (block.ayah, block.end_ayah) {
            (Some(start), Some(end)) => ayah_id >= start && ayah_id <= end,
            (Some(start), None) => ayah_id == start,
            _ => false,
        }
}

/// Whether an article cites an ayah anywhere in its blocks.
pub fn article_cites(article: &MiracleArticle, surah_id: u32, ayah_id: u32) -> bool {
    article.blocks.iter().any(|b| block_covers(b, surah_id, ayah_id))
}

/// The ayah ranges one article cites, in the order it cites them.
pub fn article_ayah_refs(article: &MiracleArticle) -> Vec<MiracleAyahRef> {
    article
        .blocks
        .iter()
        .filter(|b| b.kind == "ayah")
        .filter_map(|b| {
            let surah = b.surah?;
            let ayah = b.ayah?;
            Some(MiracleAyahRef { surah, ayah, end_ayah: b.end_ayah.unwrap_or(ayah) })
        })
        .collect()
}

/// One article's own prose, blocks joined with a blank line in reading order.
///
/// Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
/// folding them in would put somebody else's words into the article's voice and would break a
/// citation off from what it cites. Ayah blocks are skipped because they carry no text at all,
/// only a reference for the consumer to resolve.
pub fn article_text(article: &MiracleArticle) -> String {
    article
        .blocks
        .iter()
        .filter(|b| PROSE_KINDS.contains(&b.kind.as_str()) && !b.text.is_empty())
        .map(|b| b.text.as_str())
        .collect::<Vec<_>>()
        .join("\n\n")
}
