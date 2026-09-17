//! Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.
//!
//! A deliberate translation of packages/quran-engine-js/test/batch6.test.js: the same corpora,
//! the same counts, the same shape checks, so a port that drifts fails here rather than in a
//! consumer.

use std::path::Path;

use quran_engine::{batch6::root_key, Engine};

fn engine() -> Engine {
    Engine::load(Path::new("../../data")).expect("load engine")
}

fn fold(text: &str) -> String {
    text.chars()
        .filter(|c| {
            !matches!(*c as u32, 0x064B..=0x065F | 0x0670 | 0x06D6..=0x06ED | 0x0640)
        })
        .map(|c| match c {
            '\u{0671}' | '\u{0623}' | '\u{0625}' => '\u{0627}',
            '\u{0624}' => '\u{0648}',
            '\u{0626}' => '\u{064A}',
            other => other,
        })
        .collect()
}

// ---- the Names in depth ----------------------------------------------------------

#[test]
fn names_depth_counts() {
    let e = engine();
    assert_eq!(e.names_depth_count(), (99, 9, 194));
    let numbers: Vec<u32> = e.names_in_depth().iter().map(|n| n.number).collect();
    assert_eq!(numbers, (1..=99).collect::<Vec<u32>>());
}

#[test]
fn every_name_has_root_theme_and_prose() {
    let e = engine();
    let ids: Vec<&str> = e.name_themes().iter().map(|t| t.id.as_str()).collect();
    for name in e.names_in_depth() {
        assert!(!name.root.is_empty(), "name {} has no root", name.number);
        assert!(ids.contains(&name.theme.as_str()), "name {} theme {}", name.number, name.theme);
        assert!(name.explanation.len() > 40, "name {} explanation", name.number);
        assert!(name.living.len() > 20, "name {} living", name.number);
    }
}

#[test]
fn themes_partition_the_ninety_nine() {
    let e = engine();
    let mut total = 0;
    for theme in e.name_themes() {
        let members = e.names_by_theme(&theme.id);
        assert!(!members.is_empty(), "theme {} has no Names", theme.id);
        total += members.len();
    }
    assert_eq!(total, 99);
}

#[test]
fn a_root_is_spaced_and_closes_up() {
    let e = engine();
    let rahman = e.name_in_depth(1).expect("name 1");
    assert_eq!(rahman.root, "ر ح م");
    assert_eq!(root_key(&rahman.root), "رحم");
    let by_closed: Vec<u32> = e.names_by_root("رحم").iter().map(|n| n.number).collect();
    let by_spaced: Vec<u32> = e.names_by_root("ر ح م").iter().map(|n| n.number).collect();
    assert_eq!(by_closed, vec![1, 2]);
    assert_eq!(by_spaced, vec![1, 2]);
}

#[test]
fn placed_occurrences_are_real_tokens() {
    let e = engine();
    let (mut placed, mut unplaced) = (0, 0);
    for name in e.names_in_depth() {
        for o in &name.occurrences {
            let ayah = e
                .ayah(o.surah, o.ayah)
                .unwrap_or_else(|| panic!("name {} points at {}:{}", name.number, o.surah, o.ayah));
            match o.token {
                None => {
                    assert_eq!(o.tokens, 0, "name {} unplaced but spans {}", name.number, o.tokens);
                    unplaced += 1;
                }
                Some(token) => {
                    let tokens: Vec<&str> = ayah.text_arabic.split_whitespace().collect();
                    assert!(token < tokens.len(), "name {} token {} past the end", name.number, token);
                    assert!(!fold(tokens[token]).is_empty());
                    placed += 1;
                }
            }
        }
    }
    assert_eq!(placed, 184);
    assert_eq!(unplaced, 10);
}

#[test]
fn the_basmalah_carries_two_names() {
    let e = engine();
    let hits = e.names_in_ayah(1, 3);
    let numbers: Vec<u32> = hits.iter().map(|(n, _)| n.number).collect();
    let tokens: Vec<Option<usize>> = hits.iter().map(|(_, o)| o.token).collect();
    assert_eq!(numbers, vec![1, 2]);
    assert_eq!(tokens, vec![Some(0), Some(1)]);
}

#[test]
fn names_search_by_root_and_prose() {
    let e = engine();
    assert!(e.search_names_in_depth("رحم", 25).iter().any(|n| n.number == 1));
    let first = e.name_in_depth(1).expect("name 1");
    let word = first.living.split_whitespace().find(|w| w.len() > 6).expect("a long word");
    assert!(!e.search_names_in_depth(word, 25).is_empty());
    assert!(e.search_names_in_depth("", 25).is_empty());
}

