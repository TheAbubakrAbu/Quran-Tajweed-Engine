"""The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah
outlines, alphabet reference and qiraat comparison that followed it.

Mirrors packages/quran-engine-js/test/parity.test.js case for case, so a divergence between the
two reference ports shows up as a failing test rather than as a surprise in an app.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine, Semantic, chat_prompt, QUESTION_WORDS  # noqa: E402

engine = Engine.load(load_mushaf=True, load_qiraat_tajweed=True,
                     load_word_by_word=True, load_similar_ayahs=True, load_qiraat=True)


# ---- mushaf -----------------------------------------------------------------------

def test_mushaf_twenty_riwayat_eight_with_text():
    assert len(engine.mushaf.riwayat()) == 20
    assert len(engine.mushaf.riwayat_with_text()) == 8
    assert engine.mushaf.total_pages() == 604
    assert engine.mushaf.riwayah("warsh")["imam"] == "Nafi"
    assert engine.mushaf.riwayah("hisham")["textIncluded"] is False


def test_mushaf_every_riwayah_has_a_facsimile_and_a_full_page_table():
    for entry in engine.mushaf.riwayat():
        assert re.match(r"^pdfs/.+\.pdf\.xz$", entry["pdf"]), entry["riwayah"]
        assert entry["pdfBytes"] > 100_000
        # Al-Fatihah opens page 1 and an-Nas closes page 604 in every print of the set.
        assert engine.mushaf.page(1, 1, entry["riwayah"]) == 1
        assert engine.mushaf.page(114, 6, entry["riwayah"]) == 604


def test_mushaf_pages_resolve_back_to_their_ayahs():
    page = engine.mushaf.page(2, 255, "hafs")
    assert page == 42
    assert (2, 255) in engine.mushaf.ayahs_on_page(page, "hafs")
    assert engine.mushaf.first_ayah_of_page(1, "hafs") == (1, 1)


def test_mushaf_line_tables_ship_exactly_where_the_text_does():
    for entry in engine.mushaf.riwayat():
        breaks = engine.mushaf.line_breaks(1, 1, entry["riwayah"])
        if entry["textIncluded"]:
            assert isinstance(breaks, list), entry["riwayah"]
        else:
            assert breaks is None, entry["riwayah"]


# ---- riwayah tajweed ---------------------------------------------------------------

def test_qiraat_tajweed_seven_verified_packs():
    assert engine.qiraat_tajweed.available() == [
        "buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"]


def test_qiraat_tajweed_legend_carries_its_explanation():
    legend = engine.qiraat_tajweed.legend("warsh")
    assert len(legend) >= 3
    for entry in legend:
        assert len(entry["code"]) == 1
        assert entry["rule"] and entry["arabic"] and entry["english"]
        assert entry.get("short"), entry["rule"]


def test_qiraat_tajweed_word_rules_name_real_codes():
    rules = engine.qiraat_tajweed.word_rules(2, 3, "warsh")
    assert rules
    codes = {e["code"] for e in engine.qiraat_tajweed.legend("warsh")}
    for rule in rules:
        assert rule["code"] in codes
        assert rule["whole_word"] == (rule["first_letter"] < 0)
        assert rule["word"] >= 1


def test_qiraat_tajweed_khilaf_markers():
    assert engine.qiraat_tajweed.has_khilaf(2, 253, "warsh")
    assert not engine.qiraat_tajweed.has_khilaf(2, 254, "warsh")


# ---- word by word -------------------------------------------------------------------

def test_word_by_word_both_layers():
    words = engine.word_by_word.words(112, 1)
    assert [w["transliteration"] for w in words] == ["qul", "huwa", "l-lahu", "aḥadun"]
    assert words[0]["english"] == "Say"
    assert words[0]["arabic"] == engine.quran.ayah(112, 1).text_arabic.split()[0]


def test_word_by_word_arrays_match_token_counts():
    for surah in engine.quran.all():
        for ayah in surah.ayahs:
            tokens = len(ayah.text_arabic.split())
            assert len(engine.word_by_word.glosses(surah.id, ayah.id)) == tokens
            assert len(engine.word_by_word.transliterations(surah.id, ayah.id)) == tokens


def test_word_by_word_gloss_search():
    hits = engine.word_by_word.find("the Ever-Living", limit=5)
    assert any(h["surah"] == 2 and h["ayah"] == 255 for h in hits)
    assert all(h["transliteration"] for h in hits)


# ---- similar ayahs, themes, lessons ---------------------------------------------------

def test_similar_ayahs():
    matches = engine.similar_ayahs.matches(2, 255)
    found = next(m for m in matches if m["surah"] == 3 and m["ayah"] == 2)
    assert found["verified"]
    assert engine.similar_ayahs.has(2, 255)
    assert engine.similar_ayahs.count() > 5000


def test_themes_index_both_ways():
    assert len(engine.themes.all()) >= 300
    assert "2:255" in engine.themes.topic("tawheed")["ayahs"]
    assert any(t["id"] == "tawheed" for t in engine.themes.topics_for(2, 255))
    assert len(engine.themes.domains()) >= 2


def test_tajweed_lessons_walk_in_course_order():
    lessons = engine.tajweed_lessons.all_lessons()
    assert len(lessons) >= 30
    assert engine.tajweed_lessons.previous(lessons[0]["id"]) is None
    assert engine.tajweed_lessons.next(lessons[0]["id"])["id"] == lessons[1]["id"]
    assert engine.tajweed_lessons.chapter_of(lessons[0]["id"])


# ---- semantic ---------------------------------------------------------------------

def test_semantic_maxsim_ranks_by_meaning():
    vectors = {"patience": [1, 0, 0], "hardship": [0.9, 0.1, 0], "sabr": [0.95, 0.05, 0],
               "steadfast": [0.9, 0.05, 0], "dawn": [0, 1, 0], "prayer": [0, 0.95, 0]}
    semantic = Semantic(lambda w: vectors.get(w)).index([
        {"id": "sabr", "text": "sabr and steadfast endurance"},
        {"id": "fajr", "text": "prayer at dawn"},
    ])
    hits = semantic.search("patience hardship")
    assert hits[0]["id"] == "sabr"
    assert hits[0]["score"] > hits[1]["score"]


# ---- ask AI -----------------------------------------------------------------------

def test_ask_ai_named_verse_is_the_subject():
    passages = engine.ask_ai.retrieve("explain ayat al-kursi")
    assert passages[0]["reference"] == "2:255"
    assert passages[0]["is_subject"] is True


def test_ask_ai_named_surah_answers_with_its_background():
    passages = engine.ask_ai.retrieve("what is surah al-kahf about")
    assert passages[0]["reference"] == "Surah Al-Kahf"
    assert passages[0]["kind"] == "surah"


def test_ask_ai_keyword_lane_is_weighted():
    passages = engine.ask_ai.retrieve("what does the Quran say about patience in hardship")
    assert any(p["reference"] == "2:153" for p in passages)
    for passage in passages:
        if passage["kind"] == "ayah":
            assert engine.quran.ayah(passage["surah"], passage["ayah"])


def test_ask_ai_bare_follow_up_uses_the_previous_question():
    carried = engine.ask_ai.retrieve("tell me about 2:153")
    assert engine.ask_ai.retrieve("why?") == []
    with_context = engine.ask_ai.retrieve("why?", previous_question="tell me about 2:153",
                                          carried=carried)
    assert any(p["reference"] == "2:153" for p in with_context)


def test_ask_ai_prompt_shape():
    passages = engine.ask_ai.retrieve("explain 2:153")
    built = chat_prompt("explain 2:153", passages)
    assert "Never issue a religious ruling" in built["instructions"]
    assert "SUBJECT OF THE QUESTION [2:153]" in built["prompt"]
    assert built["prompt"].rstrip().endswith("QUESTION: explain 2:153")
    assert "what" in QUESTION_WORDS


# ---- surah sections ----------------------------------------------------------------

def test_sections_111_surahs_and_a_chain():
    assert engine.surah_sections.count() == 111
    assert len(engine.surah_sections.overview(1)) > 20
    assert engine.surah_sections.has_sections(1) is False

    # Hud opens with a broad passage and the sections inside it - an ayah has a chain, not a row.
    chain = [s.english for s in engine.surah_sections.sections_for(11, 3)]
    assert chain == ["Doctrine facts", "Calling to Allah"]
    assert engine.surah_sections.section_for(11, 3).english == "Calling to Allah"


def test_sections_outline_rebuilds_the_nesting():
    roots = engine.surah_sections.outline(11)
    assert len(roots) >= 2
    assert roots[0].section.english == "Doctrine facts"
    assert len(roots[0].children) == 5
    assert all(c.section.from_ayah >= roots[0].section.from_ayah
               and c.section.to_ayah <= roots[0].section.to_ayah for c in roots[0].children)


def test_sections_ranges_are_inside_their_surah():
    for surah in engine.quran.all():
        for section in engine.surah_sections.sections(surah.id):
            assert 1 <= section.from_ayah <= section.to_ayah <= surah.number_of_ayahs, \
                f"{surah.id}: {section.from_ayah}-{section.to_ayah}"
            assert section.english and section.arabic
    nuh = engine.surah_sections.search("Story of Nuh")
    assert len(nuh) >= 2
    assert any(sid == 11 for sid, _ in nuh)


# ---- arabic alphabet ----------------------------------------------------------------

def test_alphabet_28_letters_each_with_a_weight():
    letters = engine.alphabet.letters()
    assert len(letters) == 28
    weights = engine.alphabet.weight_descriptions()
    for letter in letters:
        assert letter.letter and letter.name
        assert letter.weight, f"{letter.letter} has no weight"
        assert weights.get(letter.weight), f"no description for weight {letter.weight}"
    # Alif is the one letter with no weight of its own - the fact the whole field exists for.
    assert engine.alphabet.weight("ا") == "followsPrevious"
    assert engine.alphabet.weight("ص") == "heavy"
    assert engine.alphabet.weight("س") == "light"


def test_alphabet_resolves_a_joining_form():
    assert engine.alphabet.letter("ـصـ").transliteration == "Saad"
    assert engine.alphabet.letter_by_id(1).letter == "ا"
    assert engine.alphabet.letter("nope") is None


def test_alphabet_tashkeel_numerals_and_waqf():
    assert len(engine.alphabet.tashkeel()) >= 8
    assert len(engine.alphabet.numbers()) == 11
    assert engine.alphabet.stopping_sign("۩").title == "Make Sujood"
    assert len(engine.alphabet.heavy_letters()) >= 7


# ---- qiraat comparison ---------------------------------------------------------------

def test_comparison_lists_only_published_readings():
    assert engine.qiraat_comparison.available() == [
        "buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh",
    ]


def test_comparison_a_reading_against_itself_is_identical():
    same = engine.qiraat_comparison.compare_surah(2, "hafs")
    assert same.identical == same.words
    assert same.same_skeleton == 0
    assert same.different == 0
    assert same.added == 0
    assert same.dropped == 0
    assert same.identical_percent == 100


def test_comparison_buckets_add_up_and_shubah_is_nearer():
    warsh = engine.qiraat_comparison.compare_surah(2, "warsh")
    shubah = engine.qiraat_comparison.compare_surah(2, "shubah")
    for totals in (warsh, shubah):
        assert totals.identical + totals.same_skeleton + totals.different + totals.dropped \
            == totals.words
    # Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
    assert shubah.identical_percent > warsh.identical_percent
    assert shubah.identical_percent > 95


def test_comparison_differences_are_in_reading_order():
    rows = engine.qiraat_comparison.differences(2, "warsh", limit=20)
    assert rows
    assert all(r.kind in {"sameSkeleton", "different", "added", "dropped"} for r in rows)
    assert all(r.base != r.other for r in rows)
    positions = [r.position for r in rows]
    assert positions == sorted(positions)


def test_comparison_word_streams_follow_the_readings_own_verse_count():
    # Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
    # different verses from that point on; the comparison walks the surah's words instead.
    assert engine.quran.number_of_ayahs_in_qiraah(2, "warsh") == 285
    assert len(engine.quran.qiraah_verses(2, "warsh")) == 285
    assert len(engine.qiraat_comparison.words(2, "warsh")) > 6000


# ---- the standalone stats index --------------------------------------------------------

def test_surah_stats_still_agrees_with_quran_json():
    # It ships as an 8 KB index for consumers who want the counts without parsing 30 MB of text, so
    # nothing reads it through the API - which is exactly why it needs a test to keep it honest.
    import json
    from quran_engine.engine import _default_data_dir

    stats = json.loads((_default_data_dir() / "surah-stats.json").read_text(encoding="utf-8"))
    assert len(stats) == 114
    for surah in engine.quran.all():
        row = stats[str(surah.id)]
        assert [row["ayahs"], row["words"], row["letters"], row["type"], row["juz"]] == [
            surah.number_of_ayahs, surah.word_count, surah.letter_count, surah.type, surah.juzs,
        ], f"surah {surah.id}"


if __name__ == "__main__":
    for name, fn in sorted(dict(globals()).items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"ok {name}")
    print("all parity tests passed")
