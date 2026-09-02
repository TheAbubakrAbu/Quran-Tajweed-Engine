/// The `Engine` facade ties the modules together.
///
/// Two ways to build it:
///   • `Engine.load({dataDir})`     — reads JSON from disk (dart:io). Default
///     locates the repo `/data` by walking up from the current directory.
///   • `Engine.fromJson(...)`       — accepts already-decoded JSON. Use this in
///     Flutter, where the data is bundled as assets and loaded via `rootBundle`.
import 'dart:convert';
import 'dart:io';

import 'quran.dart';
import 'juz_page.dart';
import 'mushaf.dart';
import 'qiraat_tajweed.dart';
import 'word_by_word.dart';
import 'corpora.dart';
import 'ask_ai.dart';
import 'sections.dart';
import 'alphabet.dart';
import 'qiraat_comparison.dart';
import 'reciters.dart';
import 'search.dart';
import 'tajweed.dart';
import 'names.dart';
import 'muqattaat.dart';
import 'models.dart';

class Engine {
  final Quran quran;
  final JuzPage juzPage;
  final Reciters reciters;
  final Search search;
  final Tajweed tajweed;
  final NamesOfAllah namesOfAllah;
  final Muqattaat muqattaat;

  /// The printed facsimiles and their page tables. Empty unless `loadMushaf`.
  final Mushaf mushaf;

  /// Per-riwayah printed tajweed. Empty unless `loadQiraatTajweed`.
  final QiraatTajweed qiraatTajweed;

  /// The two aligned gloss layers. Empty unless `loadWordByWord`.
  final WordByWord wordByWord;

  /// Mutashabihat. Empty unless `loadSimilarAyahs`.
  final SimilarAyahs similarAyahs;

  /// The curated topics; loaded by default.
  final Themes themes;

  /// The tajweed course; loaded by default.
  final TajweedLessons tajweedLessons;

  /// Ask AI's retrieval and prompt.
  final AskAI askAI;

  /// The per-surah outlines; loaded by default.
  final SurahSections surahSections;

  /// The letter/tashkeel/waqf reference; loaded by default.
  final ArabicAlphabet alphabet;

  /// Needs `loadQiraat`; with no qiraah text it reports "hafs" alone.
  final QiraatComparison qiraatComparison;

  Engine({
    required this.quran,
    required this.juzPage,
    required this.reciters,
    required this.tajweed,
    NamesOfAllah? namesOfAllah,
    Muqattaat? muqattaat,
    Mushaf? mushaf,
    QiraatTajweed? qiraatTajweed,
    WordByWord? wordByWord,
    SimilarAyahs? similarAyahs,
    Themes? themes,
    TajweedLessons? tajweedLessons,
    SurahSections? surahSections,
    ArabicAlphabet? alphabet,
  })  : search = Search(quran),
        surahSections = surahSections ?? const SurahSections(),
        alphabet = alphabet ?? const ArabicAlphabet(),
        qiraatComparison = QiraatComparison(quran),
        namesOfAllah = namesOfAllah ?? NamesOfAllah(),
        muqattaat = muqattaat ?? Muqattaat(),
        mushaf = mushaf ?? Mushaf(),
        qiraatTajweed = qiraatTajweed ?? QiraatTajweed(),
        wordByWord = wordByWord ?? WordByWord(),
        similarAyahs = similarAyahs ?? const SimilarAyahs(),
        themes = themes ?? Themes(),
        tajweedLessons = tajweedLessons ?? TajweedLessons(),
        askAI = AskAI(
          quran: quran,
          search: Search(quran),
          themes: themes ?? Themes(),
        );

