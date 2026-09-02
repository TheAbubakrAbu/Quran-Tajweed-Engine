//! Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one sentence
//! saying what the surah as a whole is about.
//!
//! This answers "I am at 18:60 — what is this passage doing here", which neither the translation nor
//! the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
//! outline; al-Fatihah, Fussilat and ad-Dukhan do not.
//!
//! **The outline is a tree, flattened.** Ranges are inclusive, in mushaf order, and MAY NEST: a
//! broad section is followed by the sections inside it, parent before children (Hud opens with 1–24
//! "Doctrine facts", then 1–4, 5–6, 7–11, 12–17, 18–24 within it). They also do not tile the surah —
//! an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
//! which is what [`Engine::sections_for`] returns; [`Engine::outline`] rebuilds it as a tree.
//!
//! See `../../docs/15-surah-sections.md`.

use serde::Deserialize;
use std::collections::HashMap;

/// One titled range of ayahs. `from`/`to` are inclusive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SurahSection {
    pub from: u32,
    pub to: u32,
    pub english: String,
    pub arabic: String,
}

impl SurahSection {
    pub fn contains(&self, ayah: u32) -> bool {
        self.from <= ayah && ayah <= self.to
    }
}

/// A section with the sections inside it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutlineNode {
    pub section: SurahSection,
    pub children: Vec<OutlineNode>,
}

/// One row of `data/surah-sections.json`: `[from, to, english, arabic]`, heterogeneous.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum SectionField {
    Number(u32),
    Text(String),
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SurahSectionsEntry {
    #[serde(default)]
    pub overview: String,
    #[serde(default)]
    pub sections: Vec<Vec<SectionField>>,
}

use crate::Engine;

impl Engine {
    /// One sentence on what the whole surah is about, `""` when none is recorded.
    pub fn surah_overview(&self, surah: u32) -> &str {
        self.surah_sections.get(&surah.to_string()).map(|e| e.overview.as_str()).unwrap_or("")
    }

    /// The surah's sections, flat and in the order the source records them (a parent immediately
    /// before the sections inside it).
    pub fn sections(&self, surah: u32) -> Vec<SurahSection> {
        let Some(entry) = self.surah_sections.get(&surah.to_string()) else {
            return Vec::new();
        };
        entry
            .sections
            .iter()
            .filter_map(|row| {
                if row.len() < 4 {
                    return None;
                }
                let (SectionField::Number(from), SectionField::Number(to)) = (&row[0], &row[1])
                else {
                    return None;
                };
                let (SectionField::Text(english), SectionField::Text(arabic)) = (&row[2], &row[3])
                else {
                    return None;
                };
                Some(SurahSection {
                    from: *from,
                    to: *to,
                    english: english.clone(),
                    arabic: arabic.clone(),
                })
            })
            .collect()
    }

    /// The same sections as a tree: top-level passages, each with what is inside it.
    pub fn outline(&self, surah: u32) -> Vec<OutlineNode> {
        let mut roots: Vec<OutlineNode> = Vec::new();
        // Path of indices into the tree, outermost first — Rust will not hand out two mutable
        // borrows of the same tree, so the open chain is tracked by position instead.
        let mut path: Vec<usize> = Vec::new();

        for section in self.sections(surah) {
            while let Some(open) = node_at(&roots, &path) {
                if open.section.from <= section.from && section.to <= open.section.to {
                    break;
                }
                path.pop();
            }
            let node = OutlineNode { section, children: Vec::new() };
            let siblings = match node_at_mut(&mut roots, &path) {
                Some(parent) => &mut parent.children,
                None => &mut roots,
            };
            siblings.push(node);
            path.push(siblings.len() - 1);
        }
        roots
    }

    /// Every section covering an ayah, outermost first — the breadcrumb for "you are here". Empty
    /// when the surah has no outline, or when this ayah falls between sections.
    pub fn sections_for(&self, surah: u32, ayah: u32) -> Vec<SurahSection> {
        self.sections(surah).into_iter().filter(|s| s.contains(ayah)).collect()
    }

    /// The most specific section covering an ayah — the heading a reader wants beside the verse.
    pub fn section_for(&self, surah: u32, ayah: u32) -> Option<SurahSection> {
        self.sections_for(surah, ayah).pop()
    }

    /// Whether this surah has an outline at all.
    pub fn has_sections(&self, surah: u32) -> bool {
        self.surah_sections
            .get(&surah.to_string())
            .map(|e| !e.sections.is_empty())
            .unwrap_or(false)
    }

    /// How many surahs carry an outline.
    pub fn outlined_surah_count(&self) -> usize {
        self.surah_sections.values().filter(|e| !e.sections.is_empty()).count()
    }

    /// Sections whose title carries `query`, across every surah, as `(surah, section)`.
    pub fn search_sections(&self, query: &str) -> Vec<(u32, SurahSection)> {
        let trimmed = query.trim();
        let needle = trimmed.to_lowercase();
        if needle.is_empty() {
            return Vec::new();
        }
        let mut ids: Vec<u32> =
            self.surah_sections.keys().filter_map(|k| k.parse().ok()).collect();
        ids.sort_unstable();

        let mut out = Vec::new();
        for id in ids {
            for section in self.sections(id) {
                if section.english.to_lowercase().contains(&needle)
                    || section.arabic.contains(trimmed)
                {
                    out.push((id, section));
                }
            }
        }
        out
    }
}

/// The node the path points at, or `None` for the root list.
fn node_at<'a>(roots: &'a [OutlineNode], path: &[usize]) -> Option<&'a OutlineNode> {
    let mut node = roots.get(*path.first()?)?;
    for index in &path[1..] {
        node = node.children.get(*index)?;
    }
    Some(node)
}

fn node_at_mut<'a>(roots: &'a mut [OutlineNode], path: &[usize]) -> Option<&'a mut OutlineNode> {
    let mut node = roots.get_mut(*path.first()?)?;
    for index in &path[1..] {
        node = node.children.get_mut(*index)?;
    }
    Some(node)
}

/// `data/surah-sections.json`.
pub type SurahSectionsFile = HashMap<String, SurahSectionsEntry>;
