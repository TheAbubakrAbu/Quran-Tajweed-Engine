//! Conformance test — runs the language-agnostic vectors in `/conformance/vectors.json` against the
//! engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a behavior is specified ONCE in
//! that JSON, and every language port runs the same file (see docs/PORTING.md → "Conformance
//! vectors"). The JS port (`packages/quran-engine-js/test/conformance.test.js`) is the reference
//! consumer; this mirrors that harness.
//!
//! Vectors are read generically via `serde_json::Value` so adding a case to the JSON requires no
//! changes here.

use std::path::PathBuf;

use quran_engine::{CountFilter, CountOp, Engine, SearchOpts};
use serde_json::Value;

/// Locate `conformance/vectors.json` relative to this crate's manifest dir (`../../conformance/...`).
fn load_vectors() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../conformance/vectors.json");
    let bytes = std::fs::read(&path)
        .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_slice(&bytes)
        .unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

fn engine() -> Engine {
    Engine::load_default().expect("load_default should find the repo data dir")
}

/// Parse a `"surah:ayah"` reference string into a `(surah, ayah)` pair.
fn parse_ref(id: &str) -> (u32, u32) {
    let (s, a) = id.split_once(':').unwrap_or_else(|| panic!("bad ref {id}"));
    (s.parse().unwrap(), a.parse().unwrap())
}

/// Parse a `{ op, value }` JSON object into a `CountFilter`; `Value::Null`/absent => `None`.
fn parse_filter(v: &Value) -> Option<CountFilter> {
    let obj = v.as_object()?;
    let op = CountOp::parse(obj.get("op")?.as_str()?);
    let value = obj.get("value")?.as_u64()? as u32;
    Some(CountFilter::new(op, value))
}

/// Slice of `vectors[key]` as an array (panics if absent / not an array).
fn cases<'a>(vectors: &'a Value, key: &str) -> &'a Vec<Value> {
    vectors[key]
        .as_array()
        .unwrap_or_else(|| panic!("vectors.{key} should be an array"))
}

#[test]
fn conformance_search_verses() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "searchVerses") {
        let query = v["query"].as_str().expect("searchVerses case needs a string query");
        let ids: Vec<String> = e
            .search_verses(query, &SearchOpts::default())
            .iter()
            .map(|h: &quran_engine::VerseHit| format!("{}:{}", h.surah, h.ayah))
            .collect();

        if v["empty"].as_bool() == Some(true) {
            assert!(ids.is_empty(), "\"{query}\" should be empty, got {ids:?}");
        }
        if let Some(contains) = v["contains"].as_array() {
            for id in contains {
                let id = id.as_str().unwrap();
                assert!(ids.iter().any(|x| x == id), "\"{query}\" should contain {id}, got {ids:?}");
            }
        }
        if let Some(excludes) = v["excludes"].as_array() {
            for id in excludes {
                let id = id.as_str().unwrap();
                assert!(!ids.iter().any(|x| x == id), "\"{query}\" should exclude {id}, got {ids:?}");
            }
        }
    }
}

#[test]
fn conformance_juz_from_end() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "juzFromEnd") {
        let n = v["n"].as_u64().expect("juzFromEnd case needs n") as u32;
        let got: Option<u32> = e.juz_from_end(n).map(|j| j.id);
        // `id: null` in the vector => expect None.
        let expected: Option<u32> = v["id"].as_u64().map(|x| x as u32);
        assert_eq!(got, expected, "juzFromEnd({n})");
    }
}

#[test]
fn conformance_juz_stats() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "juzStats") {
        let juz = v["juz"].as_u64().expect("juzStats case needs juz") as u32;
        let s = e.juz_stats(juz);
        if v["isNull"].as_bool() == Some(true) {
            assert!(s.is_none(), "juzStats({juz}) should be null");
            continue;
        }
        let s = s.unwrap_or_else(|| panic!("juzStats({juz}) should be present"));
        assert_eq!(u64::from(s.surah_count), v["surahCount"].as_u64().unwrap(), "juzStats({juz}).surahCount");
        assert_eq!(u64::from(s.ayah_count), v["ayahCount"].as_u64().unwrap(), "juzStats({juz}).ayahCount");
        assert_eq!(u64::from(s.word_count), v["wordCount"].as_u64().unwrap(), "juzStats({juz}).wordCount");
        assert_eq!(u64::from(s.letter_count), v["letterCount"].as_u64().unwrap(), "juzStats({juz}).letterCount");
        assert_eq!(u64::from(s.page_count), v["pageCount"].as_u64().unwrap(), "juzStats({juz}).pageCount");
    }

    // Invariant: the 30 juz partition all 6236 ayahs exactly.
    let sum: u32 = (1..=30).map(|i| e.juz_stats(i).unwrap().ayah_count).sum();
    let expected = vectors["juzStatsInvariant"]["sumAyahCountAllJuz"].as_u64().unwrap();
    assert_eq!(u64::from(sum), expected, "sum of ayah_count over all juz");
}

