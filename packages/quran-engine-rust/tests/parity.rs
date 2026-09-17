//! The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah outlines,
//! alphabet reference and qiraat comparison that followed it.
//!
//! Mirrors the JS `test/parity.test.js`, the Python `tests/test_parity.py` and the Swift
//! `ParityTests.swift` case for case, so a divergence between the ports shows up as a failing test
//! rather than as a surprise in an app.

use quran_engine::corpora::SimilarAyahsFile;
use quran_engine::{Engine, LoadOptions, PassageKind, Semantic, QUESTION_WORDS};

fn engine() -> Engine {
    Engine::load_default_with(LoadOptions {
        mushaf: true,
        qiraat_tajweed: true,
        word_by_word: true,
        similar_ayahs: true,
        qiraat: true,
        // Batch 5 has its own suite; spelling the rest out here keeps this file's intent clear
        // and means a new corpus does not silently join every existing test's working set.
        ..Default::default()
    })
    .expect("engine loads")
}

// ---- mushaf -------------------------------------------------------------------------

#[test]
fn twenty_riwayat_eight_with_text() {
    let engine = engine();
    assert_eq!(engine.riwayat().len(), 20);
    assert_eq!(engine.riwayat_with_text().len(), 8);
    assert_eq!(engine.mushaf_total_pages(), 604);
    assert_eq!(engine.riwayah("warsh").unwrap().imam, "Nafi");
    assert!(!engine.riwayah("hisham").unwrap().text_included);
}

#[test]
fn every_riwayah_has_a_facsimile_and_a_full_page_table() {
    let engine = engine();
    for entry in engine.riwayat() {
        assert!(entry.pdf.starts_with("pdfs/"), "{}", entry.riwayah);
        assert!(entry.pdf.ends_with(".pdf.xz"), "{}", entry.riwayah);
        assert!(entry.pdf_bytes > 100_000, "{}", entry.riwayah);
        // Al-Fatihah opens page 1 and an-Nas closes page 604 in every print of the set.
        assert_eq!(engine.mushaf_page(1, 1, &entry.riwayah), Some(1), "{}", entry.riwayah);
        assert_eq!(engine.mushaf_page(114, 6, &entry.riwayah), Some(604), "{}", entry.riwayah);
    }
}

#[test]
fn pages_resolve_back_to_their_ayahs() {
    let engine = engine();
    assert_eq!(engine.mushaf_page(2, 255, "hafs"), Some(42));
    let on_page = engine.mushaf_ayahs_on_page(42, "hafs");
    assert!(on_page.iter().any(|hit| hit.surah == 2 && hit.ayah == 255));
    let first = engine.mushaf_first_ayah_of_page(1, "hafs").unwrap();
    assert_eq!((first.surah, first.ayah), (1, 1));
}

#[test]
fn line_tables_ship_exactly_where_the_text_does() {
    let engine = engine();
    for entry in engine.riwayat() {
        let breaks = engine.mushaf_line_breaks(1, 1, &entry.riwayah);
        assert_eq!(breaks.is_some(), entry.text_included, "{}", entry.riwayah);
    }
}

// ---- riwayah tajweed -----------------------------------------------------------------

#[test]
fn seven_verified_packs() {
    let engine = engine();
    assert_eq!(
        engine.qiraat_tajweed_available(),
        vec!["buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"]
    );
}

#[test]
fn legend_carries_its_explanation() {
    let engine = engine();
    let legend = engine.qiraat_legend("warsh");
    assert!(legend.len() >= 3);
    for entry in &legend {
        assert_eq!(entry.code.chars().count(), 1);
        assert!(!entry.rule.is_empty() && !entry.arabic.is_empty() && !entry.english.is_empty());
        assert!(!entry.short.is_empty(), "no description for {}", entry.rule);
    }
}

