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
from .mushaf import Mushaf
from .qiraat_tajweed import QiraatTajweed
from .word_by_word import WordByWord
from .similar import SimilarAyahs
from .themes import Themes
from .lessons import TajweedLessons
from .ask_ai import AskAI
from .sections import SurahSections
from .alphabet import ArabicAlphabet
from .qiraat_comparison import QiraatComparison
from .morphology import Morphology
from .mutashabihat import Mutashabihat
from .topics import QuranTopics, AyahThemes
from .metadata import QuranMetadata
from .qiraat_variants import QiraatVariants
from .word_of_day import WordOfDay
from .names_depth import NamesDepth
from .isnad import Isnad
from .miracles import Miracles

_RIWAYAT = ["warsh", "qaloon", "duri", "susi", "buzzi", "qunbul", "shubah"]
#: The eight riwayat whose text this engine publishes - the ones with line tables.
_RIWAYAT_WITH_TEXT = ["hafs"] + _RIWAYAT


def _default_data_dir() -> Path:
    # packages/quran-engine-py/quran_engine -> repo root /data
    return Path(__file__).resolve().parents[3] / "data"


class Engine:
    def __init__(self, quran: Quran, juz_page: JuzPage, reciters: Reciters,
                 search: Search, tajweed: Tajweed,
                 names_of_allah: Optional[NamesOfAllah] = None,
                 muqattaat: Optional[Muqattaat] = None,
                 mushaf: Optional[Mushaf] = None,
                 qiraat_tajweed: Optional[QiraatTajweed] = None,
                 word_by_word: Optional[WordByWord] = None,
                 similar_ayahs: Optional[SimilarAyahs] = None,
                 themes: Optional[Themes] = None,
                 tajweed_lessons: Optional[TajweedLessons] = None,
                 surah_sections: Optional[SurahSections] = None,
                 alphabet: Optional[ArabicAlphabet] = None,
                 morphology: Optional[Morphology] = None,
                 mutashabihat: Optional[Mutashabihat] = None,
                 quran_topics: Optional[QuranTopics] = None,
                 ayah_themes: Optional[AyahThemes] = None,
                 quran_metadata: Optional[QuranMetadata] = None,
                 qiraat_variants: Optional[QiraatVariants] = None,
                 word_of_day: Optional[WordOfDay] = None,
                 names_depth: Optional[NamesDepth] = None,
                 isnad: Optional[Isnad] = None,
                 miracles: Optional[Miracles] = None):
        self.quran = quran
        self.juz_page = juz_page
        self.reciters = reciters
        self.search = search
        self._tajweed = tajweed
        self.names_of_allah = names_of_allah or NamesOfAllah()
        self.muqattaat = muqattaat or Muqattaat()
        self.mushaf = mushaf or Mushaf()
        self.qiraat_tajweed = qiraat_tajweed or QiraatTajweed()
        self.word_by_word = word_by_word or WordByWord(quran=quran)
        self.similar_ayahs = similar_ayahs or SimilarAyahs()
        self.themes = themes or Themes()
        self.morphology = morphology or Morphology()
        self.mutashabihat = mutashabihat or Mutashabihat()
        self.quran_topics = quran_topics or QuranTopics()
        self.ayah_themes = ayah_themes or AyahThemes()
        self.quran_metadata = quran_metadata or QuranMetadata()
        self.qiraat_variants = qiraat_variants or QiraatVariants()
        self.word_of_day = word_of_day or WordOfDay()
        self.names_depth = names_depth or NamesDepth()
        self.isnad = isnad or Isnad()
        self.miracles = miracles or Miracles()
        self.tajweed_lessons = tajweed_lessons or TajweedLessons()
        self.surah_sections = surah_sections or SurahSections()
        self.alphabet = alphabet or ArabicAlphabet()
        self.ask_ai = AskAI(quran, search, themes=self.themes)
        #: Needs ``load_qiraat`` to say anything; with none it reports "hafs" alone.
        self.qiraat_comparison = QiraatComparison(quran)

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
             load_tajweed: bool = True,
             load_mushaf: bool = False,
             load_qiraat_tajweed: bool = False,
             load_word_by_word: bool = False,
             load_similar_ayahs: bool = False,
             load_morphology: bool = False,
             load_mutashabihat: bool = False,
             load_quran_topics: bool = False,
             load_qiraat_variants: bool = False,
             riwayah: Optional[str] = None) -> "Engine":
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

        # Themes and lessons load by default: together they are ~250 KB, and a topic list is
        # exactly the kind of thing a consumer wants without having to know it needed a flag.
        themes = Themes(read("themes.json"))
        lessons = TajweedLessons(read("tajweed-lessons.json"))

        mushaf = None
        if load_mushaf:
            index = read("mushaf/index.json")
            pages = {e["riwayah"]: read(f"mushaf/{e['pages']}") for e in index["riwayat"]}
            lines = {e["riwayah"]: read(f"mushaf/{e['lines']}")
                     for e in index["riwayat"] if e.get("lines")}
            mushaf = Mushaf(index=index, pages=pages, lines=lines)

        qiraat_tajweed = None
        if load_qiraat_tajweed:
            qiraat_tajweed = QiraatTajweed(
                rules=read("tajweed-qiraat/rules.json"),
                riwayat={r: read(f"tajweed-qiraat/{r}.json") for r in _RIWAYAT},
            )

        word_by_word = None
        if load_word_by_word:
            pack = read("word-by-word.json")
            word_by_word = WordByWord(english=pack["english"],
                                      transliteration=pack["transliteration"], quran=quran)

        similar = SimilarAyahs(read("similar-ayahs.json")) if load_similar_ayahs else None

        # Sections (80 KB) and the alphabet (18 KB) load by default, like themes and lessons: small,
        # and both answer questions a consumer should not have to opt into.
        surah_sections = SurahSections(read("surah-sections.json"))
        alphabet = ArabicAlphabet(read("arabic-alphabet.json"))

        # Metadata (8 KB), the passage themes (142 KB) and the word list (128 KB) join them on
        # the same reasoning: small, and each answers a question a consumer should not have to
        # opt into.
        quran_metadata = QuranMetadata(read("quran-metadata.json"))
        ayah_themes = AyahThemes(read("ayah-themes.json"))
        word_of_day = WordOfDay(read("word-of-day.json"))
        names_depth = NamesDepth(read("names-depth.json"))
        isnad = Isnad(read("isnad.json"))
        # The miracles corpus (393 KB) joins them: bigger than those, but smaller than the tajweed
        # course that has always loaded by default, and a consumer cross-linking an ayah to what
        # has been written about it should not have to know a flag existed.
        miracles = Miracles(read("miracles.json"))

        morphology = Morphology(read("morphology.json")) if load_morphology else None
        mutashabihat = Mutashabihat(read("mutashabihat.json")) if load_mutashabihat else None
        quran_topics = QuranTopics(read("quran-topics.json")) if load_quran_topics else None
        qiraat_variants = None
        if load_qiraat_variants:
            qiraat_variants = QiraatVariants(
                variants=read("qiraat-variants.json"),
                places=read("qiraat-places.json"),
                audio=read("qiraat-variant-audio.json"),
            )

        return Engine(
            quran=quran,
            juz_page=JuzPage(quran, juz_list),
            reciters=Reciters(reciters),
            search=Search(quran, riwayah=riwayah),
            tajweed=Tajweed(ann, colors),
            names_of_allah=names,
            muqattaat=muqattaat,
            mushaf=mushaf,
            qiraat_tajweed=qiraat_tajweed,
            word_by_word=word_by_word,
            similar_ayahs=similar,
            themes=themes,
            tajweed_lessons=lessons,
            surah_sections=surah_sections,
            alphabet=alphabet,
            morphology=morphology,
            mutashabihat=mutashabihat,
            quran_topics=quran_topics,
            ayah_themes=ayah_themes,
            quran_metadata=quran_metadata,
            qiraat_variants=qiraat_variants,
            word_of_day=word_of_day,
            names_depth=names_depth,
            isnad=isnad,
            miracles=miracles,
        )
