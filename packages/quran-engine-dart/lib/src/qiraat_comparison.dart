// How far apart two readings actually are, measured word by word.
//
// The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs
// does not"), which says what differs but never how much. This measures it:
// align the two readings' words and sort every pair into one of three buckets.
//
//  * identical - the same word, written the same way, marks and all.
//  * sameSkeleton - the same consonantal skeleton (rasm), different vowels or
//    spelling. This is the overwhelming majority of what "a different qiraah"
//    means, and it is what the uthmani rasm was designed to allow: one written
//    form, several sound readings.
//  * different - a different skeleton, i.e. a genuinely different word form.
//
// WHY ALIGNMENT IS NOT INDEXING. Readings merge and split ayahs (Warsh's
// al-Baqarah has 285 ayahs to Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب
// as one), so ayah n of one is not ayah n of the other. The comparison walks the
// whole SURAH's word stream on both sides with a two-pointer alignment and
// bounded lookahead rather than pairing by index.
//
// WHAT IT CANNOT TELL YOU. This measures the two printed TEXTS, not the two
// recitations: a difference that lives only in how a letter is sounded (imalah,
// taqlil, ishmam) shows up only where the print marks it.
//
// See `../../docs/17-qiraat-comparison.md`.

import 'quran.dart';
import 'text.dart';

/// How far ahead to look for a resync before declaring a word added or dropped.
const int _lookahead = 3;

final RegExp _whitespace = RegExp(r'\s+');

/// What happened to one word.
enum DifferenceKind { identical, sameSkeleton, different, added, dropped }

/// One word pair.
class WordDifference {
  /// 1-based word position in the BASE reading's surah.
  final int position;

  /// The base reading's word (`''` when the other reading adds one).
  final String base;

  /// The compared reading's word (`''` when it drops one).
  final String other;
  final DifferenceKind kind;

  const WordDifference(this.position, this.base, this.other, this.kind);
}

/// The counts for a surah or for the whole Quran.
class ComparisonTotals {
  /// Words compared, in the base reading.
  int words = 0;
  int identical = 0;
  int sameSkeleton = 0;
  int different = 0;

  /// Words the compared reading has and the base does not.
  int added = 0;

  /// Words the base has and the compared reading does not.
  int dropped = 0;

  double get identicalPercent => words == 0 ? 0 : 100 * identical / words;
}

/// The consonantal skeleton of a word: diacritics and recitation signs gone, the
/// letters that are written differently for the same consonant folded together.
String qiraahSkeleton(String word) {
  final out = StringBuffer();
  for (final ch in removingArabicDiacriticsAndSigns(word).split('')) {
    switch (ch) {
      case 'ٱ':
      case 'أ':
      case 'إ':
      case 'آ':
      case 'ى':
      case 'ٰ':
        out.write('ا');
        break;
      case 'ؤ':
        out.write('و');
        break;
      case 'ئ':
        out.write('ي');
        break;
      case 'ة':
        out.write('ه');
        break;
      case 'ء':
      case 'ـ':
        break;
      default:
        out.write(ch);
    }
  }
  return out.toString();
}

class QiraatComparison {
  final Quran _quran;

  const QiraatComparison(this._quran);

  /// The riwayat whose text is loaded and so can be compared, in slug order.
  /// `'hafs'` is always one of them: it is `quran.json` itself.
  List<String> available() =>
      ({'hafs', ..._quran.loadedRiwayat}.toList()..sort());

  /// Every word of a surah in one reading, in order.
  List<String> words(int surahId, String riwayah) {
    final surah = _quran.surah(surahId);
    if (surah == null) return const [];
    // The riwayah's OWN verses, in ITS numbering: readings merge and split
    // ayahs, so walking Hafs' ayah ids and asking for each would compare
    // different verses.
    final verses = riwayah.toLowerCase() == 'hafs'
        ? surah.ayahs.map((a) => a.textArabic).toList()
        : _quran.qiraahVerses(surahId, riwayah).map((v) => v.text).toList();
    return [
      for (final text in verses)
        ...text.split(_whitespace).where((w) => w.isNotEmpty),
    ];
  }

  /// Compare one surah, word by word.
  ComparisonTotals compareSurah(int surahId, String riwayah,
          {String against = 'hafs'}) =>
      _totals(_align(surahId, against, riwayah));

