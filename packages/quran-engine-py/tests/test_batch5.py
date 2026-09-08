"""Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil, the qiraat
variant matrix and the word of the day.

Mirrors packages/quran-engine-js/test/batch5.test.js case for case, so a divergence between the
two reference ports shows up as a failing test rather than as a surprise in an app. Every count
is pinned against the app's own verify gate.
"""
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine, fold_for_morphology  # noqa: E402

engine = Engine.load(load_morphology=True, load_mutashabihat=True,
                     load_quran_topics=True, load_qiraat_variants=True)

TREES = ("thematic", "ontology", "index")
_MARKS = re.compile("[ً-ٰٟۖ-ۭـ]")


def _fold_token(text: str) -> str:
    return (_MARKS.sub("", text)
            .replace("ٱ", "ا").replace("أ", "ا").replace("إ", "ا")
            .replace("ؤ", "و").replace("ئ", "ي"))


def _tokens(surah: int, ayah: int) -> list[str]:
    a = engine.quran.ayah(surah, ayah)
    return (a.text_arabic if a else "").split()


# ---- morphology -------------------------------------------------------------------

def test_morphology_corpus_size_matches_the_app_gate():
    assert engine.morphology.count() == {"roots": 1642, "lemmas": 4817, "tokens": 77629}


def test_morphology_ids_are_one_based_and_zero_means_no_root():
    assert engine.morphology.root(0) is None
    assert engine.morphology.root(1) is not None
    ids = engine.morphology.ids(1, 1)
    assert len(ids["roots"]) == 4
    assert len(ids["lemmas"]) == 4


def test_morphology_a_token_resolves_to_its_root_and_dictionary_form():
    root = engine.morphology.root_of(1, 2, 2)
    assert root["root"]["letters"] == "ر ب ب"
    assert root["root"]["buckwalter"] == "rbb"
    assert root["root"]["joined"] == "ربب"
    assert engine.morphology.lemma_of(1, 2, 2)["lemma"]["text"]


def test_morphology_occurrences_come_back_in_mushaf_order():
    rbb = engine.morphology.find_roots("ربب")[0]
    hits = engine.morphology.occurrences_of_root(rbb["id"])
    assert len(hits) == 980
    assert hits[0] == {"surah": 1, "ayah": 2, "token": 2}
    ranks = [(h["surah"], h["ayah"], h["token"]) for h in hits]
    assert ranks == sorted(ranks)


def test_morphology_a_root_is_found_spaced_closed_up_or_in_buckwalter():
    # The fold has to close the spaces, not merely trim them: a lexicon prints "ر ب ب" and a
    # reader types "ربب".
    assert fold_for_morphology("ر ب ب") == "ربب"
    for query in ("ربب", "ر ب ب", "rbb"):
        assert any(h["root"]["buckwalter"] == "rbb"
                   for h in engine.morphology.find_roots(query, 5)), query


def test_morphology_ids_stop_at_the_table_size():
    assert engine.morphology.root(1643) is None


# ---- mutashabihat -----------------------------------------------------------------

def test_mutashabihat_counts():
    assert engine.mutashabihat.count() == {"phrases": 814, "ayahs": 2232}


def test_mutashabihat_a_phrase_knows_its_source_span_and_occurrences():
    phrase = engine.mutashabihat.phrase(10167)
    assert phrase["source"] == "9:87"
    assert phrase["span"] == (5, 10)
    assert phrase["word_count"] == 6
    assert phrase["ayah_count"] == 3
    assert phrase["surah_count"] == 2
    assert phrase["occurrences"]["9:93"] == [[13, 19]]


def test_mutashabihat_occurrences_are_in_mushaf_order_not_key_order():
    assert [o["key"] for o in engine.mutashabihat.occurrences(10167)] == ["9:87", "9:93", "63:3"]


def test_mutashabihat_a_phrase_slices_out_of_the_text_you_hand_it():
    source = engine.quran.ayah(9, 87).text_arabic
    text = engine.mutashabihat.text_of(10167, source)
    assert len(text.split()) == 6
    assert text.split()[0] in source


