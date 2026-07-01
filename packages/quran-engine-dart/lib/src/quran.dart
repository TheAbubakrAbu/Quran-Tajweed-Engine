/// Quran browsing: surahs, ayahs, translations, global ayah numbering.
import 'dart:math' show min;

import 'models.dart';
import 'text.dart';

/// ۩ ARABIC PLACE OF SAJDAH (U+06E9) — marks the 15 sajdah (prostration) ayahs.
const String sajdahMark = '۩';

/// A surah paired with one of its ayahs (used by iteration helpers).
class AyahRef {
  final Surah surah;
  final Ayah ayah;
  const AyahRef(this.surah, this.ayah);
}

/// One "About this surah" write-up source (e.g. Maududi / Ibn Ashur) from
/// `data/surah-info.json`.
class SurahInfoSource {
  final String name;
  final String contents;
  const SurahInfoSource({required this.name, required this.contents});

  factory SurahInfoSource.fromJson(Map<String, dynamic> json) =>
      SurahInfoSource(
        name: json['name'] as String? ?? '',
        contents: json['contents'] as String? ?? '',
      );
}

/// Data-driven Quran browser built from parsed `data/quran.json`.
class Quran {
  final List<Surah> surahs;
  final Map<int, Surah> _byId;
  final Map<int, int> _cumulativeOffset;
  final Map<int, List<SurahInfoSource>> _info;

  /// Ayah counts per riwayah: `riwayah` -> `surahId(string)` -> count
  /// (parsed from `data/qiraat-counts.json`). Empty for the Hafs-only build.
  final Map<String, Map<String, int>> qiraatCounts;

  /// Total ayah count across the mushaf (6236 for the standard Hafs count).
  final int totalAyahs;

  Quran(
    this.surahs, [
    Map<int, List<SurahInfoSource>>? surahInfo,
    this.qiraatCounts = const {},
  ])  : _byId = {for (final s in surahs) s.id: s},
        _cumulativeOffset = _buildOffsets(surahs),
        _info = surahInfo ?? const {},
        totalAyahs = surahs.fold(0, (acc, s) => acc + s.numberOfAyahs);

  static Map<int, int> _buildOffsets(List<Surah> surahs) {
    final m = <int, int>{};
    var acc = 0;
    for (final s in surahs) {
      m[s.id] = acc;
      acc += s.numberOfAyahs;
    }
    return m;
  }

  /// Build from already-decoded JSON.
  ///
  /// [json] is a `List` of surah maps (`data/quran.json`). Optional
  /// [surahInfoJson] is a `List` of `{id, sources:[{name, contents}]}` entries
  /// from `data/surah-info.json`.
  factory Quran.fromJson(
    List<dynamic> json, [
    List<dynamic>? surahInfoJson,
    Map<String, dynamic>? qiraatCountsJson,
  ]) {
    final surahs =
        json.map((e) => Surah.fromJson(e as Map<String, dynamic>)).toList();
    final info = <int, List<SurahInfoSource>>{};
    if (surahInfoJson != null) {
      for (final e in surahInfoJson) {
        final m = e as Map<String, dynamic>;
        info[m['id'] as int] = ((m['sources'] as List?) ?? const [])
            .map((s) => SurahInfoSource.fromJson(s as Map<String, dynamic>))
            .toList();
      }
    }
    final counts = qiraatCountsJson == null
        ? const <String, Map<String, int>>{}
        : qiraatCountsJson.map((k, v) => MapEntry(
              k,
              (v as Map).map(
                (k2, v2) => MapEntry(k2 as String, v2 as int),
              ),
            ));
    return Quran(surahs, info, counts);
  }

  /// All surahs in mushaf order (1..114).
  List<Surah> all() => surahs;

  /// Lookup a surah by id.
  Surah? surah(int id) => _byId[id];

  /// Lookup an ayah by surah + ayah id.
  Ayah? ayah(int surahId, int ayahId) {
    final s = _byId[surahId];
    if (s == null) return null;
    for (final a in s.ayahs) {
      if (a.id == ayahId) return a;
    }
    return null;
  }

  /// Global ayah number (1-based, 1..6236) used by the ayah-audio CDN.
  int globalAyahNumber(int surahId, int ayahId) {
    final off = _cumulativeOffset[surahId];
    if (off == null) throw ArgumentError('Unknown surah $surahId');
    return off + ayahId;
  }

  /// "About this surah" write-ups (Maududi / Ibn Ashur) for [surahId].
  List<SurahInfoSource> info(int surahId) => _info[surahId] ?? const [];

