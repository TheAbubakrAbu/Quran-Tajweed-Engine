import 'text.dart';

/// Root and lemma of every word of the Quran: the Quranic Arabic Corpus
/// morphology (Kais Dukes), as redistributed by the Quranic Universal Library.
///
/// The invariant, the same one `word-by-word.json` keeps: one id per whitespace
/// token of the ayah's raw Hafs text, in the text's own token order, so nothing
/// here matches or normalizes text. Id `0` means the token has neither a root
/// nor a lemma, which is the honest answer for particles and the sajdah mark.
/// Ids are 1-based into the root and lemma tables.
///
/// The reverse indexes are built on first use and kept: walking 77,629 tokens is
/// quick, but a caller asking about ten roots should not pay for it ten times.
///
/// See `../../docs/18-morphology.md`.

/// A triliteral (or quadriliteral) root, in both spellings a reader might use.
class MorphologyRoot {
  /// Spaced the way a lexicon prints it: `"ر ب ب"`.
  final String letters;

  /// The same letters transliterated: `"rbb"`.
  final String buckwalter;

  const MorphologyRoot(this.letters, this.buckwalter);

  /// [letters] with the spaces closed up: `"ربب"`.
  String get joined => letters.replaceAll(' ', '');
}

/// A dictionary form, marked and unmarked.
class MorphologyLemma {
  final String text;
  final String clean;

  const MorphologyLemma(this.text, this.clean);
}

/// One word of the Quran: the ayah, and the 0-based index of the token in it.
class WordLocation {
  final int surah;
  final int ayah;
  final int token;

  const WordLocation(this.surah, this.ayah, this.token);

  @override
  bool operator ==(Object other) =>
      other is WordLocation &&
      other.surah == surah &&
      other.ayah == ayah &&
      other.token == token;

  @override
  int get hashCode => Object.hash(surah, ayah, token);

  @override
  String toString() => '$surah:$ayah#$token';
}

/// A root or lemma paired with its id.
class MorphologyHit<T> {
  final int id;
  final T value;

  const MorphologyHit(this.id, this.value);
}

class Morphology {
  final Map<String, dynamic> _data;
  Map<int, List<WordLocation>>? _byRoot;
  Map<int, List<WordLocation>>? _byLemma;

  Morphology([this._data = const {}]);

  /// Whether a corpus was supplied at all.
  bool get isLoaded => (_data['roots'] as List<dynamic>?)?.isNotEmpty ?? false;

  /// The fold a typed query and the tables are both compared under.
  ///
  /// Every space is removed, not merely trimmed: a root is printed spaced
  /// (`"ر ب ب"`) and typed closed up (`"ربب"`), and the two have to meet.
  static String fold(String text) =>
      cleanSearch(removingArabicDiacriticsAndSigns(text))
          .split(RegExp(r'\s+'))
          .join();

  List<dynamic> get _roots => _data['roots'] as List<dynamic>? ?? const [];
  List<dynamic> get _lemmas => _data['lemmas'] as List<dynamic>? ?? const [];

  /// The root with this 1-based id.
  MorphologyRoot? root(int id) {
    if (id < 1 || id > _roots.length) return null;
    final row = (_roots[id - 1] as List<dynamic>).cast<String>();
    if (row.length < 2) return null;
    return MorphologyRoot(row[0], row[1]);
  }

  /// The dictionary form with this 1-based id.
  MorphologyLemma? lemma(int id) {
    if (id < 1 || id > _lemmas.length) return null;
    final row = (_lemmas[id - 1] as List<dynamic>).cast<String>();
    if (row.length < 2) return null;
    return MorphologyLemma(row[0], row[1]);
  }

  List<List<int>>? _rows(String field, int surahId) {
    final table = _data[field] as Map<String, dynamic>?;
    final rows = table?['$surahId'] as List<dynamic>?;
    if (rows == null) return null;
    return rows.map((row) => (row as List<dynamic>).cast<int>()).toList();
  }

  /// The root and lemma id of every token of the ayah, or null when the ayah is
  /// not covered.
  MapEntry<List<int>, List<int>>? ids(int surahId, int ayahId) {
    final roots = _rows('rootIds', surahId);
    final lemmas = _rows('lemmaIds', surahId);
    if (roots == null || lemmas == null) return null;
    if (ayahId < 1 || ayahId > roots.length || ayahId > lemmas.length) return null;
    return MapEntry(roots[ayahId - 1], lemmas[ayahId - 1]);
  }

