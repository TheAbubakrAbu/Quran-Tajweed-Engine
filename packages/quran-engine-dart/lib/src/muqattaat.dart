/// Muqaṭṭaʿāt — the disconnected opening letters of 29 surahs (e.g. الٓمٓ).
///
/// The mushaf prints them joined with maddah marks but they are recited letter
/// by letter ("Alif Lām Mīm"), so this exposes, per opening ayah, the individual
/// letters, a transliteration, and the fully-vocalized Arabic spelling (whose
/// long vowels carry the madd-lāzim maddah U+0653, so a tajweed pass colours them
/// like the real ayah).
///
/// Data: `data/muqattaat.json` (mirrors Muqattaat.swift / muqattaat.js).
/// Ash-Shūra (42) is the one surah whose muqattaʿāt span two ayahs
/// (1: Ḥā Mīm, 2: ʿAyn Sīn Qāf).

/// One muqattaʿāt opening ayah's pronunciation data.
class MuqattaatPronunciation {
  final int surah;
  final int ayah;

  /// Bare letters, e.g. `["ا", "ل", "م"]`.
  final List<String> letters;

  /// Transliteration, e.g. "Alif Lām Mīm".
  final String transliteration;

  /// Fully vocalized Arabic spelling, e.g. "أَلِفۡ لَآم مِيٓمۡ". Long vowels carry
  /// the madd-lāzim maddah (U+0653).
  final String spelledOutArabic;

  const MuqattaatPronunciation({
    required this.surah,
    required this.ayah,
    this.letters = const [],
    this.transliteration = '',
    this.spelledOutArabic = '',
  });

  factory MuqattaatPronunciation.fromJson(Map<String, dynamic> json) =>
      MuqattaatPronunciation(
        surah: json['surah'] as int,
        ayah: json['ayah'] as int,
        letters: (json['letters'] as List?)?.cast<String>() ?? const [],
        transliteration: json['transliteration'] as String? ?? '',
        spelledOutArabic: json['spelledOutArabic'] as String? ?? '',
      );
}

/// Data-driven muqattaʿāt lookup built from parsed `data/muqattaat.json`.
class Muqattaat {
  /// Map of bare letter (e.g. "ا") to its name (e.g. "Alif").
  final Map<String, String> letterNames;

  /// Every muqattaʿāt opening, in mushaf order.
  final List<MuqattaatPronunciation> ayahs;

  final Map<String, MuqattaatPronunciation> _byKey;

  Muqattaat({
    Map<String, String>? letterNames,
    List<MuqattaatPronunciation>? ayahs,
  })  : letterNames = letterNames ?? const {},
        ayahs = ayahs ?? const [],
        _byKey = {
          for (final e in ayahs ?? const <MuqattaatPronunciation>[])
            '${e.surah}:${e.ayah}': e
        };

  /// Build from already-decoded JSON (the parsed `data/muqattaat.json` map).
  factory Muqattaat.fromJson(Map<String, dynamic> json) {
    final names = <String, String>{};
    final rawNames = json['letterNames'] as Map<String, dynamic>?;
    if (rawNames != null) {
      rawNames.forEach((k, v) => names[k] = v as String);
    }
    final ayahs = ((json['ayahs'] as List?) ?? const [])
        .map((e) => MuqattaatPronunciation.fromJson(e as Map<String, dynamic>))
        .toList();
    return Muqattaat(letterNames: names, ayahs: ayahs);
  }

  /// Every muqattaʿāt opening (30 entries: one per surah, plus Ash-Shūra's 2nd
  /// ayah).
  List<MuqattaatPronunciation> all() => ayahs;

  /// Pronunciation for a muqattaʿāt ayah, or null if that ayah doesn't open with
  /// them.
  MuqattaatPronunciation? pronunciation(int surahId, int ayahId) =>
      _byKey['$surahId:$ayahId'];

  /// Transliteration of a single muqattaʿāt letter, e.g. "ا" → "Alif". Returns
  /// null for an unknown letter.
  String? letterName(String letter) => letterNames[letter];
}
