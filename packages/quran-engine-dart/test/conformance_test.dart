// Conformance test — runs the language-agnostic vectors in /conformance/vectors.json against the
// engine. These vectors are the SINGLE SOURCE OF BEHAVIORAL TRUTH: a behavior is specified ONCE in
// that JSON, and every language port runs the same file (see docs/PORTING.md -> "Conformance
// vectors"). The JS harness in packages/quran-engine-js/test/conformance.test.js is the reference
// consumer; this mirrors it.

import 'dart:convert';
import 'dart:io';

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

/// Locate the repo data dir by walking up from the current directory to find
/// a `data/quran.json`. (Same strategy as engine_test.dart.)
String locateDataDir() {
  var dir = Directory.current;
  for (var i = 0; i < 12; i++) {
    final candidate = File(
        '${dir.path}${Platform.pathSeparator}data${Platform.pathSeparator}quran.json');
    if (candidate.existsSync()) {
      return '${dir.path}${Platform.pathSeparator}data';
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Could not locate data/quran.json');
}

/// The conformance vectors live at `<repoRoot>/conformance/vectors.json`, and the
/// data dir is `<repoRoot>/data`, so the vectors sit alongside it.
Map<String, dynamic> loadVectors(String dataDir) {
  final repoRoot = File(dataDir).parent.path;
  final file = File(
      '$repoRoot${Platform.pathSeparator}conformance${Platform.pathSeparator}vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late Engine engine;
  late Map<String, dynamic> vectors;

  setUpAll(() async {
    final dataDir = locateDataDir();
    engine = await Engine.load(dataDir: dataDir);
    vectors = loadVectors(dataDir);
  });

  test('conformance: searchVerses', () {
    for (final raw in vectors['searchVerses'] as List) {
      final v = raw as Map<String, dynamic>;
      final query = v['query'] as String;
      final ids =
          engine.search.searchVerses(query).map((h) => h.id).toList();
      if (v['empty'] == true) {
        expect(ids, isEmpty, reason: '"$query" should be empty');
      }
      for (final id in (v['contains'] as List?) ?? const []) {
        expect(ids, contains(id), reason: '"$query" should contain $id');
      }
      for (final id in (v['excludes'] as List?) ?? const []) {
        expect(ids, isNot(contains(id)),
            reason: '"$query" should exclude $id');
      }
    }
  });

  test('conformance: juzFromEnd', () {
    for (final raw in vectors['juzFromEnd'] as List) {
      final v = raw as Map<String, dynamic>;
      final n = v['n'] as int;
      final expectedId = v['id'] as int?; // null in the vector -> null here
      expect(engine.juzPage.juzFromEnd(n)?.id, expectedId,
          reason: 'juzFromEnd($n)');
    }
  });

  test('conformance: juzStats', () {
    const keys = [
      'surahCount',
      'ayahCount',
      'wordCount',
      'letterCount',
      'pageCount'
    ];
    int statValue(JuzStats s, String key) {
      switch (key) {
        case 'surahCount':
          return s.surahCount;
        case 'ayahCount':
          return s.ayahCount;
        case 'wordCount':
          return s.wordCount;
        case 'letterCount':
          return s.letterCount;
        case 'pageCount':
          return s.pageCount;
        default:
          throw ArgumentError('unknown stat $key');
      }
    }

    for (final raw in vectors['juzStats'] as List) {
      final v = raw as Map<String, dynamic>;
      final juz = v['juz'] as int;
      final s = engine.juzPage.juzStats(juz);
      if (v['isNull'] == true) {
        expect(s, isNull, reason: 'juzStats($juz) should be null');
        continue;
      }
      expect(s, isNotNull, reason: 'juzStats($juz) should not be null');
      for (final k in keys) {
        expect(statValue(s!, k), v[k] as int, reason: 'juzStats($juz).$k');
      }
    }

    final invariant =
        vectors['juzStatsInvariant'] as Map<String, dynamic>;
    var sum = 0;
    for (var i = 1; i <= 30; i++) {
      sum += engine.juzPage.juzStats(i)!.ayahCount;
    }
    expect(sum, invariant['sumAyahCountAllJuz'] as int);
  });

  test('conformance: surahFromEnd', () {
    for (final raw in vectors['surahFromEnd'] as List) {
      final v = raw as Map<String, dynamic>;
      final n = v['n'] as int;
      final expectedId = v['id'] as int?; // null in the vector -> null here
      expect(engine.quran.surahFromEnd(n)?.id, expectedId,
          reason: 'surahFromEnd($n)');
    }
  });

  test('conformance: sajdah', () {
    final sj = vectors['sajdah'] as Map<String, dynamic>;
    final ids = engine.quran
        .sajdahAyahs()
        .map((r) => '${r.surah.id}:${r.ayah.id}')
        .toList();
    expect(ids.length, sj['count'] as int);
    for (final id in (sj['contains'] as List?) ?? const []) {
      expect(ids, contains(id), reason: 'sajdah should contain $id');
      final parts = (id as String).split(':').map(int.parse).toList();
      expect(engine.quran.isSajdahAyah(parts[0], parts[1]), isTrue,
          reason: 'isSajdahAyah($id)');
    }
    for (final id in (sj['excludes'] as List?) ?? const []) {
      final parts = (id as String).split(':').map(int.parse).toList();
      expect(engine.quran.isSajdahAyah(parts[0], parts[1]), isFalse,
          reason: 'isSajdahAyah($id) should be false');
    }
  });

  test('conformance: surahInfo', () {
    for (final raw in vectors['surahInfo'] as List) {
      final v = raw as Map<String, dynamic>;
      final surah = v['surah'] as int;
      final sources = engine.quran.info(surah);
      final minSources = (v['minSources'] as int?) ?? 1;
      expect(sources.length, greaterThanOrEqualTo(minSources),
          reason: 'info($surah) sources');
      final hasSourceName = v['hasSourceName'] as String?;
      if (hasSourceName != null) {
        expect(sources.any((s) => s.name == hasSourceName), isTrue,
            reason: 'info($surah) has $hasSourceName');
      }
    }
  });

  test('conformance: namesOfAllah', () {
    final n = vectors['namesOfAllah'] as Map<String, dynamic>;
    expect(engine.namesOfAllah.all().length, n['count'] as int);
    for (final raw in n['byNumber'] as List) {
      final v = raw as Map<String, dynamic>;
      final number = v['number'] as int;
      expect(engine.namesOfAllah.byNumber(number)?.transliteration,
          v['transliteration'] as String,
          reason: 'namesOfAllah.byNumber($number)');
    }
  });

  test('conformance: filterByCounts', () {
    CountFilter? parseFilter(Object? raw) {
      if (raw == null) return null;
      final m = raw as Map<String, dynamic>;
      return CountFilter(m['op'] as String, m['value'] as int);
    }

    for (final raw in vectors['filterByCounts'] as List) {
      final v = raw as Map<String, dynamic>;
      final ids = filterByCounts(
        engine.quran.all(),
        ayahs: parseFilter(v['ayahs']),
        pages: parseFilter(v['pages']),
      ).map((s) => s.id).toList()
        ..sort();
      final expected =
          (v['ids'] as List).map((e) => e as int).toList()..sort();
      expect(ids, expected, reason: 'filterByCounts $v');
    }
  });

  test('conformance: surahFlags', () {
    for (final raw in vectors['surahFlags'] as List) {
      final v = raw as Map<String, dynamic>;
      final surah = v['surah'] as int;
      expect(engine.quran.pageChangesWithinSurah(surah), v['pageChanges'] as bool,
          reason: 'pageChanges($surah)');
      expect(engine.quran.juzChangesWithinSurah(surah), v['juzChanges'] as bool,
          reason: 'juzChanges($surah)');
      expect(engine.quran.pageOrJuzChangesWithinSurah(surah),
          v['pageOrJuz'] as bool,
          reason: 'pageOrJuz($surah)');
    }
  });

  test('conformance: muqattaat', () {
    final m = vectors['muqattaat'] as Map<String, dynamic>;
    expect(engine.muqattaat.all().length, m['count'] as int);
    for (final raw in m['pronunciations'] as List) {
      final p = raw as Map<String, dynamic>;
      final surah = p['surah'] as int;
      final ayah = p['ayah'] as int;
      final got = engine.muqattaat.pronunciation(surah, ayah);
      expect(got, isNotNull, reason: 'muqattaat $surah:$ayah present');
      expect(got!.transliteration, p['transliteration'] as String,
          reason: 'muqattaat $surah:$ayah transliteration');
      if (p['spelledContainsMaddah'] == true) {
        expect(got.spelledOutArabic.contains('ٓ'), isTrue,
            reason: 'muqattaat $surah:$ayah keeps madd-lāzim maddah');
      }
    }
    for (final raw in (m['absent'] as List?) ?? const []) {
      final a = raw as Map<String, dynamic>;
      final surah = a['surah'] as int;
      final ayah = a['ayah'] as int;
      expect(engine.muqattaat.pronunciation(surah, ayah), isNull,
          reason: 'muqattaat $surah:$ayah absent');
    }
  });

  test('conformance: existsInQiraah + numberOfAyahsInQiraah', () {
    for (final raw in vectors['existsInQiraah'] as List) {
      final v = raw as Map<String, dynamic>;
      final surah = v['surah'] as int;
      final ayah = v['ayah'] as int;
      final riwayah = v['riwayah'] as String;
      expect(engine.quran.existsInQiraah(surah, ayah, riwayah),
          v['exists'] as bool,
          reason: 'existsInQiraah($surah,$ayah,$riwayah)');
    }
    for (final raw in vectors['numberOfAyahsInQiraah'] as List) {
      final v = raw as Map<String, dynamic>;
      final surah = v['surah'] as int;
      final riwayah = v['riwayah'] as String;
      expect(engine.quran.numberOfAyahsInQiraah(surah, riwayah),
          v['count'] as int,
          reason: 'numberOfAyahsInQiraah($surah,$riwayah)');
    }
  });

  test('conformance: tajweed', () {
    for (final raw in vectors['tajweed'] as List) {
      final v = raw as Map<String, dynamic>;
      final surah = v['surah'] as int;
      final ayah = v['ayah'] as int;
      final spans = engine.tajweedSpans(surah, ayah);
      final rules = spans.map((s) => s.rule).toList();

      final excludesRule = v['excludesRule'] as String?;
      if (excludesRule != null) {
        expect(rules, isNot(contains(excludesRule)),
            reason: '$surah:$ayah should NOT have $excludesRule');
      }

      final lastSpanRule = v['lastSpanRule'] as String?;
      if (lastSpanRule != null) {
        expect(spans, isNotEmpty,
            reason: '$surah:$ayah should have spans for lastSpanRule');
        final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
        expect(sorted.last.rule, lastSpanRule,
            reason: '$surah:$ayah last span rule');
      }
    }
  });
}
