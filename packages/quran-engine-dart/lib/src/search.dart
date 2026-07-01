/// Ayah & surah search. Faithful port of the search system in `search.js`.
///
/// Verse matching is unranked — results come back in mushaf order (surah, then
/// ayah). Each verse is indexed into Arabic/English blobs plus token lists.
///
/// Regular (non-boolean) verse search is a PURE SUBSTRING match against the
/// folded blobs. Word/sentence boundaries DON'T matter (e.g. "رب" matches
/// inside "ربهم"). Whole-word / phrase / prefix matching lives only in the
/// boolean grammar (`& | ! # ^ % $ =`).
import 'quran.dart';
import 'models.dart';
import 'text.dart';

/// Match mode for a single boolean search term.
enum MatchMode { contains, startsWith, endsWith, exact, wholeWord }

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
  final String arabicTashkeelBlob;
  final String englishExactBlob;
  final String arabicBlob;
  final String silentArabicBlob;
  final String englishBlob;
  final List<String> arabicTokens;
  final List<String> silentArabicTokens;
  final List<String> englishTokens;
  _VerseEntry(
    this.surah,
    this.ayah,
    this.arabicTashkeelBlob,
    this.englishExactBlob,
    this.arabicBlob,
    this.silentArabicBlob,
    this.englishBlob,
    this.arabicTokens,
    this.silentArabicTokens,
    this.englishTokens,
  );
}

/// A parsed boolean term. Mirrors the object returned by `parseTerm`.
class _Term {
  final String value;
  final bool negate;
  final MatchMode matchMode;
  final bool requiresTashkeelMatch;
  final String tashkeelPattern;
  final bool requiresExactEnglishMatch;
  final String exactEnglishPhrase;
  _Term({
    required this.value,
    required this.negate,
    required this.matchMode,
    required this.requiresTashkeelMatch,
    required this.tashkeelPattern,
    required this.requiresExactEnglishMatch,
    required this.exactEnglishPhrase,
  });
}

class _SurahEntry {
  final Surah surah;
  final String blob;
  final String compact;
  final String upper;
  _SurahEntry(this.surah, this.blob, this.compact, this.upper);
}