#[test]
fn word_rules_name_real_legend_codes() {
    let engine = engine();
    let rules = engine.qiraat_word_rules(2, 3, "warsh");
    assert!(!rules.is_empty());
    let codes: Vec<String> = engine.qiraat_legend("warsh").iter().map(|e| e.code.clone()).collect();
    for rule in &rules {
        assert!(codes.contains(&rule.code), "{}", rule.code);
        assert_eq!(rule.whole_word, rule.first_letter < 0);
        assert!(rule.word >= 1);
    }
}

#[test]
fn khilaf_markers() {
    let engine = engine();
    assert!(engine.has_khilaf(2, 253, "warsh"));
    assert!(!engine.has_khilaf(2, 254, "warsh"));
}

// ---- word by word ---------------------------------------------------------------------

#[test]
fn both_layers_aligned_to_the_ayahs_own_tokens() {
    let engine = engine();
    let words = engine.words(112, 1);
    let latin: Vec<&str> = words.iter().map(|w| w.transliteration.as_str()).collect();
    assert_eq!(latin, vec!["qul", "huwa", "l-lahu", "aḥadun"]);
    assert_eq!(words[0].english, "Say");
    let first_token = engine.ayah(112, 1).unwrap().text_arabic.split_whitespace().next().unwrap();
    assert_eq!(words[0].arabic, first_token);
}

#[test]
fn every_ayahs_arrays_match_its_token_count() {
    let engine = engine();
    for surah in engine.surahs() {
        for ayah in &surah.ayahs {
            let tokens = ayah.text_arabic.split_whitespace().count();
            assert_eq!(
                engine.glosses(surah.id, ayah.id).map(<[String]>::len),
                Some(tokens),
                "{}:{} english",
                surah.id,
                ayah.id
            );
            assert_eq!(
                engine.transliterations(surah.id, ayah.id).map(<[String]>::len),
                Some(tokens),
                "{}:{} transliteration",
                surah.id,
                ayah.id
            );
        }
    }
}

#[test]
fn gloss_search_finds_the_word() {
    let engine = engine();
    let hits = engine.find_gloss("the Ever-Living", 5);
    assert!(hits.iter().any(|h| h.surah == 2 && h.ayah == 255));
    assert!(hits.iter().all(|h| !h.transliteration.is_empty()));
}

// ---- similar ayahs, themes, lessons ------------------------------------------------------

#[test]
fn similar_ayahs() {
    let engine = engine();
    let matches = engine.similar_ayahs(2, 255);
    let found = matches.iter().find(|m| m.surah == 3 && m.ayah == 2).expect("3:2 is a match");
    assert!(found.verified);
    // The shared wording is a span into 3:2's own text, not a copy of it.
    assert_eq!(found.spans, vec![[0, 6]]);
    assert!(found.labels.is_empty());
    assert_eq!(found.score, None);
    assert!(engine.has_similar_ayahs(2, 255));
    assert!(engine.similar_ayah_count() > 5000);
}

