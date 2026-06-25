/// Pure helper functions: zero-padding, audio URLs, cache paths, sorting.
///
/// These mirror the canonical formulas in `docs/PORTING.md` exactly.
import 'models.dart';

/// Zero-pad a number to 3 digits: 1 -> "001", 57 -> "057", 114 -> "114".
String zeroPad3(int n) => n.toString().padLeft(3, '0');

/// Full-surah recitation URL: `surahLink + zeroPad3(surah) + ".mp3"`.
///
/// Throws [RangeError] if [surahNumber] is outside 1..114, or [StateError] if
/// the reciter has no full-surah feed.
String surahAudioUrl(Reciter reciter, int surahNumber) {
  if (surahNumber < 1 || surahNumber > 114) {
    throw RangeError('surah out of range: $surahNumber');
  }
  if (reciter.surahLink.isEmpty) {
    throw StateError('Reciter "${reciter.name}" has no full-surah feed');
  }
  return '${reciter.surahLink}${zeroPad3(surahNumber)}.mp3';
}

/// Ayah-by-ayah recitation URL.
///
/// `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3`.
/// Pass the global ayah number (1..6236) from [Quran.globalAyahNumber].
String ayahAudioUrl(Reciter reciter, int globalAyahNumber) =>
    'https://cdn.islamic.network/quran/audio/'
    '${reciter.ayahBitrate}/${reciter.ayahIdentifier}/$globalAyahNumber.mp3';

const _minshawiFallbackName = 'Muhammad Al-Minshawi (Murattal)';

/// True if this reciter falls back to Minshawi for individual-ayah audio.
bool defaultsToMinshawi(Reciter reciter) =>
    reciter.ayahIdentifier.contains('minshawi') &&
    !reciter.name.contains('Minshawi');

/// Display name to show while ayah audio plays (honest about the fallback).
String ayahNowPlayingName(Reciter reciter) {
  if (defaultsToMinshawi(reciter)) return _minshawiFallbackName;
  if (reciter.qiraah != null) return '${reciter.name} (${reciter.qiraah})';
  return reciter.name;
}

final _unsafeDirChars = RegExp(r'[^A-Za-z0-9\-_]');

/// Sanitize a reciter id into a filesystem-safe directory name.
///
/// Keep `[A-Za-z0-9-_]`, replace everything else with `_`, cap at 180 chars,
/// fall back to "reciter" if empty.
String sanitizeReciterDir(String reciterId) {
  var safe = reciterId.replaceAll(_unsafeDirChars, '_');
  if (safe.length > 180) safe = safe.substring(0, 180);
  return safe.isEmpty ? 'reciter' : safe;
}

/// Relative cache path for a downloaded full-surah file:
/// `sanitizeReciterDir(reciter.id) + "/" + zeroPad3(surah) + ".mp3"`.
String localSurahPath(Reciter reciter, int surahNumber) =>
    '${sanitizeReciterDir(reciter.id)}/${zeroPad3(surahNumber)}.mp3';

/// Relative path of the content-addressed shared file for a given content hash.
String sharedAudioPath(String sha256Hex, [String ext = 'mp3']) =>
    'SharedAudio/$sha256Hex.$ext';

/// Surah sort modes.
enum SortMode { surah, revelation, ayahs, page, words, letters }

/// Sort directions.
enum SortDirection { surahOrder, ascending, descending }

const _directional = {
  SortMode.revelation,
  SortMode.page,
  SortMode.ayahs,
  SortMode.words,
  SortMode.letters,
};

/// Whether a sort mode honours a direction (others are intrinsically ordered).
bool supportsDirection(SortMode mode) => _directional.contains(mode);

int _sortKey(Surah s, SortMode mode) {
  switch (mode) {
    case SortMode.revelation:
      // Number.MAX_SAFE_INTEGER fallback in JS.
      return s.revelationOrder ?? 9007199254740991;
    case SortMode.ayahs:
      return s.numberOfAyahs;
    case SortMode.page:
      return s.numberOfPages ?? 0;
    case SortMode.words:
      return s.wordCount ?? 0;
    case SortMode.letters:
      return s.letterCount ?? 0;
    case SortMode.surah:
      return s.id;
  }
}

SortMode _parseMode(Object mode) {
  if (mode is SortMode) return mode;
  switch (mode as String) {
    case 'surah':
      return SortMode.surah;
    case 'revelation':
      return SortMode.revelation;
    case 'ayahs':
      return SortMode.ayahs;
    case 'page':
      return SortMode.page;
    case 'words':
      return SortMode.words;
    case 'letters':
      return SortMode.letters;
    default:
      throw ArgumentError('Unknown sort mode: $mode');
  }
}

SortDirection _parseDirection(Object direction) {
  if (direction is SortDirection) return direction;
  switch (direction as String) {
    case 'surahOrder':
      return SortDirection.surahOrder;
    case 'ascending':
      return SortDirection.ascending;
    case 'descending':
      return SortDirection.descending;
    default:
      throw ArgumentError('Unknown sort direction: $direction');
  }
}

/// Sort surahs by [mode]/[direction].
///
/// Comparators are ascending with `id` as the tiebreaker; descending is the
/// reverse of the ascending array. `mode == surah` or `direction == surahOrder`
/// returns natural 1..114 order. [mode] and [direction] accept either the enum
/// or the equivalent string (e.g. `"ayahs"`, `"descending"`).
List<Surah> sortSurahs(
  List<Surah> surahs, [
  Object mode = SortMode.surah,
  Object direction = SortDirection.ascending,
]) {
  final m = _parseMode(mode);
  final d = _parseDirection(direction);

  if (d == SortDirection.surahOrder || m == SortMode.surah) {
    final out = [...surahs]..sort((a, b) => a.id - b.id);
    return out;
  }

  final asc = [...surahs]..sort((a, b) {
      final ka = _sortKey(a, m), kb = _sortKey(b, m);
      if (ka == kb) return a.id - b.id;
      return ka - kb;
    });

  if (d == SortDirection.descending && _directional.contains(m)) {
    return asc.reversed.toList();
  }
  return asc;
}

/// Filter by revelation type ("makkan" | "madinan").
List<Surah> filterByRevelationType(List<Surah> surahs, String type) =>
    surahs.where((s) => s.type == type).toList();