#[test]
fn conformance_surah_from_end() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "surahFromEnd") {
        let n = v["n"].as_u64().expect("surahFromEnd case needs n") as u32;
        let got: Option<u32> = e.surah_from_end(n).map(|s| s.id);
        // `id: null` in the vector => expect None.
        let expected: Option<u32> = v["id"].as_u64().map(|x| x as u32);
        assert_eq!(got, expected, "surahFromEnd({n})");
    }
}

#[test]
fn conformance_sajdah() {
    let vectors = load_vectors();
    let e = engine();
    let sj = &vectors["sajdah"];

    let ids: Vec<String> = e
        .sajdah_ayahs()
        .iter()
        .map(|(s, a)| format!("{}:{}", s.id, a.id))
        .collect();
    assert_eq!(
        ids.len() as u64,
        sj["count"].as_u64().expect("sajdah.count"),
        "sajdah count"
    );

    if let Some(contains) = sj["contains"].as_array() {
        for id in contains {
            let id = id.as_str().unwrap();
            assert!(ids.iter().any(|x| x == id), "sajdah should contain {id}");
            let (s, a) = parse_ref(id);
            assert!(e.is_sajdah_ayah(s, a), "isSajdahAyah({id})");
        }
    }
    if let Some(excludes) = sj["excludes"].as_array() {
        for id in excludes {
            let id = id.as_str().unwrap();
            let (s, a) = parse_ref(id);
            assert!(!e.is_sajdah_ayah(s, a), "isSajdahAyah({id}) should be false");
        }
    }
}

#[test]
fn conformance_surah_info() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "surahInfo") {
        let surah = v["surah"].as_u64().expect("surahInfo case needs surah") as u32;
        let sources = e.surah_info(surah);
        let min = v["minSources"].as_u64().unwrap_or(1) as usize;
        assert!(sources.len() >= min, "info({surah}) sources");
        if let Some(name) = v["hasSourceName"].as_str() {
            assert!(
                sources.iter().any(|s| s.name == name),
                "info({surah}) has {name}"
            );
        }
    }
}

#[test]
fn conformance_names_of_allah() {
    let vectors = load_vectors();
    let e = engine();
    let n = &vectors["namesOfAllah"];
    assert_eq!(
        e.names_of_allah().len() as u64,
        n["count"].as_u64().expect("namesOfAllah.count"),
        "namesOfAllah count"
    );
    if let Some(by_number) = n["byNumber"].as_array() {
        for v in by_number {
            let number = v["number"].as_u64().expect("byNumber needs number") as u32;
            let expected = v["transliteration"].as_str().expect("byNumber needs transliteration");
            assert_eq!(
                e.name_of_allah(number).map(|x| x.transliteration.as_str()),
                Some(expected),
                "name_of_allah({number}).transliteration"
            );
        }
    }
}

#[test]
fn conformance_filter_by_counts() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "filterByCounts") {
        let ayahs = parse_filter(&v["ayahs"]);
        let pages = parse_filter(&v["pages"]);
        let mut ids: Vec<u32> = e.filter_by_counts(ayahs, pages).iter().map(|s| s.id).collect();
        ids.sort_unstable();
        let mut expected: Vec<u32> = v["ids"]
            .as_array()
            .expect("filterByCounts case needs ids")
            .iter()
            .map(|x| x.as_u64().unwrap() as u32)
            .collect();
        expected.sort_unstable();
        assert_eq!(ids, expected, "filterByCounts {v}");
    }
}

