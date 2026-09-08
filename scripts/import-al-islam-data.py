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
    data/quran.json                    ayah text fields, refreshed in place
    data/morphology.json               root + lemma of every word (Quranic Arabic Corpus via QUL)
    data/mutashabihat.json             the 814 repeated phrases and where each occurs
    data/quran-topics.json             2,512 QUL topics in three families
    data/ayah-themes.json              1,049 passage themes, one sentence per run of ayahs
    data/quran-metadata.json           hizb, ruku and manzil boundaries
    data/qiraat-variants.json          who among the Ten reads which form, and what it means
    data/qiraat-places.json            where each published riwayah differs from Hafs at all
    data/qiraat-variant-audio.json     one reciter reading a verse both ways (4 riwayat)
    data/word-of-day.json              149 curated words with every occurrence of the form

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
# The upstream JSON moved out of the app and into this repo in September 2026; the qiraah
# overlays are read from here, not from the app checkout. See sources/README.md.
SOURCES = ROOT / "sources"

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


def import_qiraat(_app: pathlib.Path) -> None:
    """The 7 verified overlays, copied out of this repo's own sources/ rather than the app."""
    print("qiraat text (the 7 verified non-Hafs riwayat)")
    source = SOURCES / "Qiraat"
    for slug, name in sorted(QIRAAT_JSON.items()):
        payload = json.loads((source / f"{name}.json").read_text(encoding="utf-8"))
        # Indented, like the files already in data/qiraat: the diff of a text correction should be
        # the corrected ayahs, not the whole reading reflowed onto one line.
        write_json(DATA / "qiraat" / f"qiraah-{slug}.json", payload, indent=2)



def import_quran_text() -> None:
    """Refresh the ayah transliteration in data/quran.json from sources/Quran.json.

    The whole surah record is not overwritten: data/quran.json carries fields the app's source
    does not (word and letter counts, juz-change flags), and rewriting it wholesale would lose
    them. Only the fields that legitimately change upstream are copied, ayah by ayah, and the
    file is rewritten in the same indent-2 shape so a diff shows the corrected ayahs.

    Written for the 2026-09 transliteration swap: the app replaced its own scheme with QUL's
    "English Transliteration (Tajweed)", which moved 6,235 of the 6,236 ayahs.
    """
    print("quran text")
    source = json.loads((SOURCES / "Quran.json").read_text(encoding="utf-8"))
    target = json.loads((DATA / "quran.json").read_text(encoding="utf-8"))
    by_id = {s["id"]: {a["id"]: a for a in s.get("ayahs", [])} for s in source}

    fields = ("textArabic", "textTransliteration", "textEnglishSaheeh", "textEnglishMustafa")
    changed = {f: 0 for f in fields}
    for surah in target:
        upstream = by_id.get(surah["id"], {})
        for ayah in surah.get("ayahs", []):
            other = upstream.get(ayah["id"])
            if not other:
                continue
            for field in fields:
                if field in other and other[field] != ayah.get(field):
                    ayah[field] = other[field]
                    changed[field] += 1

    write_json(DATA / "quran.json", target, indent=2)
    moved = {f: n for f, n in changed.items() if n}
    print(f"    ayahs changed: {moved or 'none'}")


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


# ---------------------------------------------------------------------------
# Batch 5: the corpora added upstream in Al-Islam 4.6.4 (September 2026).
# ---------------------------------------------------------------------------

# The riwayat whose text this engine publishes; the beta twelve are excluded everywhere,
# including from indexes that only describe their text.
PUBLISHED_TAGS = {tag for (_slug, tag, *_rest, ships) in RIWAYAT if ships}
TAG_TO_SLUG = {tag: slug for (slug, tag, *_rest) in RIWAYAT if tag}


def import_morphology(app: pathlib.Path) -> None:
    """Root and lemma of every word, from the Quranic Arabic Corpus via QUL.

    Kept in the app's compact shape on purpose: this is one small integer per token of the
    Quran, twice over, and inflating 155,258 ids into objects would multiply the file for
    nothing. Ids are 1-based into `roots` / `lemmas`; 0 means the token has neither (particles,
    the sajdah mark). The arrays are per surah, then per ayah, then per whitespace token of the
    ayah's raw Hafs text, which is exactly how `word-by-word.json` is indexed.
    """
    print("morphology")
    pack = unxz(app / "Resources" / "Data" / "Quran" / "Morphology.json.xz")
    write_json(DATA / "morphology.json", {
        "roots": pack["roots"],            # [[letters spaced, buckwalter], ...]
        "lemmas": pack["lemmas"],          # [[dictionary form, unmarked form], ...]
        "rootIds": pack["r"],
        "lemmaIds": pack["l"],
    })