final _booleanChars = RegExp(r'[&|!#^%$=]');
// Unicode decimal-digit (general category Nd), NOT ASCII-only [0-9]. Mirrors
// the JS `/\p{Nd}/u` digit-rejection test.
final _digit = RegExp(r'\p{Nd}', unicode: true);
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
      final saheeh = r.ayah.textEnglishSaheeh;
      final mustafa = r.ayah.textEnglishMustafa;
      final translit = r.ayah.textTransliteration;

      final arabicBlob = [raw, clean].map((t) => cleanSearch(t)).join(' ');
      final silentArabicBlob = [raw, clean]
          .map((t) => cleanSearch(removingSilentArabicLettersForSearch(t)))
          .join(' ');
      final englishBlob =
          [saheeh, mustafa, translit].map((t) => cleanSearch(t)).join(' ');

      _index.add(_VerseEntry(
        r.surah.id,
        r.ayah.id,
        arabicTashkeelBlob(raw),
        exactPhraseBlob([saheeh, mustafa, translit].join(' ')),
        arabicBlob,
        silentArabicBlob,
        englishBlob,
        searchTokens(arabicBlob),
        searchTokens(silentArabicBlob),
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
  /// Order of operations mirrors `searchVerses`: clean query -> empty? []
  /// -> contains a Unicode decimal digit? [] -> boolean grammar? boolean path
  /// -> else pure-substring regular path.
  List<VerseHit> searchVerses(
    String query, {
    int offset = 0,
    int? limit,
    bool ignoreSilentLetters = false,
  }) {
    final cleaned = cleanSearch(query, whitespace: true);
    if (cleaned.isEmpty) return const [];

    // Reject any query containing a digit (numeric/refs go via surah search).
    // Done BEFORE the boolean path, so even a boolean query with a digit
    // returns [] (e.g. "allah & 2").
    if (_containsDigit(cleaned)) return const [];

    // Boolean grammar?
    if (_booleanChars.hasMatch(query)) {
      return _booleanSearch(query, offset: offset, limit: limit);
    }

    final useArabic = containsArabicLetters(query);
    final silentQuery = useArabic && ignoreSilentLetters
        ? cleanSearch(removingSilentArabicLettersForSearch(query),
            whitespace: true)
        : '';

    bool matches(_VerseEntry e) {
      if (useArabic) {
        if (e.arabicBlob.contains(cleaned)) return true;
        if (silentQuery.isEmpty) return false;
        return e.silentArabicBlob.contains(silentQuery);
      }
      return e.englishBlob.contains(cleaned);
    }

    final hits = _index
        .where(matches)
        .map((e) => VerseHit(e.surah, e.ayah))
        .toList();
    return _paginate(hits, offset, limit);
  }

  // ---- Boolean search --------------------------------------------------------
  List<VerseHit> _booleanSearch(String query, {int offset = 0, int? limit}) {
    final useArabic = containsArabicLetters(query);
    final normalized = query.replaceAll('&&', '&').replaceAll('||', '|');
    // Drop any term whose cleaned value is empty.
    final orGroups = normalized
        .split('|')
        .map((g) => g
            .split('&')
            .map((t) => _parseTerm(t))
            .where((t) => t.value.isNotEmpty)
            .toList())
        .where((g) => g.isNotEmpty)
        .toList();
    if (orGroups.isEmpty) return const [];

    bool matches(_VerseEntry e) => orGroups.any((andTerms) => andTerms.every((term) {
          final hit = _termMatch(e, term, useArabic);
          return term.negate ? !hit : hit;
        }));

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

  // ---- helpers ---------------------------------------------------------------

  /// True if [cleaned] contains any Unicode decimal digit (not ASCII-only).
  static bool _containsDigit(String cleaned) => _digit.hasMatch(cleaned);

  /// Parse a single boolean term. Mirrors `parseTerm`: strips (in order)
  /// leading `!` (negate, toggles), `#` (tashkeel-sensitive), `=` (whole-word),
  /// one `^` (starts-with), one trailing `%`/`$` (ends-with).
  static _Term _parseTerm(String rawTerm) {
    var t = rawTerm.trim();
    var negate = false;
    while (t.startsWith('!')) {
      negate = !negate;
      t = t.substring(1).trim();
    }
    var requiresTashkeel = false;
    while (t.startsWith('#')) {
      requiresTashkeel = true;
      t = t.substring(1).trim();
    }
    var wholeWord = false;
    while (t.startsWith('=')) {
      wholeWord = true;
      t = t.substring(1).trim();
    }
    var startsWith = false;
    if (t.startsWith('^')) {
      startsWith = true;
      t = t.substring(1).trim();
    }
    var endsWith = false;
    if (t.endsWith('%') || t.endsWith('\$')) {
      endsWith = true;
      t = t.substring(0, t.length - 1).trim();
    }

    final value = cleanSearch(t, whitespace: true);
    final MatchMode matchMode;
    if (wholeWord) {
      matchMode = MatchMode.wholeWord;
    } else if (startsWith && endsWith) {
      matchMode = MatchMode.exact;
    } else if (startsWith) {
      matchMode = MatchMode.startsWith;
    } else if (endsWith) {
      matchMode = MatchMode.endsWith;
    } else {
      matchMode = MatchMode.contains;
    }

    final isArabic = containsArabicLetters(t);
    return _Term(
      value: value,
      negate: negate,
      matchMode: matchMode,
      requiresTashkeelMatch: requiresTashkeel && isArabic,
      tashkeelPattern: arabicTashkeelBlob(t),
      requiresExactEnglishMatch: requiresTashkeel && !isArabic,
      exactEnglishPhrase: exactPhraseBlob(t),
    );
  }

  /// Match a single term's value against a blob/token list. Mirrors
  /// `ayahTermMatch`.
  static bool _ayahTermMatch(
      String haystack, List<String> tokens, String term, MatchMode mode) {
    switch (mode) {
      case MatchMode.contains:
        return haystack.contains(term);
      case MatchMode.startsWith:
        return haystack.startsWith(term) || tokens.any((w) => w.startsWith(term));
      case MatchMode.endsWith:
        return haystack.endsWith(term) || tokens.any((w) => w.endsWith(term));
      case MatchMode.exact:
        return haystack == term || tokens.contains(term);
      case MatchMode.wholeWord:
        return _consecutiveTokenMatch(tokens, searchTokens(term), true);
    }
  }

  /// Per-term match (un-negated). Mirrors `termMatch`.
  static bool _termMatch(_VerseEntry e, _Term term, bool useArabic) {
    if (useArabic && term.requiresTashkeelMatch) {
      final lettersMatch =
          _ayahTermMatch(e.arabicBlob, e.arabicTokens, term.value, term.matchMode);
      final tashkeelMatch = term.tashkeelPattern.isEmpty ||
          e.arabicTashkeelBlob.contains(term.tashkeelPattern);
      return lettersMatch && tashkeelMatch;
    }
    if (!useArabic && term.requiresExactEnglishMatch) {
      final exactTokens = searchTokens(term.exactEnglishPhrase);
      return term.exactEnglishPhrase.isNotEmpty &&
          _ayahTermMatch(e.englishExactBlob, exactTokens, term.exactEnglishPhrase,
              term.matchMode);
    }
    final haystack = useArabic ? e.arabicBlob : e.englishBlob;
    final tokens = useArabic ? e.arabicTokens : e.englishTokens;
    return _ayahTermMatch(haystack, tokens, term.value, term.matchMode);
  }

  /// Consecutive-token match: query tokens appear as a consecutive run of
  /// haystack tokens. Leading tokens must match exactly; the final token must
  /// match exactly when [lastMustBeExact], otherwise it only has to be a
  /// prefix. Mirrors `consecutiveTokenMatch`.
  static bool _consecutiveTokenMatch(
      List<String> haystack, List<String> query, bool lastMustBeExact) {
    if (query.isEmpty || haystack.length < query.length) return false;
    for (var start = 0; start <= haystack.length - query.length; start++) {
      var ok = true;
      for (var k = 0; k < query.length; k++) {
        final word = haystack[start + k];
        final term = query[k];
        if (k == query.length - 1 && !lastMustBeExact) {
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
