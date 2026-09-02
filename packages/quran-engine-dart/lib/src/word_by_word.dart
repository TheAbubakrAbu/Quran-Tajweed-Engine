// Word by word: what each word of an ayah means, and how it is said.
//
// Two layers over the SAME tokens — the English gloss and a Latin
// transliteration — where the tokens are the ayah's own whitespace-separated
// words. Split the ayah and index straight in; the alignment against a corpus
// that tokenizes ~200 ayahs differently was done once, at build time.
//
// A token with no word of its own (the ۞ ornament, the tail of a word the
// corpus writes as two) carries `''` in both layers — show nothing for it
// rather than a neighbour's meaning.
//
// See `../../docs/12-word-by-word.md`.

import 'quran.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// One word of an ayah, in reading order.

class GlossedWord {
  /// 1-based index of the word in the ayah.
  final int position;

  /// The ayah's own token.
  final String arabic;

  /// The gloss, `''` when the token has none.
  final String english;
  final String transliteration;

  const GlossedWord({
    required this.position,
    required this.arabic,
    required this.english,
    required this.transliteration,
  });
}

/// A hit from the word-level gloss search.

class GlossHit {
  final int surah;
  final int ayah;
  final int position;
  final String english;
  final String transliteration;

  const GlossHit({
    required this.surah,
    required this.ayah,
    required this.position,
    required this.english,
    required this.transliteration,
  });
}

class WordByWord {
  /// Surah id -> ayahs in id order -> one entry per token.
  final Map<String, List<List<String>>> _english;
  final Map<String, List<List<String>>> _transliteration;
  final Quran? _quran;

  WordByWord({Map<String, dynamic>? pack, Quran? quran})
      : _english = _layer(pack?['english'] as Map<String, dynamic>?),
        _transliteration = _layer(pack?['transliteration'] as Map<String, dynamic>?),
        _quran = quran;

  static Map<String, List<List<String>>> _layer(Map<String, dynamic>? raw) => {
        for (final surah in (raw ?? const {}).entries)
          surah.key: (surah.value as List<dynamic>)
              .map((row) => (row as List<dynamic>).cast<String>())
              .toList(growable: false),
      };

  /// Whether a pack is loaded at all — cheap enough to gate UI on.
  bool get isLoaded => _english.isNotEmpty;

  /// Every word of an ayah, in reading order.
  List<GlossedWord> words(int surahId, int ayahId) {
    final english = glosses(surahId, ayahId);
    if (english == null) return const [];
    final latin = transliterations(surahId, ayahId) ?? const <String>[];
    final text = _quran?.ayah(surahId, ayahId)?.textArabic;
    final tokens = text == null ? const <String>[] : text.trim().split(_whitespace);
    return [
      for (var i = 0; i < english.length; i++)
        GlossedWord(
          position: i + 1,
          arabic: i < tokens.length ? tokens[i] : '',
          english: english[i],
          transliteration: i < latin.length ? latin[i] : '',
        ),
    ];
  }

  /// One word, by its 1-based position.
  GlossedWord? word(int surahId, int ayahId, int position) {
    final all = words(surahId, ayahId);
    if (position < 1 || position > all.length) return null;
    return all[position - 1];
  }

  List<String>? glosses(int surahId, int ayahId) =>
      _row(_english, surahId, ayahId);

  List<String>? transliterations(int surahId, int ayahId) =>
      _row(_transliteration, surahId, ayahId);

  /// Ayahs containing a word whose gloss carries [term] — a word-level English
  /// search, which finds ayahs a translation search misses because no
  /// translator used that phrasing.
  List<GlossHit> find(String term, {int limit = 50}) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final out = <GlossHit>[];
    // Mushaf order, so the result is stable across runs.
    final surahs = _english.keys.map(int.parse).toList()..sort();
    for (final surah in surahs) {
      final rows = _english['$surah']!;
      for (var ayahIndex = 0; ayahIndex < rows.length; ayahIndex++) {
        final glosses = rows[ayahIndex];
        for (var i = 0; i < glosses.length; i++) {
          if (!glosses[i].toLowerCase().contains(needle)) continue;
          final latinRows = _transliteration['$surah'];
          final latin = latinRows != null &&
                  ayahIndex < latinRows.length &&
                  i < latinRows[ayahIndex].length
              ? latinRows[ayahIndex][i]
              : '';
          out.add(GlossHit(
            surah: surah,
            ayah: ayahIndex + 1,
            position: i + 1,
            english: glosses[i],
            transliteration: latin,
          ));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  List<String>? _row(
      Map<String, List<List<String>>> layer, int surahId, int ayahId) {
    final rows = layer['$surahId'];
    if (rows == null || ayahId < 1 || ayahId > rows.length) return null;
    return rows[ayahId - 1];
  }
}
