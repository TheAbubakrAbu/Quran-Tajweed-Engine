"""
Ayah & surah search. Mirrors src/search.js / docs 06 (core path).

Implements: folded Arabic/English substring + phrase-prefix matching (mushaf order, unranked), the
digit-rejection rule, surah name/number/reference lookup, and makkan/madani filtering. The boolean
grammar is intentionally omitted in this port (documented limitation — see docs/PORTING.md).
"""
from __future__ import annotations
import re
from typing import Optional
from .quran import Quran
from .models import Surah
from .text import (
    clean_search, search_tokens, contains_arabic_letters, arabic_digits_to_western,
)


def _phrase_prefix_match(haystack: list[str], query: list[str]) -> bool:
    if not query or len(haystack) < len(query):
        return False
    for start in range(len(haystack) - len(query) + 1):
        ok = True
        for k, term in enumerate(query):
            word = haystack[start + k]
            if k == len(query) - 1:
                if not word.startswith(term):
                    ok = False
                    break
            elif word != term:
                ok = False
                break
        if ok:
            return True
    return False


class _Entry:
    __slots__ = ("surah", "ayah", "arabic_blob", "english_blob", "arabic_tokens", "english_tokens")

    def __init__(self, surah, ayah, arabic_blob, english_blob):
        self.surah = surah
        self.ayah = ayah
        self.arabic_blob = arabic_blob
        self.english_blob = english_blob
        self.arabic_tokens = search_tokens(arabic_blob)
        self.english_tokens = search_tokens(english_blob)


class Search:
    def __init__(self, quran: Quran, riwayah: Optional[str] = None):
        self.quran = quran
        self.riwayah = riwayah
        self._index: list[_Entry] = []
        self.rebuild()
        self._build_surah_index()

    def rebuild(self):
        idx = []
        for s, a in self.quran.each_ayah():
            raw = self.quran.arabic_text(s.id, a.id, self.riwayah) or ""
            clean = self.quran.clean_arabic_text(s.id, a.id, self.riwayah) or ""
            arabic_blob = " ".join(clean_search(t) for t in (raw, clean))
            english_blob = " ".join(clean_search(t) for t in (a.text_english_saheeh, a.text_english_mustafa, a.text_transliteration))
            idx.append(_Entry(s.id, a.id, arabic_blob, english_blob))
        self._index = idx

    def search_verses(self, query: str, offset: int = 0, limit: Optional[int] = None) -> list[dict]:
        cleaned = clean_search(query, whitespace=True)
        if not cleaned:
            return []
        if re.search(r"[0-9]", cleaned):  # digit -> not a verse-text query
            return []
        use_arabic = contains_arabic_letters(query)
        q_tokens = search_tokens(cleaned)

        def matches(e: _Entry) -> bool:
            if use_arabic:
                return cleaned in e.arabic_blob or _phrase_prefix_match(e.arabic_tokens, q_tokens)
            return cleaned in e.english_blob or _phrase_prefix_match(e.english_tokens, q_tokens)

        hits = [{"surah": e.surah, "ayah": e.ayah, "id": f"{e.surah}:{e.ayah}"} for e in self._index if matches(e)]
        return hits[offset:] if limit is None else hits[offset:offset + limit]

    # ---- surah search ----
    def _build_surah_index(self):
        self._surah_index = []
        for s in self.quran.all():
            names = [s.name_arabic, s.name_transliteration, s.name_english, *s.similar_names, str(s.id)]
            blob = clean_search(" ".join(names))
            self._surah_index.append((s, blob, blob.replace(" ", ""), f"{s.name_english} {s.name_transliteration}".upper()))

    def search_surahs(self, query: str) -> list[Surah]:
        trimmed = query.strip()
        if not trimmed:
            return self.quran.all()
        norm = clean_search(trimmed).replace(" ", "")
        makkan = ["makkah", "makkan", "makki"]
        madinan = ["madinah", "madinan", "madina", "madani"]
        if norm and any(a.startswith(norm) or norm.startswith(a) for a in makkan):
            return [s for s in self.quran.all() if s.type == "makkan"]
        if norm and any(a.startswith(norm) or norm.startswith(a) for a in madinan):
            return [s for s in self.quran.all() if s.type == "madinan"]

        ref = self.parse_reference(trimmed)
        cleaned = clean_search(trimmed.replace(":", ""))
        compact = cleaned.replace(" ", "")
        upper = trimmed.upper()
        numeric = ref["surah"] if ref else _to_number(cleaned)

        out = []
        for s, blob, blob_compact, blob_upper in self._surah_index:
            if (numeric == s.id or (blob_upper and blob_upper in upper)
                    or (cleaned and cleaned in blob) or (compact and compact in blob_compact)):
                out.append(s)
        return out

    def parse_reference(self, query: str) -> Optional[dict]:
        parts = [p for p in re.split(r"[:\s]+", arabic_digits_to_western(query)) if p]
        if not parts:
            return None
        surah = _to_number(parts[0])
        if surah is None:
            cleaned = clean_search(parts[0])
            for s, blob, blob_compact, _ in self._surah_index:
                if cleaned in blob.split(" ") or cleaned.replace(" ", "") in blob_compact:
                    surah = s.id
                    break
        if surah is None:
            return None
        ayah = _to_number(parts[1]) if len(parts) >= 2 else None
        return {"surah": surah, "ayah": ayah}


def _to_number(s: str) -> Optional[int]:
    s = arabic_digits_to_western(s).strip()
    return int(s) if s.isdigit() else None
