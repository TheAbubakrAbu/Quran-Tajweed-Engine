# Changelog

All notable changes to the Quran Tajweed Engine are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] — Initial release

The first public version: a complete, framework-agnostic Quran engine.

### Data (`/data`)
- `quran.json` — 114 surahs / 6236 ayahs: Hafs Uthmani Arabic, transliteration, two English translations
  (Saheeh International, Mustafa Khattab), per-ayah juz/page/word/letter counts.
- `surah-info.json` — "About this surah" essays (Maududi, Ibn Ashur).
- `names-of-allah.json` — the 99 Names of Allah.
- `qiraat/qiraah-*.json` — 7 alternate readings (Warsh, Qaloon, Duri, Susi, Bazzi, Qunbul, Shubah).
- `juz.json` — 30 juz boundaries (derived).
- `reciters.json` — 62 reciters across 8 riwayat (derived).
- `tajweed-rules.json` — 17-category rule catalogue with canonical colors and trigger letters (derived).
- `tajweed-annotations.json` + `tajweed/NNN.json` — pre-computed tajweed spans for all 6236 ayahs (113,642 spans).
- `surahs/NNN.json` + `surahs/index.json` — per-surah split for lazy/web loading.

### Specifications (`/docs`)
- Getting started, architecture, glossary, FAQ, recipes, and the porting contract.
- Per-feature specs 01–08: Quran, Tajweed, Juz/Page, Surah recitations, Ayah recitations, Search,
  Sorting, Caching.
- Platform integration guides.

### Language ports (`/packages`)
- **JavaScript/TypeScript** (`quran-engine-js`) — reference implementation, full tajweed detector, 18 tests.
- **Python** (`quran-engine-py`) — pure stdlib, 9 tests.
- **Swift** (`quran-engine-swift`) — Swift Package, 14 tests.
- **Go** (`quran-engine-go`) — module, 10 tests.
- **Rust** (`quran-engine-rust`) — crate, 10 tests + doctest.
- **Kotlin** (`quran-engine-kotlin`) — JVM/Android, kotlinx-serialization.
- **Dart** (`quran-engine-dart`) — Dart/Flutter.

### Features
- Quran browsing (surahs, ayahs, translations, qiraat text, global ayah number).
- Tajweed coloring — two strategies: consume the annotation corpus, or run the JS detector.
- Juz & mushaf-page navigation.
- Full-surah and ayah-by-ayah recitation URL builders (60+ reciters) with Minshawi fallback.
- Search — Arabic (diacritic-folded, optional silent-letter mode), English, references, boolean grammar (JS).
- Surah sorting (6 modes) and Makkan/Madinan filtering.
- Offline-audio caching helpers (paths + `AudioCache` in JS).

### Known limitations
- Tajweed detector simplifies full final-`ر` vowel context and muqatta'at lazim-harfi sub-typing
  (see [docs/02-tajweed.md](docs/02-tajweed.md)).
- Boolean search grammar is implemented in the JS port; native ports implement the core search path.
- No audio files are bundled; the engine builds URLs to third-party CDNs.