def test_mutashabihat_has_agrees_with_phrases_for():
    assert engine.mutashabihat.has(9, 87) is True
    assert engine.mutashabihat.phrases_for(9, 87)
    assert engine.mutashabihat.has(1, 1) == bool(engine.mutashabihat.phrases_for(1, 1))


# ---- QUL topics -------------------------------------------------------------------

def test_topics_counts_and_the_double_listing():
    counts = engine.quran_topics.count()
    assert counts["topics"] == 2512
    assert counts["references"] == 30687
    # Deliberately sums to MORE than the topic count: 17 topics are listed in two indexes.
    assert counts["thematic"] + counts["ontology"] + counts["index"] == 2529
    assert (counts["thematic"], counts["ontology"], counts["index"]) == (695, 284, 1550)


def test_topics_three_independent_trees_not_a_partition():
    both = [t for t in engine.quran_topics.all() if len(t["families"]) > 1]
    assert len(both) == 17
    assert engine.quran_topics.topic(13)["families"] == ["thematic", "ontology"]
    assert engine.quran_topics.parent(13, "thematic")["name"] == "Prophets (25 mentioned by name)"
    assert engine.quran_topics.parent(13, "ontology")["name"] == "Prophet"
    # A tree is not closed over its own listing: the A-Z index hangs entries under thematic
    # topics, so asserting a parent shares its child's family would be false.
    crossing = [t for t in engine.quran_topics.all()
                if t["parents"].get("index")
                and "index" not in (engine.quran_topics.topic(t["parents"]["index"]) or
                                    {"families": []})["families"]]
    assert crossing


def test_topics_every_parent_id_resolves_in_every_tree():
    for topic in engine.quran_topics.all():
        for tree in TREES:
            parent_id = topic["parents"].get(tree)
            if parent_id:
                assert engine.quran_topics.topic(parent_id) is not None, (topic["id"], tree)


def test_topics_ancestors_terminate_in_every_tree():
    for tree in TREES:
        deep = next(t for t in engine.quran_topics.all()
                    if len(engine.quran_topics.ancestors(t["id"], tree)) >= 2)
        chain = engine.quran_topics.ancestors(deep["id"], tree)
        assert len({t["id"] for t in chain}) == len(chain)
        assert chain[-1]["parents"].get(tree) is None


def test_topics_a_child_is_listed_under_the_parent_it_names():
    for tree in TREES:
        child = next(t for t in engine.quran_topics.all() if t["parents"].get(tree))
        siblings = engine.quran_topics.children(child["parents"][tree], tree)
        assert any(s["id"] == child["id"] for s in siblings)


def test_topics_references_are_real_ayahs_and_reverse_lookup_agrees():
    sample = engine.quran_topics.all()[:200]
    for topic in sample:
        for key in topic["ayahs"]:
            s, a = (int(p) for p in key.split(":"))
            assert engine.quran.ayah(s, a) is not None, (topic["name"], key)
    first = sample[0]
    s, a = (int(p) for p in first["ayahs"][0].split(":"))
    assert any(t["id"] == first["id"] for t in engine.quran_topics.topics_for(s, a))


# ---- passage themes ---------------------------------------------------------------

def test_ayah_themes_counts():
    assert engine.ayah_themes.count() == {"surahs": 114, "passages": 1049}


def test_ayah_themes_passages_are_ordered_and_never_overlap():
    for surah in engine.quran.all():
        previous_end = 0
        for passage in engine.ayah_themes.passages(surah.id):
            assert passage["from_"] > previous_end or previous_end == 0
            assert passage["to"] >= passage["from_"]
            assert passage["to"] <= surah.number_of_ayahs
            previous_end = max(previous_end, passage["to"])


def test_ayah_themes_an_ayah_lands_in_its_passage():
    passage = engine.ayah_themes.passage_for(2, 10)
    assert passage["theme"] == "Hypocrites and the consequences of hypocrisy"
    assert (passage["from_"], passage["to"]) == (8, 16)


# ---- hizb / ruku / manzil ---------------------------------------------------------

