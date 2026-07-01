"""Surah sorting & filtering. Mirrors src/sorting.js / docs 07."""
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional, Union
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


@dataclass
class CountFilter:
    op: str    # '<' '<=' '>' '>=' '=='
    value: int


def _coerce_filter(f) -> Optional[CountFilter]:
    if f is None:
        return None
    if isinstance(f, CountFilter):
        return f
    return CountFilter(op=f["op"], value=f["value"])


def _passes_count(n: int, f: Optional[CountFilter]) -> bool:
    if f is None:
        return True
    if f.op == "<":
        return n < f.value
    if f.op == "<=":
        return n <= f.value
    if f.op == ">":
        return n > f.value
    if f.op == ">=":
        return n >= f.value
    return n == f.value


def filter_by_counts(surahs: list[Surah],
                     ayahs: Optional[Union[CountFilter, dict]] = None,
                     pages: Optional[Union[CountFilter, dict]] = None) -> list[Surah]:
    """Filter surahs by ayah-count and/or page-count predicates. A surah passes when it satisfies
    BOTH provided filters; an omitted filter is ignored. `value` is compared against the surah's
    number_of_ayahs / number_of_pages. Mirrors filterByCounts in src/sorting.js."""
    af = _coerce_filter(ayahs)
    pf = _coerce_filter(pages)
    return [s for s in surahs
            if _passes_count(s.number_of_ayahs, af) and _passes_count(s.number_of_pages or 0, pf)]
