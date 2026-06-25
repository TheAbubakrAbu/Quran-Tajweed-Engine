import 'dart:io';

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

/// Locate the repo data dir by walking up from the current directory to find
/// a `data/quran.json`.
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

void main() {
  late Engine engine;
  late Reciter alafasy;

  setUpAll(() async {
    engine = await Engine.load(dataDir: locateDataDir());
    // The Hafs "Mishary Alafasy" full-surah feed (afs) + ar.alafasy ayah feed.
    alafasy = engine.reciters.all().firstWhere((r) =>
        r.ayahIdentifier == 'ar.alafasy' &&
        r.surahLink == 'https://server8.mp3quran.net/afs/');
  });

  test('totalAyahs == 6236', () {
    expect(engine.quran.totalAyahs, 6236);
  });

  test('globalAyahNumber canonical cases', () {
    expect(engine.globalAyahNumber(1, 1), 1);
    expect(engine.globalAyahNumber(2, 1), 8);
    expect(engine.globalAyahNumber(114, 6), 6236);
  });

  test('surahAudioUrl(Alafasy, 1)', () {
    expect(surahAudioUrl(alafasy, 1),
        'https://server8.mp3quran.net/afs/001.mp3');
  });

  test('ayahAudioUrl(Alafasy, 8)', () {
    expect(ayahAudioUrl(alafasy, 8),
        'https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3');
  });

  test('juz boundaries', () {
    expect(engine.juz(1)!.startSurah, 1);
    expect(engine.juz(1)!.startAyah, 1);
    expect(engine.juz(30)!.endSurah, 114);
    expect(engine.juz(30)!.endAyah, 6);
  });

  test('sortSurahs("ayahs","descending")[0].id == 2', () {
    final sorted = sortSurahs(engine.quran.all(), 'ayahs', 'descending');
    expect(sorted.first.id, 2);
  });

  test('parseReference("2:255")', () {
    final ref = engine.search.parseReference('2:255');
    expect(ref, isNotNull);
    expect(ref!.surah, 2);
    expect(ref.ayah, 255);
  });

  test('tajweed(1,1) span substrings match recorded text', () {
    final spans = engine.tajweedSpans(1, 1);
    expect(spans, isNotEmpty);
    final text = engine.ayah(1, 1)!.textArabic;
    for (final s in spans) {
      expect(s.text, text.substring(s.start, s.end));
    }
  });
}
