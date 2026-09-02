#!/usr/bin/env python3
"""Extract the engine's newer corpora out of a sibling Al-Islam-iOS checkout.

The app ships these as compressed payloads sized for a phone bundle (raw deflate, xz,
and the block-compressed .qpk containers). This engine ships plain JSON, because a
Kotlin or Rust consumer should not have to reimplement Apple's Compression framework
to read a page table. So this script decompresses, reshapes, and writes:

    data/qiraat/qiraah-<slug>.json     the 7 verified non-Hafs riwayat, refreshed
    data/mushaf/index.json             all 20 riwayat: names, PDF, what ships for each
    data/mushaf/pdfs/*.pdf.xz          the 20 printed-mushaf facsimiles (604 pages each)
    data/mushaf/pages/<slug>.json      ayah -> page in THAT riwayah's own print (20)
    data/mushaf/lines/<slug>.json      mushaf line breaks, for the 8 whose text ships
    data/tajweed-qiraat/rules.json     the riwayah rule catalogue (key -> descriptions)
    data/tajweed-qiraat/<slug>.json    per-riwayah legend + word rules (the 7 verified)
    data/word-by-word.json             per-word English gloss + Latin transliteration
    data/similar-ayahs.json            the similar-ayah corpus
    data/themes.json                   thematic topics
    data/surah-sections.json           per-surah section outlines
    data/tajweed-lessons.json          the tajweed course
    data/surah-stats.json              per-surah ayah/word/letter counts

WHAT IS DELIBERATELY NOT IMPORTED
---------------------------------
The TEXT of the 12 beta riwayat (Ibn Amir's, Hamzah's, al-Kisai's, Abu Jafar's,
Yaqub's and Khalaf al-Ashir's transmissions). It is machine-extracted from printed
mushafs and not yet proofread word by word, so it is not fit to publish as engine
data - and their tajweed packs and line tables index INTO that text, so those stay
out with it. Their printed mushafs do ship: a facsimile is exact whatever the state
of the extraction, and `data/mushaf/pages/` makes all twenty navigable by ayah.

    python3 scripts/import-al-islam-data.py [path/to/Al-Islam-iOS]

Defaults to ../Al-Islam-iOS. Idempotent: run it again after the app updates a corpus.
"""

from __future__ import annotations

import json
import lzma
import pathlib
import re
import shutil
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

