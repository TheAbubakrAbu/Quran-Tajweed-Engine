"""
Conformance test — runs the language-agnostic vectors in /conformance/vectors.json against the
engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a behavior is specified ONCE in
that JSON, and every language port runs the same file (see docs/PORTING.md -> "Conformance vectors").
Mirrors the reference consumer: packages/quran-engine-js/test/conformance.test.js.

Run with:  python -m pytest   (or)   python tests/test_conformance.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine, filter_by_counts  # noqa: E402

# packages/quran-engine-py/tests -> repo root /conformance/vectors.json (three levels up).
_VECTORS_PATH = Path(__file__).resolve().parents[3] / "conformance" / "vectors.json"
vectors = json.loads(_VECTORS_PATH.read_text(encoding="utf-8"))

engine = Engine.load()


def test_conformance_search_verses():
    for v in vectors["searchVerses"]:
        ids = [h["id"] for h in engine.search.search_verses(v["query"])]
        if v.get("empty"):
            assert len(ids) == 0, f'"{v["query"]}" should be empty'
        for id_ in v.get("contains", []):
            assert id_ in ids, f'"{v["query"]}" should contain {id_}'
        for id_ in v.get("excludes", []):
            assert id_ not in ids, f'"{v["query"]}" should exclude {id_}'


def test_conformance_juz_from_end():
    for v in vectors["juzFromEnd"]:
        result = engine.juz_page.juz_from_end(v["n"])
        got = result.id if result is not None else None
        assert got == v["id"], f'juzFromEnd({v["n"]})'


def test_conformance_juz_stats():
    fields = {
        "surah_count": "surahCount",
        "ayah_count": "ayahCount",
        "word_count": "wordCount",
        "letter_count": "letterCount",
        "page_count": "pageCount",
    }
    for v in vectors["juzStats"]:
        s = engine.juz_page.juz_stats(v["juz"])
        if v.get("isNull"):
            assert s is None, f'juzStats({v["juz"]}) should be null'
            continue
        for attr, key in fields.items():
            assert getattr(s, attr) == v[key], f'juzStats({v["juz"]}).{attr}'

    sum_ayah = sum(engine.juz_page.juz_stats(i).ayah_count for i in range(1, 31))
    assert sum_ayah == vectors["juzStatsInvariant"]["sumAyahCountAllJuz"]


def test_conformance_surah_from_end():
    for v in vectors["surahFromEnd"]:
        result = engine.quran.surah_from_end(v["n"])
        got = result.id if result is not None else None
        assert got == v["id"], f'surahFromEnd({v["n"]})'


def test_conformance_sajdah():
    sj = vectors["sajdah"]
    ids = [f"{s.id}:{a.id}" for s, a in engine.quran.sajdah_ayahs()]
    assert len(ids) == sj["count"]
    for id_ in sj.get("contains", []):
        assert id_ in ids, f"sajdah should contain {id_}"
        s, a = (int(x) for x in id_.split(":"))
        assert engine.quran.is_sajdah_ayah(s, a), f"isSajdahAyah({id_})"
    for id_ in sj.get("excludes", []):
        s, a = (int(x) for x in id_.split(":"))
        assert not engine.quran.is_sajdah_ayah(s, a), f"isSajdahAyah({id_}) should be false"


def test_conformance_surah_info():
    for v in vectors["surahInfo"]:
        sources = engine.quran.info(v["surah"])
        assert len(sources) >= v.get("minSources", 1), f'info({v["surah"]}) sources'
        if v.get("hasSourceName"):
            assert any(s["name"] == v["hasSourceName"] for s in sources), \
                f'info({v["surah"]}) has {v["hasSourceName"]}'


def test_conformance_names_of_allah():
    assert len(engine.names_of_allah.all()) == vectors["namesOfAllah"]["count"]
    for v in vectors["namesOfAllah"]["byNumber"]:
        name = engine.names_of_allah.by_number(v["number"])
        assert name is not None and name.transliteration == v["transliteration"]


def test_conformance_filter_by_counts():
    for v in vectors["filterByCounts"]:
        ids = sorted(s.id for s in filter_by_counts(
            engine.quran.all(), ayahs=v.get("ayahs"), pages=v.get("pages")))
        assert ids == sorted(v["ids"])


def test_conformance_surah_flags():
    for v in vectors["surahFlags"]:
        assert engine.quran.page_changes_within_surah(v["surah"]) == v["pageChanges"], \
            f'pageChanges({v["surah"]})'
        assert engine.quran.juz_changes_within_surah(v["surah"]) == v["juzChanges"], \
            f'juzChanges({v["surah"]})'
        assert engine.quran.page_or_juz_changes_within_surah(v["surah"]) == v["pageOrJuz"], \
            f'pageOrJuz({v["surah"]})'


def test_conformance_exists_in_qiraah():
    for v in vectors["existsInQiraah"]:
        got = engine.quran.exists_in_qiraah(v["surah"], v["ayah"], v["riwayah"])
        assert got == v["exists"], \
            f'existsInQiraah({v["surah"]},{v["ayah"]},{v["riwayah"]})'


def test_conformance_number_of_ayahs_in_qiraah():
    for v in vectors["numberOfAyahsInQiraah"]:
        got = engine.quran.number_of_ayahs_in_qiraah(v["surah"], v["riwayah"])
        assert got == v["count"], \
            f'numberOfAyahsInQiraah({v["surah"]},{v["riwayah"]})'


def test_conformance_muqattaat():
    m = vectors["muqattaat"]
    assert len(engine.muqattaat.all()) == m["count"]
    for p in m["pronunciations"]:
        got = engine.muqattaat.pronunciation(p["surah"], p["ayah"])
        assert got is not None, f'muqattaat {p["surah"]}:{p["ayah"]} present'
        assert got.transliteration == p["transliteration"]
        if p.get("spelledContainsMaddah"):
            assert "ٓ" in got.spelled_out_arabic, \
                f'muqattaat {p["surah"]}:{p["ayah"]} keeps madd-lāzim maddah'
    for a in m.get("absent", []):
        assert engine.muqattaat.pronunciation(a["surah"], a["ayah"]) is None, \
            f'muqattaat {a["surah"]}:{a["ayah"]} absent'


def test_conformance_tajweed():
    for v in vectors["tajweed"]:
        spans = engine.tajweed(v["surah"], v["ayah"])
        rules = [sp.rule for sp in spans]
        if v.get("excludesRule"):
            assert v["excludesRule"] not in rules, \
                f'{v["surah"]}:{v["ayah"]} should NOT have {v["excludesRule"]}'
        if v.get("lastSpanRule"):
            last = max(spans, key=lambda sp: sp.start)
            assert last.rule == v["lastSpanRule"], f'{v["surah"]}:{v["ayah"]} last span rule'


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
            passed += 1
    print(f"\n{passed} tests passed")