  /// Build from already-decoded JSON. Pass the parsed contents of each file.
  ///
  /// [quranJson]            — `data/quran.json` (a List).
  /// [juzJson]              — `data/juz.json` (a List).
  /// [recitersJson]         — `data/reciters.json` (a List).
  /// [tajweedRulesJson]     — `data/tajweed-rules.json` (a Map).
  /// [tajweedAnnotationsJson] — `tajweed-annotations.json` (a List).
  /// [surahInfoJson]        — `data/surah-info.json` (a List), optional.
  /// [namesOfAllahJson]     — `data/names-of-allah.json` (a List), optional.
  /// [muqattaatJson]        — `data/muqattaat.json` (a Map), optional.
  /// [qiraatCountsJson]     — `data/qiraat-counts.json` (a Map), optional.
  factory Engine.fromJson({
    required List<dynamic> quranJson,
    required List<dynamic> juzJson,
    required List<dynamic> recitersJson,
    required Map<String, dynamic> tajweedRulesJson,
    required List<dynamic> tajweedAnnotationsJson,
    List<dynamic>? surahInfoJson,
    List<dynamic>? namesOfAllahJson,
    Map<String, dynamic>? muqattaatJson,
    Map<String, dynamic>? qiraatCountsJson,
    Map<String, dynamic>? themesJson,
    Map<String, dynamic>? tajweedLessonsJson,
    Map<String, dynamic>? mushafIndexJson,
    Map<String, Map<String, dynamic>> mushafPagesJson = const {},
    Map<String, Map<String, dynamic>> mushafLinesJson = const {},
    Map<String, dynamic>? qiraatTajweedRulesJson,
    Map<String, Map<String, dynamic>> qiraatTajweedPacksJson = const {},
    Map<String, dynamic>? wordByWordJson,
    Map<String, dynamic>? similarAyahsJson,
    Map<String, dynamic>? surahSectionsJson,
    Map<String, dynamic>? arabicAlphabetJson,
    Map<String, Map<String, dynamic>> qiraatJson = const {},
  }) {
    final quran =
        Quran.fromJson(quranJson, surahInfoJson, qiraatCountsJson, qiraatJson);
    return Engine(
      quran: quran,
      juzPage: JuzPage.fromJson(quran, juzJson),
      reciters: Reciters.fromJson(recitersJson),
      tajweed: Tajweed.fromJson(quran, tajweedRulesJson, tajweedAnnotationsJson),
      namesOfAllah: namesOfAllahJson == null
          ? NamesOfAllah()
          : NamesOfAllah.fromJson(namesOfAllahJson),
      muqattaat:
          muqattaatJson == null ? Muqattaat() : Muqattaat.fromJson(muqattaatJson),
      themes: Themes(themesJson),
      tajweedLessons: TajweedLessons(tajweedLessonsJson),
      mushaf: Mushaf(
        index: mushafIndexJson,
        pages: mushafPagesJson,
        lines: mushafLinesJson,
      ),
      qiraatTajweed: QiraatTajweed(
        rules: qiraatTajweedRulesJson ?? const {},
        riwayat: qiraatTajweedPacksJson,
      ),
      wordByWord: WordByWord(pack: wordByWordJson, quran: quran),
      similarAyahs: SimilarAyahs(similarAyahsJson ?? const {}),
      surahSections: SurahSections(surahSectionsJson ?? const {}),
      alphabet: ArabicAlphabet(arabicAlphabetJson ?? const {}),
    );
  }

  /// Load all canonical data from disk and build the engine (Dart VM only).
  ///
  /// [dataDir] overrides the data directory; otherwise the repo `/data` is
  /// located by walking up from `Directory.current` until a `quran.json` is
  /// found under a `data/` folder.
  /// The seven verified non-Hafs riwayat that carry a tajweed pack. The twelve
  /// whose text is not published have no pack: their rules index into that text.
  static const List<String> qiraatTajweedSlugs = [
    'warsh', 'qaloon', 'duri', 'susi', 'buzzi', 'qunbul', 'shubah',
  ];

