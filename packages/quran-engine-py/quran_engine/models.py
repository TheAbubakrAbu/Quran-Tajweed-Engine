"""Typed data models. These mirror the JSON schemas in /data (see docs/01-quran.md)."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Ayah:
    id: int
    text_arabic: str
    text_transliteration: str = ""
    text_english_saheeh: str = ""
    text_english_mustafa: str = ""
    juz: Optional[int] = None
    page: Optional[int] = None
    word_count: Optional[int] = None
    letter_count: Optional[int] = None

    @staticmethod
    def from_json(d: dict) -> "Ayah":
        return Ayah(
            id=d["id"],
            text_arabic=d.get("textArabic", ""),
            text_transliteration=d.get("textTransliteration", ""),
            text_english_saheeh=d.get("textEnglishSaheeh", ""),
            text_english_mustafa=d.get("textEnglishMustafa", ""),
            juz=d.get("juz"),
            page=d.get("page"),
            word_count=d.get("wordCount"),
            letter_count=d.get("letterCount"),
        )


@dataclass
class Surah:
    id: int
    type: str
    name_arabic: str
    name_transliteration: str
    name_english: str
    number_of_ayahs: int
    page_start: Optional[int] = None
    page_end: Optional[int] = None
    number_of_pages: Optional[int] = None
    first_juz: Optional[int] = None
    last_juz: Optional[int] = None
    juzs: list[int] = field(default_factory=list)
    revelation_order: Optional[int] = None
    similar_names: list[str] = field(default_factory=list)
    word_count: Optional[int] = None
    letter_count: Optional[int] = None
    ayahs: list[Ayah] = field(default_factory=list)

    @staticmethod
    def from_json(d: dict) -> "Surah":
        return Surah(
            id=d["id"],
            type=d.get("type", ""),
            name_arabic=d.get("nameArabic", ""),
            name_transliteration=d.get("nameTransliteration", ""),
            name_english=d.get("nameEnglish", ""),
            number_of_ayahs=d.get("numberOfAyahs", 0),
            page_start=d.get("pageStart"),
            page_end=d.get("pageEnd"),
            number_of_pages=d.get("numberOfPages"),
            first_juz=d.get("firstJuz"),
            last_juz=d.get("lastJuz"),
            juzs=d.get("juzs", []),
            revelation_order=d.get("revelationOrder"),
            similar_names=d.get("similarNames", []),
            word_count=d.get("wordCount"),
            letter_count=d.get("letterCount"),
            ayahs=[Ayah.from_json(a) for a in d.get("ayahs", [])],
        )


@dataclass
class JuzEntry:
    id: int
    name_arabic: str
    name_transliteration: str
    start_surah: int
    start_ayah: int
    end_surah: int
    end_ayah: int

    @staticmethod
    def from_json(d: dict) -> "JuzEntry":
        return JuzEntry(
            id=d["id"],
            name_arabic=d.get("nameArabic", ""),
            name_transliteration=d.get("nameTransliteration", ""),
            start_surah=d["startSurah"], start_ayah=d["startAyah"],
            end_surah=d["endSurah"], end_ayah=d["endAyah"],
        )


@dataclass
class Reciter:
    id: str
    name: str
    ayah_identifier: str
    ayah_bitrate: str
    surah_link: str
    qiraah: Optional[str] = None
    group: Optional[str] = None

    @staticmethod
    def from_json(d: dict) -> "Reciter":
        return Reciter(
            id=d["id"], name=d["name"],
            ayah_identifier=d.get("ayahIdentifier", ""),
            ayah_bitrate=d.get("ayahBitrate", ""),
            surah_link=d.get("surahLink", ""),
            qiraah=d.get("qiraah"),
            group=d.get("group"),
        )


@dataclass
class TajweedSpan:
    start: int          # UTF-16 offset into the ayah text
    end: int
    rule: str           # category id (see tajweed-rules.json)
    text: str
    color: Optional[str] = None  # hex color from tajweed-rules.json
