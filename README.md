<a href="https://apps.apple.com/us/app/al-islam-islamic-pillars/id6449729655?platform=iphone">
  <img src="Logo.png" alt="Logo" width="120" style="border-radius:10px;"/>
</a>

# Quran Tajweed Engine

**An open-source, offline-first, framework-agnostic Quran engine.** Complete Quran text, *correct* pre-computed tajweed coloring for every ayah, juz/page navigation, surah & ayah recitations, full-text search, sorting, and offline caching — shipped as **portable data + precise specifications + reference implementations in 7 languages**, so anyone can build a Quran app in *any* language or framework: iOS, Android, web, React Native, Flutter, Node, Deno, Bun, Python, Go, Rust — whatever you use. No network required; everything ships in the box.

> Data and algorithms are extracted, with attribution, from the open-source **[Al-Islam | Islamic Pillars](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars)** app by **Abubakr Elmallah**. This repository repackages them as a standalone, reusable engine. See [CREDITS.md](CREDITS.md).

## At a glance

| | |
|---|---|
| **6,236** ayahs | **114** surahs |
| **113,642** pre-computed tajweed annotations | **17** tajweed rule categories |
| **62** reciters | **8** riwayat |
| **7** alternate qiraat readings | **7** language ports |
| **3** Quran fonts (Uthmani / Qiraat / Indopak) | **99** Names of Allah |
| 2 English translations + transliteration | 100% offline · zero runtime deps (JS) |

---

## Why this exists

**Most Quran apps re-solve the same hard problems:** a clean Uthmani dataset, *correct* tajweed coloring — the genuinely difficult part — juz/page boundaries, reciter feeds, and diacritic-aware search. The tajweed in particular is the hard one, so this engine ships it **pre-computed for all 6,236 ayahs (113,642 annotated spans)**, eliminating the single most error-prone piece of building a Quran application. You get all of it as:

1. **Data** — JSON any language can read. This is the heart of the engine.
2. **Specs** — every feature documented precisely enough to reimplement from scratch.
3. **Reference code** — working implementations in **7 languages** you can use directly or read as the executable spec.

**New here? → start with [docs/00-getting-started.md](docs/00-getting-started.md).** New to the terms (ayah, juz, ghunnah, madd…)? → the [glossary](docs/glossary.md) explains everything.

## What's inside

```
Quran Tajweed Engine/
├── data/                       ← canonical data (language-agnostic; the core deliverable)
│   ├── quran.json              114 surahs · 6236 ayahs · Arabic + 2 English + transliteration
│   ├── surah-info.json         "About this surah" (Maududi, Ibn Ashur)
│   ├── names-of-allah.json     99 Names of Allah
│   ├── juz.json                30 juz boundaries
│   ├── reciters.json           62 reciters across 8 riwayat
│   ├── tajweed-rules.json      rule catalogue: categories, colors, trigger letters
│   ├── tajweed-annotations.json  pre-computed tajweed spans for all 6236 ayahs (113,642 spans)
│   ├── arabic-alphabet.json    letters (+tajweed weight), numbers, tashkeel, waqf stopping signs
│   ├── fonts/                  Uthmani, Qiraat, Indopak TTFs + fonts.json
│   ├── qiraat/                 7 alternate readings (Warsh, Qaloon, Duri, Susi, Bazzi, Qunbul, Shubah)
│   ├── surahs/                 per-surah split (NNN.json) + lightweight index.json
│   └── tajweed/                per-surah pre-computed tajweed (NNN.json)
├── docs/                       ← comprehensive documentation
│   ├── 00-getting-started · architecture · glossary · faq · recipes · PORTING
│   ├── fonts · arabic-alphabet · tajweed-rules-explained · tajweed-rules-reference
│   ├── 01-quran … 08-caching   per-feature specifications
│   └── integration/            web · react-native · flutter · ios · android · server
├── scripts/                    ← build-data.mjs · generate-tajweed.mjs (single-source codegen)
├── packages/                   ← reference implementations (7 languages)
│   ├── quran-engine-js/        JavaScript / TypeScript (reference, full tajweed detector)
│   ├── quran-engine-py/        Python
│   ├── quran-engine-swift/     Swift (SwiftPM)
│   ├── quran-engine-kotlin/    Kotlin / Android
│   ├── quran-engine-dart/      Dart / Flutter
│   ├── quran-engine-go/        Go
│   └── quran-engine-rust/      Rust
├── examples/                   ← runnable demos (node, terminal tajweed, browser, React)
└── scripts/                    ← build-data.mjs (regenerates derived data)
```