#[test]
fn similar_ayahs_reads_only_version_2() {
    // A version-1 file (rows keyed at the top level, the phrase as text) loads as no data, as the
    // JS port does, rather than putting the shared wording where a span is expected.
    let v1: SimilarAyahsFile = serde_json::from_str(r#"{"2:255": [[3, 2, "phrase", 1]]}"#).unwrap();
    assert!(v1.into_ayahs().is_empty());

    let v2: SimilarAyahsFile =
        serde_json::from_str(r#"{"v": 2, "ayahs": {"2:255": [[3, 2, 1, [[0, 6]], [], null]]}}"#)
            .unwrap();
    let rows = v2.into_ayahs();
    let row = &rows["2:255"][0];
    assert_eq!((row.surah, row.ayah, row.verified), (3, 2, true));
    assert_eq!(row.spans, vec![[0, 6]]);
    assert!(row.labels.is_empty());
    assert_eq!(row.score, None);
}

#[test]
fn themes_index_both_ways() {
    let engine = engine();
    assert!(engine.topics().len() >= 300);
    assert!(engine.topic("tawheed").unwrap().ayahs.iter().any(|a| a == "2:255"));
    assert!(engine.topics_for(2, 255).iter().any(|t| t.id == "tawheed"));
    assert!(engine.topic_domains().len() >= 2);
}

#[test]
fn lessons_walk_in_course_order() {
    let engine = engine();
    let lessons = engine.tajweed_lessons();
    assert!(lessons.len() >= 30);
    assert!(engine.previous_tajweed_lesson(&lessons[0].id).is_none());
    assert_eq!(engine.next_tajweed_lesson(&lessons[0].id).unwrap().id, lessons[1].id);
    assert!(engine.tajweed_chapter_of(&lessons[0].id).is_some());
    // An example points at its words by span into the ayah's raw text (version 3): the first one
    // in the course is 112:1, the words at tokens 1..=3.
    let example = lessons
        .iter()
        .flat_map(|l| l.examples.iter())
        .find(|e| e.word_span.is_some())
        .expect("an example carries a word span");
    assert_eq!((example.surah_id, example.ayah_number), (112, 1));
    assert_eq!(example.word_span, Some([1, 3]));
}

#[test]
fn lesson_quran_references_resolve_to_the_engines_own_text() {
    // Version 4: a drill or rule-card fragment whose Arabic IS Quran carries an `ayah` reference
    // and no text at all, so a port that ignores the field shows an empty row rather than a
    // verse. This reads one back out of quran.json to prove the whole path.
    let engine = engine();
    let lessons = engine.tajweed_lessons();

    let drill = lessons
        .iter()
        .flat_map(|l| l.drills.iter())
        .find(|d| d.ayah.is_some())
        .expect("a drill references the Quran");
    let [surah, ayah, first, last] = drill.ayah.unwrap();
    assert_eq!((surah, ayah, first, last), (110, 1, 0, 4));
    assert!(drill.text.is_empty(), "a referenced drill carries no copy of the words");

    // The span names the whole of an-Nasr 1, so the words it cuts are the ayah itself. Compared
    // against the engine's own text rather than a pasted literal: a copy here would have to be
    // kept in the file's exact normalization, which is the drift this version removed.
    let text = engine.ayah(surah as u32, ayah as u32).expect("110:1 is in the Quran");
    let words: Vec<&str> = text.text_arabic.split_whitespace().collect();
    assert_eq!(words.len(), 5);
    assert_eq!(words[first..=last].join(" "), words.join(" "));

    // Every reference across drills and rule cards lands inside its ayah.
    let mut referenced = 0;
    for lesson in &lessons {
        let fragments = lesson.rule_card.iter().flat_map(|c| c.fragments.iter());
        for drill in lesson.drills.iter().chain(fragments) {
            let Some([s, a, f, l]) = drill.ayah else { continue };
            referenced += 1;
            let ayah = engine.ayah(s as u32, a as u32).expect("a real ayah");
            assert!(l < ayah.text_arabic.split_whitespace().count() && f <= l);
        }
    }
    assert_eq!(referenced, 28, "7 drills and 21 rule-card fragments reference the Quran");

    // The card itself is `ruleCard`; it was declared as `mushafCard` and so decoded to nothing.
    assert_eq!(lessons.iter().filter(|l| l.rule_card.is_some()).count(), 32);
}

// ---- meaning search ---------------------------------------------------------------------

#[test]
fn maxsim_ranks_by_meaning() {
    // A toy embedder: enough to prove the scoring, without shipping a model.
    let mut semantic = Semantic::new(|word| match word {
        "patience" => Some(vec![1.0, 0.0, 0.0]),
        "hardship" => Some(vec![0.9, 0.1, 0.0]),
        "sabr" => Some(vec![0.95, 0.05, 0.0]),
        "steadfast" => Some(vec![0.9, 0.05, 0.0]),
        "dawn" => Some(vec![0.0, 1.0, 0.0]),
        "prayer" => Some(vec![0.0, 0.95, 0.0]),
        _ => None,
    });
    semantic.index(vec![
        ("sabr".to_string(), "sabr and steadfast endurance".to_string()),
        ("fajr".to_string(), "prayer at dawn".to_string()),
    ]);
    let hits = semantic.search("patience hardship", 10, 0.0);
    assert_eq!(hits[0].id, "sabr");
    assert!(hits[0].score > hits[1].score);
}

// ---- ask AI ------------------------------------------------------------------------------

#[test]
fn named_verse_is_the_subject() {
    let engine = engine();
    let passages = engine.ask_ai_retrieve("explain ayat al-kursi", None, &[], 8);
    assert_eq!(passages[0].reference, "2:255");
    assert!(passages[0].is_subject);
}

#[test]
fn named_surah_answers_with_its_background() {
    let engine = engine();
    let passages = engine.ask_ai_retrieve("what is surah al-kahf about", None, &[], 8);
    assert_eq!(passages[0].reference, "Surah Al-Kahf");
    assert_eq!(passages[0].kind, PassageKind::Surah);
}

#[test]
fn keyword_lane_is_weighted() {
    let engine = engine();
    let passages = engine.ask_ai_retrieve(
        "what does the Quran say about patience in hardship",
        None,
        &[],
        8,
    );
    assert!(passages.iter().any(|p| p.reference == "2:153"));
    for passage in &passages {
        if passage.kind == PassageKind::Ayah {
            assert!(engine.ayah(passage.surah.unwrap(), passage.ayah.unwrap()).is_some());
        }
    }
}

#[test]
fn bare_follow_up_uses_the_previous_question() {
    let engine = engine();
    let carried = engine.ask_ai_retrieve("tell me about 2:153", None, &[], 8);
    assert!(engine.ask_ai_retrieve("why?", None, &[], 8).is_empty());
    let with_context =
        engine.ask_ai_retrieve("why?", Some("tell me about 2:153"), &carried, 8);
    assert!(with_context.iter().any(|p| p.reference == "2:153"));
}

#[test]
fn prompt_shape() {
    let engine = engine();
    let passages = engine.ask_ai_retrieve("explain 2:153", None, &[], 8);
    let (instructions, prompt) = quran_engine::chat_prompt("explain 2:153", &passages, &[]);
    assert!(instructions.contains("Never issue a religious ruling"));
    assert!(prompt.contains("SUBJECT OF THE QUESTION [2:153]"));
    assert!(prompt.trim_end().ends_with("QUESTION: explain 2:153"));
    assert!(QUESTION_WORDS.contains(&"what"));
}

// ---- surah sections -------------------------------------------------------------------

#[test]
fn sections_111_surahs_and_a_chain() {
    let engine = engine();
    assert_eq!(engine.outlined_surah_count(), 111);
    assert!(engine.surah_overview(1).len() > 20);
    assert!(!engine.has_sections(1));

    // Hud opens with a broad passage and the sections inside it - an ayah has a chain, not a row.
    let chain: Vec<String> =
        engine.sections_for(11, 3).into_iter().map(|s| s.english).collect();
    assert_eq!(chain, vec!["Doctrine facts", "Calling to Allah"]);
    assert_eq!(engine.section_for(11, 3).unwrap().english, "Calling to Allah");
}

#[test]
fn outline_rebuilds_the_nesting() {
    let engine = engine();
    let roots = engine.outline(11);
    assert!(roots.len() >= 2);
    assert_eq!(roots[0].section.english, "Doctrine facts");
    assert_eq!(roots[0].children.len(), 5);
    assert!(roots[0]
        .children
        .iter()
        .all(|c| c.section.from >= roots[0].section.from && c.section.to <= roots[0].section.to));
}

#[test]
fn section_ranges_are_inside_their_surah() {
    let engine = engine();
    for surah in engine.surahs() {
        for section in engine.sections(surah.id) {
            assert!(
                section.from >= 1 && section.to <= surah.number_of_ayahs,
                "{}: {}-{}",
                surah.id,
                section.from,
                section.to
            );
            assert!(section.from <= section.to);
            assert!(!section.english.is_empty() && !section.arabic.is_empty());
        }
    }
    let nuh = engine.search_sections("Story of Nuh");
    assert!(nuh.len() >= 2);
    assert!(nuh.iter().any(|(surah, _)| *surah == 11));
}

// ---- arabic alphabet ------------------------------------------------------------------

#[test]
fn alphabet_28_letters_each_with_a_weight() {
    let engine = engine();
    assert_eq!(engine.letters().len(), 28);
    let weights = engine.weight_descriptions();
    for letter in engine.letters() {
        assert!(!letter.letter.is_empty() && !letter.name.is_empty());
        let weight = letter.weight.as_deref().unwrap_or_default();
        assert!(!weight.is_empty(), "{} has no weight", letter.letter);
        assert!(weights.contains_key(weight), "no description for weight {weight}");
    }
    // Alif is the one letter with no weight of its own - the fact the whole field exists for.
    assert_eq!(engine.letter_weight("ا"), Some("followsPrevious"));
    assert_eq!(engine.letter_weight("ص"), Some("heavy"));
    assert_eq!(engine.letter_weight("س"), Some("light"));
}

#[test]
fn alphabet_resolves_a_joining_form() {
    let engine = engine();
    assert_eq!(engine.letter("ـصـ").unwrap().transliteration, "Saad");
    assert_eq!(engine.letter_by_id(1).unwrap().letter, "ا");
    assert!(engine.letter("nope").is_none());
}

#[test]
fn alphabet_tashkeel_numerals_and_waqf() {
    let engine = engine();
    assert!(engine.tashkeel().len() >= 8);
    assert_eq!(engine.arabic_numbers().len(), 11);
    assert_eq!(engine.stopping_sign("۩").unwrap().title, "Make Sujood");
    assert!(engine.heavy_letters().len() >= 7);
}

// ---- qiraat comparison ----------------------------------------------------------------

#[test]
fn comparison_lists_only_published_readings() {
    let engine = engine();
    assert_eq!(
        engine.comparable_riwayat(),
        vec!["buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh"]
    );
}

#[test]
fn a_reading_against_itself_is_identical() {
    let engine = engine();
    let same = engine.compare_surah(2, "hafs", "hafs");
    assert_eq!(same.identical, same.words);
    assert_eq!(same.same_skeleton, 0);
    assert_eq!(same.different, 0);
    assert_eq!(same.added, 0);
    assert_eq!(same.dropped, 0);
    assert_eq!(same.identical_percent(), 100.0);
}

#[test]
fn buckets_add_up_and_shubah_is_nearer_than_warsh() {
    let engine = engine();
    let warsh = engine.compare_surah(2, "warsh", "hafs");
    let shubah = engine.compare_surah(2, "shubah", "hafs");
    for totals in [warsh, shubah] {
        assert_eq!(
            totals.identical + totals.same_skeleton + totals.different + totals.dropped,
            totals.words
        );
    }
    // Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
    assert!(shubah.identical_percent() > warsh.identical_percent());
    assert!(shubah.identical_percent() > 95.0);
}

#[test]
fn differences_are_in_reading_order() {
    let engine = engine();
    let rows = engine.qiraat_differences(2, "warsh", "hafs", 20);
    assert!(!rows.is_empty());
    assert!(rows.iter().all(|row| row.base != row.other));
    let positions: Vec<usize> = rows.iter().map(|row| row.position).collect();
    let mut sorted = positions.clone();
    sorted.sort_unstable();
    assert_eq!(positions, sorted);
}

#[test]
fn word_streams_follow_the_readings_own_verse_count() {
    let engine = engine();
    // Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
    // different verses from that point on; the comparison walks the surah's words instead.
    assert_eq!(engine.number_of_ayahs_in_qiraah(2, "warsh"), 285);
    assert_eq!(engine.qiraah_verses(2, "warsh").len(), 285);
    assert!(engine.qiraah_words(2, "warsh").len() > 6000);
}
