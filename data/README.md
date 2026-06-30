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
| `arabic-alphabet.json` | object | 47 letters + more | [docs/arabic-alphabet.md](../docs/arabic-alphabet.md) |
| `fonts/fonts.json` + `*.ttf` | object | 3 fonts | [docs/fonts.md](../docs/fonts.md) |
| `qiraat/qiraah-*.json` | object | 114 keys each | [docs/01-quran.md](../docs/01-quran.md) |
| `surahs/NNN.json` + `index.json` | per-surah | 114 + index | [docs/architecture.md](../docs/architecture.md) |

## Provenance

All files are extracted **unmodified** from the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars) app, except three derived files generated from its source for portability:

- `juz.json` — from `QuranData.juzList`.
- `reciters.json` — from the reciter tables in `QuranStructs.swift` (riwayah labels resolved to text; `id` = `"{name}|{qiraah??Hafs}|{surahLink}"`; `qiraah: null` means Hafs).
- `tajweed-rules.json` — the rule catalogue + color + letter tables from `TajweedRules.swift`. **This is the single source of truth for tajweed rules:** edit it and run `node scripts/generate-tajweed.mjs` to regenerate the per-language constant files (`tajweed-rules.generated.*` in every `packages/` port) and `docs/tajweed-rules-reference.md`.
- `arabic-alphabet.json` — from `ArabicLetters.swift` + `ArabicView.swift` (letters, weights, tashkeel, waqf signs).
- `fonts/` — the three Quran TTFs (Uthmani, Qiraat, Indopak) with `fonts.json` metadata; see [docs/fonts.md](../docs/fonts.md).

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