# slug, app tag, English label, Arabic label, imam (en/ar), death year AH, PDF base name,
# whether the app's own text is verified (and so ships here).
RIWAYAT = [
    ("hafs",         "",                          "Hafs an Asim",             "حَفص عَن عَاصِم",             "Asim",            "عَاصِم",             180, "01-asim-hafs",               True),
    ("shubah",       "Shubah an Asim",            "Shubah an Asim",           "شُعبَة عَن عَاصِم",            "Asim",            "عَاصِم",             193, "01-asim-shubah",             True),
    ("warsh",        "Warsh an Nafi",             "Warsh an Nafi",            "وَرش عَن نَافِع",              "Nafi",            "نَافِع",             197, "02-nafi-warsh",              True),
    ("qaloon",       "Qalun an Nafi",             "Qalun an Nafi",            "قَالُون عَن نَافِع",            "Nafi",            "نَافِع",             220, "02-nafi-qalun",              True),
    ("buzzi",        "al-Bazzi an Ibn Kathir",    "al-Bazzi an Ibn Kathir",   "البَزِّي عَن ابنِ كَثِير",        "Ibn Kathir",      "ابنِ كَثِير",         250, "03-ibn-kathir-al-bazzi",     True),
    ("qunbul",       "Qunbul an Ibn Kathir",      "Qunbul an Ibn Kathir",     "قُنبُل عَن ابنِ كَثِير",         "Ibn Kathir",      "ابنِ كَثِير",         291, "03-ibn-kathir-qunbul",       True),
    ("duri",         "ad-Duri an Abi Amr",        "ad-Duri an Abi Amr",       "الدُّورِي عَن أَبِي عَمرٍو",      "Abu Amr",         "أَبُو عَمرٍو",         246, "04-abu-amr-ad-duri",         True),
    ("susi",         "as-Susi an Abi Amr",        "as-Susi an Abi Amr",       "السُّوسِي عَن أَبِي عَمرٍو",      "Abu Amr",         "أَبُو عَمرٍو",         261, "04-abu-amr-as-susi",         True),
    ("hisham",       "Hisham an Ibn Amir",        "Hisham an Ibn Amir",       "هِشَام عَن ابنِ عَامِر",         "Ibn Amir",        "ابنُ عَامِر",         245, "05-ibn-amir-hisham",         False),
    ("ibn-dhakwan",  "Ibn Dhakwan an Ibn Amir",   "Ibn Dhakwan an Ibn Amir",  "ابنُ ذَكوَان عَن ابنِ عَامِر",    "Ibn Amir",        "ابنُ عَامِر",         242, "05-ibn-amir-ibn-dhakwan",    False),
    ("khalaf",       "Khalaf an Hamzah",          "Khalaf an Hamzah",         "خَلَف عَن حَمزَة",              "Hamzah",          "حَمزَة",             229, "06-hamzah-khalaf",           False),
    ("khallad",      "Khallad an Hamzah",         "Khallad an Hamzah",        "خَلَّاد عَن حَمزَة",             "Hamzah",          "حَمزَة",             220, "06-hamzah-khallad",          False),
    ("abu-harith",   "Abu al-Harith an al-Kisai", "Abu al-Harith an al-Kisai","أَبُو الحَارِث عَنِ الكِسَائِي",   "al-Kisai",        "الكِسَائِي",          240, "07-al-kisai-abu-al-harith",  False),
    ("duri-kisai",   "ad-Duri an al-Kisai",       "ad-Duri an al-Kisai",      "الدُّورِي عَنِ الكِسَائِي",       "al-Kisai",        "الكِسَائِي",          246, "07-al-kisai-ad-duri",        False),
    ("ibn-wardan",   "Ibn Wardan an Abi Jafar",   "Ibn Wardan an Abi Jafar",  "ابنُ وَردَان عَن أَبِي جَعفَر",    "Abu Jafar",       "أَبُو جَعفَر",         160, "08-abu-jafar-ibn-wardan",    False),
    ("ibn-jammaz",   "Ibn Jammaz an Abi Jafar",   "Ibn Jammaz an Abi Jafar",  "ابنُ جَمَّاز عَن أَبِي جَعفَر",    "Abu Jafar",       "أَبُو جَعفَر",         170, "08-abu-jafar-ibn-jammaz",    False),
    ("ruways",       "Ruways an Yaqub",           "Ruways an Yaqub",          "رُوَيس عَن يَعقُوب",             "Yaqub",           "يَعقُوب",            238, "09-yaqub-ruways",            False),
    ("rawh",         "Rawh an Yaqub",             "Rawh an Yaqub",            "رَوح عَن يَعقُوب",              "Yaqub",           "يَعقُوب",            234, "09-yaqub-rawh",              False),
    ("ishaq",        "Ishaq an Khalaf al-Ashir",  "Ishaq an Khalaf al-Ashir", "إِسحَاق عَن خَلَفٍ العَاشِر",     "Khalaf al-Ashir", "خَلَفٌ العَاشِر",      286, "10-khalaf-al-ashir-ishaq",   False),
    ("idris",        "Idris an Khalaf al-Ashir",  "Idris an Khalaf al-Ashir", "إِدرِيس عَن خَلَفٍ العَاشِر",     "Khalaf al-Ashir", "خَلَفٌ العَاشِر",      292, "10-khalaf-al-ashir-idris",   False),
]

# slug -> the app's file infix for Tajweed<Name>.json.deflate / Lines<Name>.json.deflate.
PACK_NAME = {
    "hafs": "Hafs", "shubah": "Shubah", "warsh": "Warsh", "qaloon": "Qaloon",
    "buzzi": "Bazzi", "qunbul": "Qunbul", "duri": "Duri", "susi": "Susi",
    "hisham": "Hisham", "ibn-dhakwan": "IbnDhakwan", "khalaf": "Khalaf", "khallad": "Khallad",
    "abu-harith": "AbuHarith", "duri-kisai": "DuriKisai", "ibn-wardan": "IbnWardan",
    "ibn-jammaz": "IbnJammaz", "ruways": "Ruways", "rawh": "Rawh", "ishaq": "Ishaq", "idris": "Idris",
}

