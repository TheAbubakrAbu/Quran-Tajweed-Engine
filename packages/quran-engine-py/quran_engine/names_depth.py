"""The 99 Names of Allah in depth. Mirrors src/namesDepth.js.

`names-of-allah.json` carries each name, its meaning and a one-line description. This carries
what sits beneath that: the triliteral root the name is built on, one of nine themes, a
paragraph on what the name means, one line on living by it, and the ayahs where the name
itself appears with the token it sits at.

Roots print SPACED ("ر ح م") the way a grammar book sets them, while morphology.json stores them
closed up ("رحم"). `root_key` closes the spaces, so matching a name to its morphology entries is
one call rather than a trap.

The written material is Tilawa's (Jamil Hammoudeh), used with permission; the occurrences point
into this engine's own Hafs text.
"""
from __future__ import annotations
from typing import Optional


class NameDepth(dict):
    """number, root, theme, explanation, living, occurrences."""


class NameTheme(dict):
    """id, label."""


def root_key(root: str) -> str:
    """A spaced root as morphology stores it: "ر ح م" -> "رحم"."""
    return "".join((root or "").split())


class NamesDepth:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._names = [NameDepth(n) for n in data.get("names", [])]
        self._themes = [NameTheme(t) for t in data.get("themes", [])]
        self._by_number = {n["number"]: n for n in self._names}

    @property
    def is_loaded(self) -> bool:
        return bool(self._names)

    def all(self) -> list[NameDepth]:
        """All 99, ordered by number."""
        return self._names

    def by_number(self, number: int) -> Optional[NameDepth]:
        return self._by_number.get(number)

    def themes(self) -> list[NameTheme]:
        """The nine themes, in the corpus's own order."""
        return self._themes

    def theme(self, theme_id: str) -> Optional[NameTheme]:
        return next((t for t in self._themes if t["id"] == theme_id), None)

    def by_theme(self, theme_id: str) -> list[NameDepth]:
        return [n for n in self._names if n.get("theme") == theme_id]

    def by_root(self, root: str) -> list[NameDepth]:
        """Every name built on one root. Accepts either spelling, spaced or closed up."""
        key = root_key(root)
        if not key:
            return []
        return [n for n in self._names if root_key(n.get("root", "")) == key]

    def in_ayah(self, surah_id: int, ayah_id: int) -> list[dict]:
        """Every name appearing in an ayah, with the occurrence that put it there.

        An occurrence whose `token` is None could not be placed in the ayah's tokens (ten of
        them, across four names); the ayah is still right, so it sorts last rather than first.
        """
        hits = []
        for name in self._names:
            for occurrence in name.get("occurrences", []):
                if occurrence["surah"] == surah_id and occurrence["ayah"] == ayah_id:
                    hits.append({"name": name, "occurrence": occurrence})
        return sorted(hits, key=lambda h: (h["occurrence"]["token"] is None, h["occurrence"]["token"] or 0))

    def search(self, query: str, limit: int = 25) -> list[NameDepth]:
        """Names whose root, explanation or living line matches a query."""
        q = (query or "").strip()
        if not q:
            return []
        lower = q.lower()
        key = root_key(q)
        out = [
            n for n in self._names
            if (key and key in root_key(n.get("root", "")))
            or lower in n.get("explanation", "").lower()
            or lower in n.get("living", "").lower()
        ]
        return out[:limit]

    def count(self) -> dict:
        return {
            "names": len(self._names),
            "themes": len(self._themes),
            "occurrences": sum(len(n.get("occurrences", [])) for n in self._names),
        }
