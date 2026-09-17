"""The scientific-miracles corpus. Mirrors src/miracles.js.

202 short articles, each making one claim about the Quran and anchoring it to the ayahs it rests
on, under 15 categories.

An article is a list of BLOCKS in reading order rather than one field of prose, because the layout
matters: the claim is a headline, the lead sets it up, a quote carries somebody else's words with
the source next to them, an ayah block is a hole the consumer fills from quran.json, and the closer
asks the rhetorical question the article was built toward.

An ``ayah`` block carries NO text, by design: surah, ayah and end_ayah only. The verse belongs to
this engine's own Hafs text, so duplicating it here would be a second copy to keep in step and
would pin the article to one riwayah. ``citing`` and ``ayah_refs`` are the two ends of that link:
which articles reach an ayah, and which ayahs one article reaches.

There are NO ``image`` blocks and ``images_included`` is false: the site's illustrations are not
republished here for licensing reasons, and the prose is written to stand without them. A consumer
that leaves a gap for a picture will be waiting forever.

Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters or
sorts by has to come off the ARTICLE. ``by_level`` and ``levels`` both do.
"""
from __future__ import annotations
from typing import Optional

#: The four levels, easiest first. Hard-coded because this is the app's own ordering and nothing
#: in the file states it: alphabetically "extreme" would sort second, which is precisely backwards.
MIRACLE_LEVELS = ["simple", "intermediate", "advanced", "extreme"]

#: The blocks that carry the article's OWN prose. A quote is somebody else's words and an ayah
#: block has no text at all, so neither belongs in ``text``.
_PROSE_KINDS = ("claim", "lead", "text", "closer")


class MiracleCategory(dict):
    """id, level."""


class MiracleArticle(dict):
    """slug, title, category, level, blocks."""


def _level_rank(level: str) -> int:
    """Where a level sorts, or past the end for one the corpus invents later."""
    try:
        return MIRACLE_LEVELS.index(level)
    except ValueError:
        return len(MIRACLE_LEVELS)


class Miracles:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._articles = [MiracleArticle(a) for a in data.get("articles", [])]
        self._categories = [MiracleCategory(c) for c in data.get("categories", [])]
        self._by_slug = {a["slug"]: a for a in self._articles}
        self._source = data.get("source", "")
        self._images_included = bool(data.get("imagesIncluded", False))

    @property
    def is_loaded(self) -> bool:
        return bool(self._articles)

    def source(self) -> str:
        """Where the corpus came from and when it was captured."""
        return self._source

    @property
    def images_included(self) -> bool:
        """False, always: the illustrations are not republished."""
        return self._images_included

    def all(self) -> list[MiracleArticle]:
        """All 202, in corpus order."""
        return self._articles

    def by_slug(self, slug: str) -> Optional[MiracleArticle]:
        return self._by_slug.get(slug)

    def categories(self) -> list[MiracleCategory]:
        """The fifteen categories, in the corpus's own order."""
        return self._categories

    def category(self, category_id: str) -> Optional[MiracleCategory]:
        return next((c for c in self._categories if c["id"] == category_id), None)

    def by_category(self, category_id: str) -> list[MiracleArticle]:
        """Every article filed under one category."""
        return [a for a in self._articles if a.get("category") == category_id]

    def by_level(self, level: str) -> list[MiracleArticle]:
        """Every article at one level.

        The ARTICLE's level, not its category's: they disagree far more often than they agree, and
        a reader who picked "simple" means the article.
        """
        return [a for a in self._articles if a.get("level") == level]

    def levels(self) -> list[str]:
        """The article levels actually present, easiest first."""
        present = {a.get("level", "") for a in self._articles}
        return sorted(present, key=lambda l: (_level_rank(l), l))

    def citing(self, surah_id: int, ayah_id: int) -> list[MiracleArticle]:
        """Every article that cites an ayah: the way into this corpus from elsewhere in the engine.

        An ``ayah`` block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An
        article that cites the same ayah in two blocks is still listed once.
        """
        def reaches(article: MiracleArticle) -> bool:
            return any(
                b.get("kind") == "ayah"
                and b.get("surah") == surah_id
                and b.get("ayah") is not None
                and b["ayah"] <= ayah_id <= b.get("endAyah", b["ayah"])
                for b in article.get("blocks", [])
            )

        return [a for a in self._articles if reaches(a)]

    def ayah_refs(self, slug: str) -> list[dict]:
        """The ayah ranges one article cites, in the order it cites them."""
        article = self._by_slug.get(slug)
        if not article:
            return []
        return [
            {"surah": b["surah"], "ayah": b["ayah"], "endAyah": b["endAyah"]}
            for b in article.get("blocks", []) if b.get("kind") == "ayah"
        ]

    def search(self, query: str, limit: int = 25) -> list[MiracleArticle]:
        """Articles whose title or prose matches a query, case-insensitively.

        Quotes are searched as well: a reader looking for a word remembers reading it, not who
        wrote it.
        """
        q = (query or "").strip().lower()
        if not q:
            return []
        out = [
            a for a in self._articles
            if q in a.get("title", "").lower()
            or any(q in (b.get("text") or "").lower() for b in a.get("blocks", []))
        ]
        return out[:limit]

    def text(self, slug: str) -> str:
        """One article's own prose, blocks joined with a blank line in reading order.

        Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
        folding them in would put somebody else's words into the article's voice and would break a
        citation off from what it cites. Ayah blocks are skipped because they carry no text at all,
        only a reference for the consumer to resolve.
        """
        article = self._by_slug.get(slug)
        if not article:
            return ""
        parts = [b.get("text") or "" for b in article.get("blocks", [])
                 if b.get("kind") in _PROSE_KINDS]
        return "\n\n".join(p for p in parts if p)

    def count(self) -> dict:
        return {
            "articles": len(self._articles),
            "categories": len(self._categories),
            "ayahRefs": sum(
                1 for a in self._articles
                for b in a.get("blocks", []) if b.get("kind") == "ayah"
            ),
        }
