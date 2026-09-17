"""Similar ayahs (mutashabihat). Mirrors src/similar.js.

Three sources, already merged and ranked at build time, so nothing here scores or sorts.
`verified` rows come from the classical mutashabihat corpus and are listed first. Generated
rows are phrase-overlap matches, each carrying the `labels` that say why they matched
("Reckoning", "Root rbb"); they are a reading aid, not a scholarly claim. The Quranic Universal
Library's table is the third source and adds `score`, its own 0-100 similarity; `score` is None
for rows from the other two sources, which rank but do not score. `verified` is the flag to gate
on if you show only one kind.

The shared wording is `spans`: 0-based inclusive token ranges into the MATCHED ayah's raw text
(QUL's own placement where it lists the pair, else the wording the corpus recorded, located in
the ayah when the data was built). The data carries no text of its own (version 2), and a match
has no `phrase`: cut the words out of quran.json's tokens by the span, so what you show is the
Quran text you already have and not a second copy of it.

The file is {"v": 2, "ayahs": {"surah:ayah": [[surah, ayah, verifiedFlag, spans, labels, score],
...]}}. A version-1 file (rows keyed at the top level, the phrase as text) is not read: it would
put the shared wording where a span is expected, so it is treated as no data rather than half of
one, exactly as the JS does.
"""
from __future__ import annotations
from typing import Optional


class SimilarMatch(dict):
    """surah, ayah, verified, labels, spans, score.

    `spans` is a list of (start, end) tuples, 0-based inclusive token indices into the matched
    ayah's raw text, empty when no source records shared wording. `labels` is empty for verified
    rows. `score` is None for rows that did not come from QUL. There is no `phrase`: read the
    words out of the Quran text by the span.
    """


class SimilarAyahs:
    def __init__(self, data: Optional[dict] = None):
        """`data` is data/similar-ayahs.json (version 2). Anything else reads as no data."""
        ayahs = data.get("ayahs") if isinstance(data, dict) and data.get("v") == 2 else None
        self._data: dict = ayahs if isinstance(ayahs, dict) else {}

    def matches(self, surah_id: int, ayah_id: int) -> list[SimilarMatch]:
        """Matches for an ayah, in display order. Empty for most short ayahs."""
        rows = self._data.get(f"{surah_id}:{ayah_id}")
        if not rows:
            return []
        out = []
        for surah, ayah, verified, spans, labels, score in rows:
            out.append(SimilarMatch({"surah": surah, "ayah": ayah, "verified": verified == 1,
                                     "labels": labels or [],
                                     "spans": [tuple(span) for span in spans] if spans else [],
                                     "score": score}))
        return out

    def has(self, surah_id: int, ayah_id: int) -> bool:
        """A dictionary hit, cheap enough to gate a button on."""
        return bool(self._data.get(f"{surah_id}:{ayah_id}"))

    def count(self) -> int:
        """How many ayahs have at least one match."""
        return len(self._data)