## Engine modules

Each module is implemented, tested, and stands alone — adopt them independently or all at once:

| Module | What it does | This engine |
|---|---|---|
| Quran text | 6,236 ayahs, Arabic + 2 English + transliteration | ✓ |
| Tajweed | pre-computed coloring, 17 rule categories | ✓ |
| Qiraat | 7 alternate readings | ✓ |
| Juz / Page | mushaf navigation | ✓ |
| Audio | 62 reciters, surah + ayah feeds | ✓ |
| Search | Arabic / English / references / boolean | ✓ |
| Sorting | 6 sort & filter modes over the 114 | ✓ |
| Offline caching | download-path helpers, no network needed | ✓ |
| Multi-language | reference ports | 7 |
| Framework-agnostic | plain JSON, any stack | ✓ |

Per-feature specifications, in priority order:

1. **Quran** — text, translations, qiraat → [docs/01](docs/01-quran.md)
2. **Tajweed** — scalar-driven rule coloring → [docs/02](docs/02-tajweed.md)
3. **Juz / Page** — mushaf navigation → [docs/03](docs/03-juz-page.md)
4. **Surah recitations** — full-surah audio → [docs/04](docs/04-surah-recitations.md)
5. **Ayah recitations** — ayah-by-ayah audio → [docs/05](docs/05-ayah-recitations.md)
6. **Ayah search** — Arabic/English, references, boolean → [docs/06](docs/06-ayah-search.md)
7. **Surah sorting** — sort & filter the 114 → [docs/07](docs/07-surah-sorting.md)
8. **Caching** — offline downloads → [docs/08](docs/08-caching.md)

**Plus:** bundled Quran [**fonts**](docs/fonts.md) (Uthmani / Qiraat / Indopak), an [**Arabic-alphabet**](docs/arabic-alphabet.md) reference (letters, tashkeel, waqf signs), and a detailed [**tajweed rules explained**](docs/tajweed-rules-explained.md) guide ("what does *idgham* mean?").

## One source of truth → seven implementations

One of the coolest engineering pieces: the entire tajweed rule catalogue (colors, trigger letters, meanings) lives in a single file — [`data/tajweed-rules.json`](data/tajweed-rules.json). **Edit one JSON file, run `node scripts/generate-tajweed.mjs`, and the per-language constants in all 7 ports** plus [docs/tajweed-rules-reference.md](docs/tajweed-rules-reference.md) regenerate together. Change one file → everything stays in lockstep.

## Language ports

One [shared contract](docs/PORTING.md); the same API everywhere. Verified ports run a test asserting the canonical reference cases (6236 ayahs, audio URLs, juz boundaries, sort order, `2:255` parsing, tajweed UTF-16 reconstruction).

| Language | Package | Notes |
|---|---|---|
| JavaScript / TypeScript | [`quran-engine-js`](packages/quran-engine-js) | reference · full tajweed detector · 18 tests ✓ |
| Python | [`quran-engine-py`](packages/quran-engine-py) | pure stdlib · 9 tests ✓ |
| Swift | [`quran-engine-swift`](packages/quran-engine-swift) | SwiftPM · 14 tests ✓ |
| Go | [`quran-engine-go`](packages/quran-engine-go) | module · 10 tests ✓ |
| Rust | [`quran-engine-rust`](packages/quran-engine-rust) | crate · 10 tests + doctest ✓ |
| Kotlin | [`quran-engine-kotlin`](packages/quran-engine-kotlin) | JVM / Android · kotlinx-serialization |
| Dart | [`quran-engine-dart`](packages/quran-engine-dart) | Dart / Flutter |

