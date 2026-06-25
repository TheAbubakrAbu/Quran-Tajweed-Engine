/// Tajweed coloring via strategy (A): consume the pre-computed annotation
/// corpus and map each `rule` to its category `colorHex`.
///
/// Annotation `start`/`end` are UTF-16 code-unit offsets. Dart `String`s are
/// UTF-16, so `text.substring(start, end)` slices them directly.
import 'models.dart';
import 'quran.dart';

class Tajweed {
  final Quran quran;

  /// rule id -> colorHex (from `data/tajweed-rules.json` categories).
  final Map<String, String> _ruleColors;

  /// "surah:ayah" -> raw annotation list ({start,end,rule}).
  final Map<String, List<Map<String, dynamic>>> _annotations;

  Tajweed._(this.quran, this._ruleColors, this._annotations);

  /// Build from already-decoded JSON.
  ///
  /// [tajweedRules] is the parsed `data/tajweed-rules.json` object.
  /// [annotations] is the parsed `tajweed-annotations.json` (a list of
  /// `{surah, ayah, annotations:[...]}`).
  factory Tajweed.fromJson(
    Quran quran,
    Map<String, dynamic> tajweedRules,
    List<dynamic> annotations,
  ) {
    final colors = <String, String>{};
    final cats = (tajweedRules['categories'] as List?) ?? const [];
    for (final c in cats) {
      final m = c as Map<String, dynamic>;
      final id = m['id'] as String?;
      final hex = m['colorHex'] as String?;
      if (id != null && hex != null) colors[id] = hex;
    }

    final byAyah = <String, List<Map<String, dynamic>>>{};
    for (final entry in annotations) {
      final e = entry as Map<String, dynamic>;
      final key = '${e['surah']}:${e['ayah']}';
      byAyah[key] = ((e['annotations'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
    }

    return Tajweed._(quran, colors, byAyah);
  }

  /// Hex color for a rule id, or null if unknown.
  String? colorForRule(String rule) => _ruleColors[rule];

  /// Colored tajweed spans for an ayah, in annotation order. Returns an empty
  /// list when the ayah has no annotations or does not exist.
  List<TajweedSpan> tajweedSpans(int surahId, int ayahId) {
    final text = quran.arabicText(surahId, ayahId);
    if (text == null) return const [];
    final anns = _annotations['$surahId:$ayahId'];
    if (anns == null) return const [];

    final out = <TajweedSpan>[];
    for (final a in anns) {
      final start = a['start'] as int;
      final end = a['end'] as int;
      final rule = a['rule'] as String;
      // UTF-16 offsets — Dart strings are UTF-16, so substring is direct.
      final slice = text.substring(start, end);
      out.add(TajweedSpan(
        start: start,
        end: end,
        rule: rule,
        colorHex: _ruleColors[rule],
        text: slice,
      ));
    }
    return out;
  }
}
