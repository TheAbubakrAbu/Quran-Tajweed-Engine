"""Juz & mushaf-page navigation. Mirrors src/juzPage.js / docs 03."""
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional
from .models import JuzEntry, Surah, Ayah
from .quran import Quran


@dataclass(frozen=True)
class JuzStats:
    """Aggregate counts for a single juz. Mirrors QuranData.JuzStats."""
    surah_count: int
    ayah_count: int
    word_count: int
    letter_count: int
    page_count: int


class JuzPage:
    def __init__(self, quran: Quran, juz_list: list[JuzEntry]):
        self.quran = quran
        self.juz_list = sorted(juz_list, key=lambda j: j.id)

    def juzes(self) -> list[JuzEntry]:
        return self.juz_list

    def juz(self, jid: int) -> Optional[JuzEntry]:
        return next((j for j in self.juz_list if j.id == jid), None)

    def ayahs_in_juz(self, juz: int) -> list[tuple[Surah, Ayah]]:
        return [(s, a) for s, a in self.quran.each_ayah() if a.juz == juz]

    def ayahs_on_page(self, page: int) -> list[tuple[Surah, Ayah]]:
        return [(s, a) for s, a in self.quran.each_ayah() if a.page == page]

    def first_ayah_of_juz(self, juz: int) -> Optional[tuple[Surah, Ayah]]:
        for s, a in self.quran.each_ayah():
            if a.juz == juz:
                return (s, a)
        return None

    def first_ayah_of_page(self, page: int) -> Optional[tuple[Surah, Ayah]]:
        for s, a in self.quran.each_ayah():
            if a.page == page:
                return (s, a)
        return None

    def juz_for_ayah(self, surah_id: int, ayah_id: int) -> Optional[int]:
        a = self.quran.ayah(surah_id, ayah_id)
        return a.juz if a else None

    def page_for_ayah(self, surah_id: int, ayah_id: int) -> Optional[int]:
        a = self.quran.ayah(surah_id, ayah_id)
        return a.page if a else None

    def total_pages(self) -> int:
        return max((a.page or 0 for _, a in self.quran.each_ayah()), default=0)

    def surahs_in_juz(self, juz: int) -> list[int]:
        j = self.juz(juz)
        if not j:
            return []
        return [s.id for s in self.quran.all() if j.start_surah <= s.id <= j.end_surah]

    def juz_from_end(self, n: int) -> Optional[JuzEntry]:
        """Resolve a juz counted from the end of the Quran: 1 -> juz 30 ... 30 -> juz 1.

        Mirrors the search-bar ``-N`` shorthand in QuranView.swift. Returns None for n outside 1..30.
        """
        if not 1 <= n <= 30:
            return None
        return self.juz(31 - n)

    def juz_stats(self, juz: int) -> Optional[JuzStats]:
        """Aggregate counts for a single juz, computed from the ayahs actually assigned to it
        (``ayah.juz == juz``) so surahs that straddle a juz boundary are split correctly.
        Mirrors ``QuranData.juzStats(for:)``. Returns None for an unknown juz id.
        """
        if not self.juz(juz):
            return None
        surah_ids: set[int] = set()
        pages: set[int] = set()
        ayah_count = word_count = letter_count = 0
        for s, a in self.quran.each_ayah():
            if a.juz != juz:
                continue
            surah_ids.add(s.id)
            ayah_count += 1
            word_count += a.word_count or 0
            letter_count += a.letter_count or 0
            if a.page is not None:
                pages.add(a.page)
        return JuzStats(
            surah_count=len(surah_ids),
            ayah_count=ayah_count,
            word_count=word_count,
            letter_count=letter_count,
            page_count=len(pages),
        )
