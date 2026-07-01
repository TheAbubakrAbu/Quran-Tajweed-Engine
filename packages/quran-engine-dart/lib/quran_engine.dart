/// Quran Tajweed Engine — Dart / Flutter port.
///
/// A thin, idiomatic, data-driven wrapper over the JSON corpus in the repo
/// `/data` directory. Implements the shared contract in `docs/PORTING.md`:
/// Quran browsing, tajweed coloring (via the pre-computed annotation corpus),
/// juz/page navigation, audio URLs, sorting, and reference parsing.
///
/// Quick start (Dart VM):
/// ```dart
/// final engine = await Engine.load();
/// engine.surah(1)!.nameEnglish;                 // "The Opener"
/// engine.tajweedSpans(1, 1);                     // colored spans
/// ```
///
/// Quick start (Flutter, asset-bundled data):
/// ```dart
/// import 'dart:convert';
/// import 'package:flutter/services.dart' show rootBundle;
///
/// Future<List> load(String p) async =>
///     jsonDecode(await rootBundle.loadString('assets/data/$p')) as List;
/// final engine = Engine.fromJson(
///   quranJson: await load('quran.json'),
///   juzJson: await load('juz.json'),
///   recitersJson: await load('reciters.json'),
///   tajweedRulesJson:
///       jsonDecode(await rootBundle.loadString('assets/data/tajweed-rules.json')),
///   tajweedAnnotationsJson: await load('tajweed-annotations.json'),
/// );
/// ```
library quran_engine;

export 'src/models.dart';
export 'src/functions.dart';
export 'src/text.dart';
export 'src/quran.dart';
export 'src/juz_page.dart';
export 'src/reciters.dart';
export 'src/tajweed.dart';
export 'src/search.dart';
export 'src/names.dart';
export 'src/muqattaat.dart';
export 'src/engine.dart';
