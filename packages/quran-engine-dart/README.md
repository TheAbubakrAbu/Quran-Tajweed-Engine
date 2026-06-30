# quran_engine (Dart / Flutter)

The Dart port of the **Quran Tajweed Engine**. A thin, idiomatic, data-driven wrapper over the JSON corpus in the repo `/data` directory. It follows the shared contract in [`../../docs/PORTING.md`](../../docs/PORTING.md) so the API feels the same across every language port.

**The data is the engine.** No network call, database, or framework is required at runtime — the engine constructs audio URLs but never fetches or bundles audio.

## Install

This package lives in the monorepo at `packages/quran-engine-dart`. Use a path dependency:

```yaml
dependencies:
  quran_engine:
    path: ../quran-engine-dart
```

## Usage (Dart VM)

`Engine.load` reads the JSON from disk via `dart:io`. With no argument it locates the repo `/data` by walking up from `Directory.current` until it finds `data/quran.json`; pass `dataDir:` to override.

```dart
import 'package:quran_engine/quran_engine.dart';

Future<void> main() async {
  final engine = await Engine.load(); // or Engine.load(dataDir: '/path/to/data')

  engine.surah(1)!.nameEnglish;            // "The Opener"
  engine.quran.totalAyahs;                 // 6236
  engine.globalAyahNumber(2, 1);           // 8
  engine.juz(30)!.endSurah;                // 114

  // Tajweed colored spans (strategy A: pre-computed annotation corpus).
  for (final span in engine.tajweedSpans(1, 1)) {
    print('${span.text}  ${span.rule}  ${span.colorHex}');
  }

  // Audio URLs (free functions).
  final reciter = engine.reciters.byQiraah('hafs').first;
  surahAudioUrl(reciter, 1);               // ".../001.mp3"
  ayahAudioUrl(reciter, engine.globalAyahNumber(1, 1));

  // Sorting & search.
  sortSurahs(engine.quran.all(), 'ayahs', 'descending').first.id; // 2
  engine.search.parseReference('2:255');   // Reference(surah: 2, ayah: 255)
  engine.search.searchVerses('mercy');     // mushaf-order verse hits
}
```

## Usage (Flutter, asset-bundled data)

In Flutter apps you typically bundle the `/data` JSON as assets and load it via `rootBundle`, then feed the already-decoded maps into `Engine.fromJson`. This needs no `dart:io` file access.

```yaml
# pubspec.yaml of your app
flutter:
  assets:
    - assets/data/quran.json
    - assets/data/juz.json
    - assets/data/reciters.json
    - assets/data/tajweed-rules.json
    - assets/data/tajweed-annotations.json
```

```dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:quran_engine/quran_engine.dart';

Future<Engine> buildEngine() async {
  Future<dynamic> j(String p) async =>
      jsonDecode(await rootBundle.loadString('assets/data/$p'));

  return Engine.fromJson(
    quranJson: await j('quran.json') as List,
    juzJson: await j('juz.json') as List,
    recitersJson: await j('reciters.json') as List,
    tajweedRulesJson: await j('tajweed-rules.json') as Map<String, dynamic>,
    tajweedAnnotationsJson: await j('tajweed-annotations.json') as List,
  );
}
```

## What this port provides

| Area | API |
|---|---|
| Quran | `Quran.surah`, `.ayah`, `.globalAyahNumber`, `.arabicText`, `.cleanArabicText`, `.eachAyah` |
| Tajweed | `Tajweed.tajweedSpans(surah, ayah)` → `List<TajweedSpan>` (strategy A) |
| Juz / Page | `JuzPage.juz`, `.ayahsInJuz`, `.ayahsOnPage`, `.firstAyahOfJuz`, `.firstAyahOfPage`, `.juzForAyah`, `.pageForAyah`, `.totalPages` |
| Surah audio | `surahAudioUrl(reciter, surah)` |
| Ayah audio | `ayahAudioUrl(reciter, globalAyah)` |
| Search | `Search.searchVerses`, `.searchSurahs`, `.parseReference` |
| Sorting | `sortSurahs(surahs, mode, direction)`, `filterByRevelationType` |
| Caching | `localSurahPath(reciter, surah)`, `sanitizeReciterDir(id)`, `sharedAudioPath` |

Models — `Surah`, `Ayah`, `JuzEntry`, `Reciter`, `TajweedSpan` — each have a `fromJson` factory matching the camelCase JSON keys.

### Tajweed strategy (A)

Tajweed colors come from the pre-computed corpus: `tajweed-annotations.json` provides per-ayah `{start, end, rule}` annotations, and each `rule` maps to a `colorHex` from `tajweed-rules.json → categories[]`. Annotation `start`/`end` are **UTF-16 code-unit offsets**. Dart `String`s are UTF-16, so `text.substring(start, end)` slices them directly — no conversion needed.

### Search scope (what is omitted)

This port implements the **core search path**: substring matching plus phrase-prefix matching on the folded Arabic/English blobs, plus reference parsing (`parseReference`). Verse search returns **mushaf order** (unranked) and **rejects any query containing a digit**.

The **boolean grammar** (`& | ! # ^ % $`), the tashkeel/exact-phrase refinements, and the "ignore silent letters" lenient Arabic variant from the JS reference engine are **intentionally omitted**. Use the JS or Python port if you need those.

## Running the tests

With the `test` package available (`dart pub get`):

```sh
dart test
```

Offline / no dependencies — a dependency-free smoke test asserts the same canonical cases:

```sh
dart run bin/smoke.dart
```

## License & attribution

MIT — see [`../../LICENSE`](../../LICENSE).

All data and algorithms are extracted from the open-source **Al-Islam | Islamic Pillars** app by **Abubakr Elmallah** (© 2025, MIT). Please preserve the attribution in [`../../CREDITS.md`](../../CREDITS.md) in any redistribution. Audio is provided only as constructed URLs to third-party CDNs (mp3quran.net, alquran.cloud / cdn.islamic.network); no audio is hosted or redistributed. The Arabic Quran text must be preserved exactly and never altered.