# slug -> the app's legacy overlay JSON, for the 7 non-Hafs riwayat whose text ships.
QIRAAT_JSON = {
    "warsh": "QiraahWarsh", "qaloon": "QiraahQaloon", "duri": "QiraahDuri", "susi": "QiraahSusi",
    "buzzi": "QiraahBuzzi", "qunbul": "QiraahQunbul", "shubah": "QiraahShubah",
}

TOTAL_PAGES = 604


def inflate(path: pathlib.Path) -> dict:
    """Raw deflate (no zlib header) - what the app's Compression-framework readers write."""
    return json.loads(zlib.decompress(path.read_bytes(), -15))


def unxz(path: pathlib.Path) -> dict:
    return json.loads(lzma.decompress(path.read_bytes()))


def write_json(path: pathlib.Path, payload, indent=None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=indent,
                      separators=(",", ":") if indent is None else None)
    # An indented file matches what json.dumps(indent=2) produced before, newline-terminated.
    written = path.write_text(text + "\n", encoding="utf-8")
    print(f"  {path.relative_to(ROOT)}  {written:,} bytes")


def rule_descriptions(app: pathlib.Path) -> dict:
    """The riwayah rule catalogue, lifted from the app's own dictionaries so the two never drift.

    `QiraahTajweed.swift` holds `shortDescriptions` and `longDescriptions` as Swift literals of
    the form `"key": "sentence",`. Parsing them beats retyping them: a rule the app renames or
    re-explains reaches the engine on the next import.
    """
    source = (app / "iPhone" / "Quran" / "QiraahTajweed.swift").read_text(encoding="utf-8")
    out: dict[str, dict[str, str]] = {}
    for field, block_name in (("short", "shortDescriptions"), ("long", "longDescriptions")):
        match = re.search(
            r"static let %s: \[String: String\] = \[(.*?)\n    \]" % block_name, source, re.S)
        if not match:
            raise SystemExit(f"could not find {block_name} in QiraahTajweed.swift")
        for key, value in re.findall(r'"([a-z_]+)": "((?:[^"\\]|\\.)*)"', match.group(1)):
            out.setdefault(key, {})[field] = value.replace('\\"', '"').replace("\\\\", "\\")
    return dict(sorted(out.items()))


def import_qiraat(app: pathlib.Path) -> None:
    print("qiraat text (the 7 verified non-Hafs riwayat)")
    source = app / "Resources" / "JSONs-Deprecated" / "Qiraat"
    for slug, name in sorted(QIRAAT_JSON.items()):
        payload = json.loads((source / f"{name}.json").read_text(encoding="utf-8"))
        # Indented, like the files already in data/qiraat: the diff of a text correction should be
        # the corrected ayahs, not the whole reading reflowed onto one line.
        write_json(DATA / "qiraat" / f"qiraah-{slug}.json", payload, indent=2)


