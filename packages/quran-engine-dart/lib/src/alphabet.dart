// The Arabic alphabet as a Quran reader meets it: every letter with its joining
// forms, its name and transliteration, and - the part that matters for tajweed -
// its WEIGHT.
//
// Weight is why this belongs in a tajweed engine rather than in a phrasebook.
// Every letter is pronounced thin (tarqiq) or full (tafkhim), a few depend on
// context (raa, and the lam of the divine name), and alif has no weight of its
// own at all: it inherits the letter before it. That single fact is behind a
// large share of beginner mistakes, and it is a property of the letter, not of
// any particular verse, so it lives here beside the letter and not in the
// annotation corpus.
//
// Also carried: the letters outside the 28, the six Persian/Urdu letters some
// printed mushafs use, the Eastern-Arabic numerals, the tashkeel marks, and the
// waqf (stopping) signs.
//
// See `../../docs/16-arabic-alphabet.md`.

/// One letter of the reference.
class ArabicLetter {
  final int id;

  /// The isolated form.
  final String letter;

  /// Final, medial and initial, as the source records them.
  final List<String> forms;
  final String name;
  final String transliteration;
  final bool showTashkeel;
  final String sound;

  /// `"light"`, `"heavy"`, `"conditional"`, `"followsPrevious"` - or null where
  /// none is recorded.
  final String? weight;

  /// Why, in one sentence.
  final String? weightRule;

  const ArabicLetter({
    required this.id,
    required this.letter,
    required this.forms,
    required this.name,
    required this.transliteration,
    required this.showTashkeel,
    required this.sound,
    this.weight,
    this.weightRule,
  });

  factory ArabicLetter.fromJson(Map<String, dynamic> json) => ArabicLetter(
        id: json['id'] as int? ?? 0,
        letter: json['letter'] as String? ?? '',
        forms: ((json['forms'] as List<dynamic>?) ?? const []).cast<String>(),
        name: json['name'] as String? ?? '',
        transliteration: json['transliteration'] as String? ?? '',
        showTashkeel: json['showTashkeel'] as bool? ?? false,
        sound: json['sound'] as String? ?? '',
        weight: json['weight'] as String?,
        weightRule: json['weightRule'] as String?,
      );
}

/// One vowel mark.
class Tashkeel {
  final String english;
  final String arabic;
  final String mark;
  final String transliteration;
  const Tashkeel(this.english, this.arabic, this.mark, this.transliteration);

  factory Tashkeel.fromJson(Map<String, dynamic> json) => Tashkeel(
        json['english'] as String? ?? '',
        json['arabic'] as String? ?? '',
        json['mark'] as String? ?? '',
        json['transliteration'] as String? ?? '',
      );
}

/// One waqf sign and what it tells the reciter to do.
class StoppingSign {
  final String symbol;
  final String title;
  const StoppingSign(this.symbol, this.title);

  factory StoppingSign.fromJson(Map<String, dynamic> json) => StoppingSign(
        json['symbol'] as String? ?? '',
        json['title'] as String? ?? '',
      );
}

/// One Eastern-Arabic digit.
class ArabicNumeral {
  final String number;
  final String name;
  final String transliteration;
  final String englishNumber;
  const ArabicNumeral(
      this.number, this.name, this.transliteration, this.englishNumber);

  factory ArabicNumeral.fromJson(Map<String, dynamic> json) => ArabicNumeral(
        json['number'] as String? ?? '',
        json['name'] as String? ?? '',
        json['transliteration'] as String? ?? '',
        json['englishNumber'] as String? ?? '',
      );
}

class ArabicAlphabet {
  final Map<String, dynamic> _data;

  const ArabicAlphabet([this._data = const {}]);

  List<ArabicLetter> _letters(String key) =>
      ((_data[key] as List<dynamic>?) ?? const [])
          .map((e) => ArabicLetter.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  /// The 28 letters of the alphabet, in order.
  List<ArabicLetter> letters() => _letters('standardLetters');

  /// Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28.
  List<ArabicLetter> otherLetters() => _letters('otherLetters');

  /// The Persian/Urdu letters some printed mushafs use for non-Arabic sounds.
  List<ArabicLetter> nonArabicScriptLetters() => _letters('nonArabicScriptLetters');

  /// Every letter this reference knows, the 28 first.
  List<ArabicLetter> allLetters() =>
      [...letters(), ...otherLetters(), ...nonArabicScriptLetters()];

  /// One letter by its isolated form. Accepts any of its joining forms too, so a
  /// letter lifted out of a word still resolves.
  ArabicLetter? letter(String letter) {
    final wanted = letter.trim();
    if (wanted.isEmpty) return null;
    for (final entry in allLetters()) {
      if (entry.letter == wanted || entry.forms.contains(wanted)) return entry;
    }
    return null;
  }

  ArabicLetter? letterById(int id) {
    for (final entry in allLetters()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// The tajweed weight of a letter, or null when the reference records none.
  String? weight(String letter) => this.letter(letter)?.weight;

  /// What a weight name means, in one line.
  Map<String, String> weightDescriptions() =>
      ((_data['weights'] as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k, v as String));

  /// The letters pronounced full - the isti'la letters.
  List<ArabicLetter> heavyLetters() =>
      letters().where((l) => l.weight == 'heavy').toList(growable: false);

  List<Tashkeel> tashkeel() => ((_data['tashkeel'] as List<dynamic>?) ?? const [])
      .map((e) => Tashkeel.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  /// The waqf signs, with what each one tells the reciter to do.
  List<StoppingSign> stoppingSigns() =>
      ((_data['stoppingSigns'] as List<dynamic>?) ?? const [])
          .map((e) => StoppingSign.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  StoppingSign? stoppingSign(String symbol) {
    for (final sign in stoppingSigns()) {
      if (sign.symbol == symbol) return sign;
    }
    return null;
  }

  /// The Eastern-Arabic numerals, 0 through 10.
  List<ArabicNumeral> numbers() => ((_data['numbers'] as List<dynamic>?) ?? const [])
      .map((e) => ArabicNumeral.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  String stoppingSignsSource() => _data['stoppingSignsSource'] as String? ?? '';
}
