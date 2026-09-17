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

    engine = Engine.load(load_mushaf=True, load_word_by_word=True)
    engine.mushaf.page(2, 255, "warsh")          # the page Warsh's own print puts it on
    engine.word_by_word.words(112, 1)             # gloss + transliteration, word by word
    engine.ask_ai.retrieve("explain ayat al-kursi")
"""

from .engine import Engine
from .models import Surah, Ayah, JuzEntry, Reciter, TajweedSpan
from .juz_page import JuzStats
from .text import clean_search, contains_arabic_letters, arabic_digits_to_western
from .audio import surah_audio_url, ayah_audio_url, ayah_now_playing_name, defaults_to_minshawi
from .sorting import sort_surahs, filter_by_revelation_type, filter_by_counts, CountFilter
from .names import NamesOfAllah, NameOfAllah
from .muqattaat import Muqattaat, MuqattaatPronunciation
from .cache import sanitize_reciter_dir, local_surah_path, shared_audio_path
from .mushaf import Mushaf
from .qiraat_tajweed import QiraatTajweed, LegendEntry, WordRule
from .word_by_word import WordByWord, Word
from .similar import SimilarAyahs, SimilarMatch
from .themes import Themes
from .lessons import TajweedLessons
from .semantic import Semantic
from .ask_ai import AskAI, Passage, chat_prompt, CHAT_INSTRUCTIONS, QUESTION_WORDS
from .sections import SurahSections, SurahSection, OutlineNode
from .alphabet import ArabicAlphabet, ArabicLetter, Tashkeel, StoppingSign, ArabicNumeral
from .qiraat_comparison import QiraatComparison, ComparisonTotals, WordDifference, skeleton
from .morphology import Morphology, Root, Lemma, WordLocation, fold_for_morphology
from .mutashabihat import Mutashabihat, Phrase
from .topics import QuranTopics, AyahThemes, QulTopic, Passage as ThemePassage, TOPIC_TREES
from .metadata import QuranMetadata, Division
from .qiraat_variants import QiraatVariants, Juncture
from .word_of_day import WordOfDay, WordEntry
from .names_depth import NamesDepth, NameDepth, NameTheme, root_key
from .isnad import Isnad, IsnadNode, IsnadLayer
from .miracles import Miracles, MiracleArticle, MiracleCategory, MIRACLE_LEVELS

__version__ = "0.1.0"

__all__ = [
    "Engine",
    "Surah", "Ayah", "JuzEntry", "Reciter", "TajweedSpan", "JuzStats",
    "clean_search", "contains_arabic_letters", "arabic_digits_to_western",
    "surah_audio_url", "ayah_audio_url", "ayah_now_playing_name", "defaults_to_minshawi",
    "sort_surahs", "filter_by_revelation_type", "filter_by_counts", "CountFilter",
    "NamesOfAllah", "NameOfAllah",
    "Muqattaat", "MuqattaatPronunciation",
    "sanitize_reciter_dir", "local_surah_path", "shared_audio_path",
    "Mushaf", "QiraatTajweed", "LegendEntry", "WordRule",
    "WordByWord", "Word", "SimilarAyahs", "SimilarMatch",
    "Themes", "TajweedLessons", "Semantic",
    "AskAI", "Passage", "chat_prompt", "CHAT_INSTRUCTIONS", "QUESTION_WORDS",
    "SurahSections", "SurahSection", "OutlineNode",
    "ArabicAlphabet", "ArabicLetter", "Tashkeel", "StoppingSign", "ArabicNumeral",
    "QiraatComparison", "ComparisonTotals", "WordDifference", "skeleton",
    "Morphology", "Root", "Lemma", "WordLocation", "fold_for_morphology",
    "Mutashabihat", "Phrase",
    "QuranTopics", "AyahThemes", "QulTopic", "ThemePassage", "TOPIC_TREES",
    "QuranMetadata", "Division",
    "QiraatVariants", "Juncture",
    "WordOfDay", "WordEntry",
    "NamesDepth", "NameDepth", "NameTheme", "root_key",
    "Isnad", "IsnadNode", "IsnadLayer",
    "Miracles", "MiracleArticle", "MiracleCategory", "MIRACLE_LEVELS",
]
