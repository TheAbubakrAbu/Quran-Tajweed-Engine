"""Meaning-based ("AI") search over any corpus. Mirrors src/semantic.js.

WHY WORD VECTORS AND MaxSim, NOT A SENTENCE EMBEDDING: measured, not assumed. One vector for a
whole verse ranks this corpus close to randomly, because translated scripture is dense and the one
idea the query asks about is washed out. Scoring word by word fixes it - embed every word, and
score a text as the MEAN over the query's words of the BEST matching word in the text. On real
verses that separates related (0.42-0.70) from unrelated (0.27-0.41) cleanly, and an unknown query
word contributes nothing instead of poisoning the vector.

THE EMBEDDER IS YOURS. This engine ships no model: word vectors are tens of megabytes and every
platform has one worth using. Pass `embed(word) -> sequence of floats or None`.
"""
from __future__ import annotations
import math
import re
from typing import Callable, Iterable, Optional, Sequence

_WORD = re.compile(r"[^\w]+", re.UNICODE)


class Semantic:
    def __init__(self, embed: Callable[[str], Optional[Sequence[float]]], min_word_length: int = 3):
        self._embed = embed
        self._min_word_length = min_word_length
        self._vectors: dict[str, Optional[list[float]]] = {}
        self._documents: list[tuple[str, object, list[list[float]]]] = []

    @property
    def size(self) -> int:
        return len(self._documents)

    def index(self, documents: Iterable[dict]) -> "Semantic":
        """Build (or rebuild) the index from dicts of {id, text, meta?}."""
        self._documents = []
        for doc in documents:
            vectors = self._vectorize(doc["text"])
            if vectors:
                self._documents.append((doc["id"], doc.get("meta"), vectors))
        return self

    def search(self, query: str, limit: int = 10, min_score: float = 0.0) -> list[dict]:
        """The documents closest in meaning to `query`, best first."""
        query_vectors = self._vectorize(query)
        if not query_vectors:
            return []
        hits = []
        for doc_id, meta, vectors in self._documents:
            total = 0.0
            for q in query_vectors:
                total += max(_dot(q, w) for w in vectors)
            score = total / len(query_vectors)
            if score >= min_score:
                hits.append({"id": doc_id, "score": score, "meta": meta})
        hits.sort(key=lambda h: (-h["score"], h["id"]))
        return hits[:limit]

    def clear(self) -> "Semantic":
        self._documents = []
        self._vectors.clear()
        return self

    def _vectorize(self, text: str) -> list[list[float]]:
        out: list[list[float]] = []
        seen: set[str] = set()
        for raw in _WORD.split(text.lower()):
            if len(raw) < self._min_word_length or raw in seen:
                continue
            seen.add(raw)
            vector = self._vector(raw)
            if vector:
                out.append(vector)
        return out

    def _vector(self, word: str) -> Optional[list[float]]:
        if word in self._vectors:
            return self._vectors[word]
        raw = self._embed(word)
        # Normalized once, so scoring is a dot product rather than three passes per pair.
        vector = _normalize(raw) if raw else None
        self._vectors[word] = vector
        return vector


def _dot(a: Sequence[float], b: Sequence[float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def _normalize(raw: Sequence[float]) -> list[float]:
    magnitude = math.sqrt(sum(x * x for x in raw))
    if magnitude == 0:
        return [0.0] * len(raw)
    return [x / magnitude for x in raw]
