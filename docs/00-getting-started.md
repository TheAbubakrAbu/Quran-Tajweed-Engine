# Getting started

Welcome. This is a **complete Quran engine** you can drop into any app, in any language. This page gets
you from zero to "I'm reading colored Quran text and playing audio" in a few minutes.

## The one big idea

**The data is the engine.** Everything lives as plain JSON in [`/data`](../data). Any language that can
read JSON can use it. The code in [`/packages`](../packages) is just convenient, idiomatic wrappers around
that data — use one if it fits your stack, or read the data directly and follow the specs in this folder.

```
┌─────────────┐   reads    ┌──────────────────────────┐   you build   ┌──────────────┐
│   /data     │ ─────────► │ a port (JS/Py/Swift/…) or │ ────────────► │   your app   │
│  (JSON)     │            │ your own code + the specs │               │ (any UI)     │
└─────────────┘            └──────────────────────────┘               └──────────────┘
```

## Pick your path

| You're building… | Use | Start here |
|---|---|---|
| Web app (React/Vue/Svelte/vanilla) | `quran-engine-js` | [integration/web.md](integration/web.md) |
| Node / Deno / Bun backend | `quran-engine-js` | [integration/server.md](integration/server.md) |
| React Native app | `quran-engine-js` | [integration/react-native.md](integration/react-native.md) |
| Flutter app | `quran-engine-dart` | [integration/flutter.md](integration/flutter.md) |
| iOS / macOS (SwiftUI) | `quran-engine-swift` | [integration/ios.md](integration/ios.md) |
| Android (Kotlin) | `quran-engine-kotlin` | [integration/android.md](integration/android.md) |
| Python (scripts/ML/backend) | `quran-engine-py` | [README](../packages/quran-engine-py/README.md) |
| Go / Rust service | `quran-engine-go` / `-rust` | package READMEs |
| Some other language | the raw data | [PORTING.md](PORTING.md) |

## 60-second tour (JavaScript)

```bash
cd packages/quran-engine-js
node --test test/*.test.js     # prove it works against the real data (18 tests)
```

```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();

// 1. Read an ayah
const ayah = engine.quran.ayah(2, 255);          // Ayat al-Kursi
console.log(ayah.textArabic);
console.log(ayah.textEnglishSaheeh);

// 2. Color it with tajweed
for (const span of engine.tajweed(ayah.textArabic)) {
  console.log(span.category, span.color, span.text);   // e.g. "maddNecessary #AE2517 آ"
}

// 3. Build an audio URL
import { surahAudioUrl, ayahAudioUrl } from "@quran-tajweed-engine/core";
const reciter = engine.reciters.all().find(r => r.name === "Mishary Alafasy");
surahAudioUrl(reciter, 2);                                          // full surah
ayahAudioUrl(reciter, engine.quran.globalAyahNumber(2, 255));       // one ayah

// 4. Search
engine.search.searchVerses("the throne");
engine.search.searchSurahs("2:255");
```

## 60-second tour (Python)

```python
from quran_engine import Engine
engine = Engine.load()

ayah = engine.quran.ayah(2, 255)
print(ayah.text_arabic)

for sp in engine.tajweed(2, 255):
    print(sp.rule, sp.color, sp.text)

from quran_engine import surah_audio_url
r = next(r for r in engine.reciters.all() if r.name == "Mishary Alafasy")
print(surah_audio_url(r, 2))
```

## The seven features

Build them in any order — each stands alone:

1. **[Quran](01-quran.md)** — the text, translations, and 7 alternate readings.
2. **[Tajweed](02-tajweed.md)** — color the recitation rules. The hard part, solved for you.
3. **[Juz & Page](03-juz-page.md)** — navigate by para and mushaf page.
4. **[Surah recitations](04-surah-recitations.md)** — full-surah audio from 60+ reciters.
5. **[Ayah recitations](05-ayah-recitations.md)** — verse-by-verse audio.
6. **[Search](06-ayah-search.md)** — Arabic, English, references, boolean.
7. **[Sorting](07-surah-sorting.md)** — order and filter the 114 surahs.

Plus **[caching](08-caching.md)** for offline audio.

## New to the terminology?

If words like *ayah, juz, riwayah, ghunnah, ikhfaa, madd* are unfamiliar, skim the
**[glossary](glossary.md)** first — it explains every term in plain English.

## Next steps

- Read the [architecture](architecture.md) to understand how the pieces fit.
- Browse [recipes](recipes.md) for copy-paste solutions to common tasks.
- Check the [FAQ](faq.md) for licensing, data size, offline use, and accuracy questions.
