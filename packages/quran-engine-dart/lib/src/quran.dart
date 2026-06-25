/// Quran browsing: surahs, ayahs, translations, global ayah numbering.
import 'models.dart';
import 'text.dart';

/// A surah paired with one of its ayahs (used by iteration helpers).
class AyahRef {
  final Surah surah;
  final Ayah ayah;
  const AyahRef(this.surah, this.ayah);
}

/// Data-driven Quran browser built from parsed `data/quran.json`.
class Quran {
  final List<Surah> surahs;
  final Map<int, Surah> _byId;
  final Map<int, int> _cumulativeOffset;

  /// Total ayah count across the mushaf (6236 for the standard Hafs count).
  final int totalAyahs;

  Quran(this.surahs)
      : _byId = {for (final s in surahs) s.id: s},
        _cumulativeOffset = _buildOffsets(surahs),
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

  /// Build from already-decoded JSON (a `List` of surah maps).
  factory Quran.fromJson(List<dynamic> json) =>
      Quran(json.map((e) => Surah.fromJson(e as Map<String, dynamic>)).toList());

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

  /// Arabic text of an ayah (Hafs only in this core port). Returns null if
  /// the ayah does not exist.
  String? arabicText(int surahId, int ayahId, [String? riwayah]) =>
      ayah(surahId, ayahId)?.textArabic;

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
