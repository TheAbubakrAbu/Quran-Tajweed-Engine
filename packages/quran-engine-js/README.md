# @quran-tajweed-engine/core

The reference implementation of the [Quran Tajweed Engine](../../README.md) — pure ESM JavaScript with TypeScript types and **zero runtime dependencies**. Runs in browsers, Node 18+, Deno, Bun, and React Native (with an `Intl.Segmenter` polyfill for grapheme clustering).

This package *is* the executable spec: every module maps to a feature doc in [`../../docs`](../../docs).

## Modules

| Import | Feature | Doc |
|---|---|---|
| `quran.js` | surahs, ayahs, translations, qiraat | 01 |
| `tajweed.js` | tajweed detection → colored spans | 02 |
| `juzPage.js` | juz & mushaf-page navigation | 03 |
| `audio.js` | reciters + surah/ayah audio URLs | 04, 05 |
| `search.js` | ayah & surah search (+ boolean) | 06 |
| `sorting.js` | surah sorting & filtering | 07 |
| `cache.js` | offline-download paths + `AudioCache` | 08 |
| `text.js` | Arabic normalization + grapheme clustering | — |

Everything is re-exported from the package root, so `import { ... } from "@quran-tajweed-engine/core"` gives you the whole API and the bundler tree-shakes what you don't use.

## Usage

### Node (zero-config)

```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();                 // reads ../../data
// opt-in heavy data:
const full = await loadFromDisk({ loadQiraat: true, loadSurahInfo: true });
```

### Browser / bundler (bring your own JSON)

```js
import { createEngine } from "@quran-tajweed-engine/core";
import quran from "../../data/quran.json";
import juz from "../../data/juz.json";
import reciters from "../../data/reciters.json";
import tajweedRules from "../../data/tajweed-rules.json";

const engine = createEngine({ quran, juz, reciters, tajweedRules });
```

### Just the tajweed engine (no data needed)

```js
import { tajweedSpans } from "@quran-tajweed-engine/core";
tajweedSpans("ٱلضَّآلِّينَ");   // → spans incl. { category: "maddNecessary", ... }
```

## Engine facade API

`createEngine(...)` / `loadFromDisk(...)` returns:

```ts
engine.quran      // Quran:    surah(), ayah(), arabicText(.., riwayah), globalAyahNumber(), info(), eachAyah()
engine.juzPage    // JuzPage:  juz(), ayahsInJuz(), ayahsOnPage(), firstAyahOf*(), juzForAyah(), totalPages()
engine.reciters   // Reciters: all(), byId(), byQiraah(), withSurahFeed(), qiraat()
engine.search     // Search:   searchVerses(), searchSurahs(), parseReference()
engine.tajweed(text, opts?)   // → colored spans (category + colorHex + text + range)
```

Plus standalone functions: `surahAudioUrl`, `ayahAudioUrl`, `sortSurahs`, `detectPaintOps`, `resolveSpans`, `AudioCache`, `localSurahPath`, and the `text.js` normalizers.

## Tests

```bash
node --test test/*.test.js     # 18 tests, run against the real ../../data
```

## Fidelity

Ported faithfully from Al-Islam's Swift source. The tajweed detector covers all rule families; two edge areas (full final-raa vowel context, muqatta'at lazim-harfi sub-typing) are simplified — see [docs/02-tajweed.md](../../docs/02-tajweed.md). Search, sorting, juz/page, and audio URL building match the Swift behavior exactly (verified by the test suite).

## License

MIT — see [../../LICENSE](../../LICENSE) and [../../CREDITS.md](../../CREDITS.md).
