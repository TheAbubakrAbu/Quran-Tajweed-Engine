//! The scientific-miracles corpus: 202 articles under 15 categories.
//!
//! A deliberate translation of packages/quran-engine-js/test/miracles.test.js: the same corpus,
//! the same counts, the same shape checks, so a port that drifts fails here rather than in a
//! consumer.

use std::collections::BTreeSet;
use std::path::Path;

use quran_engine::miracles::{MiraclesFile, MIRACLE_LEVELS};
use quran_engine::Engine;

fn engine() -> Engine {
    Engine::load(Path::new("../../data")).expect("load engine")
}

#[test]
fn counts() {
    let e = engine();
    assert_eq!(e.miracles_count(), (202, 15, 278));
    assert_eq!(e.miracles().len(), 202);
    assert_eq!(e.miracle_categories().len(), 15);
}

#[test]
fn slug_round_trips() {
    let e = engine();
    let article = e.miracle("big_bang_crunch").expect("big_bang_crunch");
    assert_eq!(article.title, "Big Bang");
    assert_eq!(article.category, "cosmology");
    assert_eq!(article.level, "extreme");
    assert!(e.miracle("no_such_article").is_none());
    // Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
    let slugs: BTreeSet<&str> = e.miracles().iter().map(|a| a.slug.as_str()).collect();
    assert_eq!(slugs.len(), 202);
}

#[test]
fn categories_partition_the_corpus() {
    let e = engine();
    let mut total = 0;
    for category in e.miracle_categories() {
        let members = e.miracles_by_category(&category.id);
        assert!(!members.is_empty(), "category {} has no articles", category.id);
        total += members.len();
    }
    assert_eq!(total, 202);
    assert_eq!(e.miracles_by_category("cosmology").len(), 18);
    assert!(e.miracles_by_category("no_such_category").is_empty());
}

#[test]
fn category_lookup() {
    let e = engine();
    let cosmology = e.miracle_category("cosmology").expect("cosmology");
    assert_eq!(cosmology.id, "cosmology");
    assert_eq!(cosmology.level, "advanced");
    assert!(e.miracle_category("no_such_category").is_none());
}

#[test]
fn article_level_is_its_own() {
    // Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
    // itself is "extreme". Filtering on the category's level would put it in the wrong bucket, and
    // it is not one article out of place: most of the corpus disagrees with its category.
    let e = engine();
    assert_eq!(e.miracle_category("cosmology").unwrap().level, "advanced");
    assert_eq!(e.miracle("big_bang_crunch").unwrap().level, "extreme");
    let differing = e
        .miracles()
        .iter()
        .filter(|a| {
            e.miracle_category(&a.category).map(|c| c.level.as_str()) != Some(a.level.as_str())
        })
        .count();
    assert_eq!(differing, 147);
}

#[test]
fn levels_run_simple_to_extreme() {
    let e = engine();
    assert_eq!(e.miracle_levels(), vec!["simple", "intermediate", "advanced", "extreme"]);
    assert_eq!(e.miracle_levels(), MIRACLE_LEVELS.to_vec());
    // Sorted as strings, "extreme" would come second. That is the whole reason the rank is
    // hard-coded.
    let mut alphabetical = e.miracle_levels();
    alphabetical.sort_unstable();
    assert_ne!(e.miracle_levels(), alphabetical);
    assert_eq!(e.miracles_by_level("simple").len(), 6);
    assert_eq!(e.miracles_by_level("intermediate").len(), 103);
    assert_eq!(e.miracles_by_level("advanced").len(), 37);
    assert_eq!(e.miracles_by_level("extreme").len(), 56);
    let total: usize = MIRACLE_LEVELS.iter().map(|l| e.miracles_by_level(l).len()).sum();
    assert_eq!(total, e.miracles().len());
}

