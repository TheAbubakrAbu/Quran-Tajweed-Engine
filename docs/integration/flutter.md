# Flutter

Use **`quran-engine-dart`** in a Flutter app. It's a thin, data-driven wrapper over the JSON in
[`/data`](../../data) — no network, database, or framework at runtime (audio is just URL strings). Tajweed
uses the pre-computed annotation corpus (strategy A), so coloring is exact and dependency-free.

## Setup

Add the package as a path (or git) dependency in your app's `pubspec.yaml`:

```yaml
dependencies:
  quran_engine:
    path: ../quran-engine-dart      # or a git/published dependency
```

Bundle the `/data` JSON as Flutter **assets** (copy the files into your app under `assets/data/`):

```yaml
flutter:
  assets:
    - assets/data/quran.json
    - assets/data/juz.json
    - assets/data/reciters.json
    - assets/data/tajweed-rules.json
    - assets/data/tajweed-annotations.json
```

## Minimal working example (load via `rootBundle` + `Engine.fromJson`)

In Flutter you can't use `dart:io` to walk the filesystem, so decode the bundled assets and feed the maps
into `Engine.fromJson`:

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

// Usage:
final engine = await buildEngine();
engine.surah(2)!.nameEnglish;                 // "The Cow"
engine.quran.ayah(2, 255)!.textArabic;        // Ayat al-Kursi
engine.globalAyahNumber(2, 255);              // global ayah number
```

Build the engine once (e.g. in `main()` before `runApp`, or behind a `FutureBuilder` / provider) and reuse
it — decoding `quran.json` is the heaviest step.

## Tajweed rendering with `RichText` / `TextSpan`

`engine.tajweedSpans(surah, ayah)` returns `List<TajweedSpan>`, each with `text`, `rule`, and `colorHex`
(e.g. `"#AE2517"`). The spans are non-overlapping and in order, but only cover the *colored* parts — fill
the gaps with the surrounding text so nothing is dropped. Convert the hex string to a `Color`:

```dart
import 'package:flutter/material.dart';
import 'package:quran_engine/quran_engine.dart';

Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));   // prepend opaque alpha
}

Widget tajweedAyah(Engine engine, int surah, int ayah) {
  final text = engine.quran.ayah(surah, ayah)!.textArabic;
  final spans = engine.tajweedSpans(surah, ayah);   // [{ text, rule, colorHex, start, end }]

  final children = <TextSpan>[];
  var cursor = 0;
  for (final s in spans) {
    if (s.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, s.start)));   // uncolored gap
    }
    children.add(TextSpan(
      text: text.substring(s.start, s.end),
      style: TextStyle(color: s.colorHex != null ? colorFromHex(s.colorHex!) : null),
    ));
    cursor = s.end;
  }
  if (cursor < text.length) children.add(TextSpan(text: text.substring(cursor)));

  return Directionality(
    textDirection: TextDirection.rtl,
    child: RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        style: const TextStyle(fontSize: 28, color: Colors.black, fontFamily: 'UthmanicHafs'),
        children: children,
      ),
    ),
  );
}
```

`TajweedSpan.start`/`end` are UTF-16 code-unit offsets; Dart `String`s are UTF-16, so `text.substring`
slices them directly. See [02-tajweed.md](../02-tajweed.md).

## Audio with `just_audio` (or `audioplayers`)

Audio URLs come from the free functions `surahAudioUrl` / `ayahAudioUrl`. The engine never fetches audio —
hand the URL to your player.

```yaml
dependencies:
  just_audio: ^0.9.0
```

```dart
import 'package:just_audio/just_audio.dart';
import 'package:quran_engine/quran_engine.dart';

final player = AudioPlayer();

Future<void> playSurah(Engine engine, int surahId) async {
  final reciter = engine.reciters.byQiraah('hafs')
      .firstWhere((r) => r.name == 'Mishary Alafasy');
  await player.setUrl(surahAudioUrl(reciter, surahId));   // full-surah mp3
  await player.play();
}

// Verse-by-verse playlist with auto-advance:
Future<void> playAyahByAyah(Engine engine, int surahId) async {
  final reciter = engine.reciters.byQiraah('hafs')
      .firstWhere((r) => r.name == 'Mishary Alafasy');
  final surah = engine.quran.surah(surahId)!;
  final sources = surah.ayahs.map((a) => AudioSource.uri(
        Uri.parse(ayahAudioUrl(reciter, engine.globalAyahNumber(surahId, a.id))),
      ));
  await player.setAudioSource(ConcatenatingAudioSource(children: sources.toList()));
  await player.play();  // just_audio advances through the playlist automatically
}
```

With `audioplayers` the equivalent is `AudioPlayer().play(UrlSource(surahAudioUrl(reciter, surahId)))`.

## See also

- [recipes.md](../recipes.md) — #2 (tajweed), #4–6 (audio), #9 (mushaf page).
- [02-tajweed.md](../02-tajweed.md) · [01-quran.md](../01-quran.md) · [06-ayah-search.md](../06-ayah-search.md)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md)
- [`quran-engine-dart` README](../../packages/quran-engine-dart/README.md)
