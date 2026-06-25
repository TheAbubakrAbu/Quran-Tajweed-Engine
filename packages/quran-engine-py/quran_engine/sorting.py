"""Surah sorting & filtering. Mirrors src/sorting.js / docs 07."""
from __future__ import annotations
from .models import Surah

_DIRECTIONAL = {"revelation", "page", "ayahs", "words", "letters"}


def _key(s: Surah, mode: str) -> int:
    if mode == "revelation":
        return s.revelation_order if s.revelation_order is not None else 10 ** 9
    if mode == "ayahs":
        return s.number_of_ayahs
    if mode == "page":
        return s.number_of_pages or 0
    if mode == "words":
        return s.word_count or 0
    if mode == "letters":
        return s.letter_count or 0
    return s.id


def sort_surahs(surahs: list[Surah], mode: str = "surah", direction: str = "ascending") -> list[Surah]:
    if direction == "surahOrder" or mode == "surah":
        return sorted(surahs, key=lambda s: s.id)
    asc = sorted(surahs, key=lambda s: (_key(s, mode), s.id))
    if direction == "descending" and mode in _DIRECTIONAL:
        return list(reversed(asc))
    return asc


def supports_direction(mode: str) -> bool:
    return mode in _DIRECTIONAL


def filter_by_revelation_type(surahs: list[Surah], rev_type: str) -> list[Surah]:
    return [s for s in surahs if s.type == rev_type]
