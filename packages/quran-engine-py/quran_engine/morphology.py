"""Root and lemma of every word of the Quran. Mirrors src/morphology.js.

The Quranic Arabic Corpus morphology (Kais Dukes) as redistributed by the Quranic Universal
Library. One id per whitespace token of the ayah's raw Hafs text, in the text's own order, so
nothing here matches or normalizes text: id 0 means the token has neither a root nor a lemma,
which is the honest answer for particles and the sajdah mark. Ids are 1-based.

The reverse indexes are built on first use and kept: walking 77,629 tokens is quick, but a
caller asking about ten roots should not pay for it ten times.
"""
from __future__ import annotations

import re
from typing import Optional

from .text import clean_search, removing_arabic_diacritics_and_signs

_SPACES = re.compile(r"\s+")


def fold_for_morphology(text: str) -> str:
    """Marks and spaces gone.

    Every space is removed, not merely trimmed: a root is printed spaced ("ر ب ب") and typed
    closed up ("ربب"), and the two have to meet.
    """
    return _SPACES.sub("", clean_search(removing_arabic_diacritics_and_signs(text or ""),
                                        whitespace=True))


class Root(dict):
    """letters, buckwalter, joined."""


class Lemma(dict):
    """text, clean."""


class WordLocation(dict):
    """surah, ayah, token."""


class Morphology:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._roots: list = data.get("roots", [])
        self._lemmas: list = data.get("lemmas", [])
        self._root_ids: dict = data.get("rootIds", {})
        self._lemma_ids: dict = data.get("lemmaIds", {})
        self._by_root: Optional[dict[int, list[WordLocation]]] = None
        self._by_lemma: Optional[dict[int, list[WordLocation]]] = None

    @property
    def is_loaded(self) -> bool:
        return bool(self._roots)

    def root(self, root_id: int) -> Optional[Root]:
        if root_id < 1 or root_id > len(self._roots):
            return None
        letters, buckwalter = self._roots[root_id - 1]
        return Root({"letters": letters, "buckwalter": buckwalter,
                     "joined": letters.replace(" ", "")})

    def lemma(self, lemma_id: int) -> Optional[Lemma]:
        if lemma_id < 1 or lemma_id > len(self._lemmas):
            return None
        text, clean = self._lemmas[lemma_id - 1]
        return Lemma({"text": text, "clean": clean})

    def ids(self, surah_id: int, ayah_id: int) -> Optional[dict]:
        """The root and lemma id of every token of the ayah, or None when it is not covered."""
        roots = self._root_ids.get(str(surah_id))
        lemmas = self._lemma_ids.get(str(surah_id))
        if not roots or not lemmas or ayah_id < 1 or ayah_id > len(roots) or ayah_id > len(lemmas):
            return None
        return {"roots": roots[ayah_id - 1], "lemmas": lemmas[ayah_id - 1]}

    def root_of(self, surah_id: int, ayah_id: int, token: int) -> Optional[dict]:
        ids = self.ids(surah_id, ayah_id)
        if not ids or token < 0 or token >= len(ids["roots"]):
            return None
        rid = ids["roots"][token]
        root = self.root(rid)
        return {"id": rid, "root": root} if root else None

    def lemma_of(self, surah_id: int, ayah_id: int, token: int) -> Optional[dict]:
        ids = self.ids(surah_id, ayah_id)
        if not ids or token < 0 or token >= len(ids["lemmas"]):
            return None
        lid = ids["lemmas"][token]
        lemma = self.lemma(lid)
        return {"id": lid, "lemma": lemma} if lemma else None

    def occurrences_of_root(self, root_id: int) -> list[WordLocation]:
        """Every word carrying this root, in mushaf order."""
        self._index()
        return (self._by_root or {}).get(root_id, [])

    def occurrences_of_lemma(self, lemma_id: int) -> list[WordLocation]:
        self._index()
        return (self._by_lemma or {}).get(lemma_id, [])

    def find_roots(self, query: str, limit: int = 50) -> list[dict]:
        """Roots whose Arabic or Buckwalter spelling starts with the query."""
        return [{"id": i, "root": Root({"letters": row[0], "buckwalter": row[1],
                                        "joined": row[0].replace(" ", "")})}
                for i, row in self._prefix_hits(self._roots, query, limit)]

    def find_lemmas(self, query: str, limit: int = 50) -> list[dict]:
        return [{"id": i, "lemma": Lemma({"text": row[0], "clean": row[1]})}
                for i, row in self._prefix_hits(self._lemmas, query, limit)]

    def count(self) -> dict:
        tokens = sum(len(row) for ayahs in self._root_ids.values() for row in ayahs)
        return {"roots": len(self._roots), "lemmas": len(self._lemmas), "tokens": tokens}

    # -- internals ---------------------------------------------------------------------

    def _prefix_hits(self, table: list, query: str, limit: int):
        folded = fold_for_morphology(query)
        latin = (query or "").strip().lower()
        if not folded and not latin:
            return []
        out = []
        for i, row in enumerate(table):
            if len(out) >= limit:
                break
            arabic = fold_for_morphology(row[0])
            roman = str(row[1] or "").lower()
            if (folded and arabic.startswith(folded)) or (latin and roman.startswith(latin)):
                out.append((i + 1, row))
        return out

    def _index(self) -> None:
        if self._by_root is not None:
            return
        by_root: dict[int, list[WordLocation]] = {}
        by_lemma: dict[int, list[WordLocation]] = {}
        for surah in sorted(int(k) for k in self._root_ids):
            roots = self._root_ids.get(str(surah), [])
            lemmas = self._lemma_ids.get(str(surah), [])
            for a, root_row in enumerate(roots):
                lemma_row = lemmas[a] if a < len(lemmas) else []
                for t, rid in enumerate(root_row):
                    location = WordLocation({"surah": surah, "ayah": a + 1, "token": t})
                    if rid:
                        by_root.setdefault(rid, []).append(location)
                    lid = lemma_row[t] if t < len(lemma_row) else 0
                    if lid:
                        by_lemma.setdefault(lid, []).append(location)
        self._by_root = by_root
        self._by_lemma = by_lemma
