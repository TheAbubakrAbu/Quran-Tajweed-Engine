//! Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil, the qiraat variant
//! matrix and the word of the day.
//!
//! Mirrors the JS `test/batch5.test.js`, the Python `tests/test_batch5.py` and the Go
//! `batch5_test.go` case for case. Every count is pinned against the app's own verify gate, so a
//! corpus that reaches the engine half-imported fails loudly rather than quietly answering less
//! than it should.

use std::collections::HashSet;

use quran_engine::batch5::{DivisionKind, TopicTree};
use quran_engine::morphology::{fold_for_morphology, WordLocation};
use quran_engine::{Engine, LoadOptions};

fn engine() -> Engine {
    Engine::load_default_with(LoadOptions {
        morphology: true,
        mutashabihat: true,
        qul_topics: true,
        qiraat_variants: true,
        ..Default::default()
    })
    .expect("engine loads")
}

fn tokens(engine: &Engine, surah: u32, ayah: u32) -> Vec<String> {
    engine
        .ayah(surah, ayah)
        .map(|a| a.text_arabic.split_whitespace().map(str::to_string).collect())
        .unwrap_or_default()
}

/// The upstream fold: harakat and the waqf marks gone, alif wasla and the hamza seats normalized.
fn fold_token(text: &str) -> String {
    text.chars()
        .filter(|c| {
            !matches!(*c as u32, 0x064B..=0x065F | 0x0670 | 0x06D6..=0x06ED | 0x0640)
        })
        .map(|c| match c {
            'ٱ' | 'أ' | 'إ' => 'ا',
            'ؤ' => 'و',
            'ئ' => 'ي',
            other => other,
        })
        .collect()
}

// ---- morphology ---------------------------------------------------------------------

#[test]
fn morphology_corpus_size_matches_the_app_gate() {
    assert_eq!(engine().morphology_count(), (1642, 4817, 77629));
}

#[test]
fn morphology_ids_are_one_based_and_zero_means_no_root() {
    let engine = engine();
    assert!(engine.root(0).is_none(), "id 0 means the token has no root");
    assert!(engine.root(1).is_some());
    assert!(engine.root(1643).is_none(), "root ids stop at the table size");
    let (roots, lemmas) = engine.morphology_ids(1, 1).expect("1:1 is covered");
    assert_eq!(roots.len(), 4);
    assert_eq!(lemmas.len(), 4);
}

#[test]
fn morphology_token_resolves_to_root_and_lemma() {
    let engine = engine();
    // 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
    let (_, root) = engine.root_of(1, 2, 2).expect("token 2 has a root");
    assert_eq!(root.letters, "ر ب ب");
    assert_eq!(root.buckwalter, "rbb");
    assert_eq!(root.joined, "ربب");
    assert!(engine.lemma_of(1, 2, 2).is_some());
}

#[test]
fn morphology_occurrences_come_back_in_mushaf_order() {
    let engine = engine();
    let hit = engine.find_roots("ربب", 5).into_iter().next().expect("ربب resolves");
    let found = engine.occurrences_of_root(hit.id);
    assert_eq!(found.len(), 980);
    assert_eq!(found[0], WordLocation { surah: 1, ayah: 2, token: 2 });
    assert!(found.windows(2).all(|pair| pair[0] < pair[1]), "not in mushaf order");
}

#[test]
fn morphology_fold_closes_the_spaces() {
    // A lexicon prints "ر ب ب" and a reader types "ربب"; the fold has to close the spaces, not
    // merely trim them.
    assert_eq!(fold_for_morphology("ر ب ب"), "ربب");
    let engine = engine();
    for query in ["ربب", "ر ب ب", "rbb"] {
        assert!(
            engine.find_roots(query, 5).iter().any(|hit| hit.root.buckwalter == "rbb"),
            "no rbb for {query}"
        );
    }
}

// ---- mutashabihat -------------------------------------------------------------------

#[test]
fn mutashabihat_counts() {
    assert_eq!(engine().mutashabihat_count(), (814, 2232));
}

#[test]
fn mutashabihat_phrase_shape() {
    let phrase = engine().mutashabihat_phrase(10167).expect("phrase 10167 exists");
    assert_eq!(phrase.source, "9:87");
    assert_eq!(phrase.span, [5, 10]);
    assert_eq!(phrase.word_count, 6);
    assert_eq!((phrase.ayah_count, phrase.surah_count), (3, 2));
    assert_eq!(phrase.occurrences["9:93"], vec![[13, 19]]);
}

#[test]
fn mutashabihat_occurrences_are_in_mushaf_order_not_key_order() {
    let keys: Vec<String> =
        engine().phrase_occurrences(10167).into_iter().map(|o| o.key).collect();
    assert_eq!(keys, vec!["9:87", "9:93", "63:3"]);
}

