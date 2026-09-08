"""Hizb, ruku and manzil. Mirrors src/metadata.js.

`juz_page` covers the two divisions a reader meets on the page. These are the three met in a
schedule: 60 hizb (the juz halved), 558 ruku (thematic sections printed in South Asian mushafs),
7 manzil (the seven-day division). Each is stored as its start keys in order, so a lookup is a
binary search rather than a table with one row per ayah.
"""
from __future__ import annotations
from bisect import bisect_right
from typing import Optional


def _rank(key: str) -> int:
    surah, ayah = (int(p) for p in str(key).split(":"))
    return surah * 1000 + ayah


class Division(dict):
    """number, surah, ayah, key."""


class Table:
    def __init__(self, starts: Optional[list[str]] = None):
        self._starts = starts or []
        self._ranks = [_rank(k) for k in self._starts]

    def __len__(self) -> int:
        return len(self._starts)

    def number_for(self, surah_id: int, ayah_id: int) -> int:
        """The 1-based number containing an ayah, or 0 when there is no table."""
        return bisect_right(self._ranks, surah_id * 1000 + ayah_id)

    def start(self, number: int) -> Optional[Division]:
        if number < 1 or number > len(self._starts):
            return None
        key = self._starts[number - 1]
        surah, ayah = (int(p) for p in key.split(":"))
        return Division({"number": number, "surah": surah, "ayah": ayah, "key": key})

    def all(self) -> list[Division]:
        return [self.start(i + 1) for i in range(len(self._starts))]

    def range(self, number: int) -> Optional[dict]:
        """Half-open: `until` is None for the last division, which runs to the end of the Quran."""
        start = self.start(number)
        if not start:
            return None
        return {"from_": start, "until": self.start(number + 1)}


class QuranMetadata:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self.hizb = Table(data.get("hizb"))
        self.ruku = Table(data.get("ruku"))
        self.manzil = Table(data.get("manzil"))

    @property
    def is_loaded(self) -> bool:
        return len(self.hizb) > 0

    def for_ayah(self, surah_id: int, ayah_id: int) -> dict:
        """All three at once, which is what a "where am I" line under an ayah wants."""
        return {"hizb": self.hizb.number_for(surah_id, ayah_id),
                "ruku": self.ruku.number_for(surah_id, ayah_id),
                "manzil": self.manzil.number_for(surah_id, ayah_id)}

    def count(self) -> dict:
        return {"hizb": len(self.hizb), "ruku": len(self.ruku), "manzil": len(self.manzil)}
