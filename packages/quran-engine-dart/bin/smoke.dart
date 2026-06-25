/// Dependency-free smoke test of the canonical cases from docs/PORTING.md.
///
/// Run with: `dart run bin/smoke.dart`  (needs no pub dependencies).
import 'dart:io';

import 'package:quran_engine/quran_engine.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
    print('  ok   $name');
  } else {
    _failed++;
    print('  FAIL $name${detail != null ? "  ($detail)" : ""}');
  }
}

Future<void> main() async {
  final engine = await Engine.load();

  final alafasy = engine.reciters.all().firstWhere((r) =>
      r.ayahIdentifier == 'ar.alafasy' &&
      r.surahLink == 'https://server8.mp3quran.net/afs/');

  check('totalAyahs == 6236', engine.quran.totalAyahs == 6236,
      '${engine.quran.totalAyahs}');

  check('globalAyahNumber(1,1) == 1', engine.globalAyahNumber(1, 1) == 1);
  check('globalAyahNumber(2,1) == 8', engine.globalAyahNumber(2, 1) == 8);
  check('globalAyahNumber(114,6) == 6236',
      engine.globalAyahNumber(114, 6) == 6236);

  check(
      'surahAudioUrl(Alafasy,1)',
      surahAudioUrl(alafasy, 1) ==
          'https://server8.mp3quran.net/afs/001.mp3',
      surahAudioUrl(alafasy, 1));

  check(
      'ayahAudioUrl(Alafasy,8)',
      ayahAudioUrl(alafasy, 8) ==
          'https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3',
      ayahAudioUrl(alafasy, 8));

  check('juz(1).startSurah == 1', engine.juz(1)!.startSurah == 1);
  check('juz(30).endSurah == 114', engine.juz(30)!.endSurah == 114);
  check('juz(30).endAyah == 6', engine.juz(30)!.endAyah == 6);

  final sorted = sortSurahs(engine.quran.all(), 'ayahs', 'descending');
  check('sortSurahs("ayahs","descending")[0].id == 2', sorted.first.id == 2,
      '${sorted.first.id}');

  final ref = engine.search.parseReference('2:255');
  check('parseReference("2:255") == {2,255}',
      ref != null && ref.surah == 2 && ref.ayah == 255, '$ref');

  final spans = engine.tajweedSpans(1, 1);
  final text = engine.ayah(1, 1)!.textArabic;
  final allMatch =
      spans.isNotEmpty && spans.every((s) => s.text == text.substring(s.start, s.end));
  check('tajweed(1,1) spans substring match', allMatch,
      '${spans.length} spans');

  print('');
  print('$_passed passed, $_failed failed');
  if (_failed > 0) exit(1);
}