#[test]
fn every_article_names_a_known_category_and_level() {
    let e = engine();
    let ids: BTreeSet<&str> = e.miracle_categories().iter().map(|c| c.id.as_str()).collect();
    for article in e.miracles() {
        assert!(!article.slug.is_empty());
        assert!(!article.title.is_empty(), "{}", article.slug);
        assert!(ids.contains(article.category.as_str()), "{}", article.slug);
        assert!(MIRACLE_LEVELS.contains(&article.level.as_str()), "{}", article.slug);
        assert!(!article.blocks.is_empty(), "{}", article.slug);
    }
}

#[test]
fn citing_finds_the_articles_that_reach_an_ayah() {
    let e = engine();
    // 21:30 is cited by exactly two: Big Bang and Exoplanets.
    let slugs: Vec<&str> = e.miracles_citing(21, 30).iter().map(|a| a.slug.as_str()).collect();
    assert_eq!(slugs, vec!["big_bang_crunch", "exoplanets"]);
    // 23:14, the embryology verse, by three.
    let slugs: Vec<&str> = e.miracles_citing(23, 14).iter().map(|a| a.slug.as_str()).collect();
    assert_eq!(slugs, vec!["bones", "fetal_development", "human_embryo"]);
    assert!(e.miracles_citing(21, 999).is_empty());
    assert!(e.miracles_citing(999, 1).is_empty());
}

#[test]
fn an_ayah_block_is_a_range() {
    // Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
    // one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range end
    // is what bounds the search, not the surah).
    let e = engine();
    let refs = e.miracle_ayah_refs("abjad_numerals");
    assert_eq!(refs.len(), 1);
    assert_eq!((refs[0].surah, refs[0].ayah, refs[0].end_ayah), (111, 1, 5));
    for ayah in 1..=5 {
        assert!(
            e.miracles_citing(111, ayah).iter().any(|a| a.slug == "abjad_numerals"),
            "111:{ayah}"
        );
    }
    assert!(!e.miracles_citing(111, 6).iter().any(|a| a.slug == "abjad_numerals"));
    assert!(e.miracle_ayah_refs("no_such_article").is_empty());
}

#[test]
fn every_ayah_ref_is_a_real_ayah() {
    let e = engine();
    let mut refs = 0;
    let mut ranges = 0;
    for article in e.miracles() {
        for r in e.miracle_ayah_refs(&article.slug) {
            assert!(r.end_ayah >= r.ayah, "{}", article.slug);
            // Both ends resolve, which is the point of storing the reference rather than the text.
            assert!(e.ayah(r.surah, r.ayah).is_some(), "{} -> {}:{}", article.slug, r.surah, r.ayah);
            assert!(
                e.ayah(r.surah, r.end_ayah).is_some(),
                "{} -> {}:{}",
                article.slug,
                r.surah,
                r.end_ayah
            );
            refs += 1;
            if r.end_ayah > r.ayah {
                ranges += 1;
            }
        }
    }
    assert_eq!(refs, 278);
    assert_eq!(ranges, 49);
}

#[test]
fn no_block_anywhere_is_an_image() {
    // The site's illustrations are deliberately not republished. A consumer that leaves a gap for
    // a picture would wait forever, so the corpus states it and the blocks bear it out.
    let e = engine();
    assert!(!e.miracles_images_included());
    let kinds: BTreeSet<&str> =
        e.miracles().iter().flat_map(|a| a.blocks.iter().map(|b| b.kind.as_str())).collect();
    assert!(!kinds.contains("image"));
    assert_eq!(
        kinds.into_iter().collect::<Vec<_>>(),
        vec!["ayah", "claim", "closer", "lead", "quote", "text"]
    );
    assert!(e.miracles_source().contains("miracles-of-quran.com"));
}

