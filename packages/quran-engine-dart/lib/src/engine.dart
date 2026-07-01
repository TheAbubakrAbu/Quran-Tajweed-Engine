/// The `Engine` facade ties the modules together.
///
/// Two ways to build it:
///   • `Engine.load({dataDir})`     — reads JSON from disk (dart:io). Default
///     locates the repo `/data` by walking up from the current directory.
///   • `Engine.fromJson(...)`       — accepts already-decoded JSON. Use this in
///     Flutter, where the data is bundled as assets and loaded via `rootBundle`.
import 'dart:convert';
import 'dart:io';

import 'quran.dart';
import 'juz_page.dart';
import 'reciters.dart';
import 'search.dart';
import 'tajweed.dart';
import 'names.dart';
import 'muqattaat.dart';
import 'models.dart';

class Engine {
  final Quran quran;
  final JuzPage juzPage;
  final Reciters reciters;
  final Search search;
  final Tajweed tajweed;
  final NamesOfAllah namesOfAllah;
  final Muqattaat muqattaat;

  Engine({
    required this.quran,
    required this.juzPage,
    required this.reciters,
    required this.tajweed,
    NamesOfAllah? namesOfAllah,
    Muqattaat? muqattaat,
  })  : search = Search(quran),
        namesOfAllah = namesOfAllah ?? NamesOfAllah(),
        muqattaat = muqattaat ?? Muqattaat();

  /// Build from already-decoded JSON. Pass the parsed contents of each file.
  ///
  /// [quranJson]            — `data/quran.json` (a List).
  /// [juzJson]              — `data/juz.json` (a List).
  /// [recitersJson]         — `data/reciters.json` (a List).
  /// [tajweedRulesJson]     — `data/tajweed-rules.json` (a Map).
  /// [tajweedAnnotationsJson] — `tajweed-annotations.json` (a List).
  /// [surahInfoJson]        — `data/surah-info.json` (a List), optional.
  /// [namesOfAllahJson]     — `data/names-of-allah.json` (a List), optional.
  /// [muqattaatJson]        — `data/muqattaat.json` (a Map), optional.
  /// [qiraatCountsJson]     — `data/qiraat-counts.json` (a Map), optional.
  factory Engine.fromJson({
    required List<dynamic> quranJson,
    required List<dynamic> juzJson,
    required List<dynamic> recitersJson,
    required Map<String, dynamic> tajweedRulesJson,
    required List<dynamic> tajweedAnnotationsJson,
    List<dynamic>? surahInfoJson,
    List<dynamic>? namesOfAllahJson,
    Map<String, dynamic>? muqattaatJson,
    Map<String, dynamic>? qiraatCountsJson,
  }) {
    final quran = Quran.fromJson(quranJson, surahInfoJson, qiraatCountsJson);
    return Engine(
      quran: quran,
      juzPage: JuzPage.fromJson(quran, juzJson),
      reciters: Reciters.fromJson(recitersJson),
      tajweed: Tajweed.fromJson(quran, tajweedRulesJson, tajweedAnnotationsJson),
      namesOfAllah: namesOfAllahJson == null
          ? NamesOfAllah()
          : NamesOfAllah.fromJson(namesOfAllahJson),
      muqattaat:
          muqattaatJson == null ? Muqattaat() : Muqattaat.fromJson(muqattaatJson),
    );
  }

  /// Load all canonical data from disk and build the engine (Dart VM only).
  ///
  /// [dataDir] overrides the data directory; otherwise the repo `/data` is
  /// located by walking up from `Directory.current` until a `quran.json` is
  /// found under a `data/` folder.
  static Future<Engine> load({String? dataDir}) async {
    final dir = dataDir ?? _locateDataDir();
    if (dir == null) {
      throw StateError(
          'Could not locate a data directory (looked for data/quran.json '
          'walking up from ${Directory.current.path}). Pass dataDir explicitly.');
    }

    Future<dynamic> read(String rel) async {
      final file = File('$dir${Platform.pathSeparator}$rel');
      return jsonDecode(await file.readAsString());
    }

    final results = await Future.wait([
      read('quran.json'),
      read('juz.json'),
      read('reciters.json'),
      read('tajweed-rules.json'),
      read('tajweed-annotations.json'),
      read('surah-info.json'),
      read('names-of-allah.json'),
      read('muqattaat.json'),
      read('qiraat-counts.json'),
    ]);

    return Engine.fromJson(
      quranJson: results[0] as List<dynamic>,
      juzJson: results[1] as List<dynamic>,
      recitersJson: results[2] as List<dynamic>,
      tajweedRulesJson: results[3] as Map<String, dynamic>,
      tajweedAnnotationsJson: results[4] as List<dynamic>,
      surahInfoJson: results[5] as List<dynamic>,
      namesOfAllahJson: results[6] as List<dynamic>,
      muqattaatJson: results[7] as Map<String, dynamic>,
      qiraatCountsJson: results[8] as Map<String, dynamic>,
    );
  }

  /// Walk up from the current directory to find a `data/` dir with quran.json.
  static String? _locateDataDir() {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final candidate =
          File('${dir.path}${Platform.pathSeparator}data'
              '${Platform.pathSeparator}quran.json');
      if (candidate.existsSync()) {
        return '${dir.path}${Platform.pathSeparator}data';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  // --- Convenience pass-throughs -------------------------------------------

  int get totalAyahs => quran.totalAyahs;

  Surah? surah(int id) => quran.surah(id);

  Ayah? ayah(int surahId, int ayahId) => quran.ayah(surahId, ayahId);

  int globalAyahNumber(int surahId, int ayahId) =>
      quran.globalAyahNumber(surahId, ayahId);

  JuzEntry? juz(int id) => juzPage.juz(id);

  List<TajweedSpan> tajweedSpans(int surahId, int ayahId) =>
      tajweed.tajweedSpans(surahId, ayahId);
}
