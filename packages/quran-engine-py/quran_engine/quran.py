"""Quran browsing: surahs, ayahs, qiraat text. Mirrors src/quran.js / docs 01."""
from __future__ import annotations
from typing import Iterator, Optional
from .models import Surah, Ayah
from .text import removing_arabic_diacritics_and_signs


class Quran:
    def __init__(self, surahs: list[Surah], qiraat: Optional[dict] = None,
                 surah_info: Optional[list[dict]] = None):
        self.surahs = surahs
        self._by_id = {s.id: s for s in surahs}
        self._qiraat = qiraat or {}
        self._info = {e["id"]: e.get("sources", []) for e in (surah_info or [])}
        # cumulative ayah offset per surah id (count of ayahs in earlier surahs)
        self._cum = {}
        acc = 0
        for s in surahs:
            self._cum[s.id] = acc
            acc += s.number_of_ayahs
        self.total_ayahs = acc

    def all(self) -> list[Surah]:
        return self.surahs

    def surah(self, sid: int) -> Optional[Surah]:
        return self._by_id.get(sid)

    def ayah(self, surah_id: int, ayah_id: int) -> Optional[Ayah]:
        s = self._by_id.get(surah_id)
        if not s:
            return None
        for a in s.ayahs:
            if a.id == ayah_id:
                return a
        return None

    def global_ayah_number(self, surah_id: int, ayah_id: int) -> int:
        if surah_id not in self._cum:
            raise ValueError(f"Unknown surah {surah_id}")
        return self._cum[surah_id] + ayah_id

    def info(self, surah_id: int) -> list[dict]:
        return self._info.get(surah_id, [])

    def arabic_text(self, surah_id: int, ayah_id: int, riwayah: Optional[str] = None) -> Optional[str]:
        a = self.ayah(surah_id, ayah_id)
        if a is None:
            return None
        if riwayah and riwayah.lower() != "hafs":
            verses = self._qiraat.get(riwayah.lower(), {}).get(str(surah_id))
            if verses:
                for v in verses:
                    if v["id"] == ayah_id:
                        return v["text"]
        return a.text_arabic

    def clean_arabic_text(self, surah_id: int, ayah_id: int, riwayah: Optional[str] = None) -> Optional[str]:
        raw = self.arabic_text(surah_id, ayah_id, riwayah)
        return None if raw is None else removing_arabic_diacritics_and_signs(raw)

    def each_ayah(self) -> Iterator[tuple[Surah, Ayah]]:
        for s in self.surahs:
            for a in s.ayahs:
                yield s, a
