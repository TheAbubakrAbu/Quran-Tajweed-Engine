"""QUL's topic indexes and the passage themes. Mirrors src/topics.js.

`QuranTopics` is 2,512 topics indexed THREE independent ways: the Clear Quran thematic tree, the
Quranic Arabic Corpus ontology, and a general A-Z index. Three trees over one pool of topics, not
three partitions of it: a topic can be a node in more than one (17 are), and a tree's parent need
not itself be listed in that tree. So every hierarchy accessor takes the tree you mean.

`AyahThemes` is 1,049 passages, one sentence per run of ayahs. They run in order and do not nest,
but they do not tile a surah either: an ayah between two passages has none.
"""
from __future__ import annotations
from typing import Optional

TOPIC_TREES = ("thematic", "ontology", "index")


class QulTopic(dict):
    """id, name, arabic, families, parents, description, wiki, ayahs, related."""


class Passage(dict):
    """surah, from_, to, theme, topic."""


class QuranTopics:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._topics: list[QulTopic] = [QulTopic(t) for t in data.get("topics", [])]
        self._by_id = {t["id"]: t for t in self._topics}
        self._children: dict[str, dict[int, list[int]]] = {}
        self._by_ayah: Optional[dict[str, list[int]]] = None

    @property
    def is_loaded(self) -> bool:
        return bool(self._topics)

    def all(self) -> list[QulTopic]:
        return self._topics

    def topic(self, topic_id: int) -> Optional[QulTopic]:
        return self._by_id.get(topic_id)

    def in_family(self, tree: str) -> list[QulTopic]:
        """The topics an index lists."""
        return [t for t in self._topics if tree in t["families"]]

    def roots(self, tree: str) -> list[QulTopic]:
        """Topics an index lists that have no parent in that same tree."""
        return [t for t in self._topics if tree in t["families"] and not t["parents"].get(tree)]

    def parent(self, topic_id: int, tree: Optional[str] = None) -> Optional[QulTopic]:
        topic = self.topic(topic_id)
        if not topic:
            return None
        which = tree or (topic["families"][0] if topic["families"] else None)
        if not which:
            return None
        parent_id = topic["parents"].get(which)
        return self.topic(parent_id) if parent_id else None

    def children(self, topic_id: int, tree: Optional[str] = None) -> list[QulTopic]:
        topic = self.topic(topic_id)
        which = tree or (topic["families"][0] if topic and topic["families"] else None)
        if not which:
            return []
        return [self._by_id[c] for c in self._child_index(which).get(topic_id, [])]

    def ancestors(self, topic_id: int, tree: Optional[str] = None) -> list[QulTopic]:
        """The chain up to the root of one tree, nearest first; cycle-safe."""
        topic = self.topic(topic_id)
        which = tree or (topic["families"][0] if topic and topic["families"] else None)
        if not which:
            return []
        out: list[QulTopic] = []
        seen = {topic_id}
        current = self.parent(topic_id, which)
        while current and current["id"] not in seen:
            seen.add(current["id"])
            out.append(current)
            current = self.parent(current["id"], which)
        return out

    def topics_for(self, surah_id: int, ayah_id: int) -> list[QulTopic]:
        """Every topic annotating this ayah, across all three indexes."""
        self._index_ayahs()
        return [self._by_id[i] for i in (self._by_ayah or {}).get(f"{surah_id}:{ayah_id}", [])]

    def search(self, query: str, limit: int = 50) -> list[QulTopic]:
        q = (query or "").strip().lower()
        if not q:
            return []
        starts: list[QulTopic] = []
        contains: list[QulTopic] = []
        for topic in self._topics:
            name = topic["name"].lower()
            if name.startswith(q):
                starts.append(topic)
            elif q in name or query in topic["arabic"]:
                contains.append(topic)
            if len(starts) >= limit:
                break
        return (starts + contains)[:limit]

    def count(self) -> dict:
        by_family = {t: 0 for t in TOPIC_TREES}
        refs = 0
        for topic in self._topics:
            for family in topic["families"]:
                by_family[family] += 1
            refs += len(topic["ayahs"])
        return {"topics": len(self._topics), **by_family, "references": refs}

    # -- internals ---------------------------------------------------------------------

    def _child_index(self, tree: str) -> dict[int, list[int]]:
        cached = self._children.get(tree)
        if cached is not None:
            return cached
        table: dict[int, list[int]] = {}
        for topic in self._topics:
            parent_id = topic["parents"].get(tree)
            if parent_id:
                table.setdefault(parent_id, []).append(topic["id"])
        for bucket in table.values():
            bucket.sort()
        self._children[tree] = table
        return table

    def _index_ayahs(self) -> None:
        if self._by_ayah is not None:
            return
        table: dict[str, list[int]] = {}
        for topic in self._topics:
            for key in topic["ayahs"]:
                table.setdefault(key, []).append(topic["id"])
        self._by_ayah = table


class AyahThemes:
    def __init__(self, data: Optional[dict] = None):
        self._data = data or {}

    @property
    def is_loaded(self) -> bool:
        return bool(self._data)

    def passages(self, surah_id: int) -> list[Passage]:
        return [Passage({"surah": surah_id, "from_": row["from"], "to": row["to"],
                         "theme": row["theme"], "topic": row.get("topic", "")})
                for row in self._data.get(str(surah_id), [])]

    def passage_for(self, surah_id: int, ayah_id: int) -> Optional[Passage]:
        """Passages do not overlap, so this is the one answer."""
        for passage in self.passages(surah_id):
            if passage["from_"] <= ayah_id <= passage["to"]:
                return passage
        return None

    def search(self, query: str, limit: int = 50) -> list[Passage]:
        q = (query or "").strip().lower()
        if not q:
            return []
        out: list[Passage] = []
        for surah in sorted(int(k) for k in self._data):
            for passage in self.passages(surah):
                if q in passage["theme"].lower() or q in passage["topic"].lower():
                    out.append(passage)
                    if len(out) >= limit:
                        return out
        return out

    def count(self) -> dict:
        return {"surahs": len(self._data),
                "passages": sum(len(rows) for rows in self._data.values())}