  /// The root of one token; null when it has none (a particle) or the index is
  /// out of range.
  MorphologyHit<MorphologyRoot>? rootOf(int surahId, int ayahId, int token) {
    final row = ids(surahId, ayahId)?.key;
    if (row == null || token < 0 || token >= row.length) return null;
    final found = root(row[token]);
    return found == null ? null : MorphologyHit(row[token], found);
  }

  /// The dictionary form of one token.
  MorphologyHit<MorphologyLemma>? lemmaOf(int surahId, int ayahId, int token) {
    final row = ids(surahId, ayahId)?.value;
    if (row == null || token < 0 || token >= row.length) return null;
    final found = lemma(row[token]);
    return found == null ? null : MorphologyHit(row[token], found);
  }

  /// Every word carrying this root, in mushaf order.
  List<WordLocation> occurrencesOfRoot(int id) {
    _buildIndex();
    return _byRoot?[id] ?? const [];
  }

  /// Every word carrying this lemma, in mushaf order.
  List<WordLocation> occurrencesOfLemma(int id) {
    _buildIndex();
    return _byLemma?[id] ?? const [];
  }

  /// Roots whose Arabic or Buckwalter spelling starts with the query.
  List<MorphologyHit<MorphologyRoot>> findRoots(String query, {int limit = 50}) =>
      _prefixHits(_roots, query, limit)
          .map((id) => MorphologyHit(id, root(id)!))
          .toList(growable: false);

  /// Dictionary forms whose marked or unmarked spelling starts with the query.
  List<MorphologyHit<MorphologyLemma>> findLemmas(String query, {int limit = 50}) =>
      _prefixHits(_lemmas, query, limit)
          .map((id) => MorphologyHit(id, lemma(id)!))
          .toList(growable: false);

  /// Corpus size: roots, lemmas, and the tokens they cover.
  Map<String, int> count() {
    var tokens = 0;
    final table = _data['rootIds'] as Map<String, dynamic>? ?? const {};
    for (final ayahs in table.values) {
      for (final row in ayahs as List<dynamic>) {
        tokens += (row as List<dynamic>).length;
      }
    }
    return {'roots': _roots.length, 'lemmas': _lemmas.length, 'tokens': tokens};
  }

  List<int> _prefixHits(List<dynamic> table, String query, int limit) {
    final folded = fold(query);
    final latin = query.trim().toLowerCase();
    if (folded.isEmpty && latin.isEmpty) return const [];
    final out = <int>[];
    for (var i = 0; i < table.length; i++) {
      if (limit > 0 && out.length >= limit) break;
      final row = (table[i] as List<dynamic>).cast<String>();
      if (row.isEmpty) continue;
      final arabic = fold(row[0]);
      final roman = row.length > 1 ? row[1].toLowerCase() : '';
      if ((folded.isNotEmpty && arabic.startsWith(folded)) ||
          (latin.isNotEmpty && roman.startsWith(latin))) {
        out.add(i + 1);
      }
    }
    return out;
  }

  /// Walk the corpus once, in mushaf order, so the lists come out ordered.
  void _buildIndex() {
    if (_byRoot != null) return;
    final byRoot = <int, List<WordLocation>>{};
    final byLemma = <int, List<WordLocation>>{};
    final rootTable = _data['rootIds'] as Map<String, dynamic>? ?? const {};
    final surahs = rootTable.keys.map(int.parse).toList()..sort();
    for (final surah in surahs) {
      final roots = _rows('rootIds', surah) ?? const [];
      final lemmas = _rows('lemmaIds', surah) ?? const [];
      for (var a = 0; a < roots.length; a++) {
        final lemmaRow = a < lemmas.length ? lemmas[a] : const <int>[];
        for (var t = 0; t < roots[a].length; t++) {
          final location = WordLocation(surah, a + 1, t);
          final rootId = roots[a][t];
          if (rootId != 0) byRoot.putIfAbsent(rootId, () => []).add(location);
          final lemmaId = t < lemmaRow.length ? lemmaRow[t] : 0;
          if (lemmaId != 0) byLemma.putIfAbsent(lemmaId, () => []).add(location);
        }
      }
    }
    _byRoot = byRoot;
    _byLemma = byLemma;
  }
}
