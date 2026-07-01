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

  /// Resolve a juz counted from the end of the Quran: 1 -> juz 30, 2 -> juz 29 ... 30 -> juz 1.
  ///
  /// Mirrors the search-bar `-N` shorthand in QuranView.swift. Returns null for n outside 1..30.
  JuzEntry? juzFromEnd(int n) {
    if (n < 1 || n > 30) return null;
    return juz(31 - n);
  }

  /// Aggregate counts for a single juz, computed from the ayahs actually assigned to it
  /// (`ayah.juz == juz`) so surahs that straddle a juz boundary are split correctly.
  /// Mirrors `QuranData.juzStats(for:)`. Returns null for an unknown juz id.
  JuzStats? juzStats(int juz) {
    if (this.juz(juz) == null) return null;
    final surahIds = <int>{};
    final pages = <int>{};
    var ayahCount = 0, wordCount = 0, letterCount = 0;
    for (final r in quran.eachAyah()) {
      if (r.ayah.juz != juz) continue;
      surahIds.add(r.surah.id);
      ayahCount += 1;
      wordCount += r.ayah.wordCount ?? 0;
      letterCount += r.ayah.letterCount ?? 0;
      final p = r.ayah.page;
      if (p != null) pages.add(p);
    }
    return JuzStats(
      surahCount: surahIds.length,
      ayahCount: ayahCount,
      wordCount: wordCount,
      letterCount: letterCount,
      pageCount: pages.length,
    );
  }
}

/// Aggregate counts for a single juz. Mirrors `QuranData.JuzStats`.
class JuzStats {
  final int surahCount;
  final int ayahCount;
  final int wordCount;
  final int letterCount;
  final int pageCount;

  const JuzStats({
    required this.surahCount,
    required this.ayahCount,
    required this.wordCount,
    required this.letterCount,
    required this.pageCount,
  });
}
