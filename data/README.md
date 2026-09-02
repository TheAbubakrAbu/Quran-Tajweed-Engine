# Data dictionary

Canonical, language-agnostic data for the Quran Tajweed Engine. Plain UTF-8 JSON — load it from any language. Full schemas and usage live in [`../docs`](../docs); this is the quick reference.

| File | Type | Records | Schema doc |
|------|------|---------|------------|
| `quran.json` | array | 114 surahs / 6236 ayahs | [docs/01-quran.md](../docs/01-quran.md) |
| `surah-info.json` | array | 114 | [docs/01-quran.md](../docs/01-quran.md) |
| `names-of-allah.json` | array | 99 | below |
| `juz.json` | array | 30 | [docs/03-juz-page.md](../docs/03-juz-page.md) |
| `reciters.json` | array | 62 | [docs/04-surah-recitations.md](../docs/04-surah-recitations.md) |
| `tajweed-rules.json` | object | 17 categories | [docs/02-tajweed.md](../docs/02-tajweed.md) · **single source of truth** |
| `tajweed-annotations.json` | array | 6236 ayahs | [tajweed/README.md](tajweed/README.md) |
| `arabic-alphabet.json` | object | 47 letters + more | [docs/16](../docs/16-arabic-alphabet.md) · [the file](../docs/arabic-alphabet.md) |
| `fonts/fonts.json` + `*.ttf` | object | 3 fonts | [docs/fonts.md](../docs/fonts.md) |
| `qiraat/qiraah-*.json` | object | 114 keys each | [docs/01-quran.md](../docs/01-quran.md) |
| `qiraat-counts.json` | object | 7 riwayat | [docs/01-quran.md](../docs/01-quran.md) |
| `mushaf/index.json` | object | 20 riwayat | [docs/10-mushaf.md](../docs/10-mushaf.md) |
| `mushaf/pdfs/*.pdf.xz` | binary | 20 × 604 pages | [docs/10-mushaf.md](../docs/10-mushaf.md) |
| `mushaf/pages/<slug>.json` | object | 20 files | [docs/10-mushaf.md](../docs/10-mushaf.md) |
| `mushaf/lines/<slug>.json` | object | 8 files | [docs/10-mushaf.md](../docs/10-mushaf.md) |
| `tajweed-qiraat/rules.json` | object | 17 rule keys | [docs/11-qiraat-tajweed.md](../docs/11-qiraat-tajweed.md) |
| `tajweed-qiraat/<slug>.json` | object | 7 files | [docs/11-qiraat-tajweed.md](../docs/11-qiraat-tajweed.md) |
| `word-by-word.json` | object | 77,629 words × 2 layers | [docs/12-word-by-word.md](../docs/12-word-by-word.md) |
| `similar-ayahs.json` | object | 5,446 ayahs | [docs/13-similar-and-themes.md](../docs/13-similar-and-themes.md) |
| `themes.json` | object | 323 topics | [docs/13-similar-and-themes.md](../docs/13-similar-and-themes.md) |
| `tajweed-lessons.json` | object | 8 chapters / 34 lessons | [docs/13-similar-and-themes.md](../docs/13-similar-and-themes.md) |
| `surah-sections.json` | object | 741 sections / 111 surahs | [docs/15-surah-sections.md](../docs/15-surah-sections.md) |
| `surah-stats.json` | object | 114 | a standalone index — see below |
| `surahs/NNN.json` + `index.json` | per-surah | 114 + index | [docs/architecture.md](../docs/architecture.md) |

### `surah-stats.json` is a convenience index, not a source

Every value in it — ayah, word and letter counts, juz list, revelation type — is already on the surah in `quran.json`, and a test asserts the two still agree. It ships as an 8 KB file for a consumer that wants the counts without parsing 30 MB of text; the engine's own API answers those questions from `Quran`, so no module reads it.

## Provenance

All files are extracted **unmodified** from the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-iOS) app, except three derived files generated from its source for portability:

- `juz.json` — from `QuranData.juzList`.
- `reciters.json` — from the reciter tables in `QuranStructs.swift` (riwayah labels resolved to text; `id` = `"{name}|{qiraah??Hafs}|{surahLink}"`; `qiraah: null` means Hafs).
- `tajweed-rules.json` — the rule catalogue + color + letter tables from `TajweedRules.swift`. **This is the single source of truth for tajweed rules:** edit it and run `node scripts/generate-tajweed.mjs` to regenerate the per-language constant files (`tajweed-rules.generated.*` in every `packages/` port) and `docs/tajweed-rules-reference.md`.
- `arabic-alphabet.json` — from `ArabicLetters.swift` + `ArabicView.swift` (letters, weights, tashkeel, waqf signs).
- `fonts/` — the three Quran TTFs (Uthmani, Qiraat, Indopak) with `fonts.json` metadata; see [docs/fonts.md](../docs/fonts.md).

The mushaf, riwayah-tajweed, word-by-word, similar-ayah, theme, lesson, section and stats corpora are extracted from the same app by [`scripts/import-al-islam-data.py`](../scripts/import-al-islam-data.py), which decompresses the packs it ships them in and reshapes them as plain JSON. Re-run it after the app updates a corpus.

**Not published here:** the text of the twelve riwayat outside the eight verified ones. It is machine-extracted from printed mushafs and not yet proofread word by word, so it is not fit to hand other developers as engine data — and their line tables and tajweed packs index into it, so those stay out with it. Their printed mushafs and page tables *do* ship, because a facsimile is exact whatever the state of the extraction. See [docs/10-mushaf.md](../docs/10-mushaf.md#the-twelve-without-text).

See [../CREDITS.md](../CREDITS.md) for full attribution. The Quranic Arabic text is sacred — keep it exact.

## `names-of-allah.json`

```jsonc
{
  "name": "الرَّحمَٰن",
  "transliteration": "Ar-Rahman",
  "number": 1,
  "found": "(1:3) (17:110)",          // ayah references where it occurs
  "meaning": "The Entirely Merciful",
  "desc": "He who wills goodness and mercy for all His creatures",
  "otherNames": ["The Most Merciful", "The Most Compassionate", "The Beneficent"]
}
```

## File-size note

`quran.json` (~5.3 MB) and the seven `qiraat/*.json` (~1.6 MB each) are large. For web, load them lazily / on demand, or pre-split per surah. The Node loader (`createEngine`) only requires `quran.json`, `juz.json`, `reciters.json`, and `tajweed-rules.json`; `surah-info.json` and `qiraat/` are opt-in.