// ---- the chains of transmission --------------------------------------------------

#[test]
fn isnad_counts() {
    let e = engine();
    assert_eq!(e.isnad_count(), (10, 20, 13));
    assert!(e.isnad_prophet().is_some());
}

#[test]
fn every_riwayah_resolves_to_an_imam_two_apiece() {
    let e = engine();
    for imam in e.isnad_imam_keys() {
        let n = e
            .isnad_narrator_keys()
            .iter()
            .filter(|tag| e.isnad_imam_of(tag).as_deref() == Some(imam))
            .count();
        assert_eq!(n, 2, "{imam} has {n} narrators");
    }
    for tag in e.isnad_narrator_keys() {
        assert!(e.isnad_imam_of(tag).is_some(), "{tag} resolves to no imam");
    }
}

#[test]
fn every_imam_reaches_companions() {
    let e = engine();
    for imam in e.isnad_imam_keys() {
        let chain = e.isnad_imam(imam).expect("imam chain");
        // Abu Jafar WAS a Successor and read on Companions himself, so he has no teachers layer.
        if imam != "Abu Jafar" {
            assert!(!chain.teachers.is_empty(), "{imam} has no teachers");
        }
        assert!(!chain.companions.is_empty(), "{imam} reaches no Companion");
        for node in &chain.teachers {
            assert_eq!(node.role, "successor");
            assert!(node.detail.starts_with("d."), "{} has no death year", node.name);
        }
        for node in &chain.companions {
            assert_eq!(node.role, "companion");
        }
    }
}

#[test]
fn a_chain_runs_from_the_prophet_to_the_narrator() {
    let e = engine();
    for tag in e.isnad_narrator_keys() {
        let layers = e.isnad_chain(tag);
        assert!(layers.len() >= 4, "{tag} chain is only {} layers", layers.len());
        assert_eq!(layers[0].title, "THE PROPHET");
        assert_eq!(layers[1].title, "THE COMPANIONS");
        let titles: Vec<&str> = layers.iter().map(|l| l.title.as_str()).collect();
        let imam = titles.iter().position(|t| *t == "THE IMAM").expect("an imam layer");
        let narrator = titles.iter().position(|t| *t == "THE NARRATOR").expect("a narrator layer");
        assert!(imam < narrator, "{tag} has the narrator above the imam");
    }
}

#[test]
fn an_imam_chain_ends_at_his_two_narrators() {
    let e = engine();
    for imam in e.isnad_imam_keys() {
        let layers = e.isnad_chain(imam);
        let last = layers.last().expect("a last layer");
        assert_eq!(last.title, "HIS TWO NARRATORS", "{imam}");
        assert_eq!(last.nodes.len(), 2, "{imam}");
    }
}

#[test]
fn reading_directly_is_having_no_links() {
    let e = engine();
    for tag in e.isnad_narrator_keys() {
        let chain = e.isnad_narrator(tag).expect("narrator chain");
        assert_eq!(e.isnad_reads_directly(tag), chain.links.is_empty(), "{tag}");
        let sentence = e.isnad_sentence(tag);
        assert!(!sentence.is_empty(), "{tag}");
        assert_eq!(sentence.contains("did not meet"), !chain.links.is_empty(), "{tag}");
    }
}

#[test]
fn hafs_reads_directly_and_qunbul_does_not() {
    let e = engine();
    assert_eq!(e.isnad_imam_of("Hafs an Asim").as_deref(), Some("Asim"));
    assert!(e.isnad_reads_directly("Hafs an Asim"));
    assert!(e.isnad_sentence("Hafs an Asim").starts_with("Hafs read on Asim himself"));

    assert_eq!(e.isnad_imam_of("Qunbul an Ibn Kathir").as_deref(), Some("Ibn Kathir"));
    assert!(!e.isnad_reads_directly("Qunbul an Ibn Kathir"));
    assert_eq!(e.isnad_narrator("Qunbul an Ibn Kathir").expect("chain").links.len(), 3);
}

#[test]
fn an_unknown_key_answers_nothing() {
    let e = engine();
    assert!(e.isnad_chain("Nobody an Nobody").is_empty());
    assert_eq!(e.isnad_sentence("Nobody an Nobody"), "");
    assert!(e.isnad_imam_of("no separator here").is_none());
}
