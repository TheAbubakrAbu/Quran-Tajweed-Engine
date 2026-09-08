"""A curated word of Quranic vocabulary with every occurrence of the form. Mirrors src/wordOfDay.js.

149 words, ordered so consecutive days feel varied (the themes are interleaved in the corpus
itself), which is why the day mapping is a walk and not a hash: hashing would scatter the
curation's own ordering, and the ordering is the point.

Occurrences are derived from the Hafs text by matching the form folded, so the count on a card
and the list behind it are one derivation. A form can repeat inside one ayah, so an occurrence
carries token indices, plural.

Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used with permission.
"""
from __future__ import annotations
from datetime import date, datetime
from typing import Optional, Union


class WordEntry(dict):
    """id, arabic, transliteration, meaning, surah, ayah, token, count, occurrences."""


def _local_day_index(when: Union[date, datetime, None]) -> int:
    """Days since the Unix epoch, by the given date's own calendar day."""
    if when is None:
        when = datetime.now()
    day = when.date() if isinstance(when, datetime) else when
    return (day - date(1970, 1, 1)).days


class WordOfDay:
    def __init__(self, data: Optional[dict] = None):
        self._words = [WordEntry(w) for w in (data or {}).get("words", [])]
        self._by_id = {w["id"]: w for w in self._words}

    @property
    def is_loaded(self) -> bool:
        return bool(self._words)

    def all(self) -> list[WordEntry]:
        return self._words

    def word(self, word_id: str) -> Optional[WordEntry]:
        return self._by_id.get(word_id)

    def for_day_index(self, day_index: int) -> Optional[WordEntry]:
        """The corpus walked in order, one entry per day, wrapping.

        Take this rather than `for_date` if your app has its own idea of when a day turns over
        (the upstream app rolls at Fajr, not midnight): hand it your own day number and the
        mapping is identical.
        """
        if not self._words:
            return None
        return self._words[int(day_index) % len(self._words)]

    def for_date(self, when: Union[date, datetime, None] = None) -> Optional[WordEntry]:
        return self.for_day_index(_local_day_index(when))

    def search(self, query: str, limit: int = 25) -> list[WordEntry]:
        q = (query or "").strip()
        if not q:
            return []
        lower = q.lower()
        return [w for w in self._words
                if q in w["arabic"] or lower in w["transliteration"].lower()
                or lower in w["meaning"].lower()][:limit]

    def words_in(self, surah_id: int, ayah_id: int) -> list[WordEntry]:
        return [w for w in self._words
                if any(o["surah"] == surah_id and o["ayah"] == ayah_id for o in w["occurrences"])]

    def count(self) -> dict:
        return {"words": len(self._words),
                "occurrences": sum(w["count"] for w in self._words)}