#[test]
fn mutashabihat_phrase_slices_out_of_the_text_you_hand_it() {
    let engine = engine();
    let source = engine.ayah(9, 87).expect("9:87").text_arabic.clone();
    let text = engine.phrase_text(10167, &source);
    assert_eq!(text.split_whitespace().count(), 6);
    assert!(source.contains(text.split_whitespace().next().unwrap()));
}

#[test]
fn mutashabihat_has_agrees_with_the_lookup() {
    let engine = engine();
    assert!(engine.has_mutashabihat(9, 87));
    assert!(!engine.mutashabihat_for(9, 87).is_empty());
    assert_eq!(engine.has_mutashabihat(1, 1), !engine.mutashabihat_for(1, 1).is_empty());
}

// ---- QUL topics ---------------------------------------------------------------------

#[test]
fn qul_topic_counts_and_the_double_listing() {
    let (topics, thematic, ontology, index, references) = engine().qul_topic_count();
    assert_eq!(topics, 2512);
    assert_eq!(references, 30687);
    assert_eq!((thematic, ontology, index), (695, 284, 1550));
    // Deliberately sums to MORE than the topic count: the 17 topics listed in two indexes are
    // counted in both, which is what "listed in" means.
    assert_eq!(thematic + ontology + index, 2529);
}

#[test]
fn qul_topics_are_three_independent_trees() {
    let engine = engine();
    let both = engine.qul_topics().iter().filter(|t| t.families.len() > 1).count();
    assert_eq!(both, 17);
    assert_eq!(
        engine.topic_parent(13, Some(TopicTree::Thematic)).map(|t| t.name.as_str()),
        Some("Prophets (25 mentioned by name)")
    );
    assert_eq!(
        engine.topic_parent(13, Some(TopicTree::Ontology)).map(|t| t.name.as_str()),
        Some("Prophet")
    );
    // A tree is not closed over its own listing either: the A-Z index hangs entries under
    // thematic topics, so asserting a parent shares its child's family would be false.
    let crossing = engine
        .qul_topics()
        .iter()
        .filter(|topic| match topic.parent_in(TopicTree::Index) {
            Some(parent) => engine
                .qul_topic(parent)
                .is_some_and(|p| !p.listed_in(TopicTree::Index)),
            None => false,
        })
        .count();
    assert!(crossing > 0, "expected the index tree to reach outside its own listing");
}

#[test]
fn qul_topic_parents_all_resolve() {
    let engine = engine();
    for topic in engine.qul_topics() {
        for tree in TopicTree::ALL {
            if let Some(parent) = topic.parent_in(tree) {
                assert!(
                    engine.qul_topic(parent).is_some(),
                    "topic {} ({}) has a dangling {} parent {parent}",
                    topic.id,
                    topic.name,
                    tree.as_str()
                );
            }
        }
    }
}

#[test]
fn qul_topic_ancestors_terminate_in_every_tree() {
    let engine = engine();
    for tree in TopicTree::ALL {
        let deep = engine
            .qul_topics()
            .iter()
            .find(|t| engine.topic_ancestors(t.id, Some(tree)).len() >= 2)
            .unwrap_or_else(|| panic!("no topic two levels down in {}", tree.as_str()));
        let chain = engine.topic_ancestors(deep.id, Some(tree));
        let unique: HashSet<u32> = chain.iter().map(|t| t.id).collect();
        assert_eq!(unique.len(), chain.len(), "cycle in {}", tree.as_str());
        assert!(chain.last().unwrap().parent_in(tree).is_none());
    }
}

#[test]
fn qul_topic_children_list_their_parent() {
    let engine = engine();
    for tree in TopicTree::ALL {
        let child = engine
            .qul_topics()
            .iter()
            .find(|t| t.parent_in(tree).is_some())
            .expect("a child in every tree");
        let parent = child.parent_in(tree).unwrap();
        assert!(
            engine.topic_children(parent, Some(tree)).iter().any(|s| s.id == child.id),
            "{} missing from its {} parent",
            child.name,
            tree.as_str()
        );
    }
}

#[test]
fn qul_topic_references_are_real_ayahs() {
    let engine = engine();
    let sample: Vec<_> = engine.qul_topics().iter().take(200).collect();
    for topic in &sample {
        for key in &topic.ayahs {
            let (surah, ayah) = quran_engine::batch5::split_ayah_key(key);
            assert!(engine.ayah(surah, ayah).is_some(), "{} cites {key}", topic.name);
        }
    }
    let first = sample[0];
    let (surah, ayah) = quran_engine::batch5::split_ayah_key(&first.ayahs[0]);
    assert!(engine.qul_topics_for(surah, ayah).iter().any(|t| t.id == first.id));
}

