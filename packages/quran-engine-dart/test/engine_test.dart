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

  test('juz from end + per-juz stats', () {
    final jp = engine.juzPage;
    expect(jp.juzFromEnd(1)!.id, 30);
    expect(jp.juzFromEnd(30)!.id, 1);
    expect(jp.juzFromEnd(0), isNull);
    expect(jp.juzFromEnd(31), isNull);

    final stats = jp.juzStats(30)!;
    expect(stats.ayahCount, jp.ayahsInJuz(30).length);
    expect(stats.surahCount >= 1 && stats.pageCount >= 1, isTrue);
    expect(stats.wordCount > 0 && stats.letterCount > 0, isTrue);
    expect(jp.juzStats(99), isNull);

    var sum = 0;
    for (var i = 1; i <= 30; i++) {
      sum += jp.juzStats(i)!.ayahCount;
    }
    expect(sum, 6236);
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

  bool hits(List<VerseHit> r, int surah, int ayah) =>
      r.any((h) => h.surah == surah && h.ayah == ayah);

  test('regular search is pure substring (mid-word "orld" hits 1:2)', () {
    // "world" appears in the English translation of al-Fatihah 1:2
    // ("Lord of the worlds"); a mid-word substring must still match.
    final r = engine.search.searchVerses('orld');
    expect(hits(r, 1, 2), isTrue);
  });

  test('=lord (whole-word) hits 1:2 but =lor does not; plain lor does', () {
    expect(hits(engine.search.searchVerses('=lord'), 1, 2), isTrue);
    // whole-word: "lor" is not a complete token, so it must NOT match.
    expect(hits(engine.search.searchVerses('=lor'), 1, 2), isFalse);
    // plain substring: "lor" is inside "lord", so it DOES match.
    expect(hits(engine.search.searchVerses('lor'), 1, 2), isTrue);
  });

  test('"allah & 2" returns 0 (digit rejected before boolean path)', () {
    expect(engine.search.searchVerses('allah & 2'), isEmpty);
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
