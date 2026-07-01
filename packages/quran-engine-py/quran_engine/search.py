"""
Ayah & surah search. Faithful port of src/search.js.

Verse matching is unranked — results come back in mushaf order (surah, then ayah). Each verse is
indexed into Arabic/English blobs plus token lists; the regular path is pure substring, while a small
boolean grammar (`&` AND, `|` OR, `!` NOT, `#` exact, `=` whole-word, `^` starts-with, `%`/`$`
ends-with) drives whole-word / prefix / tashkeel-sensitive matching.
"""
from __future__ import annotations
import re
from typing import Optional
from .quran import Quran
from .models import Surah
from .text import (
    clean_search, search_tokens, contains_arabic_letters, arabic_digits_to_western,
    arabic_tashkeel_blob, exact_phrase_blob, removing_silent_arabic_letters_for_search,
)

_BOOLEAN_CHARS = re.compile(r"[&|!#^%$=]")


def _consecutive_token_match(haystack: list[str], query: list[str], last_must_be_exact: bool) -> bool:
    """Query tokens appear as a consecutive run of haystack tokens; leading tokens exact-equal, the
    last token exact when last_must_be_exact else a prefix. Mirrors consecutiveTokenMatch()."""
    if not query or len(haystack) < len(query):
        return False
    for start in range(len(haystack) - len(query) + 1):
        ok = True
        for k, term in enumerate(query):
            word = haystack[start + k]
            if k == len(query) - 1 and not last_must_be_exact:
                if not word.startswith(term):
                    ok = False
                    break
            elif word != term:
                ok = False
                break
        if ok:
            return True
    return False


class _Term:
    __slots__ = (
        "value", "negate", "match_mode", "requires_tashkeel_match", "tashkeel_pattern",
        "requires_exact_english_match", "exact_english_phrase",
    )


def _parse_term(raw_term: str) -> _Term:
    """Parse a single boolean term. Mirrors parseTerm(): strips (in order) leading `!` (negate, toggles),
    `#` (tashkeel-sensitive), `=` (whole-word), one `^` (starts-with), one trailing `%`/`$` (ends-with)."""
    t = raw_term.strip()
    negate = False
    while t.startswith("!"):
        negate = not negate
        t = t[1:].strip()
    requires_tashkeel = False
    while t.startswith("#"):
        requires_tashkeel = True
        t = t[1:].strip()
    whole_word = False
    while t.startswith("="):
        whole_word = True
        t = t[1:].strip()
    starts_with = False
    if t.startswith("^"):
        starts_with = True
        t = t[1:].strip()
    ends_with = False
    if t.endswith("%") or t.endswith("$"):
        ends_with = True
        t = t[:-1].strip()

    value = clean_search(t, whitespace=True)
    if whole_word:
        match_mode = "whole_word"
    elif starts_with and ends_with:
        match_mode = "exact"
    elif starts_with:
        match_mode = "starts_with"
    elif ends_with:
        match_mode = "ends_with"
    else:
        match_mode = "contains"

    is_arabic = contains_arabic_letters(t)
    term = _Term()
    term.value = value
    term.negate = negate
    term.match_mode = match_mode
    term.requires_tashkeel_match = requires_tashkeel and is_arabic
    term.tashkeel_pattern = arabic_tashkeel_blob(t)
    term.requires_exact_english_match = requires_tashkeel and not is_arabic
    term.exact_english_phrase = exact_phrase_blob(t)
    return term


def _ayah_term_match(haystack: str, tokens: list[str], term: str, mode: str) -> bool:
    """Match a term's value against a blob/token list under one mode. Mirrors ayahTermMatch()."""
    if mode == "starts_with":
        return haystack.startswith(term) or any(w.startswith(term) for w in tokens)
    if mode == "ends_with":
        return haystack.endswith(term) or any(w.endswith(term) for w in tokens)
    if mode == "exact":
        return haystack == term or term in tokens
    if mode == "whole_word":
        return _consecutive_token_match(tokens, search_tokens(term), True)
    # contains
    return term in haystack


