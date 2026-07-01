"""Muqaṭṭaʿāt — the disconnected opening letters of 29 surahs (e.g. الٓمٓ). The mushaf prints them
joined with maddah marks but they are recited letter by letter ("Alif Lām Mīm"), so this exposes,
per opening ayah, the individual letters, a transliteration, and the fully-vocalized Arabic spelling
(whose long vowels carry the madd-lāzim maddah U+0653, so a tajweed pass colours them like the real
ayah).

Data: data/muqattaat.json. Ash-Shūra (42) is the one surah whose muqattaʿāt span two ayahs
(1: Ḥā Mīm, 2: ʿAyn Sīn Qāf). Mirrors src/muqattaat.js."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class MuqattaatPronunciation:
    surah: int
    ayah: int
    letters: list[str] = field(default_factory=list)   # bare letters, e.g. ["ا","ل","م"]
    transliteration: str = ""                           # "Alif Lām Mīm"
    spelled_out_arabic: str = ""                         # fully vocalized, e.g. "أَلِفۡ لَآم مِيٓمۡ"

    @staticmethod
    def from_json(d: dict) -> "MuqattaatPronunciation":
        return MuqattaatPronunciation(
            surah=d["surah"],
            ayah=d["ayah"],
            letters=d.get("letters", []),
            transliteration=d.get("transliteration", ""),
            spelled_out_arabic=d.get("spelledOutArabic", ""),
        )


class Muqattaat:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self.letter_names: dict[str, str] = data.get("letterNames", {})
        self.ayahs: list[MuqattaatPronunciation] = [
            MuqattaatPronunciation.from_json(a) for a in data.get("ayahs", [])
        ]
        self._by_key = {(e.surah, e.ayah): e for e in self.ayahs}

    def all(self) -> list[MuqattaatPronunciation]:
        """Every muqattaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd ayah)."""
        return self.ayahs

    def pronunciation(self, surah_id: int, ayah_id: int) -> Optional[MuqattaatPronunciation]:
        """Pronunciation for a muqattaʿāt ayah, or None if that ayah doesn't open with them."""
        return self._by_key.get((surah_id, ayah_id))

    def letter_name(self, letter: str) -> Optional[str]:
        """Transliteration of a single muqattaʿāt letter, e.g. "ا" → "Alif"."""
        return self.letter_names.get(letter)
