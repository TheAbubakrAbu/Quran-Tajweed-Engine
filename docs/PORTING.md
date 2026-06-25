# Porting guide — the shared contract

This is the single contract that **every language port** (`packages/quran-engine-*`) implements, so the
API feels the same everywhere. If you're adding a new language, follow this document and the per-feature
specs in `docs/01…08`.

The philosophy: **the data is the engine.** A port is a thin, idiomatic wrapper over the JSON in `/data`
plus a handful of pure functions. Nothing here needs a network call, a database, or a framework.

## What a "core" port must provide

| Area | Functions / methods | Spec |
|---|---|---|
| **Load** | parse `quran.json`, `juz.json`, `reciters.json`, `tajweed-rules.json` (+ optional `surah-info.json`, `qiraat/*`, `tajweed-annotations.json`) | 01 |
| **Quran** | `surah(id)`, `ayah(surah, ayah)`, `globalAyahNumber(surah, ayah)`, `arabicText(surah, ayah, riwayah?)`, `cleanArabicText(...)`, iterate ayahs | 01 |
| **Tajweed** | `tajweedSpans(surah, ayah)` → colored spans, by loading the pre-computed annotations and mapping `rule`→`colorHex`. (Full detector port is optional — see "Tajweed strategy".) | 02 |
| **Juz/Page** | `juz(id)`, `ayahsInJuz(n)`, `ayahsOnPage(n)`, `firstAyahOfJuz(n)`, `firstAyahOfPage(n)`, `juzForAyah(...)`, `pageForAyah(...)`, `totalPages()` | 03 |
| **Surah audio** | `surahAudioUrl(reciter, surah)` = `surahLink + zeroPad3(surah) + ".mp3"` | 04 |
| **Ayah audio** | `ayahAudioUrl(reciter, globalAyah)` = `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3` | 05 |
| **Search** | `searchVerses(query, opts)`, `searchSurahs(query)`, `parseReference("2:255")` | 06 |
| **Sorting** | `sortSurahs(mode, direction)`, `filterByRevelationType(type)` | 07 |
| **Caching** | `localSurahPath(reciter, surah)`, `sanitizeReciterDir(id)` (storage backend is host-specific) | 08 |

A port is "complete" when it implements Load + Quran + Tajweed(via annotations) + Juz/Page + audio URLs +
sorting + reference parsing. Search (full normalization) and caching are "extended" — nice to have.

## Canonical formulas (copy these exactly)

```
zeroPad3(n)                  → "001", "057", "114"
globalAyahNumber(s, a)       → (Σ numberOfAyahs of surahs with id < s) + a       # 1..6236
surahAudioUrl(r, s)          → r.surahLink + zeroPad3(s) + ".mp3"
ayahAudioUrl(r, g)           → "https://cdn.islamic.network/quran/audio/" + r.ayahBitrate + "/" + r.ayahIdentifier + "/" + g + ".mp3"
sanitizeReciterDir(id)       → replace every char not in [A-Za-z0-9-_] with "_", cap 180 chars (fallback "reciter")
localSurahPath(r, s)         → sanitizeReciterDir(r.id) + "/" + zeroPad3(s) + ".mp3"
```

Reciter `id` = `"{name}|{qiraah or 'Hafs'}|{surahLink}"`. `qiraah` is null/absent for Hafs.

## Tajweed strategy (important)

Two ways to get tajweed colors. **Prefer (A)** for new ports — it's small, correct, and consistent:

- **(A) Consume the pre-computed corpus.** Load `data/tajweed/NNN.json` (or `tajweed-annotations.json`),
  take the ayah's `annotations`, and map each `rule` to `tajweed-rules.json → categories[].colorHex`. The
  `start`/`end` are UTF-16 offsets — see "String indexing" below. This needs ~30 lines of code.
- **(B) Port the detector.** Re-implement `docs/02-tajweed.md` from scratch. Only do this if you need to
  color text the corpus doesn't cover (other qiraat, user input) or you want zero data dependency.

## String indexing (UTF-16 offsets)

The annotation `start`/`end` are **UTF-16 code-unit offsets**, because the source Quran text and the
reference engine are UTF-16. Arabic letters in the Quran are in the Basic Multilingual Plane (1 UTF-16
unit each), but **combining marks and a few symbols can matter**, so handle this precisely:

- **JS, Swift (`NSString`/`utf16`), Java, Kotlin, Dart, C#** — native UTF-16. Use offsets directly.
- **Python** — strings are code-point indexed. Convert: build the slice via
  `text.encode("utf-16-le")` and slice on `2*start : 2*end`, or precompute a code-point↔UTF-16 map. The
  Python port includes a helper (`utf16_slice`).
- **Rust** — strings are UTF-8/byte indexed. Decode to `Vec<u16>` (`text.encode_utf16()`), slice, and
  re-encode with `String::from_utf16`.
- **Go** — strings are bytes; use `utf16.Encode([]rune(text))`, slice, `utf16.Decode`.

When in doubt, the test for any port: for every annotation, the reconstructed slice must equal the same
slice the JS engine produces. The JS test suite and the Python port both assert this.

## Sorting rules (exact)

- Comparators are **ascending with `id` as the tiebreaker**.
- **Descending** = reverse of the ascending array.
- `mode = "surah"` or `direction = "surahOrder"` → natural 1..114, no sort.
- Direction-aware modes: `revelation`, `ayahs`, `page`, `words`, `letters`. Others are intrinsic.

## Search normalization (exact)

The Arabic/English fold is the load-bearing part. Implement `cleanSearch` precisely (see `docs/06`):
fold hamza/alif/waw/yaa variants → strip punctuation + symbols + combining marks (keep `& | ! #`) →
lowercase → collapse whitespace. Verse search returns **mushaf order** (unranked) and **rejects any query
containing a digit**. A minimal port may implement substring matching on the folded blobs and skip the
boolean grammar; document what you skipped.

## Reference behaviors to match (test cases)

```
quran.totalAyahs                         == 6236
globalAyahNumber(1, 1)                    == 1
globalAyahNumber(2, 1)                    == 8
globalAyahNumber(114, 6)                  == 6236
surahAudioUrl(Alafasy, 1)                 == "https://server8.mp3quran.net/afs/001.mp3"
ayahAudioUrl(Alafasy, 8)                  == "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"
juz(1).startSurah/startAyah               == 1 / 1
juz(30).endSurah/endAyah                  == 114 / 6
sortSurahs("ayahs","descending")[0].id    == 2     (Al-Baqarah, 286 ayahs)
parseReference("2:255")                   == { surah: 2, ayah: 255 }
```

Every port should ship a tiny test asserting these.

## Directory convention

```
packages/
  quran-engine-js/      reference (ESM JS + TS types)
  quran-engine-py/      Python
  quran-engine-swift/   Swift Package
  quran-engine-kotlin/  Kotlin / Android
  quran-engine-dart/    Dart / Flutter
  quran-engine-go/      Go module
  quran-engine-rust/    Rust crate
```

Ports locate `/data` relative to the repo root (or accept an injected data directory / parsed objects, so
they also work when the data is bundled as an app asset).
