// Meaning-based ("AI") search: find the ayahs about a topic whether or not
// they use its words.
//
// ## Why word vectors and MaxSim, not a sentence embedding
//
// Measured, not assumed. Scoring an ayah by the cosine between a SENTENCE
// embedding of the query and one of the ayah ranks this corpus close to
// randomly: translated scripture is dense, and one vector for a whole verse
// washes out the single idea the query is asking about. Scoring word by word
// fixes it — embed every word, and score a text as the MEAN over the query's
// words of the BEST matching word in the text. On real verses that separates
// related (0.42–0.70) from unrelated (0.27–0.41) cleanly, and it degrades
// gracefully: a query word the model has never seen contributes nothing instead
// of poisoning the vector.
//
// ## The embedder is yours
//
// This engine ships no model — word vectors are tens of megabytes and every
// platform already has one worth using. Hand the constructor a function from a
// lowercased word to its vector, or null when it has none. Vectors are cached
// per word, so a repeated word costs one lookup for the whole corpus.
//
// See `../../docs/14-ask-ai.md`.

import 'dart:math' as math;

final RegExp _word = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// One scored document.

class SemanticHit {
  final String id;

  /// Mean best-match cosine over the query's words, 0..1.
  final double score;
  const SemanticHit(this.id, this.score);
}

/// One corpus entry to index.

class SemanticDocument {
  final String id;
  final String text;
  const SemanticDocument(this.id, this.text);
}

/// A word-vector MaxSim index over any corpus.

class Semantic {
  final List<double>? Function(String word) _embed;

  /// Words shorter than this are skipped on both sides.
  final int minWordLength;

  final Map<String, List<double>?> _vectors = {};
  final List<MapEntry<String, List<List<double>>>> _documents = [];

  Semantic(this._embed, {this.minWordLength = 3});

  /// How many documents are indexed.
  int get size => _documents.length;

  /// Build (or rebuild) the index. Call once per corpus.
  Semantic index(Iterable<SemanticDocument> corpus) {
    _documents.clear();
    for (final document in corpus) {
      final vectors = _vectorize(document.text);
      if (vectors.isNotEmpty) {
        _documents.add(MapEntry(document.id, vectors));
      }
    }
    return this;
  }

  /// The documents closest in meaning to [query], best first. [minScore] is a
  /// floor on "actually related" — 0.42 is a sensible start on English
  /// translations, but calibrate it against YOUR embedder.
  List<SemanticHit> search(String query, {int limit = 10, double minScore = 0}) {
    final queryVectors = _vectorize(query);
    if (queryVectors.isEmpty) return const [];

    final hits = <SemanticHit>[];
    for (final document in _documents) {
      var total = 0.0;
      for (final q in queryVectors) {
        var best = -1.0;
        for (final w in document.value) {
          final score = cosine(q, w);
          if (score > best) best = score;
        }
        total += best;
      }
      final score = total / queryVectors.length;
      if (score >= minScore) hits.add(SemanticHit(document.key, score));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.id.compareTo(b.id);
    });
    return hits.take(limit).toList(growable: false);
  }

  /// Drop the index and the vector cache.
  Semantic clear() {
    _documents.clear();
    _vectors.clear();
    return this;
  }

  List<List<double>> _vectorize(String text) {
    final out = <List<double>>[];
    final seen = <String>{};
    for (final raw in text.toLowerCase().split(_word)) {
      if (raw.length < minWordLength || !seen.add(raw)) continue;
      final vector = _vector(raw);
      if (vector != null) out.add(vector);
    }
    return out;
  }

  List<double>? _vector(String word) {
    if (_vectors.containsKey(word)) return _vectors[word];
    final raw = _embed(word);
    // Normalized once here, so scoring is a dot product rather than three
    // passes per pair.
    final vector = (raw == null || raw.isEmpty) ? null : _normalize(raw);
    _vectors[word] = vector;
    return vector;
  }
}

/// Cosine similarity of two ALREADY NORMALIZED vectors, i.e. their dot product.

double cosine(List<double> a, List<double> b) {
  final n = a.length < b.length ? a.length : b.length;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

List<double> _normalize(List<double> raw) {
  var magnitude = 0.0;
  for (final value in raw) {
    magnitude += value * value;
  }
  magnitude = math.sqrt(magnitude);
  if (magnitude == 0) return List<double>.filled(raw.length, 0);
  return [for (final value in raw) value / magnitude];
}
