//! Riwayah tajweed: where a reading differs from Hafs, and why.
//!
//! A different layer from the tajweed detector, which reads the text and works out the universal
//! rules. This carries what is SPECIFIC to a transmission and cannot be detected, because it IS the
//! text's difference: Warsh's taqlil, al-Bazzi's doubled ta, the places two readings part.
//!
//! Two things to get right:
//!
//! * **The meaning of a colour is per edition.** Each mushaf prints its own legend, so the same
//!   code is a different rule in a different riwayah. Always read the legend. The `rule` KEY is
//!   stable across riwayat, which is why one catalogue can explain it for all of them.
//! * **Extents are base-letter indices, not character offsets** — `first_letter..=last_letter` in
//!   reading order with diacritics not counted, or the whole word when `whole_word`.
//!
//! Only the seven verified non-Hafs riwayat carry a pack. See `../../docs/11-qiraat-tajweed.md`.

use serde::Deserialize;
use std::collections::HashMap;

/// One legend row as it ships, before the shared explanation is merged in.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct LegendRow {
    pub code: String,
    pub rule: String,
    pub arabic: String,
    pub english: String,
}

/// A legend row with its shared explanation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LegendEntry {
    /// The single letter this riwayah's data uses for the rule.
    pub code: String,
    /// Stable rule key, e.g. `"idgham"` — the same across riwayat.
    pub rule: String,
    /// The rule's name as this mushaf prints it.
    pub arabic: String,
    pub english: String,
    /// One-line explanation, from the shared catalogue.
    pub short: String,
    pub long: String,
}

/// What one word of one ayah is coloured for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WordRule {
    /// 1-based word index within the ayah.
    pub word: u32,
    pub rule: String,
    pub code: String,
    pub arabic: String,
    pub english: String,
    /// Inclusive base-letter index the rule colours, or `-1` for the whole word.
    pub first_letter: i32,
    pub last_letter: i32,
    pub whole_word: bool,
}

/// One entry of `data/tajweed-qiraat/rules.json`.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct RuleDescription {
    pub short: String,
    pub long: String,
}

/// One field of a `[code, firstLetter, lastLetter]` triple.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum RuleField {
    Index(i32),
    Code(String),
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QiraatTajweedPack {
    pub riwayah: String,
    pub version: u32,
    pub legend: Vec<LegendRow>,
    /// Surah -> ayah -> word -> `[code, firstLetter, lastLetter]`.
    pub rules: HashMap<String, HashMap<String, HashMap<String, Vec<Vec<RuleField>>>>>,
    pub khilaf_markers: HashMap<String, Vec<u32>>,
}

use crate::Engine;

impl Engine {
    /// The riwayat that have a pack loaded, in slug order.
    pub fn qiraat_tajweed_available(&self) -> Vec<&str> {
        let mut slugs: Vec<&str> = self.qiraat_tajweed.keys().map(String::as_str).collect();
        slugs.sort_unstable();
        slugs
    }

    /// This riwayah's printed legend, each entry carrying the shared explanation of its rule.
    pub fn qiraat_legend(&self, riwayah: &str) -> Vec<LegendEntry> {
        let Some(pack) = self.qiraat_tajweed.get(riwayah) else {
            return Vec::new();
        };
        pack.legend
            .iter()
            .map(|row| {
                let description = self.qiraat_rule_descriptions.get(&row.rule);
                LegendEntry {
                    code: row.code.clone(),
                    rule: row.rule.clone(),
                    arabic: row.arabic.clone(),
                    english: row.english.clone(),
                    short: description.map(|d| d.short.clone()).unwrap_or_default(),
                    long: description.map(|d| d.long.clone()).unwrap_or_default(),
                }
            })
            .collect()
    }

    /// What this riwayah colours in one ayah, word by word.
    pub fn qiraat_word_rules(&self, surah: u32, ayah: u32, riwayah: &str) -> Vec<WordRule> {
        let Some(pack) = self.qiraat_tajweed.get(riwayah) else {
            return Vec::new();
        };
        let Some(words) = pack
            .rules
            .get(&surah.to_string())
            .and_then(|s| s.get(&ayah.to_string()))
        else {
            return Vec::new();
        };
        let legend = self.qiraat_legend(riwayah);

        let mut keys: Vec<u32> = words.keys().filter_map(|k| k.parse().ok()).collect();
        keys.sort_unstable();

        let mut out = Vec::new();
        for key in keys {
            for triple in words.get(&key.to_string()).into_iter().flatten() {
                let (RuleField::Code(code), RuleField::Index(lo), RuleField::Index(hi)) =
                    (&triple[0], &triple[1], &triple[2])
                else {
                    continue;
                };
                let entry = legend.iter().find(|e| &e.code == code);
                out.push(WordRule {
                    word: key,
                    rule: entry.map(|e| e.rule.clone()).unwrap_or_else(|| code.clone()),
                    code: code.clone(),
                    arabic: entry.map(|e| e.arabic.clone()).unwrap_or_default(),
                    english: entry.map(|e| e.english.clone()).unwrap_or_default(),
                    first_letter: *lo,
                    last_letter: *hi,
                    whole_word: *lo < 0,
                });
            }
        }
        out
    }

    /// The ayahs of a surah this riwayah reads differently from Hafs somewhere — the index behind a
    /// "show me where these two readings part" list, without walking every ayah's rules.
    pub fn khilaf_ayahs(&self, surah: u32, riwayah: &str) -> &[u32] {
        self.qiraat_tajweed
            .get(riwayah)
            .and_then(|p| p.khilaf_markers.get(&surah.to_string()))
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    pub fn has_khilaf(&self, surah: u32, ayah: u32, riwayah: &str) -> bool {
        self.khilaf_ayahs(surah, riwayah).contains(&ayah)
    }

    /// What a rule key means, in one line and in a paragraph. Shared across every riwayah using it.
    pub fn describe_qiraat_rule(&self, rule: &str) -> Option<&RuleDescription> {
        self.qiraat_rule_descriptions.get(rule)
    }

    /// Every rule key the catalogue explains.
    pub fn qiraat_rule_keys(&self) -> Vec<&str> {
        let mut keys: Vec<&str> = self.qiraat_rule_descriptions.keys().map(String::as_str).collect();
        keys.sort_unstable();
        keys
    }
}
