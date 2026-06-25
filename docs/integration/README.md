# Integration guides

Platform-by-platform guides for dropping the **Quran Tajweed Engine** into a real app. Each guide covers
install/setup, a minimal working sample, a tajweed-rendering snippet, an audio snippet, and links back to
the per-feature specs.

All of them read the same canonical JSON in [`/data`](../../data) — see
[getting started](../00-getting-started.md) and the [architecture](../architecture.md) for the big picture.

| Guide | Stack | Package |
|---|---|---|
| [web.md](web.md) | Browser / bundler (Vite, webpack) + vanilla JS, React | `quran-engine-js` |
| [react-native.md](react-native.md) | React Native / Expo (Hermes) with bundled or CDN data | `quran-engine-js` |
| [flutter.md](flutter.md) | Flutter — asset-bundled data, `RichText` tajweed, `just_audio` | `quran-engine-dart` |
| [ios.md](ios.md) | SwiftUI — SwiftPM, `AttributedString` tajweed, `AVPlayer` | `quran-engine-swift` |
| [android.md](android.md) | Jetpack Compose — `AnnotatedString` tajweed, `ExoPlayer` | `quran-engine-kotlin` |
| [server.md](server.md) | Node / Deno / Bun + Go / Rust / Python JSON HTTP APIs | `quran-engine-js` / `-go` / `-rust` / `-py` |

**One-liners**

- **[web.md](web.md)** — Import the JSON, `createEngine`, lazy-load per-surah files, render colored tajweed spans, search, and an `<audio>` player; framework-agnostic + a React hook component.
- **[react-native.md](react-native.md)** — Bundle JSON as assets or pull from a CDN; the Hermes `Intl.Segmenter` caveat (prefer the corpus), `expo-av` audio, and an `expo-file-system` `CacheStore`.
- **[flutter.md](flutter.md)** — Bundle `/data` via `pubspec` assets, `Engine.fromJson`, `RichText`/`TextSpan` from tajweed spans, `just_audio`.
- **[ios.md](ios.md)** — Add the SwiftPM package, point the loader at bundled `/data`, `AttributedString` from tajweed spans, `AVPlayer`.
- **[android.md](android.md)** — Add the module, load data from `assets/`, `buildAnnotatedString` with `SpanStyle` colors, `ExoPlayer`.
- **[server.md](server.md)** — Build a tiny JSON HTTP API (`/surah/:id`, `/ayah/:s/:a`, `/search`, `/audio/...`) in Node, with equivalent notes for Go / Rust / Python.

## See also

- [recipes.md](../recipes.md) — copy-paste solutions to common tasks.
- [PORTING.md](../PORTING.md) — the shared contract every language port follows.
- Feature specs: [01-quran](../01-quran.md) · [02-tajweed](../02-tajweed.md) · [03-juz-page](../03-juz-page.md) · [04-surah-recitations](../04-surah-recitations.md) · [05-ayah-recitations](../05-ayah-recitations.md) · [06-ayah-search](../06-ayah-search.md) · [07-surah-sorting](../07-surah-sorting.md) · [08-caching](../08-caching.md).