def import_mutashabihat(app: pathlib.Path) -> None:
    """The repeated phrases: QUL's "Mutashabihat ul Quran" set, named rather than positional.

    The app stores each phrase as a 7-element array; a consumer reading JSON should not have to
    know that element 4 is the surah count, so this names the fields. Spans are 0-based
    inclusive token ranges of the raw Hafs text.
    """
    print("mutashabihat")
    pack = unxz(app / "Resources" / "Data" / "Quran" / "Mutashabihat.json.xz")
    phrases = {}
    for pid, row in pack["phrases"].items():
        source, start, end, count, ayah_count, surah_count, occurrences = row
        phrases[pid] = {
            "source": source,
            "span": [start, end],
            "count": count,
            "ayahCount": ayah_count,
            "surahCount": surah_count,
            "occurrences": occurrences,
        }
    write_json(DATA / "mutashabihat.json", {"phrases": phrases, "index": pack["index"]})


def import_topics(app: pathlib.Path) -> None:
    """QUL's three topic families, the passage themes, and the hizb/ruku/manzil boundaries.

    `quran-topics.json` is a different corpus from `themes.json`, not a newer one: themes is the
    323 curated topics, this is 2,512 from the Clear Quran thematic index, the Quranic Arabic
    Corpus ontology and a general A-Z index.

    All THREE parent links are carried, because they are three independent trees over one pool of
    topics and a topic can sit in more than one: Adam is a node in the thematic tree under 2284
    and in the ontology under 272, and collapsing that to a single "family parent" would silently
    drop one of them. The `t` and `o` flags say which indexes a topic is listed in (17 topics are
    listed in both), so they are carried as flags rather than as one exclusive family. A tree's
    parent may itself be a topic listed elsewhere - the A-Z index hangs "House of" under Moses,
    who is a thematic topic - so a tree is not closed over its own listing either.
    """
    print("topics, passage themes and metadata")
    quran_data = app / "Resources" / "Data" / "Quran"

    raw = unxz(quran_data / "QuranTopics.json.xz")["topics"]
    topics = []
    for row in raw:
        name = row.get("n") or ""
        if not name:
            continue
        thematic, ontology = row.get("t", 0) == 1, row.get("o", 0) == 1
        listed = []
        if thematic:
            listed.append("thematic")
        if ontology:
            listed.append("ontology")
        if not listed:
            listed.append("index")
        topics.append({
            "id": row["id"],
            "name": name,
            "arabic": row.get("ar", ""),
            # The indexes this topic is listed in; 17 topics are listed in two.
            "families": listed,
            # One parent per tree, independently. Null where the topic is not in that tree, or
            # is one of its roots.
            "parents": {
                "thematic": row.get("tp"),
                "ontology": row.get("op"),
                "index": row.get("p"),
            },
            "description": row.get("d", ""),
            "wiki": row.get("w", ""),
            "ayahs": row.get("ay", []),
            "related": row.get("rel", []),
        })
    write_json(DATA / "quran-topics.json", {"topics": topics})

    # One sentence per run of ayahs: [firstAyah, lastAyah, theme, topic].
    themes = unxz(quran_data / "AyahThemes.json.xz")["themes"]
    write_json(DATA / "ayah-themes.json", {
        surah: [{"from": row[0], "to": row[1], "theme": row[2], "topic": row[3]} for row in rows]
        for surah, rows in themes.items()
    })

    meta = json.loads((quran_data / "QuranMetadata.json").read_text(encoding="utf-8"))
    write_json(DATA / "quran-metadata.json",
               {k: meta[k] for k in ("hizb", "ruku", "manzil")}, indent=2)


def import_qiraat_variants(app: pathlib.Path) -> None:
    """WHO among the Ten reads a word differently, and what the difference means.

    A layer the qiraah texts cannot supply. `data/qiraat/` gives each reading's own words; this
    gives the reader behind each form, a transliteration, an English rendering and usually a
    grammarian's note. Source is the Quran.com qiraat matrix (Quran Foundation).

    `readers` are the ten imams; `transmitters` the twenty riwayat. A reading lists `readers`
    when both of an imam's transmitters follow it, and `transmitters` when they part company.
    Segment ranges are 0-based inclusive token indices of the raw Hafs text, `null` where the
    builder could not place the word.
    """
    print("qiraat variants")
    quran_data = app / "Resources" / "Data" / "Quran"
    pack = unxz(quran_data / "QiraatVariants.json.xz")

    readers = {rid: {"id": int(rid), "name": row["n"], "abbreviation": row.get("a", row["n"]),
                     "city": row.get("c", ""), "position": row.get("p", 99)}
               for rid, row in pack["readers"].items()}
    transmitters = {}
    for tid, row in pack["transmitters"].items():
        tag = row.get("tag", "")
        transmitters[tid] = {
            "id": int(tid), "name": row["n"], "reader": row["r"],
            # The engine's own slug, so a consumer can join this to data/qiraat/ and data/mushaf/.
            "riwayah": TAG_TO_SLUG.get(tag, "hafs" if tag == "" else None),
            "textPublished": tag in PUBLISHED_TAGS,
        }

    ayahs = {}
    for key, rows in pack["ayahs"].items():
        junctures = []
        for row in rows:
            readings = []
            for reading in row.get("readings", []):
                text = reading.get("t") or ""
                if not text:
                    continue
                readings.append({
                    "text": text,
                    "transliteration": reading.get("tr", ""),
                    "english": reading.get("en", ""),
                    "explanation": reading.get("ex", ""),
                    "grammaticalForm": reading.get("gf", ""),
                    "rootLetters": reading.get("rt", ""),
                    "readers": reading.get("rd", []),
                    "transmitters": reading.get("tm", []),
                })
            if not readings:
                continue
            segments = []
            for seg in row.get("seg", []):
                if len(seg) != 3:
                    continue
                seg_key, start, end = seg
                segments.append({"ayah": seg_key,
                                 "span": [start, end] if start >= 0 and end >= start else None})
            junctures.append({
                "word": row.get("t", ""),
                "category": row.get("c", ""),
                "segments": segments,
                "readings": readings,
                "note": row.get("note", ""),
            })
        if junctures:
            ayahs[key] = junctures

    write_json(DATA / "qiraat-variants.json",
               {"readers": readers, "transmitters": transmitters, "ayahs": ayahs})