#[test]
fn conformance_surah_flags() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "surahFlags") {
        let surah = v["surah"].as_u64().expect("surahFlags case needs surah") as u32;
        assert_eq!(
            e.page_changes_within_surah(surah),
            v["pageChanges"].as_bool().expect("pageChanges"),
            "pageChanges({surah})"
        );
        assert_eq!(
            e.juz_changes_within_surah(surah),
            v["juzChanges"].as_bool().expect("juzChanges"),
            "juzChanges({surah})"
        );
        assert_eq!(
            e.page_or_juz_changes_within_surah(surah),
            v["pageOrJuz"].as_bool().expect("pageOrJuz"),
            "pageOrJuz({surah})"
        );
    }
}

#[test]
fn conformance_exists_and_number_in_qiraah() {
    let vectors = load_vectors();
    let e = engine();

    for v in cases(&vectors, "existsInQiraah") {
        let surah = v["surah"].as_u64().expect("existsInQiraah case needs surah") as u32;
        let ayah = v["ayah"].as_u64().expect("existsInQiraah case needs ayah") as u32;
        let riwayah = v["riwayah"].as_str().expect("existsInQiraah case needs riwayah");
        let expected = v["exists"].as_bool().expect("existsInQiraah case needs exists");
        assert_eq!(
            e.exists_in_qiraah(surah, ayah, riwayah),
            expected,
            "existsInQiraah({surah},{ayah},{riwayah})"
        );
    }

    for v in cases(&vectors, "numberOfAyahsInQiraah") {
        let surah = v["surah"].as_u64().expect("numberOfAyahsInQiraah case needs surah") as u32;
        let riwayah = v["riwayah"].as_str().expect("numberOfAyahsInQiraah case needs riwayah");
        let expected = v["count"].as_u64().expect("numberOfAyahsInQiraah case needs count") as u32;
        assert_eq!(
            e.number_of_ayahs_in_qiraah(surah, riwayah),
            expected,
            "numberOfAyahsInQiraah({surah},{riwayah})"
        );
    }
}

#[test]
fn conformance_muqattaat() {
    /// U+0653 ARABIC MADDAH ABOVE — the madd-lāzim mark long vowels carry.
    const MADDAH: char = '\u{0653}';

    let vectors = load_vectors();
    let e = engine();
    let m = &vectors["muqattaat"];

    assert_eq!(
        e.muqattaat().len() as u64,
        m["count"].as_u64().expect("muqattaat.count"),
        "muqattaat count"
    );

    if let Some(pronunciations) = m["pronunciations"].as_array() {
        for p in pronunciations {
            let surah = p["surah"].as_u64().expect("pronunciation surah") as u32;
            let ayah = p["ayah"].as_u64().expect("pronunciation ayah") as u32;
            let got = e
                .muqattaat_pronunciation(surah, ayah)
                .unwrap_or_else(|| panic!("muqattaat {surah}:{ayah} present"));
            assert_eq!(
                got.transliteration,
                p["transliteration"].as_str().expect("transliteration"),
                "muqattaat {surah}:{ayah} transliteration"
            );
            if p["spelledContainsMaddah"].as_bool() == Some(true) {
                assert!(
                    got.spelled_out_arabic.contains(MADDAH),
                    "muqattaat {surah}:{ayah} keeps madd-lāzim maddah"
                );
            }
        }
    }

    if let Some(absent) = m["absent"].as_array() {
        for a in absent {
            let surah = a["surah"].as_u64().expect("absent surah") as u32;
            let ayah = a["ayah"].as_u64().expect("absent ayah") as u32;
            assert!(
                e.muqattaat_pronunciation(surah, ayah).is_none(),
                "muqattaat {surah}:{ayah} absent"
            );
        }
    }
}

#[test]
fn conformance_tajweed() {
    let vectors = load_vectors();
    let e = engine();
    for v in cases(&vectors, "tajweed") {
        let surah = v["surah"].as_u64().unwrap() as u32;
        let ayah = v["ayah"].as_u64().unwrap() as u32;
        let spans = e.tajweed(surah, ayah);
        let rules: Vec<&str> = spans.iter().map(|s| s.rule.as_str()).collect();

        if let Some(excluded) = v["excludesRule"].as_str() {
            assert!(
                !rules.contains(&excluded),
                "{surah}:{ayah} should NOT have rule {excluded}, got {rules:?}"
            );
        }
        if let Some(last_rule) = v["lastSpanRule"].as_str() {
            let last = spans
                .iter()
                .max_by_key(|s| s.start)
                .unwrap_or_else(|| panic!("{surah}:{ayah} should have spans"));
            assert_eq!(last.rule, last_rule, "{surah}:{ayah} last span rule");
        }
    }
}
