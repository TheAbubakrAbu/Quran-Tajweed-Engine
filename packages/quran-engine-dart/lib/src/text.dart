/// Arabic text utilities used by the engine. Ported from the JS `text.js`.

/// Remove Quranic recitation marks / diacritics (the "clean Arabic" used for
/// display + search). Mirrors `removingArabicDiacriticsAndSigns`.
String removingArabicDiacriticsAndSigns(String text) {
  final buf = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x0671) {
      buf.write('ا'); // hamzat wasl -> alif
      continue;
    }
    if ((rune >= 0x064b && rune <= 0x065f) ||
        (rune >= 0x06d6 && rune <= 0x06ed) ||
        rune == 0x0670 ||
        rune == 0x0657 ||
        rune == 0x0674 ||
        rune == 0x0656) {
      continue;
    }
    buf.writeCharCode(rune);
  }
  return buf.toString();
}

const _arabicLetterRanges = [
  [0x0600, 0x06ff],
  [0x0750, 0x077f],
  [0x08a0, 0x08ff],
  [0xfb50, 0xfdff],
  [0xfe70, 0xfeff],
  [0x1ee00, 0x1eeff],
];

/// True if the string contains any Arabic-script letter.
bool containsArabicLetters(String text) {
  for (final rune in text.runes) {
    for (final r in _arabicLetterRanges) {
      if (rune >= r[0] && rune <= r[1]) return true;
    }
  }
  return false;
}

const _canonicalArabicMap = {
  'ٰ': 'ا', // dagger alif
  'ٱ': 'ا',
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٲ': 'ا', 'ٳ': 'ا', 'ٵ': 'ا',
  'ؤ': 'و', 'ئ': 'ي', 'ء': '', 'ٴ': '', 'ٶ': 'و', 'ٷ': 'و', 'ٸ': 'ي',
  'ۥ': 'و', // small waw
  'ۦ': 'ي', // small yeh
  'ى': 'ا', // alif maqsura -> alif
  'ة': 'ه', // teh marbuta -> heh
};

const _keptOperators = {'&', '|', '!', '#'};

/// Unicode general categories P (punctuation), S (symbol), M (mark).
/// Dart's RegExp supports `\p{...}` with the `unicode: true` flag.
final _strippable = RegExp(r'[\p{P}\p{S}\p{M}]', unicode: true);
final _whitespace = RegExp(r'\s+', unicode: true);

/// Collapse runs of whitespace into single spaces (no leading/trailing).
String collapsingWhitespace(String text) =>
    text.split(_whitespace).where((s) => s.isNotEmpty).join(' ');

/// The core search normalizer. Mirrors `cleanSearch`:
///   fold Arabic carriers -> strip punctuation/symbols/marks (except & | ! #)
///   -> lowercase -> collapse whitespace.
String cleanSearch(String text, {bool whitespace = false}) {
  var folded = text;
  _canonicalArabicMap.forEach((k, v) {
    folded = folded.replaceAll(k, v);
  });

  final buf = StringBuffer();
  for (final ch in _characters(folded)) {
    if (_keptOperators.contains(ch)) {
      buf.write(ch);
      continue;
    }
    if (_strippable.hasMatch(ch)) continue;
    buf.write(ch);
  }

  var cleaned = collapsingWhitespace(buf.toString().toLowerCase());
  if (whitespace) cleaned = cleaned.trim();
  return cleaned;
}

/// Tokenize a cleaned blob on spaces.
List<String> searchTokens(String cleanedText) =>
    cleanedText.split(' ').where((s) => s.isNotEmpty).toList();

/// Convert Arabic-Indic / Eastern-Arabic digits to Western.
String arabicDigitsToWestern(String text) {
  const map = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };
  final buf = StringBuffer();
  for (final ch in _characters(text)) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

/// Iterate over a string's code points as single-character strings.
Iterable<String> _characters(String text) =>
    text.runes.map((r) => String.fromCharCode(r));