// ---- passage themes -----------------------------------------------------------------

#[test]
fn passage_counts() {
    assert_eq!(engine().passage_count(), (114, 1049));
}

#[test]
fn passages_are_ordered_and_never_overlap() {
    let engine = engine();
    for surah in engine.surahs() {
        let mut previous_end = 0;
        for passage in engine.passages(surah.id) {
            assert!(
                previous_end == 0 || passage.from > previous_end,
                "surah {}: {} overlaps {previous_end}",
                surah.id,
                passage.from
            );
            assert!(passage.to >= passage.from);
            assert!(passage.to <= surah.number_of_ayahs);
            previous_end = passage.to;
        }
    }
}

#[test]
fn passage_for_finds_the_containing_passage() {
    let passage = engine().passage_for(2, 10).cloned().expect("2:10 is inside a passage");
    assert_eq!(passage.theme, "Hypocrites and the consequences of hypocrisy");
    assert_eq!((passage.from, passage.to), (8, 16));
}

// ---- hizb / ruku / manzil -----------------------------------------------------------

#[test]
fn division_counts_and_first_starts() {
    let engine = engine();
    assert_eq!(engine.division_count(DivisionKind::Hizb), 60);
    assert_eq!(engine.division_count(DivisionKind::Ruku), 558);
    assert_eq!(engine.division_count(DivisionKind::Manzil), 7);
    for kind in [DivisionKind::Hizb, DivisionKind::Ruku, DivisionKind::Manzil] {
        assert_eq!(engine.division_start(kind, 1).unwrap().key, "1:1");
    }
}

#[test]
fn division_starts_ascend_and_are_real_ayahs() {
    let engine = engine();
    for kind in [DivisionKind::Hizb, DivisionKind::Ruku, DivisionKind::Manzil] {
        let all = engine.divisions(kind);
        for pair in all.windows(2) {
            let (a, b) = (&pair[0], &pair[1]);
            assert!(
                a.surah < b.surah || (a.surah == b.surah && a.ayah < b.ayah),
                "out of order at {}",
                b.key
            );
            assert!(engine.ayah(b.surah, b.ayah).is_some(), "{} is not an ayah", b.key);
        }
    }
}

#[test]
fn division_lookup_contains_the_ayah() {
    let engine = engine();
    assert_eq!(engine.divisions_for(1, 1), (1, 1, 1));
    let (hizb, _, manzil) = engine.divisions_for(114, 6);
    assert_eq!((hizb, manzil), (60, 7));
    let n = engine.division_for(DivisionKind::Hizb, 2, 255);
    let (from, until) = engine.division_range(DivisionKind::Hizb, n).expect("a range");
    assert!(from.surah < 2 || (from.surah == 2 && from.ayah <= 255));
    if let Some(next) = until {
        assert!(next.surah > 2 || (next.surah == 2 && next.ayah > 255));
    }
}

// ---- qiraat variants ----------------------------------------------------------------

#[test]
fn qiraat_variant_counts() {
    assert_eq!(engine().qiraat_variant_count(), (1409, 1634, 3503));
}

#[test]
fn qiraat_variant_readers_and_transmitters() {
    let engine = engine();
    let junctures = engine.junctures(102, 6);
    assert!(!junctures.is_empty(), "102:6 carries a variant");
    for juncture in junctures {
        assert!(juncture.readings.len() >= 2, "a juncture with one reading is not a variant");
        for reading in &juncture.readings {
            assert!(!reading.text.is_empty());
            assert!(
                !reading.readers.is_empty() || !reading.transmitters.is_empty(),
                "a reading nobody reads"
            );
            assert!(!engine.variant_attribution(reading).is_empty());
        }
    }
}

#[test]
fn hafs_follows_a_reading_at_junctures_he_is_party_to() {
    let engine = engine();
    let mut matched = 0;
    for surah in 1..=20u32 {
        for ayah in 1..=20u32 {
            for juncture in engine.junctures(surah, ayah) {
                if engine.reading_for(juncture, "hafs").is_some() {
                    matched += 1;
                }
            }
        }
    }
    assert!(matched > 0, "Hafs reads none of the sampled junctures, which cannot be right");
}

#[test]
fn segment_spans_are_inclusive_or_an_honest_none() {
    let engine = engine();
    for surah in 1..=30u32 {
        for ayah in 1..=30u32 {
            for juncture in engine.junctures(surah, ayah) {
                for segment in &juncture.segments {
                    let Some([from, to]) = segment.span else { continue };
                    assert!(to >= from);
                    let (s, a) = quran_engine::batch5::split_ayah_key(&segment.ayah);
                    assert!(to < tokens(&engine, s, a).len(), "{} span past the end", segment.ayah);
                }
            }
        }
    }
}