class _Entry:
    __slots__ = (
        "surah", "ayah", "arabic_blob", "silent_arabic_blob", "english_blob",
        "arabic_tashkeel_blob", "english_exact_blob",
        "arabic_tokens", "english_tokens",
    )

    def __init__(self, surah, ayah, arabic_blob, silent_arabic_blob, english_blob,
                 arabic_tashkeel_blob, english_exact_blob):
        self.surah = surah
        self.ayah = ayah
        self.arabic_blob = arabic_blob
        self.silent_arabic_blob = silent_arabic_blob
        self.english_blob = english_blob
        self.arabic_tashkeel_blob = arabic_tashkeel_blob
        self.english_exact_blob = english_exact_blob
        self.arabic_tokens = search_tokens(arabic_blob)
        self.english_tokens = search_tokens(english_blob)

    def _term_match(self, term: _Term, use_arabic: bool) -> bool:
        """Per-term match (un-negated). Mirrors termMatch()."""
        if use_arabic and term.requires_tashkeel_match:
            letters_match = _ayah_term_match(self.arabic_blob, self.arabic_tokens, term.value, term.match_mode)
            tashkeel_match = term.tashkeel_pattern == "" or term.tashkeel_pattern in self.arabic_tashkeel_blob
            return letters_match and tashkeel_match
        if not use_arabic and term.requires_exact_english_match:
            exact_tokens = search_tokens(term.exact_english_phrase)
            return term.exact_english_phrase != "" and _ayah_term_match(
                self.english_exact_blob, exact_tokens, term.exact_english_phrase, term.match_mode)
        haystack = self.arabic_blob if use_arabic else self.english_blob
        tokens = self.arabic_tokens if use_arabic else self.english_tokens
        return _ayah_term_match(haystack, tokens, term.value, term.match_mode)


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
            english = (a.text_english_saheeh, a.text_english_mustafa, a.text_transliteration)
            arabic_blob = " ".join(clean_search(t) for t in (raw, clean))
            silent_arabic_blob = " ".join(
                clean_search(removing_silent_arabic_letters_for_search(t)) for t in (raw, clean))
            english_blob = " ".join(clean_search(t) for t in english)
            idx.append(_Entry(
                s.id, a.id, arabic_blob, silent_arabic_blob, english_blob,
                arabic_tashkeel_blob(raw), exact_phrase_blob(" ".join(english)),
            ))
        self._index = idx

    def search_verses(self, query: str, offset: int = 0, limit: Optional[int] = None,
                      ignore_silent_letters: bool = False) -> list[dict]:
        cleaned = clean_search(query, whitespace=True)
        if not cleaned:
            return []
        # Reject any query containing a (Unicode) digit. Done BEFORE the boolean path, exactly as
        # QuranData.search(term:) does — so even a boolean query with a digit returns [].
        if re.search(r"\d", cleaned, re.UNICODE):
            return []
        if _BOOLEAN_CHARS.search(query):
            return self._boolean_search(query, offset, limit)

        use_arabic = contains_arabic_letters(query)
        silent_query = (
            clean_search(removing_silent_arabic_letters_for_search(query), whitespace=True)
            if use_arabic and ignore_silent_letters else ""
        )

        # Plain substring search in mushaf order — word/sentence boundaries DON'T matter. Whole-word /
        # phrase matching lives in the `=` operator; `#` does an exact (tashkeel-sensitive) match.
        def matches(e: _Entry) -> bool:
            if use_arabic:
                if cleaned in e.arabic_blob:
                    return True
                if not silent_query:
                    return False
                return silent_query in e.silent_arabic_blob
            return cleaned in e.english_blob

        return self._paginate([e for e in self._index if matches(e)], offset, limit)

    # ---- boolean search ----
    def _boolean_search(self, query: str, offset: int, limit: Optional[int]) -> list[dict]:
        use_arabic = contains_arabic_letters(query)
        normalized = query.replace("&&", "&").replace("||", "|")
        # Drop any term whose cleaned value is empty — booleanAyahSearchTerm() returns nil in that case.
        or_groups = [
            [t for t in (_parse_term(raw) for raw in group.split("&")) if t.value != ""]
            for group in normalized.split("|")
        ]
        or_groups = [g for g in or_groups if g]
        if not or_groups:
            return []

        def matches(e: _Entry) -> bool:
            return any(
                all(
                    (not e._term_match(term, use_arabic)) if term.negate
                    else e._term_match(term, use_arabic)
                    for term in and_terms
                )
                for and_terms in or_groups
            )

        return self._paginate([e for e in self._index if matches(e)], offset, limit)

    @staticmethod
    def _paginate(entries: list[_Entry], offset: int, limit: Optional[int]) -> list[dict]:
        hits = [{"surah": e.surah, "ayah": e.ayah, "id": f"{e.surah}:{e.ayah}"} for e in entries]
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
