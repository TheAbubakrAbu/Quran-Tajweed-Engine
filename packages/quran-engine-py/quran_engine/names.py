"""The 99 Names of Allah (Asma' ul-Husna). Thin accessor over data/names-of-allah.json.
Mirrors src/names.js."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class NameOfAllah:
    name: str               # Arabic
    transliteration: str
    number: int             # 1..99
    found: str = ""         # ayah references where it appears (e.g. "(1:3) (17:110)")
    meaning: str = ""
    desc: str = ""
    other_names: list[str] = field(default_factory=list)

    @staticmethod
    def from_json(d: dict) -> "NameOfAllah":
        return NameOfAllah(
            name=d.get("name", ""),
            transliteration=d.get("transliteration", ""),
            number=d["number"],
            found=d.get("found", ""),
            meaning=d.get("meaning", ""),
            desc=d.get("desc", ""),
            other_names=d.get("otherNames", []),
        )


class NamesOfAllah:
    def __init__(self, names: Optional[list[NameOfAllah]] = None):
        self.list = sorted(names or [], key=lambda n: n.number)
        self._by_number = {n.number: n for n in self.list}

    def all(self) -> list[NameOfAllah]:
        """All 99 names, ordered by number."""
        return self.list

    def by_number(self, number: int) -> Optional[NameOfAllah]:
        return self._by_number.get(number)
