"""Quran browsing: surahs, ayahs, qiraat text. Mirrors src/quran.js / docs 01."""
from __future__ import annotations
from typing import Iterator, Optional
from .models import Surah, Ayah
from .text import removing_arabic_diacritics_and_signs

# ۩ ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs.
SAJDAH_MARK = "۩"


class Quran:
    def __init__(self, surahs: list[Surah], qiraat: Optional[dict] = None,
                 surah_info: Optional[list[dict]] = None,
                 qiraat_counts: Optional[dict] = None):
        self.surahs = surahs
        self._by_id = {s.id: s for s in surahs}
        self._qiraat = qiraat or {}
        # riwayah -> surahId(str) -> ayah count (data/qiraat-counts.json)
        self._qiraat_counts = qiraat_counts or {}
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

    def surah_from_end(self, n: int) -> Optional[Surah]:
        """Resolve a surah counted from the END of the mushaf: 1 -> An-Nas (114) … 114 ->
        Al-Fatihah (1). Returns None for n outside 1..114."""
        if not isinstance(n, int) or isinstance(n, bool) or n < 1 or n > len(self.surahs):
            return None
        return self.surah(len(self.surahs) + 1 - n)

    def is_sajdah_ayah(self, surah_id: int, ayah_id: int) -> bool:
        """Whether an ayah is a sajdah (prostration) ayah — carries the ۩ mark (U+06E9)."""
        a = self.ayah(surah_id, ayah_id)
        return SAJDAH_MARK in (a.text_arabic if a else "")

    def page_changes_within_surah(self, surah_id: int) -> bool:
        """Whether a mushaf page boundary falls inside this surah. Mirrors Surah.pageChangesWithinSurah."""
        s = self.surah(surah_id)
        if not s:
            return False
        if (s.number_of_pages or 1) > 1:
            return True
        return len({a.page for a in s.ayahs if a.page is not None}) > 1

    def juz_changes_within_surah(self, surah_id: int) -> bool:
        """Whether a juz boundary falls inside this surah. Mirrors Surah.juzChangesWithinSurah."""
        s = self.surah(surah_id)
        if not s:
            return False
        if len(s.juzs or []) > 1:
            return True
        if s.first_juz is not None and s.last_juz is not None and s.first_juz != s.last_juz:
            return True
        return len({a.juz for a in s.ayahs if a.juz is not None}) > 1

    def page_or_juz_changes_within_surah(self, surah_id: int) -> bool:
        """Whether a page OR juz boundary falls inside this surah. Mirrors Surah.pageOrJuzChangesWithinSurah."""
        return self.page_changes_within_surah(surah_id) or self.juz_changes_within_surah(surah_id)

    def sajdah_ayahs(self) -> list[tuple[Surah, Ayah]]:
        """The 15 sajdah ayahs, in mushaf order, detected by the ۩ mark in the Arabic text."""
        return [(s, a) for s, a in self.each_ayah() if SAJDAH_MARK in (a.text_arabic or "")]

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

    def exists_in_qiraah(self, surah_id: int, ayah_id: int, riwayah: Optional[str] = None) -> bool:
        """Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs every ayah exists;
        other riwayat merge/split some ayahs, so a Hafs ayah "exists" iff the riwayah's feed carries an
        ayah with that id (its feeds are numbered contiguously 1..count, so this is `ayah_id <= count`).
        Mirrors Ayah.existsInQiraah(_:). An unknown/unloaded riwayah falls back to Hafs (exists)."""
        if self.ayah(surah_id, ayah_id) is None:
            return False
        r = (riwayah or "").lower()
        if not r or r == "hafs":
            return True
        count = self._qiraat_counts.get(r, {}).get(str(surah_id))
        if count is None:
            return True
        return ayah_id <= count

    def number_of_ayahs_in_qiraah(self, surah_id: int, riwayah: Optional[str] = None) -> int:
        """Ayah count of a surah in the given riwayah — the number of Hafs ayahs that exist there (e.g.
        Baqarah is 286 in Hafs but 285 in Warsh). Mirrors Surah.numberOfAyahs(for:)."""
        s = self.surah(surah_id)
        if not s:
            return 0
        r = (riwayah or "").lower()
        if not r or r == "hafs":
            return s.number_of_ayahs
        count = self._qiraat_counts.get(r, {}).get(str(surah_id))
        if count is None:
            return s.number_of_ayahs
        return min(s.number_of_ayahs, count)

    def clean_arabic_text(self, surah_id: int, ayah_id: int, riwayah: Optional[str] = None) -> Optional[str]:
        raw = self.arabic_text(surah_id, ayah_id, riwayah)
        return None if raw is None else removing_arabic_diacritics_and_signs(raw)

    def each_ayah(self) -> Iterator[tuple[Surah, Ayah]]:
        for s in self.surahs:
            for a in s.ayahs:
                yield s, a
