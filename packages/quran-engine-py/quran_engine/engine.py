"""The Engine facade + disk loader. Mirrors createEngine / loadFromDisk in src/index.js + src/node.js."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Optional

from .models import Surah, JuzEntry, Reciter, TajweedSpan
from .quran import Quran
from .juz_page import JuzPage
from .audio import Reciters
from .search import Search
from .tajweed import Tajweed
from .names import NamesOfAllah, NameOfAllah
from .muqattaat import Muqattaat

_RIWAYAT = ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"]


def _default_data_dir() -> Path:
    # packages/quran-engine-py/quran_engine -> repo root /data
    return Path(__file__).resolve().parents[3] / "data"


class Engine:
    def __init__(self, quran: Quran, juz_page: JuzPage, reciters: Reciters,
                 search: Search, tajweed: Tajweed,
                 names_of_allah: Optional[NamesOfAllah] = None,
                 muqattaat: Optional[Muqattaat] = None):
        self.quran = quran
        self.juz_page = juz_page
        self.reciters = reciters
        self.search = search
        self._tajweed = tajweed
        self.names_of_allah = names_of_allah or NamesOfAllah()
        self.muqattaat = muqattaat or Muqattaat()

    def tajweed(self, surah_id: int, ayah_id: int) -> list[TajweedSpan]:
        a = self.quran.ayah(surah_id, ayah_id)
        if a is None:
            return []
        return self._tajweed.spans(surah_id, ayah_id, a.text_arabic)

    @staticmethod
    def load(data_dir: Optional[str | Path] = None, *,
             load_qiraat: bool = False, load_surah_info: bool = True,
             load_names_of_allah: bool = True,
             load_muqattaat: bool = True,
             load_tajweed: bool = True, riwayah: Optional[str] = None) -> "Engine":
        d = Path(data_dir) if data_dir else _default_data_dir()

        def read(rel: str):
            return json.loads((d / rel).read_text(encoding="utf-8"))

        surahs = [Surah.from_json(s) for s in read("quran.json")]
        juz_list = [JuzEntry.from_json(j) for j in read("juz.json")]
        reciters = [Reciter.from_json(r) for r in read("reciters.json")]
        rules = read("tajweed-rules.json")
        colors = {c["id"]: c["colorHex"] for c in rules["categories"]}

        qiraat = None
        if load_qiraat:
            qiraat = {r: read(f"qiraat/qiraah-{r}.json") for r in _RIWAYAT}
        surah_info = read("surah-info.json") if load_surah_info else None
        qiraat_counts = read("qiraat-counts.json")

        names = None
        if load_names_of_allah:
            names = NamesOfAllah([NameOfAllah.from_json(n) for n in read("names-of-allah.json")])

        muqattaat = None
        if load_muqattaat:
            muqattaat = Muqattaat(read("muqattaat.json"))

        quran = Quran(surahs, qiraat=qiraat, surah_info=surah_info, qiraat_counts=qiraat_counts)

        ann: dict[tuple[int, int], list[dict]] = {}
        if load_tajweed:
            for entry in read("tajweed-annotations.json"):
                ann[(entry["surah"], entry["ayah"])] = entry["annotations"]

        return Engine(
            quran=quran,
            juz_page=JuzPage(quran, juz_list),
            reciters=Reciters(reciters),
            search=Search(quran, riwayah=riwayah),
            tajweed=Tajweed(ann, colors),
            names_of_allah=names,
            muqattaat=muqattaat,
        )