def test_metadata_counts_and_first_starts():
    assert engine.quran_metadata.count() == {"hizb": 60, "ruku": 558, "manzil": 7}
    for table in (engine.quran_metadata.hizb, engine.quran_metadata.ruku,
                  engine.quran_metadata.manzil):
        assert table.start(1) == {"number": 1, "surah": 1, "ayah": 1, "key": "1:1"}


def test_metadata_every_start_is_ascending_and_real():
    for table in (engine.quran_metadata.hizb, engine.quran_metadata.ruku,
                  engine.quran_metadata.manzil):
        rows = table.all()
        for a, b in zip(rows, rows[1:]):
            assert (a["surah"], a["ayah"]) < (b["surah"], b["ayah"])
            assert engine.quran.ayah(b["surah"], b["ayah"]) is not None


def test_metadata_lookup_returns_the_division_containing_the_ayah():
    assert engine.quran_metadata.for_ayah(1, 1) == {"hizb": 1, "ruku": 1, "manzil": 1}
    last = engine.quran_metadata.for_ayah(114, 6)
    assert last["hizb"] == 60 and last["manzil"] == 7
    n = engine.quran_metadata.hizb.number_for(2, 255)
    span = engine.quran_metadata.hizb.range(n)
    assert (span["from_"]["surah"], span["from_"]["ayah"]) <= (2, 255)
    assert span["until"] is None or (span["until"]["surah"], span["until"]["ayah"]) > (2, 255)


# ---- qiraat variants --------------------------------------------------------------

def test_variants_counts():
    assert engine.qiraat_variants.count() == {"ayahs": 1409, "junctures": 1634, "readings": 3503}


def test_variants_ten_readers_twenty_transmitters_eight_published():
    readers = list(engine.qiraat_variants._readers.values())
    transmitters = list(engine.qiraat_variants._transmitters.values())
    assert len(readers) == 10
    assert len(transmitters) == 20
    for t in transmitters:
        assert engine.qiraat_variants.reader(t["reader"]) is not None, t["name"]
    assert sum(1 for t in transmitters if t["textPublished"]) == 8


def test_variants_a_juncture_names_word_readings_and_who_reads_them():
    junctures = engine.qiraat_variants.junctures(102, 6)
    assert junctures
    juncture = junctures[0]
    assert len(juncture["readings"]) >= 2
    for reading in juncture["readings"]:
        assert reading["text"]
        assert reading.get("readers") or reading.get("transmitters")


def test_variants_every_reading_has_an_attribution():
    for key in list(engine.qiraat_variants._ayahs)[:50]:
        s, a = (int(p) for p in key.split(":"))
        for juncture in engine.qiraat_variants.junctures(s, a):
            for reading in juncture["readings"]:
                assert engine.qiraat_variants.attribution(reading), key


def test_variants_hafs_follows_a_reading_at_junctures_he_is_party_to():
    matched = 0
    for key in list(engine.qiraat_variants._ayahs)[:100]:
        s, a = (int(p) for p in key.split(":"))
        for juncture in engine.qiraat_variants.junctures(s, a):
            if engine.qiraat_variants.reading_for(juncture, "hafs"):
                matched += 1
    assert matched > 0


def test_variants_segment_spans_are_inclusive_or_an_honest_none():
    for key in list(engine.qiraat_variants._ayahs)[:200]:
        s, a = (int(p) for p in key.split(":"))
        for juncture in engine.qiraat_variants.junctures(s, a):
            for segment in juncture["segments"]:
                if segment["span"] is None:
                    continue
                start, end = segment["span"]
                assert 0 <= start <= end
                ss, sa = (int(p) for p in segment["ayah"].split(":"))
                assert end < len(_tokens(ss, sa)), segment["ayah"]


# ---- qiraat places ----------------------------------------------------------------

def test_places_only_the_published_riwayat_are_indexed():
    slugs = engine.qiraat_variants.riwayat_with_places()
    assert len(slugs) == 7  # Hafs is the reference and indexes nothing against itself
    assert slugs == sorted(["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"])


