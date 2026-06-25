/// Juz (para) and mushaf-page navigation.
import 'models.dart';
import 'quran.dart';

/// Juz/page navigation over a [Quran].
class JuzPage {
  final Quran quran;
  final List<JuzEntry> juzList;

  JuzPage(this.quran, List<JuzEntry> juzList)
      : juzList = [...juzList]..sort((a, b) => a.id - b.id);

  /// Build from already-decoded `data/juz.json`.
  factory JuzPage.fromJson(Quran quran, List<dynamic> json) => JuzPage(
        quran,
        json.map((e) => JuzEntry.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// All 30 juz boundary entries.
  List<JuzEntry> juzes() => juzList;

  /// Lookup a juz by id.
  JuzEntry? juz(int id) {
    for (final j in juzList) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// Every ayah in a juz, in mushaf order.
  List<AyahRef> ayahsInJuz(int juz) =>
      quran.eachAyah().where((r) => r.ayah.juz == juz).toList();

  /// Every ayah on a mushaf page, in mushaf order.
  List<AyahRef> ayahsOnPage(int page) =>
      quran.eachAyah().where((r) => r.ayah.page == page).toList();

  /// First ayah of a juz (for "jump to juz").
  AyahRef? firstAyahOfJuz(int juz) {
    for (final r in quran.eachAyah()) {
      if (r.ayah.juz == juz) return r;
    }
    return null;
  }

  /// First ayah of a mushaf page.
  AyahRef? firstAyahOfPage(int page) {
    for (final r in quran.eachAyah()) {
      if (r.ayah.page == page) return r;
    }
    return null;
  }

  /// The juz number an ayah belongs to.
  int? juzForAyah(int surahId, int ayahId) =>
      quran.ayah(surahId, ayahId)?.juz;

  /// The mushaf page an ayah is on.
  int? pageForAyah(int surahId, int ayahId) =>
      quran.ayah(surahId, ayahId)?.page;

  /// Total page count of the bundled mushaf (max page seen).
  int totalPages() {
    var max = 0;
    for (final r in quran.eachAyah()) {
      final p = r.ayah.page ?? 0;
      if (p > max) max = p;
    }
    return max;
  }

  /// Surah ids contained in a juz (by boundary range).
  List<int> surahsInJuz(int juz) {
    final j = this.juz(juz);
    if (j == null) return const [];
    return quran
        .all()
        .where((s) => s.id >= j.startSurah && s.id <= j.endSurah)
        .map((s) => s.id)
        .toList();
  }
}
