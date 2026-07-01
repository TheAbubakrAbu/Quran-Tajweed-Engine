/// The 99 Names of Allah (Asmā’ ul-Ḥusnā).
///
/// A thin accessor over `data/names-of-allah.json`. Mirrors `names.js`.

/// A single Name of Allah.
class NameOfAllah {
  /// Arabic.
  final String name;
  final String transliteration;

  /// 1..99.
  final int number;

  /// Ayah references where it appears, e.g. "(1:3) (17:110)".
  final String found;
  final String meaning;
  final String desc;
  final List<String> otherNames;

  const NameOfAllah({
    required this.name,
    required this.transliteration,
    required this.number,
    this.found = '',
    this.meaning = '',
    this.desc = '',
    this.otherNames = const [],
  });

  factory NameOfAllah.fromJson(Map<String, dynamic> json) => NameOfAllah(
        name: json['name'] as String? ?? '',
        transliteration: json['transliteration'] as String? ?? '',
        number: json['number'] as int,
        found: json['found'] as String? ?? '',
        meaning: json['meaning'] as String? ?? '',
        desc: json['desc'] as String? ?? '',
        otherNames:
            (json['otherNames'] as List?)?.cast<String>() ?? const [],
      );
}

/// Accessor over the 99 Names, ordered by number.
class NamesOfAllah {
  final List<NameOfAllah> _list;
  final Map<int, NameOfAllah> _byNumber;

  NamesOfAllah([List<NameOfAllah> list = const []])
      : _list = ([...list]..sort((a, b) => a.number - b.number)),
        _byNumber = {for (final n in list) n.number: n};

  /// Build from already-decoded JSON (a `List` of name maps).
  factory NamesOfAllah.fromJson(List<dynamic> json) => NamesOfAllah(
        json
            .map((e) => NameOfAllah.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// All 99 names, ordered by number.
  List<NameOfAllah> all() => _list;

  /// Lookup a name by its number (1..99). Returns null if absent.
  NameOfAllah? byNumber(int number) => _byNumber[number];
}