  /// Resolve a surah counted from the END of the mushaf: 1 → An-Nās (114),
  /// 2 → Al-Falaq … 114 → Al-Fātiḥah. Returns null for [n] outside 1..114.
  Surah? surahFromEnd(int n) {
    if (n < 1 || n > surahs.length) return null;
    return surah(surahs.length + 1 - n);
  }

  /// Whether an ayah is a sajdah (prostration) ayah — carries the ۩ mark
  /// (U+06E9).
  bool isSajdahAyah(int surahId, int ayahId) =>
      (ayah(surahId, ayahId)?.textArabic ?? '').contains(sajdahMark);

  /// Whether a mushaf page boundary falls inside this surah.
  /// Mirrors `Surah.pageChangesWithinSurah`.
  bool pageChangesWithinSurah(int surahId) {
    final s = surah(surahId);
    if (s == null) return false;
    if ((s.numberOfPages ?? 1) > 1) return true;
    final pages = <int>{};
    for (final a in s.ayahs) {
      if (a.page != null) pages.add(a.page!);
    }
    return pages.length > 1;
  }

  /// Whether a juz boundary falls inside this surah.
  /// Mirrors `Surah.juzChangesWithinSurah`.
  bool juzChangesWithinSurah(int surahId) {
    final s = surah(surahId);
    if (s == null) return false;
    if (s.juzs.length > 1) return true;
    if (s.firstJuz != null && s.lastJuz != null && s.firstJuz != s.lastJuz) {
      return true;
    }
    final juzs = <int>{};
    for (final a in s.ayahs) {
      if (a.juz != null) juzs.add(a.juz!);
    }
    return juzs.length > 1;
  }

  /// Whether a page OR juz boundary falls inside this surah.
  /// Mirrors `Surah.pageOrJuzChangesWithinSurah`.
  bool pageOrJuzChangesWithinSurah(int surahId) =>
      pageChangesWithinSurah(surahId) || juzChangesWithinSurah(surahId);

  /// The 15 sajdah (prostration) ayahs, in mushaf order, detected by the ۩
  /// mark in the Arabic text.
  List<AyahRef> sajdahAyahs() {
    final out = <AyahRef>[];
    for (final ref in eachAyah()) {
      if (ref.ayah.textArabic.contains(sajdahMark)) out.add(ref);
    }
    return out;
  }

  /// Arabic text of an ayah (Hafs only in this core port). Returns null if
  /// the ayah does not exist.
  String? arabicText(int surahId, int ayahId, [String? riwayah]) =>
      ayah(surahId, ayahId)?.textArabic;

  /// Whether a Hafs ayah exists as its own verse in the given riwayah. In Hafs
  /// every ayah exists; other riwayat merge/split some ayahs, so a Hafs ayah
  /// "exists" iff the riwayah's feed carries an ayah with that id (its feeds are
  /// numbered contiguously 1..count, so this is `ayahId <= count`). An
  /// unknown/unloaded riwayah falls back to Hafs (exists).
  bool existsInQiraah(int surahId, int ayahId, [String? riwayah]) {
    if (ayah(surahId, ayahId) == null) return false;
    final r = (riwayah ?? '').toLowerCase();
    if (r.isEmpty || r == 'hafs') return true;
    final count = qiraatCounts[r]?[surahId.toString()];
    if (count == null) return true;
    return ayahId <= count;
  }

  /// Ayah count of a surah in the given riwayah — the number of Hafs ayahs that
  /// exist there (e.g. Baqarah is 286 in Hafs but 285 in Warsh). Returns 0 for
  /// an unknown surah.
  int numberOfAyahsInQiraah(int surahId, [String? riwayah]) {
    final s = surah(surahId);
    if (s == null) return 0;
    final r = (riwayah ?? '').toLowerCase();
    if (r.isEmpty || r == 'hafs') return s.numberOfAyahs;
    final count = qiraatCounts[r]?[surahId.toString()];
    if (count == null) return s.numberOfAyahs;
    return min(s.numberOfAyahs, count);
  }

  /// Arabic text with diacritics/recitation marks stripped.
  String? cleanArabicText(int surahId, int ayahId, [String? riwayah]) {
    final raw = arabicText(surahId, ayahId, riwayah);
    return raw == null ? null : removingArabicDiacriticsAndSigns(raw);
  }

  /// Iterate every ayah with its surah, in mushaf order.
  Iterable<AyahRef> eachAyah() sync* {
    for (final surah in surahs) {
      for (final ayah in surah.ayahs) {
        yield AyahRef(surah, ayah);
      }
    }
  }
}
