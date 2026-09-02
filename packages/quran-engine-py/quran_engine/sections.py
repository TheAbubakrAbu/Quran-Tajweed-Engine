"""Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one
sentence saying what the surah as a whole is about.

This answers "I am at 18:60 - what is this passage doing here", which neither the translation nor
the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
outline; al-Fatihah, Fussilat and ad-Dukhan do not.

THE OUTLINE IS A TREE, FLATTENED. Ranges are inclusive, in mushaf order, and MAY NEST: a broad
section is followed by the sections inside it, parent before children (Hud opens with 1-24
"Doctrine facts", then 1-4, 5-6, 7-11, 12-17, 18-24 within it). They also do not tile the surah -
an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
which is what ``sections_for`` returns; ``outline`` rebuilds the same thing as a tree.

See ../../docs/15-surah-sections.md.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


@dataclass(frozen=True)
class SurahSection:
    """One titled range of ayahs. ``from_ayah``/``to_ayah`` are inclusive."""

    from_ayah: int
    to_ayah: int
    english: str
    arabic: str

    def contains(self, ayah_id: int) -> bool:
        return self.from_ayah <= ayah_id <= self.to_ayah


@dataclass
class OutlineNode:
    """A section with the sections inside it."""

    section: SurahSection
    children: list["OutlineNode"] = field(default_factory=list)


class SurahSections:
    def __init__(self, data: Optional[dict] = None) -> None:
        self._data = data or {}

    def overview(self, surah_id: int) -> str:
        """One sentence on what the whole surah is about, "" when none is recorded."""
        return self._data.get(str(surah_id), {}).get("overview", "")

    def sections(self, surah_id: int) -> list[SurahSection]:
        """The surah's sections, flat and in the order the source records them (a parent
        immediately before the sections inside it)."""
        rows = self._data.get(str(surah_id), {}).get("sections") or []
        return [SurahSection(row[0], row[1], row[2], row[3]) for row in rows]

    def outline(self, surah_id: int) -> list[OutlineNode]:
        """The same sections as a tree: top-level passages, each with what is inside it."""
        roots: list[OutlineNode] = []
        stack: list[OutlineNode] = []
        for section in self.sections(surah_id):
            # A section belongs to the nearest still-open range that fully contains it.
            while stack and not (stack[-1].section.from_ayah <= section.from_ayah
                                 and section.to_ayah <= stack[-1].section.to_ayah):
                stack.pop()
            node = OutlineNode(section)
            (stack[-1].children if stack else roots).append(node)
            stack.append(node)
        return roots

    def sections_for(self, surah_id: int, ayah_id: int) -> list[SurahSection]:
        """Every section covering an ayah, outermost first - the breadcrumb for "you are here".
        Empty when the surah has no outline, or when this ayah falls between sections."""
        return [s for s in self.sections(surah_id) if s.contains(ayah_id)]

    def section_for(self, surah_id: int, ayah_id: int) -> Optional[SurahSection]:
        """The most specific section covering an ayah - the heading a reader wants beside it."""
        chain = self.sections_for(surah_id, ayah_id)
        return chain[-1] if chain else None

    def has_sections(self, surah_id: int) -> bool:
        return bool(self._data.get(str(surah_id), {}).get("sections"))

    def count(self) -> int:
        """How many surahs carry an outline."""
        return sum(1 for sid in self._data if self.has_sections(int(sid)))

    def search(self, query: str) -> list[tuple[int, SurahSection]]:
        """Sections whose title carries ``query``, across every surah, as (surah, section)."""
        trimmed = query.strip()
        needle = trimmed.lower()
        if not needle:
            return []
        out: list[tuple[int, SurahSection]] = []
        for sid in sorted(int(k) for k in self._data):
            for section in self.sections(sid):
                if needle in section.english.lower() or trimmed in section.arabic:
                    out.append((sid, section))
        return out