  /// Compare the whole Quran. This walks every word of both readings - about
  /// 155,000 comparisons - so cache the result rather than calling it per render.
  ComparisonTotals compare(String riwayah, {String against = 'hafs'}) {
    final sum = ComparisonTotals();
    for (final surah in _quran.all()) {
      final part = compareSurah(surah.id, riwayah, against: against);
      sum.words += part.words;
      sum.identical += part.identical;
      sum.sameSkeleton += part.sameSkeleton;
      sum.different += part.different;
      sum.added += part.added;
      sum.dropped += part.dropped;
    }
    return sum;
  }

  /// The words that are not identical, in reading order - the rows behind a
  /// comparison view. A [limit] of 0 returns them all.
  List<WordDifference> differences(int surahId, String riwayah,
      {String against = 'hafs', int limit = 0}) {
    final rows = _align(surahId, against, riwayah)
        .where((row) => row.kind != DifferenceKind.identical)
        .toList();
    return limit > 0 ? rows.take(limit).toList(growable: false) : rows;
  }

  /// Two-pointer alignment with bounded lookahead.
  List<WordDifference> _align(int surahId, String base, String other) {
    final left = words(surahId, base);
    final right = words(surahId, other);
    final leftSkeletons = left.map(qiraahSkeleton).toList(growable: false);
    final rightSkeletons = right.map(qiraahSkeleton).toList(growable: false);
    final rows = <WordDifference>[];

    var i = 0;
    var j = 0;
    while (i < left.length && j < right.length) {
      if (left[i] == right[j]) {
        rows.add(WordDifference(i + 1, left[i], right[j], DifferenceKind.identical));
        i++;
        j++;
        continue;
      }
      if (leftSkeletons[i] == rightSkeletons[j]) {
        rows.add(WordDifference(i + 1, left[i], right[j], DifferenceKind.sameSkeleton));
        i++;
        j++;
        continue;
      }
      // Not a match. Before calling it a different word, see whether one side
      // simply has an extra word here - a merge or a split - by looking for the
      // next place they agree.
      final resync = _findResync(leftSkeletons, rightSkeletons, i, j);
      if (resync != null) {
        for (var k = i; k < resync[0]; k++) {
          rows.add(WordDifference(k + 1, left[k], '', DifferenceKind.dropped));
        }
        for (var k = j; k < resync[1]; k++) {
          rows.add(WordDifference(i + 1, '', right[k], DifferenceKind.added));
        }
        i = resync[0];
        j = resync[1];
        continue;
      }
      rows.add(WordDifference(i + 1, left[i], right[j], DifferenceKind.different));
      i++;
      j++;
    }
    for (; i < left.length; i++) {
      rows.add(WordDifference(i + 1, left[i], '', DifferenceKind.dropped));
    }
    for (; j < right.length; j++) {
      rows.add(WordDifference(left.length, '', right[j], DifferenceKind.added));
    }
    return rows;
  }

  ComparisonTotals _totals(List<WordDifference> rows) {
    final out = ComparisonTotals();
    for (final row in rows) {
      if (row.kind == DifferenceKind.added) {
        out.added++;
        continue;
      }
      out.words++;
      switch (row.kind) {
        case DifferenceKind.identical:
          out.identical++;
          break;
        case DifferenceKind.sameSkeleton:
          out.sameSkeleton++;
          break;
        case DifferenceKind.dropped:
          out.dropped++;
          break;
        default:
          out.different++;
      }
    }
    return out;
  }
}

/// The nearest offset within the lookahead window at which the two streams agree
/// again by skipping words on ONE side only - an insertion or a deletion.
///
/// Skipping on both sides at once is deliberately not a resync: that is a
/// substitution, one word standing where another does, which is the `different`
/// bucket. Allowing it here collapsed every genuine word difference into a
/// dropped+added pair and left `different` permanently at zero.
List<int>? _findResync(List<String> left, List<String> right, int i, int j) {
  for (var skip = 1; skip <= _lookahead; skip++) {
    if (i + skip < left.length && left[i + skip] == right[j]) return [i + skip, j];
    if (j + skip < right.length && left[i] == right[j + skip]) return [i, j + skip];
  }
  return null;
}
