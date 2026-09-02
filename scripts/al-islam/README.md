# The Al-Islam build scripts

The Python (and one Swift) tooling that produces the corpora this engine ships, copied verbatim
from the [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-iOS) app's `Scripts/` directory.

They are here for **provenance and reproducibility**, not as part of the engine's API. The engine's
deliverable is `data/` - plain JSON any language can read. These scripts are how that JSON came to
exist, so anyone can check the derivation, re-run it against a corrected source, or build the same
kind of pack for another reading.

## Running them

Every script's paths are relative to the **app** checkout, not to this repo:

```bash
cd ../Al-Islam-iOS
python3 Scripts/build_wordbyword.py
```

Run [`scripts/import-al-islam-data.py`](../import-al-islam-data.py) afterwards to bring the result
back here as JSON. Nothing in this directory writes into `data/`; that importer is the only path in.

## What each one produces

### Feeds a corpus this engine ships

| Script | Produces | Lands here as |
|---|---|---|
| `fetch_wordbyword.py` | downloads the per-word Latin transliteration layer | (source for the next one) |
| `build_wordbyword.py` | `WordByWord.json.xz` - per-word gloss + transliteration, aligned at build time to the app's own tokens | `data/word-by-word.json` |
| `verify_wordbyword.py` | the gate: both layers must match every ayah's token count, and rebuild byte for byte | - |
| `build_tajweed_v2.py` | the riwayah tajweed packs: rules and exact letter extents derived from each printed mushaf's own marks | `data/tajweed-qiraat/*.json` |
| `build_similar_ayahs.py` / `verify_similar_ayahs.py` | the merged, pre-ranked mutashabihat corpus | `data/similar-ayahs.json` |
| `build_quran_themes.py` / `verify_quran_themes.py` | the curated thematic topics | `data/themes.json` |
| `build_tajweed_lessons.py` / `verify_tajweed_lessons.py` | the tajweed course | `data/tajweed-lessons.json` |
| `generate_surah_stats.py` | per-surah ayah / word / letter counts | `data/surah-stats.json` |
| `tajweed-extraction/` | the multi-stage pipeline that lifted the riwayah marks out of the printed mushaf PDFs in the first place (stage 1 ink extraction, stage 2 rule inference, stage 3 packing), plus the v1 packs it produced | `data/tajweed-qiraat/*.json` |

### App packaging, kept for completeness

These shape the corpora for a phone bundle rather than changing their content. Nothing here affects
`data/`, which is always the uncompressed JSON.

| Script | What it does |
|---|---|
| `reblock_packs.py` | re-blocks the `.hpk` / `.tpk` / `.qpk` containers losslessly, trading block size against decompression granularity |
| `build_solidpacks.py` | bundles the per-riwayah payloads into one solid-compressed archive |
| `fix_beta_spaces.py` | whitespace repair for the machine-extracted riwayah texts (the twelve this engine does **not** publish) |

### Fonts and rendering

Not engine data - `data/fonts/` ships the finished TTFs - but this is how those faces were built
and checked.

| Script | What it does |
|---|---|
| `build_hijazi_font.py` | derives the Hijazi face from `fonts/hijazi-upstream.ttf` |
| `patch_quran_font_coverage.py` / `audit_quran_font_coverage.py` | fills and then audits the glyph coverage a Quran face needs |
| `patch_dotless_glyphs.py` | the dotless (early-script) variants |
| `patch_ayah_medallion_287.py` | one ayah-marker glyph fix |
| `render_arabic.swift` | renders a string with a given face, for eyeballing a patch |

### App-only

| Script | What it does |
|---|---|
| `build_islam_corpus.py` / `verify_islam_corpus.py` | lifts the app's Islam-tab articles (pillars, beliefs, how-to guides) out of their SwiftUI source into a searchable pack. Not Quran data, and not shipped here - included so the app's `Scripts/` directory is complete. |
