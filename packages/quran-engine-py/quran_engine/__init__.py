"""
quran_engine — a framework-agnostic Quran engine for Python.

Part of the open-source Quran Tajweed Engine. Data and algorithms are extracted, with attribution,
from the Al-Islam app by Abubakr Elmallah. See ../../CREDITS.md.

Quick start:

    from quran_engine import Engine
    engine = Engine.load()                      # reads the repo's /data directory
    engine.quran.surah(1).name_english          # "The Opener"
    engine.tajweed(1, 1)                          # colored tajweed spans
    engine.juz_page.first_ayah_of_juz(30)        # jump target
    engine.audio.surah_url(reciter, 1)           # full-surah mp3 URL
    engine.search.search_verses("lord of the worlds")
"""

from .engine import Engine
from .models import Surah, Ayah, JuzEntry, Reciter, TajweedSpan
from .text import clean_search, contains_arabic_letters, arabic_digits_to_western
from .audio import surah_audio_url, ayah_audio_url, ayah_now_playing_name, defaults_to_minshawi
from .sorting import sort_surahs, filter_by_revelation_type
from .cache import sanitize_reciter_dir, local_surah_path, shared_audio_path

__version__ = "0.1.0"

__all__ = [
    "Engine",
    "Surah", "Ayah", "JuzEntry", "Reciter", "TajweedSpan",
    "clean_search", "contains_arabic_letters", "arabic_digits_to_western",
    "surah_audio_url", "ayah_audio_url", "ayah_now_playing_name", "defaults_to_minshawi",
    "sort_surahs", "filter_by_revelation_type",
    "sanitize_reciter_dir", "local_surah_path", "shared_audio_path",
]
