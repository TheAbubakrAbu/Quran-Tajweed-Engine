# QuranEngine (Swift)

The Swift port of the open-source **Quran Tajweed Engine**. A thin, idiomatic wrapper over the JSON corpus in [`../../data`](../../data) plus a handful of pure functions — no network, database, or framework required.

This package follows the shared contract in [`../../docs/PORTING.md`](../../docs/PORTING.md); the behaviour matches the reference JS implementation in [`../quran-engine-js`](../quran-engine-js). See `../../docs/01-quran.md` … `08-caching.md` for the per-feature specs.

## Requirements

- Swift tools 5.7+ (built/tested with Swift 6.x).
- The `/data` directory at the repo root, or an explicit data directory / app-bundled assets.

## Install

Add as a local package dependency:

```swift
.package(path: "../quran-engine-swift")
```

## Usage

```swift
import QuranEngine

// Auto-locate the repo /data (or pass dataDirectory:, or set QURAN_ENGINE_DATA).
let engine = try Engine.load()

// Quran browsing
engine.quran.totalAyahs                       // 6236
engine.quran.surah(2)?.nameEnglish            // "The Cow"
engine.quran.globalAyahNumber(2, 1)           // 8
engine.quran.arabicText(1, 1)                 // Hafs Uthmani text
engine.quran.cleanArabicText(1, 1)            // diacritics stripped

// Audio URLs
let reciter = engine.reciters.byId("Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/")!
try surahAudioURL(reciter, 1)                 // ".../afs/001.mp3"
ayahAudioURL(reciter, 8)                       // ".../128/ar.alafasy/8.mp3"

// Juz / page
engine.juzPage.juz(30)?.endSurah               // 114
engine.juzPage.ayahsInJuz(1)
engine.juzPage.juzFromEnd(1)?.id               // 30  (juz from the end: -1 → juz 30)
engine.juzPage.juzStats(30)                    // JuzStats(surahCount, ayahCount, wordCount, letterCount, pageCount)

// Sorting
sortSurahs(engine.quran.all(), .ayahs, .descending).first?.id   // 2

// Tajweed (strategy A: pre-computed annotations → category colors)
for span in engine.tajweed.tajweedSpans(1, 1) {
    print(span.rule, span.colorHex ?? "?", span.text)
}

// Search
engine.search.searchVerses("mercy", limit: 10)   // mushaf order, unranked
engine.search.searchSurahs("baqarah")
engine.search.parseReference("2:255")            // AyahReference(surah: 2, ayah: 255)

// Caching paths (storage backend is host-specific)
sanitizeReciterDir(reciter.id)
localSurahPath(reciter, 1)
```

## Loading the data directory

`Engine.load(dataDirectory:)` resolves `/data` in this order:

1. an explicit `dataDirectory:` URL,
2. the `QURAN_ENGINE_DATA` environment variable,
3. a path computed from `#filePath` walking up to the repo root + `/data`,
4. `<cwd>/data` and a few parent-relative fallbacks.

For an app, bundle the JSON as assets and pass the bundle URL as `dataDirectory:`.

## Tajweed strategy

This port uses **strategy (A)** from the porting guide: it loads `tajweed-annotations.json` and maps each annotation's `rule` to a color from `tajweed-rules.json` → `categories[].colorHex`. Annotation `start`/`end` are UTF-16 code-unit offsets; Swift slices them natively via `String.Index(utf16Offset:in:)`. Each returned `TajweedSpan.text` is the reconstructed UTF-16 slice and equals the slice the reference engine produces (asserted in the tests).

## Search scope

The core search path is implemented: cleaned-blob substring + phrase-prefix token matching, mushaf order, digit-rejection for verse text, optional "ignore silent letters" Arabic variant, and surah search by name / number / `2:255` reference / makkan-madani.

**Omitted:** the boolean grammar (`& | ! # ^ % $`). Per the porting guide's "minimal port" allowance, queries with those operators are treated as plain text rather than parsed as a boolean expression.

## Tests

```sh
swift test
```

The test target asserts the canonical cases from `docs/PORTING.md` (totalAyahs == 6236, global ayah numbers, audio URLs, juz boundaries, sorting, reference parsing) and verifies that every tajweed span's reconstructed UTF-16 slice equals its recorded text.

## License & attribution

MIT. All data and algorithms are extracted from the open-source **Al-Islam | Islamic Pillars** app by **Abubakr Elmallah**. Please preserve this attribution — see [`../../CREDITS.md`](../../CREDITS.md) and [`../../LICENSE`](../../LICENSE).