  /// Load all canonical data from disk and build the engine (Dart VM only).
  ///
  /// The heavier corpora are opt-in: [loadMushaf] reads `mushaf/index.json` plus
  /// every riwayah's page table (and line table, where the text ships),
  /// [loadQiraatTajweed] the shared rule catalogue and the seven verified packs,
  /// [loadWordByWord] both aligned gloss layers, [loadSimilarAyahs] the
  /// mutashabihat. `themes.json` and `tajweed-lessons.json` always load: together
  /// they are ~250 KB, and a topic list is the kind of thing a consumer wants
  /// without a flag.
  static Future<Engine> load({
    String? dataDir,
    bool loadMushaf = false,
    bool loadQiraatTajweed = false,
    bool loadWordByWord = false,
    bool loadSimilarAyahs = false,
    bool loadQiraat = false,
  }) async {
    final dir = dataDir ?? _locateDataDir();
    if (dir == null) {
      throw StateError(
          'Could not locate a data directory (looked for data/quran.json '
          'walking up from ${Directory.current.path}). Pass dataDir explicitly.');
    }

    Future<dynamic> read(String rel) async {
      final file = File('$dir${Platform.pathSeparator}$rel');
      return jsonDecode(await file.readAsString());
    }

    final results = await Future.wait([
      read('quran.json'),
      read('juz.json'),
      read('reciters.json'),
      read('tajweed-rules.json'),
      read('tajweed-annotations.json'),
      read('surah-info.json'),
      read('names-of-allah.json'),
      read('muqattaat.json'),
      read('qiraat-counts.json'),
    ]);

    Future<Map<String, dynamic>?> readOptional(String rel) async {
      // A missing optional corpus is not an error — the accessors simply return
      // nothing — but a file that IS there and will not parse still throws, so a
      // corrupt pack fails loudly instead of silently disappearing.
      final file = File('$dir${Platform.pathSeparator}$rel');
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }

    final themesJson = await readOptional('themes.json');
    // Sections (80 KB) and the alphabet (18 KB) join the always-loaded set: small,
    // and both answer questions a consumer should not have to opt into.
    final surahSectionsJson = await readOptional('surah-sections.json');
    final arabicAlphabetJson = await readOptional('arabic-alphabet.json');

    final qiraatJson = <String, Map<String, dynamic>>{};
    if (loadQiraat) {
      for (final slug in qiraatTajweedSlugs) {
        qiraatJson[slug] =
            await read('qiraat/qiraah-$slug.json') as Map<String, dynamic>;
      }
    }
    final lessonsJson = await readOptional('tajweed-lessons.json');

    Map<String, dynamic>? mushafIndexJson;
    final mushafPages = <String, Map<String, dynamic>>{};
    final mushafLines = <String, Map<String, dynamic>>{};
    if (loadMushaf) {
      mushafIndexJson = await read('mushaf/index.json') as Map<String, dynamic>;
      for (final raw in (mushafIndexJson['riwayat'] as List<dynamic>)) {
        final entry = raw as Map<String, dynamic>;
        final slug = entry['riwayah'] as String;
        mushafPages[slug] =
            await read('mushaf/${entry['pages']}') as Map<String, dynamic>;
        final lines = entry['lines'] as String?;
        if (lines != null) {
          mushafLines[slug] = await read('mushaf/$lines') as Map<String, dynamic>;
        }
      }
    }

    Map<String, dynamic>? qiraatRules;
    final qiraatPacks = <String, Map<String, dynamic>>{};
    if (loadQiraatTajweed) {
      qiraatRules =
          await read('tajweed-qiraat/rules.json') as Map<String, dynamic>;
      for (final slug in qiraatTajweedSlugs) {
        qiraatPacks[slug] =
            await read('tajweed-qiraat/$slug.json') as Map<String, dynamic>;
      }
    }

    final wordByWordJson = loadWordByWord
        ? await read('word-by-word.json') as Map<String, dynamic>
        : null;
    final similarJson = loadSimilarAyahs
        ? await read('similar-ayahs.json') as Map<String, dynamic>
        : null;

    return Engine.fromJson(
      quranJson: results[0] as List<dynamic>,
      juzJson: results[1] as List<dynamic>,
      recitersJson: results[2] as List<dynamic>,
      tajweedRulesJson: results[3] as Map<String, dynamic>,
      tajweedAnnotationsJson: results[4] as List<dynamic>,
      surahInfoJson: results[5] as List<dynamic>,
      namesOfAllahJson: results[6] as List<dynamic>,
      muqattaatJson: results[7] as Map<String, dynamic>,
      qiraatCountsJson: results[8] as Map<String, dynamic>,
      themesJson: themesJson,
      tajweedLessonsJson: lessonsJson,
      mushafIndexJson: mushafIndexJson,
      mushafPagesJson: mushafPages,
      mushafLinesJson: mushafLines,
      qiraatTajweedRulesJson: qiraatRules,
      qiraatTajweedPacksJson: qiraatPacks,
      wordByWordJson: wordByWordJson,
      similarAyahsJson: similarJson,
      surahSectionsJson: surahSectionsJson,
      arabicAlphabetJson: arabicAlphabetJson,
      qiraatJson: qiraatJson,
    );
  }

  /// Walk up from the current directory to find a `data/` dir with quran.json.
  static String? _locateDataDir() {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final candidate =
          File('${dir.path}${Platform.pathSeparator}data'
              '${Platform.pathSeparator}quran.json');
      if (candidate.existsSync()) {
        return '${dir.path}${Platform.pathSeparator}data';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  // --- Convenience pass-throughs -------------------------------------------

  int get totalAyahs => quran.totalAyahs;

  Surah? surah(int id) => quran.surah(id);

  Ayah? ayah(int surahId, int ayahId) => quran.ayah(surahId, ayahId);

  int globalAyahNumber(int surahId, int ayahId) =>
      quran.globalAyahNumber(surahId, ayahId);

  JuzEntry? juz(int id) => juzPage.juz(id);

  List<TajweedSpan> tajweedSpans(int surahId, int ayahId) =>
      tajweed.tajweedSpans(surahId, ayahId);
}