// ---- qiraat places ------------------------------------------------------------------

#[test]
fn places_cover_only_the_published_riwayat() {
    // Hafs is the reference and indexes nothing against itself.
    assert_eq!(
        engine().riwayat_with_places(),
        vec!["buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"]
    );
}

#[test]
fn places_point_at_tokens_the_ayah_has() {
    let engine = engine();
    for slug in engine.riwayat_with_places() {
        for surah in [1u32, 2, 18] {
            for place in engine.qiraat_places(&slug, surah) {
                let count = tokens(&engine, surah, place.ayah).len();
                for index in place.word.iter().chain(place.letter.iter()) {
                    assert!(*index < count, "{slug} {surah}:{} index {index}", place.ayah);
                }
            }
        }
    }
}

#[test]
fn al_fatihah_carries_a_difference_for_warsh() {
    let engine = engine();
    let fourth = engine
        .qiraat_places("warsh", 1)
        .into_iter()
        .find(|place| place.ayah == 4)
        .expect("Warsh differs from Hafs at 1:4");
    assert!(!fourth.word.is_empty() || !fourth.letter.is_empty());
}

// ---- paired recordings --------------------------------------------------------------

#[test]
fn audio_covers_four_riwayat_and_honestly_no_others() {
    let engine = engine();
    assert_eq!(engine.riwayat_with_audio().len(), 4);
    assert!(
        engine.variant_audio("qunbul", 1, 4).is_none(),
        "Qunbul has no reciter who published both sides with timings"
    );
}

#[test]
fn audio_pair_is_one_reciter_two_urls_and_matching_span_kinds() {
    let engine = engine();
    let mut found = 0;
    'outer: for slug in engine.riwayat_with_audio() {
        for surah in 1..=114u32 {
            for ayah in 1..=10u32 {
                let Some(pair) = engine.variant_audio(&slug, surah, ayah) else { continue };
                found += 1;
                assert!(!pair.reciter.is_empty());
                assert!(pair.hafs.url.ends_with(".mp3") && pair.riwayah.url.ends_with(".mp3"));
                assert_ne!(pair.hafs.url, pair.riwayah.url, "a pair must differ in the reading");
                assert_eq!(pair.hafs.start_ms.is_none(), pair.riwayah.start_ms.is_none());
                if let (Some(start), Some(end)) = (pair.hafs.start_ms, pair.hafs.end_ms) {
                    assert!(end > start);
                }
                if found >= 8 {
                    break 'outer;
                }
                break;
            }
        }
    }
    assert!(found >= 4, "only found {found} pairs");
}

// ---- word of the day ----------------------------------------------------------------

#[test]
fn word_of_day_count() {
    assert_eq!(engine().word_of_day_count().0, 149);
}

#[test]
fn word_of_day_walk_wraps_and_handles_a_negative_index() {
    let engine = engine();
    let all = engine.words_of_day();
    let n = all.len() as i64;
    assert_eq!(engine.word_of_day_for_index(0).unwrap().id, all[0].id);
    assert_eq!(engine.word_of_day_for_index(n).unwrap().id, all[0].id);
    assert_eq!(engine.word_of_day_for_index(-1).unwrap().id, all[all.len() - 1].id);
}

#[test]
fn word_of_day_count_is_the_length_of_the_list_behind_it() {
    for word in engine().words_of_day() {
        let total: usize = word.occurrences.iter().map(|o| o.tokens.len()).sum();
        assert_eq!(word.count as usize, total, "{}", word.id);
    }
}

#[test]
fn word_of_day_anchor_and_folded_tokens() {
    // Occurrences were matched FOLDED upstream, so ٱلۡحَمۡدُۖ at 64:1 is the same form as
    // ٱلۡحَمۡدُ; comparing written tokens literally would call a pause mark a mismatch.
    let engine = engine();
    for word in engine.words_of_day() {
        let first = &word.occurrences[0];
        assert_eq!((first.surah, first.ayah, first.tokens[0]), (word.surah, word.ayah, word.token));
        let target = fold_token(&word.arabic);
        for occurrence in &word.occurrences {
            let row = tokens(&engine, occurrence.surah, occurrence.ayah);
            for &index in &occurrence.tokens {
                assert_eq!(
                    fold_token(&row[index]),
                    target,
                    "{} at {}:{} token {index}",
                    word.id,
                    occurrence.surah,
                    occurrence.ayah
                );
            }
        }
    }
}

#[test]
fn word_of_day_search_and_reverse_lookup() {
    let engine = engine();
    let first = &engine.words_of_day()[0];
    assert!(engine.search_words_of_day(&first.arabic, 25).iter().any(|w| w.id == first.id));
    assert!(engine.words_of_day_in(first.surah, first.ayah).iter().any(|w| w.id == first.id));
}
