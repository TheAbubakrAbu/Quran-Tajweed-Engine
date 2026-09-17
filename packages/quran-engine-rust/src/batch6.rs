//! The corpora added upstream in Al-Islam 4.6.5: the 99 Names in depth, and the chains of
//! transmission of the Ten Readings.
//!
//! See `../../docs/23-names-depth.md` and `24-isnad.md`.

use std::collections::HashMap;

use serde::Deserialize;

// ---- the Names in depth ----------------------------------------------------------

/// One of the nine themes the Names are grouped under.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NameTheme {
    pub id: String,
    pub label: String,
}

/// One ayah a Name appears in.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NameOccurrence {
    pub surah: u32,
    pub ayah: u32,
    /// 0-based whitespace-token index into the ayah's raw text, or `None` where the corpus could
    /// not place the Name in the ayah (ten occurrences across four Names). The ayah is still
    /// right: show the verse whole and highlight nothing.
    #[serde(default)]
    pub token: Option<usize>,
    /// How many tokens the Name spans (0 for an unplaced occurrence).
    pub tokens: usize,
}

/// The layer under `names-of-allah.json`: what the Name is built on and what it asks of a reader.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NameDepth {
    pub number: u32,
    /// Printed SPACED, the way a grammar book sets a root ("ر ح م"). `root_key` closes it up to
    /// the form `morphology.json` stores.
    #[serde(default)]
    pub root: String,
    #[serde(default)]
    pub theme: String,
    #[serde(default)]
    pub explanation: String,
    #[serde(default)]
    pub living: String,
    #[serde(default)]
    pub occurrences: Vec<NameOccurrence>,
}

/// `data/names-depth.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NamesDepthFile {
    #[serde(default)]
    pub themes: Vec<NameTheme>,
    #[serde(default)]
    pub names: Vec<NameDepth>,
}

/// A spaced root as morphology stores it: `"ر ح م"` -> `"رحم"`.
///
/// Every port strips whitespace explicitly rather than trimming, because a root is spaced in the
/// middle and not only at the ends.
pub fn root_key(root: &str) -> String {
    root.split_whitespace().collect()
}

// ---- the chains of transmission --------------------------------------------------

/// One person in a chain.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct IsnadNode {
    pub name: String,
    #[serde(default)]
    pub arabic: String,
    /// The death year, e.g. "d. 117 AH".
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub role: String,
}

/// One generation of a chain, as a consumer draws it: a row, connected downward.
#[derive(Debug, Clone)]
pub struct IsnadLayer {
    pub title: String,
    pub nodes: Vec<IsnadNode>,
}

/// An imam's side: the Successors he read on, and the Companions they read on.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ImamChain {
    #[serde(default)]
    pub teachers: Vec<IsnadNode>,
    #[serde(default)]
    pub companions: Vec<IsnadNode>,
}

/// A narrator's side: the links between him and the imam (empty where he read on the imam
/// himself), and the students who carried his narration on.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NarratorChain {
    /// The imam this narration comes from.
    #[serde(default)]
    pub imam: String,
    #[serde(default)]
    pub links: Vec<IsnadNode>,
    #[serde(default)]
    pub students: Vec<IsnadNode>,
}

/// `data/isnad.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct IsnadFile {
    #[serde(default)]
    pub prophet: Option<IsnadNode>,
    #[serde(default)]
    pub companions: Vec<IsnadNode>,
    #[serde(default)]
    pub imams: HashMap<String, ImamChain>,
    #[serde(default)]
    pub narrators: HashMap<String, NarratorChain>,
}

/// The imam a riwayah comes from, if the file knows him.
///
/// Read from the corpus, NOT parsed off the tag: four tags name the imam in the Arabic genitive
/// ("ad-Duri an Abi Amr") while his key is the nominative ("Abu Amr"), so splitting on `" an "`
/// would resolve those four to nothing.
pub fn imam_of(file: &IsnadFile, riwayah: &str) -> Option<String> {
    let imam = &file.narrators.get(riwayah)?.imam;
    file.imams.contains_key(imam).then(|| imam.clone())
}

fn narrator_name(riwayah: &str) -> &str {
    match riwayah.find(" an ") {
        Some(i) => &riwayah[..i],
        None => riwayah,
    }
}

