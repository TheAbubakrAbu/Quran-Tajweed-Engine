"""
Tajweed coloring by consuming the pre-computed annotation corpus (data/tajweed/).

This is strategy (A) from docs/PORTING.md: load annotations + map each rule to a color. It needs no
detection logic, so it's small and exactly consistent with the reference engine. To color arbitrary text
(other qiraat, user input) you'd port the detector from docs/02-tajweed.md instead.
"""
from __future__ import annotations
from .models import TajweedSpan
from .text import utf16_slice


class Tajweed:
    def __init__(self, annotations_by_key: dict[tuple[int, int], list[dict]], colors_by_rule: dict[str, str]):
        self._ann = annotations_by_key
        self._colors = colors_by_rule

    def spans(self, surah_id: int, ayah_id: int, ayah_text: str) -> list[TajweedSpan]:
        out = []
        for a in self._ann.get((surah_id, ayah_id), []):
            start, end, rule = a["start"], a["end"], a["rule"]
            out.append(TajweedSpan(
                start=start, end=end, rule=rule,
                text=utf16_slice(ayah_text, start, end),
                color=self._colors.get(rule),
            ))
        return out
