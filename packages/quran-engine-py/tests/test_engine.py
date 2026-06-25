"""Run with:  python -m pytest   (or)   python tests/test_engine.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine  # noqa: E402
from quran_engine.audio import surah_audio_url, ayah_audio_url  # noqa: E402
from quran_engine.sorting import sort_surahs  # noqa: E402
from quran_engine.cache import local_surah_path, sanitize_reciter_dir  # noqa: E402

engine = Engine.load()


def test_quran_counts():
    assert len(engine.quran.all()) == 114
    assert engine.quran.total_ayahs == 6236


def test_lookup():
    assert engine.quran.surah(1).name_english == "The Opener"
    assert engine.quran.surah(1).number_of_ayahs == 7
    assert len(engine.quran.ayah(2, 255).text_arabic) > 10


def test_global_ayah_number():
    assert engine.quran.global_ayah_number(1, 1) == 1
    assert engine.quran.global_ayah_number(2, 1) == 8
    assert engine.quran.global_ayah_number(114, 6) == 6236


def test_juz():
    assert len(engine.juz_page.juzes()) == 30
    assert engine.juz_page.juz(1).start_surah == 1
    assert engine.juz_page.juz(30).end_surah == 114
    s, a = engine.juz_page.first_ayah_of_juz(1)
    assert s.id == 1 and a.id == 1


def test_audio_urls():
    alafasy = next(r for r in engine.reciters.all() if r.name == "Mishary Alafasy")
    assert surah_audio_url(alafasy, 1) == "https://server8.mp3quran.net/afs/001.mp3"
    g = engine.quran.global_ayah_number(2, 1)
    assert ayah_audio_url(alafasy, g) == "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"


def test_sorting():
    desc = sort_surahs(engine.quran.all(), "ayahs", "descending")
    assert desc[0].id == 2  # Al-Baqarah longest


def test_search():
    res = engine.search.search_verses("lord of the worlds")
    assert any(r["id"] == "1:2" for r in res)
    assert engine.search.search_verses("2 255") == []
    assert any(s.id == 1 for s in engine.search.search_surahs("fatihah"))
    assert engine.search.parse_reference("2:255") == {"surah": 2, "ayah": 255}


def test_tajweed():
    spans = engine.tajweed(1, 1)
    assert len(spans) > 0
    text = engine.quran.ayah(1, 1).text_arabic
    for sp in spans:
        # reconstructed slice must equal the recorded text
        from quran_engine.text import utf16_slice
        assert utf16_slice(text, sp.start, sp.end) == sp.text
        assert sp.color and sp.color.startswith("#")


def test_cache_paths():
    rid = "Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/"
    assert local_surah_path(rid, 1) == f"{sanitize_reciter_dir(rid)}/001.mp3"
    assert all(c.isalnum() or c in "-_" for c in sanitize_reciter_dir(rid))


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
            passed += 1
    print(f"\n{passed} tests passed")