def test_places_every_index_points_at_a_token_the_ayah_has():
    for slug in engine.qiraat_variants.riwayat_with_places():
        for surah in (1, 2, 18):
            for row in engine.qiraat_variants.places(slug, surah):
                count = len(_tokens(surah, row["ayah"]))
                for index in list(row["word"]) + list(row["letter"]):
                    assert 0 <= index < count, (slug, surah, row["ayah"], index)


def test_places_al_fatihah_carries_a_difference_for_warsh():
    rows = engine.qiraat_variants.places("warsh", 1)
    fourth = next((r for r in rows if r["ayah"] == 4), None)
    assert fourth is not None
    assert fourth["word"] or fourth["letter"]


# ---- paired recordings ------------------------------------------------------------

def test_audio_four_riwayat_have_pairs_and_the_rest_honestly_have_none():
    assert len(engine.qiraat_variants.riwayat_with_audio()) == 4
    assert engine.qiraat_variants.audio("qunbul", 1, 4) is None


def test_audio_a_pair_is_one_reciter_two_urls_and_matching_span_kinds():
    found = 0
    for slug in engine.qiraat_variants.riwayat_with_audio():
        for surah in range(1, 115):
            if found >= 8:
                break
            for ayah in range(1, 11):
                pair = engine.qiraat_variants.audio(slug, surah, ayah)
                if not pair:
                    continue
                found += 1
                assert pair["reciter"]
                assert pair["hafs"]["url"].endswith(".mp3")
                assert pair["riwayah"]["url"].endswith(".mp3")
                assert pair["hafs"]["url"] != pair["riwayah"]["url"]
                assert (pair["hafs"]["start_ms"] is None) == (pair["riwayah"]["start_ms"] is None)
                if pair["hafs"]["start_ms"] is not None:
                    assert pair["hafs"]["end_ms"] > pair["hafs"]["start_ms"]
                    assert pair["riwayah"]["end_ms"] > pair["riwayah"]["start_ms"]
                break
    assert found >= 4


# ---- word of the day --------------------------------------------------------------

def test_word_of_day_count():
    assert engine.word_of_day.count()["words"] == 149


def test_word_of_day_walk_is_stable_wraps_and_handles_a_negative_index():
    words = engine.word_of_day.all()
    n = len(words)
    assert engine.word_of_day.for_day_index(0)["id"] == words[0]["id"]
    assert engine.word_of_day.for_day_index(n)["id"] == words[0]["id"]
    assert engine.word_of_day.for_day_index(-1)["id"] == words[n - 1]["id"]
    assert engine.word_of_day.for_date(date(2026, 9, 8))["id"] == \
        engine.word_of_day.for_date(date(2026, 9, 8))["id"]


def test_word_of_day_the_count_is_the_length_of_the_list_behind_it():
    for word in engine.word_of_day.all():
        assert word["count"] == sum(len(o["tokens"]) for o in word["occurrences"]), word["id"]


def test_word_of_day_the_anchor_is_the_first_appearance_and_tokens_match_folded():
    # Occurrences were matched FOLDED upstream, so ٱلۡحَمۡدُۖ at 64:1 is the same form as
    # ٱلۡحَمۡدُ; comparing written tokens literally would call a pause mark a mismatch.
    for word in engine.word_of_day.all():
        first = word["occurrences"][0]
        assert (first["surah"], first["ayah"], first["tokens"][0]) == \
            (word["surah"], word["ayah"], word["token"]), word["id"]
        target = _fold_token(word["arabic"])
        for occurrence in word["occurrences"]:
            tokens = _tokens(occurrence["surah"], occurrence["ayah"])
            for index in occurrence["tokens"]:
                assert _fold_token(tokens[index]) == target, (word["id"], occurrence, index)


def test_word_of_day_search_and_reverse_lookup():
    first = engine.word_of_day.all()[0]
    assert any(w["id"] == first["id"] for w in engine.word_of_day.search(first["arabic"]))
    assert any(w["id"] == first["id"]
               for w in engine.word_of_day.words_in(first["surah"], first["ayah"]))