def import_mushaf(app: pathlib.Path, quran: list) -> None:
    print("mushaf facsimiles")
    pdf_source = app / "Resources" / "Mushaf PDFs"
    quran_data = app / "Resources" / "Data" / "Quran"

    index = []
    for (slug, tag, label, arabic, imam, imam_ar, died, pdf, verified) in RIWAYAT:
        name = PACK_NAME[slug]

        # Page table: the riwayah's own pagination, which is NOT Hafs' (merged ayahs and
        # different orthography move the boundaries). Hafs' lives in quran.json already.
        if slug == "hafs":
            pages = {}
            for surah in quran:
                pages[str(surah["id"])] = {str(a["id"]): a["page"] for a in surah["ayahs"]}
        else:
            pages = inflate(quran_data / f"Tajweed{name}.json.deflate")["pages"]
        write_json(DATA / "mushaf" / "pages" / f"{slug}.json",
                   {"riwayah": slug, "totalPages": TOTAL_PAGES, "pages": pages})

        # Line breaks index into the riwayah's TEXT, so they ship only where the text does.
        lines_file = quran_data / f"Lines{name}.json.deflate"
        has_lines = verified and lines_file.exists()
        if has_lines:
            payload = inflate(lines_file)
            write_json(DATA / "mushaf" / "lines" / f"{slug}.json",
                       {"riwayah": slug, "version": payload["v"], "lineBreaks": payload["s"]})

        target = DATA / "mushaf" / "pdfs" / f"{pdf}.pdf.xz"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pdf_source / f"{pdf}.pdf.xz", target)

        index.append({
            "riwayah": slug,
            "tag": tag,
            "name": label,
            "nameArabic": arabic,
            "imam": imam,
            "imamArabic": imam_ar,
            "narratorDiedAH": died,
            "pdf": f"pdfs/{pdf}.pdf.xz",
            "pdfBytes": target.stat().st_size,
            "pages": f"pages/{slug}.json",
            "lines": f"lines/{slug}.json" if has_lines else None,
            "tajweed": f"../tajweed-qiraat/{slug}.json" if (verified and slug != "hafs") else None,
            "textIncluded": verified,
        })

    write_json(DATA / "mushaf" / "index.json", {
        "totalPages": TOTAL_PAGES,
        "note": ("Every facsimile is exactly 604 pages on the Madani page division, so PDF page N "
                 "is mushaf page N. The 12 riwayat with textIncluded=false ship their printed "
                 "mushaf and page table only: their machine-extracted text is not yet proofread, "
                 "and their tajweed and line data index into it."),
        "riwayat": index,
    }, indent=2)


def import_tajweed_qiraat(app: pathlib.Path) -> None:
    print("riwayah tajweed")
    quran_data = app / "Resources" / "Data" / "Quran"
    write_json(DATA / "tajweed-qiraat" / "rules.json", rule_descriptions(app), indent=2)

    for (slug, _tag, _label, _ar, _imam, _imam_ar, _died, _pdf, verified) in RIWAYAT:
        if not verified or slug == "hafs":
            continue
        payload = inflate(quran_data / f"Tajweed{PACK_NAME[slug]}.json.deflate")
        write_json(DATA / "tajweed-qiraat" / f"{slug}.json", {
            "riwayah": slug,
            "version": payload["v"],
            "legend": [{"code": e["c"], "rule": e["k"], "arabic": e["ar"], "english": e["en"]}
                       for e in payload["legend"]],
            "rules": payload["rules"],
            "khilafMarkers": payload["khilafMarkers"],
        })


def import_payloads(app: pathlib.Path) -> None:
    print("word-by-word and the search corpora")
    quran_data = app / "Resources" / "Data" / "Quran"

    pack = unxz(quran_data / "WordByWord.json.xz")
    if pack.get("v") != 2:
        raise SystemExit("WordByWord.json.xz is not a version-2 pack - rebuild it in the app first")
    write_json(DATA / "word-by-word.json",
               {"english": pack["en"], "transliteration": pack["tr"]})

    write_json(DATA / "similar-ayahs.json", unxz(quran_data / "SimilarAyahs.json.xz"))
    write_json(DATA / "themes.json", unxz(quran_data / "ThematicTopics.json.xz"))
    write_json(DATA / "surah-sections.json", unxz(quran_data / "SurahSections.json.xz"))
    write_json(DATA / "tajweed-lessons.json", unxz(quran_data / "TajweedLessons.json.xz"))
    write_json(DATA / "surah-stats.json",
               json.loads((quran_data / "surah-stats.json").read_text(encoding="utf-8")))


def main() -> None:
    app = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "Al-Islam-iOS"
    if not (app / "Resources" / "Data" / "Quran").is_dir():
        raise SystemExit(f"no Al-Islam-iOS checkout at {app} (pass its path as the first argument)")

    quran = json.loads((DATA / "quran.json").read_text(encoding="utf-8"))
    import_qiraat(app)
    import_mushaf(app, quran)
    import_tajweed_qiraat(app)
    import_payloads(app)
    print("done")


if __name__ == "__main__":
    main()
