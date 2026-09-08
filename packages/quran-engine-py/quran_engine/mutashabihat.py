"""The phrases the Quran repeats. Mirrors src/mutashabihat.js.

A different thing from `similar_ayahs`: that answers "what else reads like this verse" with
whole-ayah matches; this answers "which exact run of words does this verse share, and which
words are they" - the memoriser's question. 814 phrases from the Quranic Universal Library.

Spans are 0-based inclusive token ranges of the raw Hafs text, mapped at build time.
"""
from __future__ import annotations
from typing import Optional


def _rank(key: str) -> tuple[int, int]:
    parts = key.split(":")
    try:
        return int(parts[0]), int(parts[1])
    except (ValueError, IndexError):
        return 10 ** 9, 0


class Phrase(dict):
    """id, source, span, count, ayah_count, surah_count, occurrences, word_count."""


class Mutashabihat:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._phrases: dict = data.get("phrases", {})
        self._index: dict = data.get("index", {})

    @property
    def is_loaded(self) -> bool:
        return bool(self._phrases)

    def phrases_for(self, surah_id: int, ayah_id: int) -> list[Phrase]:
        """The phrases this ayah carries, longest first."""
        ids = self._index.get(f"{surah_id}:{ayah_id}", [])
        out = [p for p in (self.phrase(i) for i in ids) if p]
        out.sort(key=lambda p: (-p["word_count"], p["id"]))
        return out

    def phrase(self, phrase_id: int) -> Optional[Phrase]:
        row = self._phrases.get(str(phrase_id))
        if not row:
            return None
        span = row["span"]
        return Phrase({
            "id": phrase_id,
            "source": row["source"],
            "span": (span[0], span[1]),
            "count": row["count"],
            "ayah_count": row["ayahCount"],
            "surah_count": row["surahCount"],
            "occurrences": row.get("occurrences", {}),
            "word_count": span[1] - span[0] + 1,
        })

    def has(self, surah_id: int, ayah_id: int) -> bool:
        return bool(self._index.get(f"{surah_id}:{ayah_id}"))

    def occurrences(self, phrase_id: int) -> list[dict]:
        """A phrase's occurrences in mushaf order, each with the spans carrying it there."""
        phrase = self.phrase(phrase_id)
        if not phrase:
            return []
        out = []
        for key in sorted(phrase["occurrences"], key=_rank):
            surah, ayah = (int(p) for p in key.split(":"))
            out.append({"surah": surah, "ayah": ayah, "key": key,
                        "spans": phrase["occurrences"][key]})
        return out

    def text_of(self, phrase_id: int, source_ayah_text: str) -> str:
        """The phrase's own words, sliced out of the ayah text you hand it."""
        phrase = self.phrase(phrase_id)
        if not phrase:
            return ""
        tokens = (source_ayah_text or "").split()
        start, end = phrase["span"]
        return " ".join(tokens[start:end + 1])

    def count(self) -> dict:
        return {"phrases": len(self._phrases), "ayahs": len(self._index)}
