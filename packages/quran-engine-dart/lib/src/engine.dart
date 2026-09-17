/// The `Engine` facade ties the modules together.
///
/// Two ways to build it:
///   • `Engine.load({dataDir})`: reads JSON from disk (dart:io). Default
///     locates the repo `/data` by walking up from the current directory.
///   • `Engine.fromJson(...)`: accepts already-decoded JSON. Use this in
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
import 'batch6.dart';
import 'miracles.dart';
import 'qiraat_comparison.dart';
import 'word_of_day.dart';
import 'qiraat_variants.dart';
import 'batch5.dart';
import 'morphology.dart';
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

  /// Root and lemma of every word. Empty unless `loadMorphology`.
  final Morphology morphology;

  /// The repeated phrases. Empty unless `loadMutashabihat`.
  final Mutashabihat mutashabihat;

  /// The three QUL topic indexes. Empty unless `loadQuranTopics`.
  final QuranTopics quranTopics;

  /// The passage themes; loaded by default.
  final AyahThemes ayahThemes;

  /// Hizb, ruku and manzil; loaded by default.
  final QuranMetadata quranMetadata;

  /// The variant matrix, place index and paired recordings. Empty unless
  /// `loadQiraatVariants`.
  final QiraatVariants qiraatVariants;

  /// The curated vocabulary; loaded by default.
  final WordOfDay wordOfDay;
  final NamesDepth namesDepth;
  final Isnad isnad;

  /// The scientific-miracles corpus; loaded by default.
  final Miracles miracles;

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
    Morphology? morphology,
    Mutashabihat? mutashabihat,
    QuranTopics? quranTopics,
    AyahThemes? ayahThemes,
    QuranMetadata? quranMetadata,
    QiraatVariants? qiraatVariants,
    WordOfDay? wordOfDay,
    NamesDepth? namesDepth,
    Isnad? isnad,
    Miracles? miracles,
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
        similarAyahs = similarAyahs ?? SimilarAyahs(),
        morphology = morphology ?? Morphology(),
        mutashabihat = mutashabihat ?? const Mutashabihat(),
        quranTopics = quranTopics ?? QuranTopics(),
        ayahThemes = ayahThemes ?? const AyahThemes(),
        quranMetadata = quranMetadata ?? QuranMetadata(),
        qiraatVariants = qiraatVariants ?? const QiraatVariants(),
        wordOfDay = wordOfDay ?? WordOfDay(),
        namesDepth = namesDepth ?? NamesDepth(),
        isnad = isnad ?? Isnad(),
        miracles = miracles ?? Miracles(),
        themes = themes ?? Themes(),
        tajweedLessons = tajweedLessons ?? TajweedLessons(),
        askAI = AskAI(
          quran: quran,
          search: Search(quran),
          themes: themes ?? Themes(),
        );

  /// Build from already-decoded JSON. Pass the parsed contents of each file.
  ///
  /// [quranJson], `data/quran.json` (a List).
  /// [juzJson], `data/juz.json` (a List).
  /// [recitersJson], `data/reciters.json` (a List).
  /// [tajweedRulesJson], `data/tajweed-rules.json` (a Map).
  /// [tajweedAnnotationsJson], `tajweed-annotations.json` (a List).
  /// [surahInfoJson], `data/surah-info.json` (a List), optional.
  /// [namesOfAllahJson], `data/names-of-allah.json` (a List), optional.
  /// [muqattaatJson], `data/muqattaat.json` (a Map), optional.
  /// [qiraatCountsJson], `data/qiraat-counts.json` (a Map), optional.
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
    Map<String, dynamic>? morphologyJson,
    Map<String, dynamic>? mutashabihatJson,
    Map<String, dynamic>? quranTopicsJson,
    Map<String, dynamic>? ayahThemesJson,
    Map<String, dynamic>? quranMetadataJson,
    Map<String, dynamic>? qiraatVariantsJson,
    Map<String, dynamic>? qiraatPlacesJson,
    Map<String, dynamic>? qiraatVariantAudioJson,
    Map<String, dynamic>? wordOfDayJson,
    Map<String, dynamic>? namesDepthJson,
    Map<String, dynamic>? isnadJson,
    Map<String, dynamic>? miraclesJson,
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
      similarAyahs: SimilarAyahs(similarAyahsJson),
      morphology: Morphology(morphologyJson ?? const {}),
      mutashabihat: Mutashabihat(mutashabihatJson ?? const {}),
      quranTopics: QuranTopics(quranTopicsJson),
      ayahThemes: AyahThemes(ayahThemesJson ?? const {}),
      quranMetadata: QuranMetadata(quranMetadataJson),
      qiraatVariants: QiraatVariants(
        variants: qiraatVariantsJson ?? const {},
        places: qiraatPlacesJson ?? const {},
        audio: qiraatVariantAudioJson ?? const {},
      ),
      wordOfDay: WordOfDay(wordOfDayJson),
      namesDepth: NamesDepth(namesDepthJson),
      isnad: Isnad(isnadJson),
      miracles: Miracles(miraclesJson),
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
    bool loadMorphology = false,
    bool loadMutashabihat = false,
    bool loadQuranTopics = false,
    bool loadQiraatVariants = false,
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
      // A missing optional corpus is not an error: the accessors simply return
      // nothing, but a file that IS there and will not parse still throws, so a
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

    // Metadata (8 KB), the passage themes (142 KB) and the word list (128 KB)
    // join the always-loaded set on the same reasoning as the sections and the
    // alphabet: small, and each answers a question a consumer should not have to
    // opt into.
    final quranMetadataJson = await readOptional('quran-metadata.json');
    final ayahThemesJson = await readOptional('ayah-themes.json');
    final wordOfDayJson = await readOptional('word-of-day.json');
    // The Names in depth (47 KB) and the chains (20 KB) load by default too.
    final namesDepthJson = await readOptional('names-depth.json');
    final isnadJson = await readOptional('isnad.json');
    // The miracles corpus (393 KB) joins them: bigger than those, but smaller
    // than the tajweed course that has always loaded by default, and a consumer
    // cross-linking an ayah to what has been written about it should not have to
    // know a flag existed.
    final miraclesJson = await readOptional('miracles.json');

    final morphologyJson = loadMorphology
        ? await read('morphology.json') as Map<String, dynamic>
        : null;
    final mutashabihatJson = loadMutashabihat
        ? await read('mutashabihat.json') as Map<String, dynamic>
        : null;
    final quranTopicsJson = loadQuranTopics
        ? await read('quran-topics.json') as Map<String, dynamic>
        : null;
    Map<String, dynamic>? qiraatVariantsJson;
    Map<String, dynamic>? qiraatPlacesJson;
    Map<String, dynamic>? qiraatVariantAudioJson;
    if (loadQiraatVariants) {
      qiraatVariantsJson =
          await read('qiraat-variants.json') as Map<String, dynamic>;
      qiraatPlacesJson = await read('qiraat-places.json') as Map<String, dynamic>;
      qiraatVariantAudioJson =
          await read('qiraat-variant-audio.json') as Map<String, dynamic>;
    }

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
      morphologyJson: morphologyJson,
      mutashabihatJson: mutashabihatJson,
      quranTopicsJson: quranTopicsJson,
      ayahThemesJson: ayahThemesJson,
      quranMetadataJson: quranMetadataJson,
      qiraatVariantsJson: qiraatVariantsJson,
      qiraatPlacesJson: qiraatPlacesJson,
      qiraatVariantAudioJson: qiraatVariantAudioJson,
      wordOfDayJson: wordOfDayJson,
      namesDepthJson: namesDepthJson,
      isnadJson: isnadJson,
      miraclesJson: miraclesJson,
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