## Quick start

**JavaScript:**
```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();
engine.quran.ayah(2, 255).textArabic;                 // Ayat al-Kursi
engine.tajweed(engine.quran.ayah(2, 255).textArabic); // colored tajweed spans
engine.search.searchVerses("the throne");
```

**Python:**
```python
from quran_engine import Engine
engine = Engine.load()
engine.quran.ayah(2, 255).text_arabic
[ (sp.rule, sp.color, sp.text) for sp in engine.tajweed(2, 255) ]
```

**Swift / Kotlin / Dart / Go / Rust** — see each package README. Pick your platform in the [getting-started guide](docs/00-getting-started.md#pick-your-path) or the [integration guides](docs/integration/).

Try it now (the terminal demo prints the ayah with real color-coded tajweed):
```bash
node examples/node-quickstart.mjs          # full feature tour, printed
node examples/tajweed-terminal.mjs 112      # tajweed rendered in your terminal, in color
```

## Performance

Everything runs locally with no network calls. Indicative figures from the JavaScript port (Node 24, Apple Silicon — your numbers will vary):

- **Full engine load:** ~0.8 s to parse the entire Quran and build the in-memory search index over all 6,236 ayahs (qiraat and surah-info are opt-in, not loaded by default).
- **Tajweed coloring:** ~0.1 ms per ayah with the live detector; instant when reading the pre-computed `tajweed-annotations.json` corpus.
- **Search:** single-digit milliseconds for a full Arabic/English query across the whole Quran.
- **On-disk data:** `quran.json` ~5 MB · `tajweed-annotations.json` ~5 MB (113,642 spans) · whole `data/` directory ~37 MB including all qiraat, fonts, and per-surah splits.

## Modular architecture

One comprehensive engine with feature submodules you pull in à la carte. Within each language port, every feature is a separate module (`quran`, `tajweed`, `juzPage`, `audio`, `search`, `sorting`, `cache`) — import only what you need. The `data/` directory is the shared substrate every submodule and every language port reads from. See [architecture.md](docs/architecture.md).

## Using the data from any language

The data is plain UTF-8 JSON — load it natively and follow the specs. The one cross-language subtlety is that tajweed offsets are UTF-16 units (trivial in JS/Swift/Kotlin/Dart, a one-line convert in Python/Go/Rust). Full details: [docs/PORTING.md](docs/PORTING.md).

## Apps by the author

- [**Al-Islam | Islamic Pillars**](https://github.com/TheAbubakrAbu/Al-Islam-iOS)
- [**Al-Adhan | Prayer Times**](https://github.com/TheAbubakrAbu/Al-Adhan-iOS)
- [**Al-Quran | Beginner Quran**](https://github.com/TheAbubakrAbu/Al-Quran-iOS)

## License & attribution

MIT — see [LICENSE](LICENSE). Use, modify, and redistribute freely, **with attribution**. Credit this engine and the upstream Al-Islam project, and preserve the provenance in [CREDITS.md](CREDITS.md). The Quran text is sacred — keep it unmodified.

## Contributing

New language ports, better tajweed accuracy, more data, and examples are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## A note on intent

This project — like the apps it draws from, **[Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars)**, **[Al-Adhan](https://github.com/TheAbubakrAbu/Al-Adhan-Prayer-Times)**, and **[Al-Quran](https://github.com/TheAbubakrAbu/Al-Quran-Beginner-Quran)** — is offered as *sadaqah jariyah*: a continuing charity for the benefit of the Muslim community and anyone building tools to read, learn, and listen to the Quran. If it helps you, please keep the chain of attribution intact and consider contributing improvements back, so the reward continues for everyone who came before you.

> *"When a person dies, all their deeds end except three: a continuing charity (sadaqah jariyah), beneficial knowledge, or a righteous child who prays for them."* — Prophet Muhammad ﷺ (Sahih Muslim)
