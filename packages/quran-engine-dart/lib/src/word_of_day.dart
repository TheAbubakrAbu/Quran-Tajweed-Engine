/// A curated word of Quranic vocabulary, with every ayah the same written form
/// appears in.
///
/// 149 words, ordered so that consecutive days feel varied (the themes are
/// interleaved in the corpus itself), which is why the day mapping below is a
/// walk and not a hash: hashing would scatter the curation's own ordering, and
/// the ordering is the point.
///
/// The occurrence list is derived from the Hafs text by matching the form
/// folded, so the count on a card and the list behind it are one derivation and
/// cannot disagree. A form can repeat inside a single ayah, so an occurrence
/// carries token indices, plural.
///
/// Curation, transliteration and glosses are Tilawa's (Jamil Hammoudeh), used
/// with permission.
///
/// See `../../docs/22-word-of-day.md`.

/// One ayah carrying a curated form.
class WordOccurrence {
  final int surah;
  final int ayah;

  /// 0-based whitespace-token indices into the ayah's raw text.
  final List<int> tokens;

  const WordOccurrence(this.surah, this.ayah, this.tokens);
}

/// One curated word.
class WordOfDayEntry {
  final String id;

  /// The form as it stands at its first appearance.
  final String arabic;
  final String transliteration;
  final String meaning;

  /// The anchor: where the form first appears.
  final int surah;
  final int ayah;
  final int token;

  /// Hits across the whole Quran.
  final int count;

  /// Every ayah carrying the form, in mushaf order.
  final List<WordOccurrence> occurrences;

  const WordOfDayEntry({
    required this.id,
    required this.arabic,
    required this.transliteration,
    required this.meaning,
    required this.surah,
    required this.ayah,
    required this.token,
    required this.count,
    required this.occurrences,
  });

  factory WordOfDayEntry.fromJson(Map<String, dynamic> row) => WordOfDayEntry(
        id: row['id'] as String,
        arabic: row['arabic'] as String,
        transliteration: row['transliteration'] as String? ?? '',
        meaning: row['meaning'] as String? ?? '',
        surah: row['surah'] as int,
        ayah: row['ayah'] as int,
        token: row['token'] as int,
        count: row['count'] as int,
        occurrences: (row['occurrences'] as List<dynamic>? ?? const []).map((raw) {
          final o = raw as Map<String, dynamic>;
          return WordOccurrence(o['surah'] as int, o['ayah'] as int,
              (o['tokens'] as List<dynamic>).cast<int>());
        }).toList(growable: false),
      );
}

class WordOfDay {
  final List<WordOfDayEntry> _words;
  final Map<String, WordOfDayEntry> _byId;

  WordOfDay([Map<String, dynamic>? json])
      : _words = ((json?['words'] as List<dynamic>?) ?? const [])
            .map((row) => WordOfDayEntry.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
        _byId = {} {
    for (final word in _words) {
      _byId[word.id] = word;
    }
  }

  bool get isLoaded => _words.isNotEmpty;

  /// The whole corpus, in curation order.
  List<WordOfDayEntry> all() => _words;

  WordOfDayEntry? word(String id) => _byId[id];

  /// The word for a day number: the corpus walked in order, wrapping.
  ///
  /// Take this rather than [forDate] if your app has its own idea of when a day
  /// turns over (the upstream app rolls at Fajr, not midnight): hand it your own
  /// day number and the mapping is identical.
  WordOfDayEntry? forDayIndex(int dayIndex) {
    if (_words.isEmpty) return null;
    final n = _words.length;
    return _words[((dayIndex % n) + n) % n];
  }

  /// Today's word, by the calendar day of the given local date.
  WordOfDayEntry? forDate([DateTime? date]) {
    final when = date ?? DateTime.now();
    final midnight = DateTime(when.year, when.month, when.day);
    return forDayIndex(midnight.millisecondsSinceEpoch ~/ 86400000);
  }

  /// Matches the written form, the transliteration and the gloss.
  List<WordOfDayEntry> search(String query, {int limit = 25}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    return _words
        .where((w) =>
            w.arabic.contains(q) ||
            w.transliteration.toLowerCase().contains(lower) ||
            w.meaning.toLowerCase().contains(lower))
        .take(limit)
        .toList(growable: false);
  }

  /// Every curated word appearing in an ayah.
  List<WordOfDayEntry> wordsIn(int surahId, int ayahId) => _words
      .where((w) =>
          w.occurrences.any((o) => o.surah == surahId && o.ayah == ayahId))
      .toList(growable: false);

  Map<String, int> count() => {
        'words': _words.length,
        'occurrences': _words.fold(0, (total, w) => total + w.count),
      };
}
