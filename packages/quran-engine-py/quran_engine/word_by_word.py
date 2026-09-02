"""Word by word: what each word means, and how it is said. Mirrors src/wordByWord.js.

Two layers over the SAME tokens - the English gloss and a Latin transliteration - where the tokens
are the ayah's own whitespace-separated words. Split the ayah and index straight in; the alignment
against a corpus that tokenizes ~200 ayahs differently was done once, at build time.

A token with no word of its own (the ۞ ornament, the tail of a merged word) carries "" in both.
"""
from __future__ import annotations
import re
from typing import Optional

_WHITESPACE = re.compile(r"\s+")


class Word(dict):
    """position, arabic, english, transliteration."""


class WordByWord:
    def __init__(self, english: Optional[dict] = None, transliteration: Optional[dict] = None,
                 quran=None):
        self._english = english or {}
        self._transliteration = transliteration or {}
        self._quran = quran

    @property
    def is_loaded(self) -> bool:
        return bool(self._english)

    def words(self, surah_id: int, ayah_id: int) -> list[Word]:
        english = self.glosses(surah_id, ayah_id)
        if english is None:
            return []
        latin = self.transliterations(surah_id, ayah_id) or []
        tokens = self._tokens(surah_id, ayah_id)
        return [Word({
            "position": i + 1,
            "arabic": tokens[i] if i < len(tokens) else "",
            "english": gloss,
            "transliteration": latin[i] if i < len(latin) else "",
        }) for i, gloss in enumerate(english)]

    def word(self, surah_id: int, ayah_id: int, position: int) -> Optional[Word]:
        words = self.words(surah_id, ayah_id)
        return words[position - 1] if 1 <= position <= len(words) else None

    def glosses(self, surah_id: int, ayah_id: int) -> Optional[list[str]]:
        return self._row(self._english, surah_id, ayah_id)

    def transliterations(self, surah_id: int, ayah_id: int) -> Optional[list[str]]:
        return self._row(self._transliteration, surah_id, ayah_id)

    def find(self, term: str, limit: int = 50) -> list[dict]:
        """Ayahs with a word whose gloss carries `term` - a word-level English search."""
        needle = term.strip().lower()
        if not needle:
            return []
        out: list[dict] = []
        for surah in sorted(self._english, key=int):
            for ayah_index, glosses in enumerate(self._english[surah]):
                for i, gloss in enumerate(glosses):
                    if needle not in gloss.lower():
                        continue
                    rows = self._transliteration.get(surah) or []
                    latin = rows[ayah_index][i] if ayah_index < len(rows) and i < len(rows[ayah_index]) else ""
                    out.append({"surah": int(surah), "ayah": ayah_index + 1, "position": i + 1,
                                "english": gloss, "transliteration": latin})
                    if len(out) >= limit:
                        return out
        return out

    @staticmethod
    def _row(layer: dict, surah_id: int, ayah_id: int) -> Optional[list[str]]:
        rows = layer.get(str(surah_id))
        if not rows or ayah_id < 1 or ayah_id > len(rows):
            return None
        return rows[ayah_id - 1]

    def _tokens(self, surah_id: int, ayah_id: int) -> list[str]:
        if self._quran is None:
            return []
        ayah = self._quran.ayah(surah_id, ayah_id)
        return _WHITESPACE.split(ayah.text_arabic.strip()) if ayah else []
