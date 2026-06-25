/// Ayah & surah search.
///
/// This is the core path only: substring matching plus phrase-prefix matching
/// on the folded blobs, and reference parsing. The boolean grammar
/// (`& | ! # ^ % $`) and the tashkeel/exact-phrase refinements from the JS
/// reference are intentionally OMITTED in this port (documented in README).
/// Verse search returns mushaf order (unranked) and rejects digit queries.
import 'quran.dart';
import 'models.dart';
import 'text.dart';

/// A verse search hit.
class VerseHit {
  final int surah;
  final int ayah;
  const VerseHit(this.surah, this.ayah);
  String get id => '$surah:$ayah';
}

/// A parsed ayah reference, e.g. "2:255" -> {surah: 2, ayah: 255}.
class Reference {
  final int surah;
  final int? ayah;
  const Reference(this.surah, [this.ayah]);

  @override
  bool operator ==(Object other) =>
      other is Reference && other.surah == surah && other.ayah == ayah;

  @override
  int get hashCode => Object.hash(surah, ayah);

  @override
  String toString() => 'Reference(surah: $surah, ayah: $ayah)';
}

class _VerseEntry {
  final int surah;
  final int ayah;
  final String arabicBlob;
  final String englishBlob;
  final List<String> arabicTokens;
  final List<String> englishTokens;
  _VerseEntry(this.surah, this.ayah, this.arabicBlob, this.englishBlob,
      this.arabicTokens, this.englishTokens);
}

class _SurahEntry {
  final Surah surah;
  final String blob;
  final String compact;
  final String upper;
  _SurahEntry(this.surah, this.blob, this.compact, this.upper);
}

final _digit = RegExp(r'[0-9]');
final _refSplit = RegExp(r'[:\s]+');

class Search {
  final Quran quran;
  final List<_VerseEntry> _index = [];
  final List<_SurahEntry> _surahIndex = [];

  Search(this.quran) {
    _rebuild();
    _buildSurahIndex();
  }

  void _rebuild() {
    _index.clear();
    for (final r in quran.eachAyah()) {
      final raw = quran.arabicText(r.surah.id, r.ayah.id) ?? '';
      final clean = quran.cleanArabicText(r.surah.id, r.ayah.id) ?? '';
      final arabicBlob =
          [raw, clean].map((t) => cleanSearch(t)).join(' ');
      final englishBlob = [
        r.ayah.textEnglishSaheeh,
        r.ayah.textEnglishMustafa,
        r.ayah.textTransliteration,
      ].map((t) => cleanSearch(t)).join(' ');
      _index.add(_VerseEntry(
        r.surah.id,
        r.ayah.id,
        arabicBlob,
        englishBlob,
        searchTokens(arabicBlob),
        searchTokens(englishBlob),
      ));
    }
  }

  void _buildSurahIndex() {
    _surahIndex.clear();
    for (final s in quran.all()) {
      final names = [
        s.nameArabic,
        s.nameTransliteration,
        s.nameEnglish,
        ...s.similarNames,
      ];
      final blob = cleanSearch([...names, s.id.toString()].join(' '));
      _surahIndex.add(_SurahEntry(
        s,
        blob,
        blob.replaceAll(' ', ''),
        '${s.nameEnglish} ${s.nameTransliteration}'.toUpperCase(),
      ));
    }
  }

  /// Search verse text. Returns mushaf-order hits (unranked).
  ///
  /// Rejects any query containing a digit. [ignoreSilentLetters] from the JS
  /// reference is not implemented in this core port.
  List<VerseHit> searchVerses(String query, {int offset = 0, int? limit}) {
    final cleaned = cleanSearch(query, whitespace: true);
    if (cleaned.isEmpty) return const [];
    if (_digit.hasMatch(cleaned)) return const [];

    final useArabic = containsArabicLetters(query);
    final qTokens = searchTokens(cleaned);

    bool matches(_VerseEntry e) {
      if (useArabic) {
        return e.arabicBlob.contains(cleaned) ||
            _phrasePrefixMatch(e.arabicTokens, qTokens);
      }
      return e.englishBlob.contains(cleaned) ||
          _phrasePrefixMatch(e.englishTokens, qTokens);
    }

    final hits = _index
        .where(matches)
        .map((e) => VerseHit(e.surah, e.ayah))
        .toList();
    return _paginate(hits, offset, limit);
  }

  /// Search surahs by name, number, "2:255" reference, or makkan/madani.
  List<Surah> searchSurahs(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return quran.all();

    final norm = cleanSearch(trimmed).replaceAll(' ', '');
    const makkan = ['makkah', 'makkan', 'makki'];
    const madinan = ['madinah', 'madinan', 'madina', 'madani'];
    bool aliasHit(List<String> aliases) =>
        aliases.any((a) => a.startsWith(norm) || norm.startsWith(a));
    if (norm.isNotEmpty && aliasHit(makkan)) {
      return quran.all().where((s) => s.type == 'makkan').toList();
    }
    if (norm.isNotEmpty && aliasHit(madinan)) {
      return quran.all().where((s) => s.type == 'madinan').toList();
    }

    final ref = parseReference(trimmed);
    final cleaned = cleanSearch(trimmed.replaceAll(':', ''));
    final compact = cleaned.replaceAll(' ', '');
    final upper = trimmed.toUpperCase();
    final numeric = ref?.surah ?? _toNumber(cleaned);

    return _surahIndex
        .where((e) =>
            numeric == e.surah.id ||
            (e.upper.isNotEmpty && upper.contains(e.upper)) ||
            (cleaned.isNotEmpty && e.blob.contains(cleaned)) ||
            (compact.isNotEmpty && e.compact.contains(compact)))
        .map((e) => e.surah)
        .toList();
  }

  /// Parse an ayah reference like "2:255", "2 255", or Arabic-digit forms.
  Reference? parseReference(String query) {
    final parts = arabicDigitsToWestern(query)
        .split(_refSplit)
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    int? surah = _toNumber(parts[0]);
    if (surah == null) {
      final cleaned = cleanSearch(parts[0]);
      final compactQ = cleaned.replaceAll(' ', '');
      for (final e in _surahIndex) {
        if (e.blob.split(' ').contains(cleaned) ||
            e.compact.contains(compactQ)) {
          surah = e.surah.id;
          break;
        }
      }
    }
    if (surah == null) return null;
    final ayah = parts.length >= 2 ? _toNumber(parts[1]) : null;
    return Reference(surah, ayah);
  }

  static bool _phrasePrefixMatch(List<String> haystack, List<String> query) {
    if (query.isEmpty || haystack.length < query.length) return false;
    for (var start = 0; start <= haystack.length - query.length; start++) {
      var ok = true;
      for (var k = 0; k < query.length; k++) {
        final word = haystack[start + k];
        final term = query[k];
        if (k == query.length - 1) {
          if (!word.startsWith(term)) {
            ok = false;
            break;
          }
        } else if (word != term) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  static List<T> _paginate<T>(List<T> arr, int offset, int? limit) {
    if (limit == null) return arr.sublist(offset.clamp(0, arr.length));
    final start = offset.clamp(0, arr.length);
    final end = (offset + limit).clamp(0, arr.length);
    return arr.sublist(start, end);
  }

  static int? _toNumber(String s) {
    final t = arabicDigitsToWestern(s).trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }
}
