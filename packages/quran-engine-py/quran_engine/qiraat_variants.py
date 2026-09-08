"""Who among the Ten reads a word differently, and what it means. Mirrors src/qiraatVariants.js.

`data/qiraat/` gives each reading its own words, and `qiraat_comparison` will align two of them:
that answers WHAT each riwayah reads. It cannot say that a form is Hamzah's rather than Nafi's,
that it is a passive where Hafs has an active, or that al-Mahdawi held the two to mean the same
thing. That is this module, from the Quran.com qiraat matrix.

Readers against transmitters: a reading lists `readers` when both of an imam's transmitters
follow it, and `transmitters` when the two part company. Segment ranges are 0-based inclusive
token indices of the raw Hafs text, None where the builder could not place the word.

Only the eight riwayat whose text this engine publishes appear in `places`. The other twelve do
appear as attributions, which is right: attributing a reading to Ibn Dhakwan says nothing about
the state of his extracted text.
"""
from __future__ import annotations
from typing import Optional


class Juncture(dict):
    """id, word, category, segments, readings, note."""


class QiraatVariants:
    def __init__(self, variants: Optional[dict] = None, places: Optional[dict] = None,
                 audio: Optional[dict] = None):
        variants = variants or {}
        self._readers: dict = variants.get("readers", {})
        self._transmitters: dict = variants.get("transmitters", {})
        self._ayahs: dict = variants.get("ayahs", {})
        self._places: dict = (places or {}).get("riwayat", {})
        self._audio_sources: list = (audio or {}).get("sources", [])
        self._audio: dict = (audio or {}).get("riwayat", {})

    @property
    def is_loaded(self) -> bool:
        return bool(self._ayahs)

    def junctures(self, surah_id: int, ayah_id: int) -> list[Juncture]:
        rows = self._ayahs.get(f"{surah_id}:{ayah_id}", [])
        return [Juncture({"id": i, "word": row.get("word", ""),
                          "category": row.get("category", ""),
                          "segments": row.get("segments", []),
                          "readings": row.get("readings", []),
                          "note": row.get("note", "")})
                for i, row in enumerate(rows)]

    def has(self, surah_id: int, ayah_id: int) -> bool:
        """Only 1,409 of the 6,236 ayahs carry a variant at all."""
        return bool(self._ayahs.get(f"{surah_id}:{ayah_id}"))

    def reader(self, reader_id: int) -> Optional[dict]:
        return self._readers.get(str(reader_id))

    def transmitter(self, transmitter_id: int) -> Optional[dict]:
        return self._transmitters.get(str(transmitter_id))

    def transmitters_following(self, reading: dict) -> list[dict]:
        """An imam's own pair, plus any transmitters listed individually."""
        out: list[dict] = []
        seen: set[int] = set()
        for reader_id in reading.get("readers", []):
            for t in self._transmitters.values():
                if t["reader"] == reader_id and t["id"] not in seen:
                    seen.add(t["id"])
                    out.append(t)
        for tid in reading.get("transmitters", []):
            t = self.transmitter(tid)
            if t and t["id"] not in seen:
                seen.add(t["id"])
                out.append(t)
        return out

    def reading_for(self, juncture: dict, riwayah: str) -> Optional[dict]:
        """The reading a riwayah follows at a juncture, by engine slug."""
        for reading in juncture.get("readings", []):
            if any(t.get("riwayah") == riwayah for t in self.transmitters_following(reading)):
                return reading
        return None

    def attribution(self, reading: dict) -> str:
        """Imams first in canonical order, then lone transmitters with their imam named."""
        readers = sorted((r for r in (self.reader(i) for i in reading.get("readers", [])) if r),
                         key=lambda r: r["position"])
        transmitters = sorted(
            (t for t in (self.transmitter(i) for i in reading.get("transmitters", [])) if t),
            key=lambda t: ((self.reader(t["reader"]) or {}).get("position", 99), t["id"]))
        parts = []
        if readers:
            parts.append(", ".join(r["abbreviation"] for r in readers))
        if transmitters:
            rendered = []
            for t in transmitters:
                imam = (self.reader(t["reader"]) or {}).get("abbreviation", "")
                rendered.append(f"{t['name']} ({imam})" if imam else t["name"])
            parts.append(", ".join(rendered))
        return " · ".join(parts)

    def places(self, riwayah: str, surah_id: int) -> list[dict]:
        """Where a riwayah differs from Hafs in a surah.

        Two kinds, found two ways: `word` indices are words dropped, added or spelled
        differently, which a text diff finds; `letter` indices are words the printed mushaf marks
        as read with other vowels over the SAME skeleton, which no text diff can see.
        """
        table = self._places.get(riwayah, {}).get(str(surah_id), {})
        return [{"ayah": ayah,
                 "word": table[str(ayah)].get("word", []),
                 "letter": table[str(ayah)].get("letter", [])}
                for ayah in sorted(int(k) for k in table)]

    def riwayat_with_places(self) -> list[str]:
        return sorted(self._places)

    def audio(self, riwayah: str, surah_id: int, ayah_id: int) -> Optional[dict]:
        """One reciter reading the verse both ways, for the four riwayat where one exists.

        The rest carry none: no reciter published both sides with timings. That is a fact about
        the world, and the honest rendering of it is "no recording", not a dead button.
        """
        rows = self._audio.get(riwayah, {}).get(str(surah_id), [])
        row = next((r for r in rows if r[0] == ayah_id), None)
        if not row:
            return None
        source = self._audio_sources[row[1]] if row[1] < len(self._audio_sources) else None
        if not source:
            return None
        is_span = source.get("kind") == "span"
        name = f"{surah_id:03d}.mp3" if is_span else f"{surah_id:03d}{ayah_id:03d}.mp3"
        return {
            "reciter": source["reciter"],
            "hafs": {"url": f"{source['hafsBase']}/{name}",
                     "start_ms": row[2] if is_span else None,
                     "end_ms": row[3] if is_span else None},
            "riwayah": {"url": f"{source['riwayahBase']}/{name}",
                        "start_ms": row[4] if is_span else None,
                        "end_ms": row[5] if is_span else None},
        }

    def riwayat_with_audio(self) -> list[str]:
        return sorted(self._audio)

    def count(self) -> dict:
        junctures = sum(len(rows) for rows in self._ayahs.values())
        readings = sum(len(row.get("readings", []))
                       for rows in self._ayahs.values() for row in rows)
        return {"ayahs": len(self._ayahs), "junctures": junctures, "readings": readings}
