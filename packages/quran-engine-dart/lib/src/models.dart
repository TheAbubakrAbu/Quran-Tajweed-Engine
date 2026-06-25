/// Plain data models for the Quran engine.
///
/// Every `fromJson` factory maps the camelCase keys used by the JSON corpus in
/// `/data` (see `docs/PORTING.md`). Models are immutable value objects.

/// A single ayah (verse).
class Ayah {
  final int id;

  /// Hafs Uthmani text with full diacritics.
  final String textArabic;
  final String textTransliteration;

  /// Saheeh International translation.
  final String textEnglishSaheeh;

  /// Mustafa Khattab (The Clear Quran) translation.
  final String textEnglishMustafa;

  final int? juz;
  final int? page;
  final int? wordCount;
  final int? letterCount;

  const Ayah({
    required this.id,
    required this.textArabic,
    this.textTransliteration = '',
    this.textEnglishSaheeh = '',
    this.textEnglishMustafa = '',
    this.juz,
    this.page,
    this.wordCount,
    this.letterCount,
  });

  factory Ayah.fromJson(Map<String, dynamic> json) => Ayah(
        id: json['id'] as int,
        textArabic: json['textArabic'] as String? ?? '',
        textTransliteration: json['textTransliteration'] as String? ?? '',
        textEnglishSaheeh: json['textEnglishSaheeh'] as String? ?? '',
        textEnglishMustafa: json['textEnglishMustafa'] as String? ?? '',
        juz: json['juz'] as int?,
        page: json['page'] as int?,
        wordCount: json['wordCount'] as int?,
        letterCount: json['letterCount'] as int?,
      );
}

/// A surah (chapter), including its ayahs.
class Surah {
  final int id;

  /// "makkan" | "madinan".
  final String type;
  final String nameArabic;
  final String nameTransliteration;
  final String nameEnglish;
  final int numberOfAyahs;
  final int? pageStart;
  final int? pageEnd;
  final int? numberOfPages;
  final int? firstJuz;
  final int? lastJuz;
  final List<int> juzs;
  final int? revelationOrder;
  final List<String> similarNames;
  final int? wordCount;
  final int? letterCount;
  final List<Ayah> ayahs;

  const Surah({
    required this.id,
    required this.type,
    required this.nameArabic,
    required this.nameTransliteration,
    required this.nameEnglish,
    required this.numberOfAyahs,
    this.pageStart,
    this.pageEnd,
    this.numberOfPages,
    this.firstJuz,
    this.lastJuz,
    this.juzs = const [],
    this.revelationOrder,
    this.similarNames = const [],
    this.wordCount,
    this.letterCount,
    this.ayahs = const [],
  });

  factory Surah.fromJson(Map<String, dynamic> json) => Surah(
        id: json['id'] as int,
        type: json['type'] as String? ?? '',
        nameArabic: json['nameArabic'] as String? ?? '',
        nameTransliteration: json['nameTransliteration'] as String? ?? '',
        nameEnglish: json['nameEnglish'] as String? ?? '',
        numberOfAyahs: json['numberOfAyahs'] as int? ?? 0,
        pageStart: json['pageStart'] as int?,
        pageEnd: json['pageEnd'] as int?,
        numberOfPages: json['numberOfPages'] as int?,
        firstJuz: json['firstJuz'] as int?,
        lastJuz: json['lastJuz'] as int?,
        juzs: (json['juzs'] as List?)?.cast<int>() ?? const [],
        revelationOrder: json['revelationOrder'] as int?,
        similarNames:
            (json['similarNames'] as List?)?.cast<String>() ?? const [],
        wordCount: json['wordCount'] as int?,
        letterCount: json['letterCount'] as int?,
        ayahs: (json['ayahs'] as List?)
                ?.map((e) => Ayah.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// A juz (para) boundary entry from `data/juz.json`.
class JuzEntry {
  final int id;
  final String nameArabic;
  final String nameTransliteration;
  final int startSurah;
  final int startAyah;
  final int endSurah;
  final int endAyah;

  const JuzEntry({
    required this.id,
    required this.nameArabic,
    required this.nameTransliteration,
    required this.startSurah,
    required this.startAyah,
    required this.endSurah,
    required this.endAyah,
  });

  factory JuzEntry.fromJson(Map<String, dynamic> json) => JuzEntry(
        id: json['id'] as int,
        nameArabic: json['nameArabic'] as String? ?? '',
        nameTransliteration: json['nameTransliteration'] as String? ?? '',
        startSurah: json['startSurah'] as int,
        startAyah: json['startAyah'] as int,
        endSurah: json['endSurah'] as int,
        endAyah: json['endAyah'] as int,
      );
}

/// A reciter from `data/reciters.json`.
///
/// `id` = `"{name}|{qiraah or 'Hafs'}|{surahLink}"`. `qiraah` is null for Hafs.
class Reciter {
  final String id;
  final String name;

  /// e.g. "ar.alafasy" — used for the ayah-by-ayah CDN path.
  final String ayahIdentifier;

  /// e.g. "128" — used verbatim (a string) in the ayah URL.
  final String ayahBitrate;

  /// Full-surah CDN base, with a trailing slash.
  final String surahLink;

  /// null => Hafs; otherwise the riwayah label.
  final String? qiraah;
  final String? group;

  const Reciter({
    required this.id,
    required this.name,
    required this.ayahIdentifier,
    required this.ayahBitrate,
    required this.surahLink,
    this.qiraah,
    this.group,
  });

  factory Reciter.fromJson(Map<String, dynamic> json) => Reciter(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        ayahIdentifier: json['ayahIdentifier'] as String? ?? '',
        ayahBitrate: json['ayahBitrate'] as String? ?? '',
        surahLink: json['surahLink'] as String? ?? '',
        qiraah: json['qiraah'] as String?,
        group: json['group'] as String?,
      );
}

/// A colored tajweed span over a slice of an ayah's Arabic text.
///
/// `start`/`end` are UTF-16 code-unit offsets into [Ayah.textArabic]. Because
/// Dart `String`s are UTF-16, `text.substring(start, end) == text`.
class TajweedSpan {
  /// UTF-16 start offset (inclusive).
  final int start;

  /// UTF-16 end offset (exclusive).
  final int end;

  /// The tajweed rule id (e.g. "lamShamsiyah"); maps to a category id.
  final String rule;

  /// Hex color for the rule, e.g. "#B4B4B4", or null if the rule is unknown.
  final String? colorHex;

  /// The exact substring of the ayah this span covers.
  final String text;

  const TajweedSpan({
    required this.start,
    required this.end,
    required this.rule,
    required this.colorHex,
    required this.text,
  });
}
