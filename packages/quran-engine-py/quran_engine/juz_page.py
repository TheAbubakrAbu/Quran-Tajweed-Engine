"""Juz & mushaf-page navigation. Mirrors src/juzPage.js / docs 03."""
from __future__ import annotations
from typing import Optional
from .models import JuzEntry, Surah, Ayah
from .quran import Quran


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
