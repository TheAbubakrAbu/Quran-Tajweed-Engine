"""The printed mushaf: twenty riwayat as page-exact facsimiles, and each one's own page table.

Mirrors src/mushaf.js. See docs/10-mushaf.md for the format and the reasoning; the short version
is that a riwayah is NOT paginated like Hafs, and twelve of the twenty ship their facsimile and
page table but no text (theirs is machine-extracted and not yet proofread).
"""
from __future__ import annotations
from typing import Optional


class Mushaf:
    def __init__(self, index: Optional[dict] = None,
                 pages: Optional[dict] = None,
                 lines: Optional[dict] = None):
        index = index or {}
        self._riwayat: list[dict] = index.get("riwayat", [])
        self._total_pages: int = index.get("totalPages", 604)
        self._by_riwayah = {r["riwayah"]: r for r in self._riwayat}
        self._pages = pages or {}
        self._lines = lines or {}
        self._on_page: dict[str, dict[int, list[tuple[int, int]]]] = {}

    def riwayat(self) -> list[dict]:
        """Every riwayah, in the classical order of the Ten Qiraat."""
        return self._riwayat

    def riwayat_with_text(self) -> list[dict]:
        """Only the riwayat whose text this engine publishes (the eight verified ones)."""
        return [r for r in self._riwayat if r.get("textIncluded")]

    def riwayah(self, slug: str) -> Optional[dict]:
        return self._by_riwayah.get(slug)

    def total_pages(self) -> int:
        return self._total_pages

    def pdf_path(self, slug: str) -> Optional[str]:
        """Path to the facsimile, relative to data/mushaf/. It is one solid xz stream over the PDF."""
        entry = self._by_riwayah.get(slug)
        return entry.get("pdf") if entry else None

    def page(self, surah_id: int, ayah_id: int, riwayah: str = "hafs") -> Optional[int]:
        """The page an ayah is printed on in THIS riwayah's mushaf, which is not Hafs' page."""
        table = (self._pages.get(riwayah) or {}).get("pages") or {}
        value = (table.get(str(surah_id)) or {}).get(str(ayah_id))
        return value if isinstance(value, int) else None

    def ayahs_on_page(self, page: int, riwayah: str = "hafs") -> list[tuple[int, int]]:
        """Every (surah, ayah) printed on a page, in mushaf order."""
        return self._page_index(riwayah).get(page, [])

    def first_ayah_of_page(self, page: int, riwayah: str = "hafs") -> Optional[tuple[int, int]]:
        on_page = self.ayahs_on_page(page, riwayah)
        return on_page[0] if on_page else None

    def line_breaks(self, surah_id: int, ayah_id: int, riwayah: str = "hafs") -> Optional[list[int]]:
        """Character offsets into the ayah where the printed mushaf starts a new line.

        None when the riwayah's text - and so its line table - is not published.
        """
        table = (self._lines.get(riwayah) or {}).get("lineBreaks") or {}
        value = (table.get(str(surah_id)) or {}).get(str(ayah_id))
        return value if isinstance(value, list) else None

    def has_tajweed_pack(self, riwayah: str) -> bool:
        entry = self._by_riwayah.get(riwayah)
        return bool(entry and entry.get("tajweed"))

    def _page_index(self, riwayah: str) -> dict[int, list[tuple[int, int]]]:
        cached = self._on_page.get(riwayah)
        if cached is not None:
            return cached
        index: dict[int, list[tuple[int, int]]] = {}
        table = (self._pages.get(riwayah) or {}).get("pages") or {}
        for surah in sorted(table, key=int):
            for ayah in sorted(table[surah], key=int):
                index.setdefault(table[surah][ayah], []).append((int(surah), int(ayah)))
        self._on_page[riwayah] = index
        return index
