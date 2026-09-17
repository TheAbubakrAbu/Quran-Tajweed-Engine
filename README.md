# Quran Tajweed Engine

**An open-source, offline-first, framework-agnostic Quran engine.** Complete Quran text, *correct* pre-computed tajweed coloring for every ayah, juz/page navigation, surah & ayah recitations, full-text search, sorting, and offline caching — shipped as **portable data + precise specifications + reference implementations in 7 languages**, so anyone can build a Quran app in *any* language or framework: iOS, Android, web, React Native, Flutter, Node, Deno, Bun, Python, Go, Rust — whatever you use. No network required; everything ships in the box.

> Data and algorithms are extracted, with attribution, from the open-source **[Al-Islam | Islamic Pillars](https://github.com/TheAbubakrAbu/Al-Islam-iOS)** app by **Abubakr Elmallah**. This repository repackages them as a standalone, reusable engine. See [CREDITS.md](CREDITS.md).

<a href="https://apps.apple.com/us/app/al-islam-islamic-pillars/id6449729655?platform=iphone">
  <img src="Logo.png" alt="Logo" width="120" style="border-radius:10px;"/>
</a>

## At a glance

| | |
|---|---|
| **6,236** ayahs | **114** surahs |
| **113,611** pre-computed tajweed annotations | **17** tajweed rule categories |
| **62** reciters | **20** riwayat, as page-exact printed mushafs |
| **7** alternate qiraat readings | **7** riwayah tajweed packs (where a reading differs from Hafs) |
| **77,629** words glossed **and** transliterated | **323** curated themes · **5,446** ayahs with similar-ayah matches |
| **77,629** words with **root and lemma** | **814** repeated phrases · **2,512** QUL topics · **1,049** passage themes |
| **1,634** qiraat variant junctures with attribution | **60** hizb · **558** ruku · **7** manzil |
| **3** Quran fonts (Uthmani / Qiraat / Indopak) | **99** Names of Allah |
| 2 English translations + transliteration | **7** language ports |
| Retrieval + prompt for a grounded "Ask AI" | 100% offline · zero runtime deps (JS) |

---

## Why this exists

**Most Quran apps re-solve the same hard problems:** a clean Uthmani dataset, *correct* tajweed coloring — the genuinely difficult part — juz/page boundaries, reciter feeds, and diacritic-aware search. The tajweed in particular is the hard one, so this engine ships it **pre-computed for all 6,236 ayahs (113,611 annotated spans)**, eliminating the single most error-prone piece of building a Quran application. You get all of it as:

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
│   ├── muqattaat.json          disconnected opening letters (29 surahs) + vocalized names
│   ├── juz.json                30 juz boundaries
│   ├── reciters.json           62 reciters across 8 riwayat
│   ├── tajweed-rules.json      rule catalogue: categories, colors, trigger letters
│   ├── tajweed-annotations.json  pre-computed tajweed spans for all 6236 ayahs (113,611 spans)
│   ├── arabic-alphabet.json    letters (+tajweed weight), numbers, tashkeel, waqf stopping signs
│   ├── fonts/                  Uthmani, Qiraat, Indopak TTFs + fonts.json
│   ├── qiraat/                 7 alternate readings (Warsh, Qaloon, Duri, Susi, Bazzi, Qunbul, Shubah)
│   ├── qiraat-counts.json      per-riwayah ayah counts → existsInQiraah / numberOfAyahs(for:)
│   ├── mushaf/                 20 printed mushafs (604-page facsimiles) + per-riwayah page & line tables
│   ├── tajweed-qiraat/         where each reading differs from Hafs, + the shared rule catalogue
│   ├── word-by-word.json       77,629 words: English gloss + Latin transliteration, token-aligned
│   ├── similar-ayahs.json      mutashabihat: 5,446 ayahs with their matches, pre-ranked; shared words as spans
│   ├── themes.json             323 curated topics, each with its ayahs
│   ├── tajweed-lessons.json    the 10-chapter tajweed course
│   ├── morphology.json         root + lemma of all 77,629 words (Quranic Arabic Corpus via QUL)
│   ├── mutashabihat.json       814 repeated phrases and every ayah carrying each
│   ├── quran-topics.json       2,512 QUL topics in three independent indexes
│   ├── ayah-themes.json        1,049 passage themes, one sentence per run of ayahs
│   ├── quran-metadata.json     hizb, ruku and manzil boundaries
│   ├── qiraat-variants.json    who among the Ten reads which form, and why it matters
│   ├── qiraat-places.json      where each published riwayah differs from Hafs at all
│   ├── qiraat-variant-audio.json  one reciter reading a verse both ways (4 riwayat)
│   ├── word-of-day.json        149 curated words with every occurrence of the form
│   ├── surah-sections.json     per-surah section outlines · surah-stats.json  counts
│   ├── surahs/                 per-surah split (NNN.json) + lightweight index.json
│   └── tajweed/                per-surah pre-computed tajweed (NNN.json)
├── docs/                       ← comprehensive documentation
│   ├── 00-getting-started · architecture · glossary · faq · recipes · PORTING
│   ├── fonts · arabic-alphabet · tajweed-rules-explained · tajweed-rules-reference
│   ├── 01-quran … 17-qiraat…  per-feature specifications
│   └── integration/            web · react-native · flutter · ios · android · server
├── scripts/                    ← build-data.mjs · generate-tajweed.mjs (single-source codegen)
│   ├── import-al-islam-data.py extracts the newer corpora out of the app's compressed packs
│   └── al-islam/               the app's own build tooling, for provenance (see its README)
├── packages/                   ← reference implementations (7 languages)
│   ├── quran-engine-js/        JavaScript / TypeScript (reference, full tajweed detector)
│   ├── quran-engine-py/        Python
│   ├── quran-engine-swift/     Swift (SwiftPM)
│   ├── quran-engine-kotlin/    Kotlin / Android
│   ├── quran-engine-dart/      Dart / Flutter
│   ├── quran-engine-go/        Go
│   └── quran-engine-rust/      Rust
├── examples/                   ← runnable demos (node, terminal tajweed, browser, React)
└── sources/                    ← upstream JSON the data was built from (provenance, not API)
    ├── Quran.json · SurahInfos.json · NamesOfAllah.json · Qiraat/ · QUL/
    └── Qiraat/_staging-riwayat/  the 12 beta riwayat + the extraction pipeline
```

## Engine modules

Each module is implemented, tested, and stands alone — adopt them independently or all at once:

| Module | What it does | This engine |
|---|---|---|
| Quran text | 6,236 ayahs, Arabic + 2 English + transliteration | ✓ |
| Tajweed | pre-computed coloring, 17 rule categories | ✓ |
| Qiraat | 7 alternate readings | ✓ |
| Printed mushaf | 20 riwayat as 604-page facsimiles + their own page tables | ✓ |
| Riwayah tajweed | where a reading differs from Hafs, and why | 7 packs |
| Word by word | gloss + transliteration, aligned to the ayah's own tokens | ✓ |
| Similar ayahs | mutashabihat, verified + generated, pre-ranked | ✓ |
| Themes | 323 curated topics, indexed both ways | ✓ |
| Surah sections | 741 titled passages across 111 surahs, nested | ✓ |
| Arabic alphabet | 28 letters with tajweed weight, tashkeel, waqf signs | ✓ |
| Qiraat comparison | two readings aligned word by word, three buckets | ✓ |
| Morphology | root + lemma of every word, searchable by root | ✓ |
| Mutashabihat | 814 repeated phrases, with the shared tokens | ✓ |
| QUL topics | 2,512 topics in three indexes + 1,049 passage themes | ✓ |
| Mushaf divisions | hizb, ruku, manzil | ✓ |
| Qiraat variants | who among the Ten reads what, and what it means | ✓ |
| Word of the day | 149 curated words with every occurrence | ✓ |
| Tajweed course | 10 chapters, 57 lessons with drills | ✓ |
| Juz / Page | mushaf navigation | ✓ |
| Audio | 62 reciters, surah + ayah feeds | ✓ |
| Search | Arabic / English / references / boolean | ✓ |
| Meaning search | word-vector MaxSim, bring your own embedder | ✓ |
| Ask AI | retrieval lanes + the grounded prompt (no model shipped) | ✓ |
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
9. **The printed mushaf** — 20 facsimiles, per-riwayah pagination → [docs/10](docs/10-mushaf.md)
10. **Riwayah tajweed** — where a reading differs from Hafs → [docs/11](docs/11-qiraat-tajweed.md)
11. **Word by word** — gloss + transliteration → [docs/12](docs/12-word-by-word.md)
12. **Similar ayahs, themes, lessons** → [docs/13](docs/13-similar-and-themes.md)
13. **Ask AI** — retrieval, meaning search, the prompt → [docs/14](docs/14-ask-ai.md)
14. **Surah sections** — where a surah changes subject → [docs/15](docs/15-surah-sections.md)
15. **Arabic alphabet** — letters, weights, tashkeel, waqf signs → [docs/16](docs/16-arabic-alphabet.md)
16. **Qiraat comparison** — how far apart two readings are, measured → [docs/17](docs/17-qiraat-comparison.md)
17. **Morphology** — root and lemma of every word → [docs/18](docs/18-morphology.md)
18. **Mutashabihat** — the phrases the Quran repeats → [docs/19](docs/19-mutashabihat.md)
19. **Topics, passages and divisions** — three ways of saying where you are → [docs/20](docs/20-topics-and-metadata.md)
20. **Qiraat variants** — who reads what, and what it means → [docs/21](docs/21-qiraat-variants.md)
21. **Word of the day** — curated vocabulary with every occurrence → [docs/22](docs/22-word-of-day.md)
22. **The 99 Names in depth** — roots, themes, explanations and where each Name appears → [docs/23](docs/23-names-depth.md)
23. **Chains of transmission** — the isnād of each of the Ten Readings → [docs/24](docs/24-isnad.md)
24. **Scientific miracles**: 202 articles, each anchored to the ayahs it rests on → [docs/25](docs/25-miracles.md)

**Plus:** bundled Quran [**fonts**](docs/fonts.md) (Uthmani / Qiraat / Indopak), the [**alphabet data file**](docs/arabic-alphabet.md) documented field by field, and a detailed [**tajweed rules explained**](docs/tajweed-rules-explained.md) guide ("what does *idgham* mean?").

**[What's new](docs/whats-new.md)**, what each release added, newest first. The long version is [CHANGELOG.md](CHANGELOG.md).

## One source of truth → seven implementations

One of the coolest engineering pieces: the entire tajweed rule catalogue (colors, trigger letters, meanings) lives in a single file — [`data/tajweed-rules.json`](data/tajweed-rules.json). **Edit one JSON file, run `node scripts/generate-tajweed.mjs`, and the per-language constants in all 7 ports** plus [docs/tajweed-rules-reference.md](docs/tajweed-rules-reference.md) regenerate together. Change one file → everything stays in lockstep.

## Language ports

One [shared contract](docs/PORTING.md); the same API everywhere. Verified ports run a test asserting the canonical reference cases (6236 ayahs, audio URLs, juz boundaries, sort order, `2:255` parsing, tajweed UTF-16 reconstruction).

| Language | Package | Core | Beyond the core |
|---|---|---|---|
| JavaScript / TypeScript | [`quran-engine-js`](packages/quran-engine-js) | reference · full tajweed detector · 71 tests ✓ | ✓ |
| Python | [`quran-engine-py`](packages/quran-engine-py) | pure stdlib ✓ | ✓ |
| Swift | [`quran-engine-swift`](packages/quran-engine-swift) | SwiftPM · 56 tests ✓ | ✓ |
| Rust | [`quran-engine-rust`](packages/quran-engine-rust) | crate · 58 tests + doctests ✓ | ✓ |
| Go | [`quran-engine-go`](packages/quran-engine-go) | module · 56 tests ✓ | ✓ |
| Kotlin | [`quran-engine-kotlin`](packages/quran-engine-kotlin) | JVM / Android · kotlinx-serialization · 54 tests ✓ | ✓ |
| Dart | [`quran-engine-dart`](packages/quran-engine-dart) | Dart / Flutter · 55 tests ✓ | ✓ |

Every module is in every port, each with a parity suite translated case for case, so a divergence fails a test instead of surprising an app. See [docs/PORTING.md](docs/PORTING.md#module-coverage-per-port).

## Quick start

**JavaScript:**
```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();
engine.quran.ayah(2, 255).textArabic;                 // Ayat al-Kursi
engine.tajweed(engine.quran.ayah(2, 255).textArabic); // colored tajweed spans
engine.search.searchVerses("the throne");
engine.askAI.retrieve("what does the Quran say about patience in hardship");
```

```js
// The heavier corpora are opt-in.
const engine = await loadFromDisk({ loadMushaf: true, loadWordByWord: true, loadQiraatTajweed: true });
engine.mushaf.page(2, 255, "warsh");                  // the page Warsh's own print puts it on
engine.wordByWord.words(112, 1);                      // [{ arabic, english, transliteration }, …]
engine.qiraatTajweed.wordRules(2, 3, "warsh");        // what Warsh reads differently here
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
- **On-disk data:** `quran.json` ~5 MB · `tajweed-annotations.json` ~5 MB (113,611 spans) · whole `data/` directory ~67 MB including all qiraat, fonts, per-surah splits, and the 20 printed-mushaf facsimiles (~23 MB of those, and the engine never loads them itself).

## Modular architecture

One comprehensive engine with feature submodules you pull in à la carte. Within each language port, every feature is a separate module (`quran`, `tajweed`, `juzPage`, `audio`, `search`, `sorting`, `cache`) — import only what you need. The `data/` directory is the shared substrate every submodule and every language port reads from. See [architecture.md](docs/architecture.md).

## Using the data from any language

The data is plain UTF-8 JSON — load it natively and follow the specs. The one cross-language subtlety is that tajweed offsets are UTF-16 units (trivial in JS/Swift/Kotlin/Dart, a one-line convert in Python/Go/Rust). Full details: [docs/PORTING.md](docs/PORTING.md).

## The Al-Islamic Apps

Five repositories by the same author: three apps, and the two engines the apps are built on. Everything is free, offline-first, and open source.

**Apps**

- [**Al-Islam | Islamic Pillars**](https://github.com/TheAbubakrAbu/Al-Islam-iOS) — prayer times, the Quran, hadith, tafsir, and the Islamic essentials in one app
- [**Al-Adhan | Prayer Times**](https://github.com/TheAbubakrAbu/Al-Adhan-iOS) — prayer times, adhan notifications, and the Qibla
- [**Al-Quran | Beginner Quran**](https://github.com/TheAbubakrAbu/Al-Quran-iOS) — the Quran for beginners and Arabic learners

**Engines** — the data layers behind those apps, extracted so anyone can build on them in any language

- [**Quran Tajweed Engine**](https://github.com/TheAbubakrAbu/Quran-Tajweed-Engine) — *this repository*. 6,236 ayahs with pre-computed tajweed, qiraat, and recitations
- [**Hadith JSON Engine**](https://github.com/TheAbubakrAbu/Hadith-JSON-Engine) — the same idea for hadith: 50,884 hadiths across 17 collections, repaired, graded, cited, and packed

## License & attribution

MIT — see [LICENSE](LICENSE). Use, modify, and redistribute freely, **with attribution**. Credit this engine and the upstream Al-Islam project, and preserve the provenance in [CREDITS.md](CREDITS.md). The Quran text is sacred — keep it unmodified.

## Contributing

New language ports, better tajweed accuracy, more data, and examples are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## A note on intent

This project — like the apps it draws from, **[Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-iOS)**, **[Al-Adhan](https://github.com/TheAbubakrAbu/Al-Adhan-iOS)**, and **[Al-Quran](https://github.com/TheAbubakrAbu/Al-Quran-iOS)**, and its sibling the **[Hadith JSON Engine](https://github.com/TheAbubakrAbu/Hadith-JSON-Engine)** — is offered as *sadaqah jariyah*: a continuing charity for the benefit of the Muslim community and anyone building tools to read, learn, and listen to the Quran. If it helps you, please keep the chain of attribution intact and consider contributing improvements back, so the reward continues for everyone who came before you.

> *"When a person dies, all their deeds end except three: a continuing charity (sadaqah jariyah), beneficial knowledge, or a righteous child who prays for them."* — Prophet Muhammad ﷺ (Sahih Muslim)
