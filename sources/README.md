# Upstream sources

**This folder is provenance, not the deliverable.** The engine's API reads `data/`; nothing here
is loaded by any port, shipped in any package, or referenced by any spec. What lives here is the
*original* JSON that `data/` and the Al-Islam app's compressed packs were both built from, kept
so that a pack can be rebuilt, a text correction can be traced to its source, and a claim in the
docs can be checked against the thing it describes.

It was published here in September 2026, copied from `Al-Islam-iOS/Resources/JSONs-Deprecated/`.
The app keeps its own copy, because its `Scripts/` build the packs from these files; this is the
copy everyone else can read. The app's README points here.

## What maps to what

| Source file | Engine `data/` | App pack |
|---|---|---|
| `Quran.json` | `quran.json` | `Data/Quran/quran.qpk` |
| `SurahInfos.json` | `surah-info.json` | `Data/Quran/surahinfos.qpk` |
| `NamesOfAllah.json` | `names-of-allah.json` | `namesofallah.qpk` |
| `Qiraat/Qiraah*.json` (7 verified riwayat) | `qiraat/*.json` | `Data/Quran/qiraat.qpk` |
| `Qiraat/quran-com-qiraat.json.xz` | `qiraat-variants.json` | `Data/Quran/QiraatVariants.json.xz` |
| `QUL/*` (see below) | `morphology`, `mutashabihat`, `topics`, `ayah-themes`, `quran-metadata`, `similar-ayahs` | the matching `Data/Quran/*.json.xz` |
| `Qiraat/_staging-riwayat/*.json` (12 beta riwayat) | *not published* | `Data/Quran/Qiraah*.json.deflate` |

The loader that reads the packs was verified against these sources with 216,885 equality
assertions; `NamesOfAllah.json` with 851. Deleting this folder saves space and destroys the
ability to repeat that.

## The 12 beta riwayat

`Qiraat/_staging-riwayat/` holds the machine-extracted text of the twelve riwayat the app ships
behind *Settings -> Quran -> Beta Qiraat*, plus the extraction pipeline that produced them. Its
own README carries the measured accuracy table and the promote-out-of-beta checklist, and
`HANDOFF-2026-08-24.md` records the correction pass.

**This text is deliberately not published through the engine.** It has not been reviewed by a
qari, and the `Lines*` and `Tajweed*` packs that index into it stay out with it. What the engine
does publish for all twenty riwayat is the printed facsimile and each riwayah's own page table:
see `data/mushaf/index.json`, where `textIncluded` is the flag.

## What is not here, and how to remake it

The extraction intermediates are not published: the `.raw` / `.surahs` / `.final` / `.text`
dumps, the detector maps and the PDF parse cache, some 630 MB. Every one of them is a
deterministic function of the source PDF, so they are regenerated rather than stored:

| File | Remade by |
|---|---|
| `data/<slug>.raw.json`, `data/<slug>.surahs.json`, `data/<slug>.colors.json` | `pipeline/extract.py` |
| `data/<slug>.colorlayer.json` | `pipeline/colorlayer.py` |
| `data/<slug>.lines.json`, `.lines.report.json` | `pipeline/printlines_build.py` |

What *is* kept in `pipeline/data/` is the 10 MB that encodes human review and so cannot be
regenerated at all: the `ctxdet-*.json` context detectors and every one of their `.pre-*`
snapshots, the per-family `glyphcounts-*`, `bazzi-shapemap.json`, `bazzi-learned.json`,
`manualmap.json` and `ishmam-kasr.json`.

The line drawn here is "can a script remake it", which is stricter than the one the app draws:
the app also tracks each riwayah's `.colors.json`, `.colorlayer.json` and `.lines.json` (154 MB
together), and those are left out of this repository because `extract.py`, `colorlayer.py` and
`printlines_build.py` remake them from the PDFs. If you need them without re-running the
extraction, take them from the app checkout, where they are tracked.

The extraction input is the Islamweb PDF series, which is not in any repo either (225 MB).
`Qiraat/_staging-riwayat/pdfs/README.md` names all 22 volumes, gives the Internet Archive mirror they were
fetched from, and explains the slug-to-filename mapping `extract.pdf_path()` performs. Note that
`pipeline/pipeline.sh` is a bootstrap driver from one session, with absolute scratch paths in it;
read it as a record of the order things ran in, not as a script to invoke.

## Data sources and attribution

- **Hafs and the 7 verified riwayah overlays**: King Fahd Glorious Quran Printing Complex texts
  (https://qurancomplex.gov.sa), as distributed for development use (see also
  https://qul.tarteel.ai).
- **The 12 beta riwayat**: extracted from Islamweb's electronic mushaf series (Islamweb / Qatar
  Ministry of Awqaf, https://www.islamweb.net), with permission obtained by email (Aug 2026).
  PDF mirror used for extraction: https://archive.org/details/quran-islamweb.net
- Review references for the beta texts: https://nquran.com (page images per riwayah) and the
  Quran.com qiraat data (https://qul.tarteel.ai / QUL).

## QUL (Quranic Universal Library)

`QUL/` holds the qul.tarteel.ai downloads that the app's `Resources/Data/Quran/` packs of
2026-09-07 are built from, by `Scripts/build_qul_packs.py` and gated by
`Scripts/verify_qul_packs.py` (both copied into `scripts/al-islam/`):

- `word-root.db.zip`, `word-lemma.db.zip` (Quranic Arabic Corpus morphology) -> `Morphology.json.xz`
- `mutashabihat/phrases.json` + `phrase_verses.json` -> `Mutashabihat.json.xz`
- `topics.db` (Clear Quran thematic index, Corpus ontology, general index) -> `QuranTopics.json.xz`
- `ayah-themes.db` -> `AyahThemes.json.xz`
- `quran-metadata-{hizb,ruku,manzil}.json.zip` -> `QuranMetadata.json`
- `matching-ayah.json` -> the spans and extra pairs merged into `SimilarAyahs.json.xz`
- `english-transliteration-tajweed.json.zip` -> the ayah transliteration inside `quran.qpk`

`Qiraat/quran-com-qiraat.json.xz` is the Quran.com qiraat matrix (Quran Foundation), fetched
2026-09-06 from the page data of `quran.com/<surah>:<ayah>/qiraat` and compacted. It is not a
published API: clear the English renderings and explanations with the Quran Foundation before a
release that exposes them.

QUL word positions are Quran.com's; the builders map them onto the app's own tokens (see the
module doc of `build_qul_packs.py` for the two numbering quirks).
