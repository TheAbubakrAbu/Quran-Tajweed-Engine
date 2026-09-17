// Riwayah tajweed: where a reading differs from Hafs, and why.
//
// A different layer from `tajweed.dart`, which reads the text and works out the
// universal rules. This carries what is SPECIFIC to a transmission and cannot
// be detected, because it IS the text's difference: Warsh's taqlil, al-Bazzi's
// doubled ta, the places two readings part.
//
// Two things to get right:
//
//  * **The meaning of a colour is per edition.** Each mushaf prints its own
//    legend, so the same code is a different rule in a different riwayah.
//    Always read [QiraatTajweed.legend]. The `rule` KEY is stable across
//    riwayat, which is why one catalogue can explain it for all of them.
//  * **Extents are base-letter indices, not character offsets**, 
//    `firstLetter..lastLetter` inclusive in reading order with diacritics not
//    counted, or the whole word when `wholeWord`.
//
// Only the seven verified non-Hafs riwayat carry a pack.
// See `../../docs/11-qiraat-tajweed.md`.
// A legend row with its shared explanation merged in.

class LegendEntry {
  /// The single letter this riwayah's data uses for the rule.
  final String code;

  /// Stable rule key, e.g. `"idgham"`: the same across riwayat.
  final String rule;

  /// The rule's name as this mushaf prints it.
  final String arabic;
  final String english;

  /// One-line explanation, from the shared catalogue.
  final String short;
  final String long;

  const LegendEntry({
    required this.code,
    required this.rule,
    required this.arabic,
    required this.english,
    this.short = '',
    this.long = '',
  });
}

/// What one word of one ayah is coloured for.

class WordRule {
  /// 1-based word index within the ayah.
  final int word;
  final String rule;
  final String code;
  final String arabic;
  final String english;

  /// Inclusive base-letter index the rule colours, or -1 for the whole word.
  final int firstLetter;
  final int lastLetter;
  final bool wholeWord;

  const WordRule({
    required this.word,
    required this.rule,
    required this.code,
    required this.arabic,
    required this.english,
    required this.firstLetter,
    required this.lastLetter,
    required this.wholeWord,
  });
}

/// One entry of `data/tajweed-qiraat/rules.json`.

class RuleDescription {
  final String short;
  final String long;
  const RuleDescription(this.short, this.long);
}

class QiraatTajweed {
  final Map<String, RuleDescription> _descriptions;
  final Map<String, Map<String, dynamic>> _riwayat;
  final Map<String, Map<String, LegendEntry>> _legendByCode = {};

  QiraatTajweed({
    Map<String, dynamic> rules = const {},
    Map<String, Map<String, dynamic>> riwayat = const {},
  })  : _descriptions = {
          for (final entry in rules.entries)
            entry.key: RuleDescription(
              (entry.value as Map<String, dynamic>)['short'] as String? ?? '',
              (entry.value)['long'] as String? ?? '',
            ),
        },
        _riwayat = riwayat;

  /// The riwayat that have a pack loaded, in slug order.
  List<String> available() => _riwayat.keys.toList()..sort();

  /// This riwayah's printed legend, each entry carrying the shared explanation.
  List<LegendEntry> legend(String riwayah) {
    final pack = _riwayat[riwayah];
    if (pack == null) return const [];
    return ((pack['legend'] as List<dynamic>?) ?? const []).map((raw) {
      final row = raw as Map<String, dynamic>;
      final rule = row['rule'] as String? ?? '';
      final description = _descriptions[rule];
      return LegendEntry(
        code: row['code'] as String? ?? '',
        rule: rule,
        arabic: row['arabic'] as String? ?? '',
        english: row['english'] as String? ?? '',
        short: description?.short ?? '',
        long: description?.long ?? '',
      );
    }).toList(growable: false);
  }

  /// What this riwayah colours in one ayah, word by word.
  List<WordRule> wordRules(int surahId, int ayahId, String riwayah) {
    final pack = _riwayat[riwayah];
    final ayahs = pack?['rules'] as Map<String, dynamic>?;
    final words =
        (ayahs?['$surahId'] as Map<String, dynamic>?)?['$ayahId'] as Map<String, dynamic>?;
    if (words == null) return const [];
    final byCode = _codes(riwayah);

    final out = <WordRule>[];
    final keys = words.keys.map(int.parse).toList()..sort();
    for (final key in keys) {
      for (final raw in (words['$key'] as List<dynamic>)) {
        // [code, firstLetter, lastLetter], heterogeneous, so read positionally.
        final triple = raw as List<dynamic>;
        if (triple.length < 3) continue;
        final code = triple[0] as String;
        final lo = triple[1] as int;
        final hi = triple[2] as int;
        final entry = byCode[code];
        out.add(WordRule(
          word: key,
          rule: entry?.rule ?? code,
          code: code,
          arabic: entry?.arabic ?? '',
          english: entry?.english ?? '',
          firstLetter: lo,
          lastLetter: hi,
          wholeWord: lo < 0,
        ));
      }
    }
    return out;
  }

  /// The ayahs of a surah this riwayah reads differently from Hafs somewhere, 
  /// the index behind a "show me where these two readings part" list, without
  /// walking every ayah's rules.
  List<int> khilafAyahs(int surahId, String riwayah) {
    final markers = _riwayat[riwayah]?['khilafMarkers'] as Map<String, dynamic>?;
    return ((markers?['$surahId'] as List<dynamic>?) ?? const []).cast<int>();
  }

  bool hasKhilaf(int surahId, int ayahId, String riwayah) =>
      khilafAyahs(surahId, riwayah).contains(ayahId);

  /// What a rule key means, in one line and in a paragraph.
  RuleDescription? describe(String rule) => _descriptions[rule];

  /// Every rule key the catalogue explains.
  List<String> ruleKeys() => _descriptions.keys.toList()..sort();

  Map<String, LegendEntry> _codes(String riwayah) =>
      _legendByCode.putIfAbsent(riwayah, () {
        return {for (final entry in legend(riwayah)) entry.code: entry};
      });
}