#[test]
fn a_link_is_a_url_or_a_slug_never_both() {
    let e = engine();
    let known: BTreeSet<&str> = e.miracles().iter().map(|a| a.slug.as_str()).collect();
    let mut urls = 0;
    let mut slugs = 0;
    for article in e.miracles() {
        for block in &article.blocks {
            for link in &block.links {
                assert!(!link.label.is_empty(), "{}", article.slug);
                assert_ne!(link.url.is_some(), link.slug.is_some(), "{}", article.slug);
                match &link.slug {
                    // An internal cross-reference resolves, so following one is `miracle` and
                    // nothing more.
                    Some(slug) => {
                        assert!(known.contains(slug.as_str()), "{} -> {slug}", article.slug);
                        assert!(e.miracle(slug).is_some());
                        slugs += 1;
                    }
                    None => urls += 1,
                }
            }
        }
    }
    assert_eq!(urls, 73);
    assert_eq!(slugs, 12);
    // One of each form, named, so a port that models only one of them fails here.
    let internal: Vec<&quran_engine::miracles::MiracleLink> =
        e.miracle("big_bang_crunch").unwrap().blocks.iter().flat_map(|b| b.links.iter()).collect();
    assert_eq!(internal.len(), 1);
    assert_eq!(internal[0].label, "Dark Energy");
    assert_eq!(internal[0].slug.as_deref(), Some("dark_energy"));
    let external: Vec<&quran_engine::miracles::MiracleLink> = e
        .miracle("atoms")
        .unwrap()
        .blocks
        .iter()
        .flat_map(|b| b.links.iter())
        .filter(|l| l.url.is_some())
        .collect();
    assert!(!external.is_empty());
    assert!(external.iter().all(|l| l.url.as_deref().unwrap().starts_with("http")));
}

#[test]
fn text_leaves_the_quotes_out() {
    let e = engine();
    let abjad = e.miracle("abjad_numerals").unwrap();
    let quote = abjad.blocks.iter().find(|b| b.kind == "quote").expect("a quote block");
    assert_eq!(quote.source_label.as_deref(), Some("Wikipedia, Abjad Numerals, 2021"));
    let text = e.miracle_text("abjad_numerals");
    // The quote sits between the lead and the first text block, and none of it comes through: it
    // is somebody else's words next to a source label, not the article's voice.
    assert!(!text.contains(&quote.text[..40]));
    assert!(!text.contains("Wikipedia"));
    // What does come through is claim, lead, text and closer, in reading order.
    assert!(text.starts_with("Alphanumeric code."));
    assert!(text.contains("We found this ancient numeral system encoded in the Quran."));
    assert_eq!(text.split("\n\n").count(), 6);
    assert_eq!(e.miracle_text("big_bang_crunch").split("\n\n").count(), 4);
    assert_eq!(e.miracle_text("no_such_article"), "");
}

#[test]
fn search_matches_title_or_prose() {
    let e = engine();
    let hits: Vec<&str> = e.search_miracles("big bang", 25).iter().map(|a| a.slug.as_str()).collect();
    assert!(hits.contains(&"big_bang_crunch"));
    let upper: Vec<&str> = e.search_miracles("BIG BANG", 25).iter().map(|a| a.slug.as_str()).collect();
    assert_eq!(hits, upper);
    assert!(e.search_miracles("cosmology", 3).len() <= 3);
    assert!(e.search_miracles("", 25).is_empty());
    assert!(e.search_miracles("   ", 25).is_empty());
    assert!(e.search_miracles("zzzznotaword", 25).is_empty());
}

#[test]
fn an_empty_corpus_answers_nothing() {
    // `Engine::load` builds this module from the file's default when it is absent, and every call
    // has to survive that: a consumer without the pack sees an empty corpus, not a crash.
    let empty = MiraclesFile::default();
    assert!(empty.articles.is_empty());
    assert!(empty.categories.is_empty());
    assert!(!empty.images_included);
    assert_eq!(empty.source, "");
    // And the loaded one is not empty, so the check above is not vacuous.
    let e = engine();
    assert!(!e.miracles().is_empty());
    assert_eq!(e.miracle_levels().len(), 4);
}