def import_qiraat_places(app: pathlib.Path) -> None:
    """Where a riwayah differs from Hafs at all, ayah by ayah, for the published readings.

    The comparison answers "how does this riwayah read this ayah"; this answers the question
    before it, so a reader can step from one difference to the next instead of hunting. Two
    kinds, because they are found two ways and a consumer may want only the first: a `word`
    index is a word dropped, added or spelled differently, found by diffing the two texts; a
    `letter` index is a word the printed mushaf marks as read with other vowels over the SAME
    skeleton, which no text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).

    The app encodes the second kind as a negative index; unpacking it here means no consumer has
    to know that. The beta riwayat are dropped with their text.
    """
    print("qiraat places")
    pack = unxz(app / "Resources" / "Data" / "Quran" / "QiraatPlaces.json.xz")
    out = {}
    for tag, surahs in pack["riwayat"].items():
        if tag not in PUBLISHED_TAGS:
            continue
        slug = TAG_TO_SLUG[tag]
        table = {}
        for surah, rows in surahs.items():
            for row in rows:
                ayah, indices = row[0], row[1:]
                table.setdefault(surah, {})[str(ayah)] = {
                    "word": sorted(i for i in indices if i >= 0),
                    "letter": sorted(-i - 1 for i in indices if i < 0),
                }
        out[slug] = table
    write_json(DATA / "qiraat-places.json", {"riwayat": out})


def import_qiraat_variant_audio(app: pathlib.Path) -> None:
    """The same reciter reading a verse both ways, for the four riwayat where one exists.

    A pair drawn from two shaykhs would differ in voice, pace and maqam as well, and teach
    nothing about the variant, so only reciters who published both sides with timings are here.
    Rows are `[surah, sourceIndex, hafsStartMs, hafsEndMs, riwayahStartMs, riwayahEndMs]` per
    ayah; a `file` source is a whole per-verse recording and ignores the offsets, a `span`
    source is a seek inside a full-surah one. URLs are built from the source's two bases.
    """
    print("qiraat variant audio")
    pack = unxz(app / "Resources" / "Data" / "Quran" / "QiraatVariantAudio.json.xz")
    write_json(DATA / "qiraat-variant-audio.json", {
        "sources": pack["sources"],
        "riwayat": {TAG_TO_SLUG.get(tag, tag): rows for tag, rows in pack["riwayat"].items()},
    }, indent=2)


def import_word_of_day(app: pathlib.Path) -> None:
    """149 curated words, each with every ayah the same written form appears in.

    The curation and glosses are Tilawa's (Jamil Hammoudeh, with permission); the occurrences
    are derived from the Hafs text, so the count and the list behind it are one derivation.
    `token` indices are into the ayah's raw whitespace tokens, as everywhere else.
    """
    print("word of the day")
    pack = unxz(app / "Resources" / "Data" / "Quran" / "WordOfDay.json.xz")
    words = [{
        "id": row["id"],
        "arabic": row["ar"],
        "transliteration": row.get("tr", ""),
        "meaning": row.get("en", ""),
        "surah": row["s"],
        "ayah": row["a"],
        "token": row["p"],
        "count": row["n"],
        "occurrences": [{"surah": o[0], "ayah": o[1], "tokens": o[2]} for o in row["occ"]],
    } for row in pack["words"]]
    write_json(DATA / "word-of-day.json", {"words": words})


def main() -> None:
    app = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "Al-Islam-iOS"
    if not (app / "Resources" / "Data" / "Quran").is_dir():
        raise SystemExit(f"no Al-Islam-iOS checkout at {app} (pass its path as the first argument)")

    import_quran_text()
    quran = json.loads((DATA / "quran.json").read_text(encoding="utf-8"))
    import_qiraat(app)
    import_mushaf(app, quran)
    import_tajweed_qiraat(app)
    import_payloads(app)
    import_morphology(app)
    import_mutashabihat(app)
    import_topics(app)
    import_qiraat_variants(app)
    import_qiraat_places(app)
    import_qiraat_variant_audio(app)
    import_word_of_day(app)
    print("done")


if __name__ == "__main__":
    main()
