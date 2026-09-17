"""Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.

A deliberate translation of packages/quran-engine-js/test/batch6.test.js: the same corpora, the
same counts, the same shape checks, so a port that drifts fails here rather than in a consumer.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine  # noqa: E402
from quran_engine.names_depth import root_key  # noqa: E402

engine = Engine.load()

# ---- the Names in depth ----------------------------------------------------------

def test_counts():
    c = engine.names_depth.count()
    assert c["names"] == 99, c
    assert c["themes"] == 9, c
    assert c["occurrences"] == 194, c
    assert [n["number"] for n in engine.names_depth.all()] == list(range(1, 100))


def test_every_name_has_root_theme_prose():
    ids = {t["id"] for t in engine.names_depth.themes()}
    for name in engine.names_depth.all():
        assert name["root"], name["number"]
        assert name["theme"] in ids, (name["number"], name["theme"])
        assert len(name["explanation"]) > 40, name["number"]
        assert len(name["living"]) > 20, name["number"]


def test_themes_partition():
    total = 0
    for theme in engine.names_depth.themes():
        members = engine.names_depth.by_theme(theme["id"])
        assert members, theme["id"]
        total += len(members)
    assert total == 99, total


def test_root_spaced_and_closed():
    rahman = engine.names_depth.by_number(1)
    assert rahman["root"] == "ر ح م"
    assert root_key(rahman["root"]) == "رحم"
    assert [n["number"] for n in engine.names_depth.by_root("رحم")] == [1, 2]
    assert [n["number"] for n in engine.names_depth.by_root("ر ح م")] == [1, 2]


def test_placed_occurrences_are_real_tokens():
    marks = re.compile("[ً-ٰٟۖ-ۭـ]")

    def fold(s):
        s = marks.sub("", s)
        return (s.replace("ٱ", "ا").replace("أ", "ا")
                 .replace("إ", "ا").replace("ؤ", "و")
                 .replace("ئ", "ي"))

    placed = unplaced = 0
    for name in engine.names_depth.all():
        for o in name["occurrences"]:
            ayah = engine.quran.ayah(o["surah"], o["ayah"])
            assert ayah is not None, (name["number"], o)
            if o["token"] is None:
                assert o["tokens"] == 0, (name["number"], o)
                unplaced += 1
                continue
            tokens = [t for t in (ayah.text_arabic or "").split() if t]
            assert o["token"] < len(tokens), (name["number"], o)
            assert fold(tokens[o["token"]]), (name["number"], o)
            placed += 1
    assert placed == 184, placed
    assert unplaced == 10, unplaced


def test_basmalah_names():
    hits = engine.names_depth.in_ayah(1, 3)
    assert [h["name"]["number"] for h in hits] == [1, 2]
    assert [h["occurrence"]["token"] for h in hits] == [0, 1]


def test_search():
    assert any(n["number"] == 1 for n in engine.names_depth.search("رحم"))
    first = engine.names_depth.by_number(1)
    word = next(w for w in first["living"].split() if len(w) > 6)
    assert engine.names_depth.search(word)
    assert engine.names_depth.search("") == []


# ---- the chains of transmission --------------------------------------------------

def test_isnad_counts():
    c = engine.isnad.count()
    assert c == {"imams": 10, "narrators": 20, "companions": 13}, c
    assert engine.isnad.prophet() is not None


def test_every_riwayah_resolves_two_apiece():
    per = {k: 0 for k in engine.isnad.imam_keys()}
    for tag in engine.isnad.narrator_keys():
        imam = engine.isnad.imam_of(tag)
        assert imam, tag
        per[imam] += 1
    for imam, n in per.items():
        assert n == 2, (imam, n)


def test_imams_reach_companions():
    for imam in engine.isnad.imam_keys():
        chain = engine.isnad.imam(imam)
        # Abu Jafar WAS a Successor and read on Companions himself, so he has no teachers layer.
        if imam != "Abu Jafar":
            assert chain["teachers"], imam
        assert chain["companions"], imam
        for node in chain["teachers"]:
            assert node["role"] == "successor", node
            assert node["detail"].startswith("d."), node
        for node in chain["companions"]:
            assert node["role"] == "companion", node


def test_chain_runs_prophet_to_narrator():
    for tag in engine.isnad.narrator_keys():
        layers = engine.isnad.chain(tag)
        assert len(layers) >= 4, (tag, len(layers))
        assert layers[0]["title"] == "THE PROPHET"
        assert layers[1]["title"] == "THE COMPANIONS"
        titles = [l["title"] for l in layers]
        assert "THE IMAM" in titles and "THE NARRATOR" in titles, tag
        assert titles.index("THE IMAM") < titles.index("THE NARRATOR"), tag


def test_imam_chain_ends_at_two_narrators():
    for imam in engine.isnad.imam_keys():
        last = engine.isnad.chain(imam)[-1]
        assert last["title"] == "HIS TWO NARRATORS", imam
        assert len(last["nodes"]) == 2, imam


def test_reads_directly_matches_links():
    for tag in engine.isnad.narrator_keys():
        chain = engine.isnad.narrator(tag)
        assert engine.isnad.reads_directly(tag) == (not chain["links"]), tag
        sentence = engine.isnad.sentence(tag)
        assert sentence, tag
        assert ("did not meet" in sentence) == bool(chain["links"]), tag


def test_hafs_and_qunbul():
    assert engine.isnad.imam_of("Hafs an Asim") == "Asim"
    assert engine.isnad.reads_directly("Hafs an Asim")
    assert engine.isnad.sentence("Hafs an Asim").startswith("Hafs read on Asim himself")
    assert engine.isnad.imam_of("Qunbul an Ibn Kathir") == "Ibn Kathir"
    assert not engine.isnad.reads_directly("Qunbul an Ibn Kathir")
    assert len(engine.isnad.narrator("Qunbul an Ibn Kathir")["links"]) == 3


def test_unknown_key():
    assert engine.isnad.chain("Nobody an Nobody") == []
    assert engine.isnad.sentence("Nobody an Nobody") == ""
    assert engine.isnad.imam_of("no separator here") is None


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
            passed += 1
    print(f"\n{passed} tests passed")
