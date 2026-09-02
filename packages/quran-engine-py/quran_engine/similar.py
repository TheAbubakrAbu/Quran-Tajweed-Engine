"""Similar ayahs (mutashabihat). Mirrors src/similar.js.

Rows are merged and ranked at build time: `verified` rows come from the classical corpus and are
listed first; generated rows carry the `labels` that say why they matched.
"""
from __future__ import annotations
from typing import Optional


class SimilarMatch(dict):
    """surah, ayah, phrase, verified, labels."""


class SimilarAyahs:
    def __init__(self, data: Optional[dict] = None):
        self._data = data or {}

    def matches(self, surah_id: int, ayah_id: int) -> list[SimilarMatch]:
        rows = self._data.get(f"{surah_id}:{ayah_id}")
        if not rows:
            return []
        out = []
        for row in rows:
            surah, ayah, phrase, verified = row[0], row[1], row[2], row[3]
            labels = row[4] if len(row) > 4 and row[4] else []
            out.append(SimilarMatch({"surah": surah, "ayah": ayah, "phrase": phrase or "",
                                     "verified": verified == 1, "labels": labels}))
        return out

    def has(self, surah_id: int, ayah_id: int) -> bool:
        """A dictionary hit, cheap enough to gate a button on."""
        return bool(self._data.get(f"{surah_id}:{ayah_id}"))

    def count(self) -> int:
        return len(self._data)
