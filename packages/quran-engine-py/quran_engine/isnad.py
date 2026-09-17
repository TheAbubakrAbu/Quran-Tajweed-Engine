"""The chains of transmission (isnad) of the Ten Readings. Mirrors src/isnad.js.

From the Prophet \ufdfa down through the Companions who learned from him, the
Successors who taught each imam, the imam himself, the links between him and each of his two
narrators, and the students who carried each narration on.

The links are the standard ones of the classical record: Ibn al-Jazari's al-Nashr and Ghayat
al-Nihayah, al-Dani's al-Taysir, and the turuq of al-Shatibiyyah and al-Durrah. Where a
narrator's students are not listed with confidence, the layer is simply absent.

A chain is returned as LAYERS, one per generation, top (the Prophet) to bottom, which is how a
consumer draws it: a row per layer, connected downward.
"""
from __future__ import annotations
from typing import Optional


class IsnadNode(dict):
    """name, arabic, detail, role."""


class IsnadLayer(dict):
    """title, nodes."""


class Isnad:
    def __init__(self, data: Optional[dict] = None):
        data = data or {}
        self._prophet = IsnadNode(data["prophet"]) if data.get("prophet") else None
        self._companions = [IsnadNode(c) for c in data.get("companions", [])]
        self._imams = data.get("imams", {})
        self._narrators = data.get("narrators", {})

    @property
    def is_loaded(self) -> bool:
        return bool(self._imams)

    def prophet(self) -> Optional[IsnadNode]:
        return self._prophet

    def companions(self) -> list[IsnadNode]:
        """The thirteen Companions the readings are transmitted from."""
        return self._companions

    def imam_keys(self) -> list[str]:
        return list(self._imams)

    def narrator_keys(self) -> list[str]:
        return list(self._narrators)

    def imam(self, imam: str) -> Optional[dict]:
        return self._imams.get(imam)

    def narrator(self, riwayah: str) -> Optional[dict]:
        return self._narrators.get(riwayah)

    def reads_directly(self, riwayah: str) -> bool:
        """Whether a narrator read on his imam himself, with nobody between them."""
        chain = self._narrators.get(riwayah)
        return bool(chain) and not chain["links"]

    def imam_of(self, riwayah: str) -> Optional[str]:
        """The imam a riwayah comes from.

        Read from the corpus, NOT parsed off the tag: four tags name the imam in the Arabic
        genitive ("ad-Duri an Abi Amr") while his key is the nominative ("Abu Amr"), so splitting
        on " an " would resolve those four to nothing.
        """
        chain = self._narrators.get(riwayah)
        imam = chain.get("imam") if chain else None
        return imam if imam in self._imams else None

    def top_layers(self, imam: str) -> list[IsnadLayer]:
        """The Prophet, the Companions his teachers read on, and those teachers."""
        chain = self._imams.get(imam)
        if not chain:
            return []
        layers: list[IsnadLayer] = []
        if self._prophet:
            layers.append(IsnadLayer(title="THE PROPHET", nodes=[self._prophet]))
        if chain["companions"]:
            layers.append(IsnadLayer(title="THE COMPANIONS", nodes=[IsnadNode(c) for c in chain["companions"]]))
        if chain["teachers"]:
            title = "HIS TEACHER" if len(chain["teachers"]) == 1 else "HIS TEACHERS"
            layers.append(IsnadLayer(title=title, nodes=[IsnadNode(t) for t in chain["teachers"]]))
        return layers

    def chain(self, key: str) -> list[IsnadLayer]:
        """A whole chain as layers: a riwayah tag for one narration, an imam key for a reading."""
        k = (key or "").strip()
        if k in self._imams:
            return self._chain_of_imam(k)
        if k in self._narrators:
            return self._chain_of_narrator(k)
        return []

    def _chain_of_imam(self, imam: str) -> list[IsnadLayer]:
        layers = self.top_layers(imam)
        if not layers:
            return []
        layers.append(IsnadLayer(title="THE IMAM",
                                 nodes=[IsnadNode(name=imam, arabic="", detail="", role="imam")]))
        narrators = [
            IsnadNode(name=tag[:tag.find(" an ")], arabic="", detail="", role="narrator")
            for tag in self._narrators if self.imam_of(tag) == imam
        ]
        if narrators:
            layers.append(IsnadLayer(title="HIS TWO NARRATORS", nodes=narrators))
        return layers

    def _chain_of_narrator(self, riwayah: str) -> list[IsnadLayer]:
        imam = self.imam_of(riwayah)
        if not imam:
            return []
        layers = self.top_layers(imam)
        if not layers:
            return []
        layers.append(IsnadLayer(title="THE IMAM",
                                 nodes=[IsnadNode(name=imam, arabic="", detail="", role="imam")]))
        chain = self._narrators[riwayah]
        if chain["links"]:
            title = "THE LINK BETWEEN" if len(chain["links"]) == 1 else "THE LINKS BETWEEN"
            layers.append(IsnadLayer(title=title, nodes=[IsnadNode(n) for n in chain["links"]]))
        layers.append(IsnadLayer(
            title="THE NARRATOR",
            nodes=[IsnadNode(name=riwayah[:riwayah.find(" an ")], arabic="", detail="", role="narrator")]))
        if chain["students"]:
            layers.append(IsnadLayer(title="HIS STUDENTS", nodes=[IsnadNode(n) for n in chain["students"]]))
        return layers

    def sentence(self, riwayah: str) -> str:
        """One sentence on how a narrator reaches his imam: directly, or through the links between."""
        imam = self.imam_of(riwayah)
        chain = self._narrators.get(riwayah)
        if not imam or not chain:
            return ""
        narrator = riwayah[:riwayah.find(" an ")]
        if not chain["links"]:
            return (f"{narrator} read on {imam} himself, and {imam}'s chain runs through his "
                    "teachers to the Companions and to the Prophet ﷺ.")
        names = [n["name"] for n in chain["links"]]
        path = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and then " + names[-1]
        return (f"{narrator} did not meet {imam}: the reading reached him through {path}, and from "
                f"{imam} it runs through his teachers to the Companions and to the Prophet ﷺ.")

    def count(self) -> dict:
        return {"imams": len(self._imams), "narrators": len(self._narrators),
                "companions": len(self._companions)}
