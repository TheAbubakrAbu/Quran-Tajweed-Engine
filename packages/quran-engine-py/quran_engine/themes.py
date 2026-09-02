"""Browse by theme: curated topics, each listing the ayahs that speak to it. Mirrors src/themes.js."""
from __future__ import annotations
from typing import Optional


class Themes:
    def __init__(self, data: Optional[dict] = None):
        self._topics: list[dict] = (data or {}).get("topics", [])
        self._by_id = {t["id"]: t for t in self._topics}
        self._by_ayah: Optional[dict[str, list[dict]]] = None

    def all(self) -> list[dict]:
        return self._topics

    def topic(self, topic_id: str) -> Optional[dict]:
        return self._by_id.get(topic_id)

    def domains(self) -> list[str]:
        return list(dict.fromkeys(t["domain"] for t in self._topics))

    def categories(self, domain: Optional[str] = None) -> list[str]:
        scope = [t for t in self._topics if t["domain"] == domain] if domain else self._topics
        return list(dict.fromkeys(t["category"] for t in scope))

    def in_domain(self, domain: str) -> list[dict]:
        return [t for t in self._topics if t["domain"] == domain]

    def in_category(self, category: str) -> list[dict]:
        return [t for t in self._topics if t["category"] == category]

    def topics_for(self, surah_id: int, ayah_id: int) -> list[dict]:
        """The topics an ayah appears under."""
        if self._by_ayah is None:
            index: dict[str, list[dict]] = {}
            for topic in self._topics:
                for ref in topic["ayahs"]:
                    index.setdefault(ref, []).append(topic)
            self._by_ayah = index
        return self._by_ayah.get(f"{surah_id}:{ayah_id}", [])

    def search(self, query: str) -> list[dict]:
        needle = query.strip().lower()
        if not needle:
            return []
        return [t for t in self._topics
                if any(needle in t[field].lower() for field in ("name", "description", "category", "domain"))]