fn plain(name: &str, role: &str) -> IsnadNode {
    IsnadNode { name: name.to_string(), arabic: String::new(), detail: String::new(), role: role.to_string() }
}

/// The layers above any imam: the Prophet ﷺ, the Companions his teachers read on, and those
/// teachers. Shared by both chain forms, since every chain runs through them.
pub fn top_layers(file: &IsnadFile, imam: &str) -> Vec<IsnadLayer> {
    let Some(chain) = file.imams.get(imam) else {
        return Vec::new();
    };
    let mut layers = Vec::new();
    if let Some(prophet) = &file.prophet {
        layers.push(IsnadLayer { title: "THE PROPHET".into(), nodes: vec![prophet.clone()] });
    }
    if !chain.companions.is_empty() {
        layers.push(IsnadLayer { title: "THE COMPANIONS".into(), nodes: chain.companions.clone() });
    }
    if !chain.teachers.is_empty() {
        let title = if chain.teachers.len() == 1 { "HIS TEACHER" } else { "HIS TEACHERS" };
        layers.push(IsnadLayer { title: title.into(), nodes: chain.teachers.clone() });
    }
    layers
}

/// A whole chain as layers. `key` is a riwayah tag (`"Warsh an Nafi"`) for one narration's chain,
/// or an imam key (`"Nafi"`) for the reading's, which ends at his two narrators.
pub fn chain(file: &IsnadFile, key: &str) -> Vec<IsnadLayer> {
    let key = key.trim();
    if file.imams.contains_key(key) {
        let mut layers = top_layers(file, key);
        if layers.is_empty() {
            return layers;
        }
        layers.push(IsnadLayer { title: "THE IMAM".into(), nodes: vec![plain(key, "imam")] });
        // Sorted, so the two narrators come out in the same order on every run: a HashMap's
        // iteration order is not stable and the parity suites compare these lists.
        let mut tags: Vec<&String> = file
            .narrators
            .keys()
            .filter(|tag| imam_of(file, tag).as_deref() == Some(key))
            .collect();
        tags.sort();
        let nodes: Vec<IsnadNode> = tags.iter().map(|tag| plain(narrator_name(tag), "narrator")).collect();
        if !nodes.is_empty() {
            layers.push(IsnadLayer { title: "HIS TWO NARRATORS".into(), nodes });
        }
        return layers;
    }

    let Some(narrator) = file.narrators.get(key) else {
        return Vec::new();
    };
    let Some(imam) = imam_of(file, key) else {
        return Vec::new();
    };
    let mut layers = top_layers(file, &imam);
    if layers.is_empty() {
        return layers;
    }
    layers.push(IsnadLayer { title: "THE IMAM".into(), nodes: vec![plain(&imam, "imam")] });
    if !narrator.links.is_empty() {
        let title = if narrator.links.len() == 1 { "THE LINK BETWEEN" } else { "THE LINKS BETWEEN" };
        layers.push(IsnadLayer { title: title.into(), nodes: narrator.links.clone() });
    }
    layers.push(IsnadLayer { title: "THE NARRATOR".into(), nodes: vec![plain(narrator_name(key), "narrator")] });
    if !narrator.students.is_empty() {
        layers.push(IsnadLayer { title: "HIS STUDENTS".into(), nodes: narrator.students.clone() });
    }
    layers
}

/// One sentence on how a narrator reaches his imam: directly, or through the links between.
pub fn sentence(file: &IsnadFile, riwayah: &str) -> String {
    let (Some(chain), Some(imam)) = (file.narrators.get(riwayah), imam_of(file, riwayah)) else {
        return String::new();
    };
    let narrator = narrator_name(riwayah);
    if chain.links.is_empty() {
        return format!(
            "{narrator} read on {imam} himself, and {imam}'s chain runs through his teachers to the Companions and to the Prophet \u{fdfa}."
        );
    }
    let names: Vec<&str> = chain.links.iter().map(|n| n.name.as_str()).collect();
    let path = if names.len() == 1 {
        names[0].to_string()
    } else {
        format!("{} and then {}", names[..names.len() - 1].join(", "), names[names.len() - 1])
    };
    format!(
        "{narrator} did not meet {imam}: the reading reached him through {path}, and from {imam} it runs through his teachers to the Companions and to the Prophet \u{fdfa}."
    )
}
