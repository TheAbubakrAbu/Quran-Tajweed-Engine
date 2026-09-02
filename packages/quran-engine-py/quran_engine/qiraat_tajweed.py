"""Riwayah tajweed: where a reading differs from Hafs, and why. Mirrors src/qiraatTajweed.js.

Different layer from `tajweed.py`, which detects the universal recitation rules from the text.
This carries what is SPECIFIC to a transmission and cannot be detected, because it IS the text's
difference: Warsh's taqlil, al-Bazzi's doubled ta, the places two readings part.

Two things to know: the meaning of a colour is PER EDITION (always read `legend`), and extents are
base-LETTER indices in reading order, not character offsets - or the whole word when `whole_word`.
"""
from __future__ import annotations
from typing import Optional


class LegendEntry(dict):
    """A legend row: code, rule, arabic, english, and the shared short/long explanation."""


class WordRule(dict):
    """word, rule, code, arabic, english, first_letter, last_letter, whole_word."""


class QiraatTajweed:
    def __init__(self, rules: Optional[dict] = None, riwayat: Optional[dict] = None):
        self._descriptions = rules or {}
        self._riwayat = riwayat or {}
        self._codes_cache: dict[str, dict[str, dict]] = {}

    def available(self) -> list[str]:
        return sorted(self._riwayat)

    def legend(self, riwayah: str) -> list[LegendEntry]:
        pack = self._riwayat.get(riwayah)
        if not pack:
            return []
        return [LegendEntry({**entry, **self._descriptions.get(entry["rule"], {})})
                for entry in pack["legend"]]

    def word_rules(self, surah_id: int, ayah_id: int, riwayah: str) -> list[WordRule]:
        pack = self._riwayat.get(riwayah)
        words = ((pack or {}).get("rules") or {}).get(str(surah_id), {}).get(str(ayah_id))
        if not words:
            return []
        by_code = self._codes(riwayah)
        out: list[WordRule] = []
        for key in sorted(words, key=int):
            for code, lo, hi in words[key]:
                entry = by_code.get(code, {})
                out.append(WordRule({
                    "word": int(key),
                    "rule": entry.get("rule", code),
                    "code": code,
                    "arabic": entry.get("arabic", ""),
                    "english": entry.get("english", ""),
                    "first_letter": lo,
                    "last_letter": hi,
                    "whole_word": lo < 0,
                }))
        return out

    def khilaf_ayahs(self, surah_id: int, riwayah: str) -> list[int]:
        """The ayahs of a surah this riwayah reads differently from Hafs somewhere."""
        pack = self._riwayat.get(riwayah) or {}
        return (pack.get("khilafMarkers") or {}).get(str(surah_id), [])

    def has_khilaf(self, surah_id: int, ayah_id: int, riwayah: str) -> bool:
        return ayah_id in self.khilaf_ayahs(surah_id, riwayah)

    def describe(self, rule: str) -> Optional[dict]:
        """What a rule key means, in one line and in a paragraph. Shared across riwayat."""
        return self._descriptions.get(rule)

    def rule_keys(self) -> list[str]:
        return sorted(self._descriptions)

    def _codes(self, riwayah: str) -> dict[str, dict]:
        cached = self._codes_cache.get(riwayah)
        if cached is None:
            cached = {entry["code"]: entry for entry in self.legend(riwayah)}
            self._codes_cache[riwayah] = cached
        return cached
