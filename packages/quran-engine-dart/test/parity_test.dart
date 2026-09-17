// The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the
// surah outlines, alphabet reference and qiraat comparison that followed it.
//
// Mirrors the JS `test/parity.test.js`, the Python `tests/test_parity.py`, the
// Swift `ParityTests.swift`, the Rust `tests/parity.rs`, the Go `parity_test.go`
// and the Kotlin `ParityTest.kt` case for case, so a divergence between the
// ports shows up as a failing test rather than as a surprise in an app.

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

final RegExp _whitespace = RegExp(r'\s+');

void main() {
  late Engine engine;

  setUpAll(() async {
    engine = await Engine.load(
      loadMushaf: true,
      loadQiraatTajweed: true,
      loadWordByWord: true,
      loadSimilarAyahs: true,
      loadQiraat: true,
    );
  });

  // ---- mushaf -------------------------------------------------------------

  group('mushaf', () {
    test('twenty riwayat, eight with text', () {
      expect(engine.mushaf.riwayat().length, 20);
      expect(engine.mushaf.riwayatWithText().length, 8);
      expect(engine.mushaf.totalPages(), 604);
      expect(engine.mushaf.riwayah('warsh')!.imam, 'Nafi');
      expect(engine.mushaf.riwayah('hisham')!.textIncluded, isFalse);
    });

    test('every riwayah has a facsimile and a full page table', () {
      for (final entry in engine.mushaf.riwayat()) {
        expect(entry.pdf, startsWith('pdfs/'), reason: entry.riwayah);
        expect(entry.pdf, endsWith('.pdf.xz'), reason: entry.riwayah);
        expect(entry.pdfBytes, greaterThan(100000), reason: entry.riwayah);
        // Al-Fatihah opens page 1 and an-Nas closes page 604 in every print.
        expect(engine.mushaf.page(1, 1, entry.riwayah), 1, reason: entry.riwayah);
        expect(engine.mushaf.page(114, 6, entry.riwayah), 604, reason: entry.riwayah);
      }
    });

    test('pages resolve back to their ayahs', () {
      expect(engine.mushaf.page(2, 255, 'hafs'), 42);
      expect(
        engine.mushaf.ayahsOnPage(42, 'hafs').any((r) => r.surah == 2 && r.ayah == 255),
        isTrue,
      );
      expect(engine.mushaf.firstAyahOfPage(1, 'hafs'), const VerseRef(1, 1));
    });

    test('line tables ship exactly where the text does', () {
      for (final entry in engine.mushaf.riwayat()) {
        final breaks = engine.mushaf.lineBreaks(1, 1, entry.riwayah);
        expect(breaks != null, entry.textIncluded, reason: entry.riwayah);
      }
    });
  });

  // ---- riwayah tajweed ----------------------------------------------------

  group('riwayah tajweed', () {
    test('seven verified packs', () {
      expect(engine.qiraatTajweed.available(),
          ['buzzi', 'duri', 'qaloon', 'qunbul', 'shubah', 'susi', 'warsh']);
    });

    test('legend carries its explanation', () {
      final legend = engine.qiraatTajweed.legend('warsh');
      expect(legend.length, greaterThanOrEqualTo(3));
      for (final entry in legend) {
        expect(entry.code.length, 1);
        expect(entry.rule, isNotEmpty);
        expect(entry.arabic, isNotEmpty);
        expect(entry.english, isNotEmpty);
        expect(entry.short, isNotEmpty, reason: 'no description for ${entry.rule}');
      }
    });

    test('word rules name real legend codes', () {
      final rules = engine.qiraatTajweed.wordRules(2, 3, 'warsh');
      expect(rules, isNotEmpty);
      final codes = engine.qiraatTajweed.legend('warsh').map((e) => e.code).toList();
      for (final rule in rules) {
        expect(codes, contains(rule.code));
        expect(rule.wholeWord, rule.firstLetter < 0);
        expect(rule.word, greaterThanOrEqualTo(1));
      }
    });

    test('khilaf markers', () {
      expect(engine.qiraatTajweed.hasKhilaf(2, 253, 'warsh'), isTrue);
      expect(engine.qiraatTajweed.hasKhilaf(2, 254, 'warsh'), isFalse);
    });
  });

  // ---- word by word -------------------------------------------------------

  group('word by word', () {
    test("both layers aligned to the ayah's own tokens", () {
      final words = engine.wordByWord.words(112, 1);
      expect(words.map((w) => w.transliteration).toList(),
          ['qul', 'huwa', 'l-lahu', 'aḥadun']);
      expect(words[0].english, 'Say');
      final firstToken =
          engine.quran.ayah(112, 1)!.textArabic.trim().split(_whitespace).first;
      expect(words[0].arabic, firstToken);
    });

    test("every ayah's arrays match its token count", () {
      for (final surah in engine.quran.all()) {
        for (final ayah in surah.ayahs) {
          final tokens = ayah.textArabic.trim().split(_whitespace).length;
          expect(engine.wordByWord.glosses(surah.id, ayah.id)?.length, tokens,
              reason: '${surah.id}:${ayah.id} english');
          expect(engine.wordByWord.transliterations(surah.id, ayah.id)?.length,
              tokens,
              reason: '${surah.id}:${ayah.id} transliteration');
        }
      }
    });

    test('gloss search finds the word', () {
      final hits = engine.wordByWord.find('the Ever-Living', limit: 5);
      expect(hits.any((h) => h.surah == 2 && h.ayah == 255), isTrue);
      expect(hits.every((h) => h.transliteration.isNotEmpty), isTrue);
    });
  });

  // ---- similar ayahs, themes, lessons --------------------------------------

  group('corpora', () {
    test('similar ayahs', () {
      final matches = engine.similarAyahs.matches(2, 255);
      final found = matches.where((m) => m.surah == 3 && m.ayah == 2).toList();
      expect(found, isNotEmpty, reason: '3:2 is a match');
      expect(found.first.verified, isTrue);
      // Version 2 carries no text: the shared wording is a span into the
      // matched ayah.
      expect(found.first.spans, [
        [0, 6]
      ]);
      expect(found.first.labels, isEmpty);
      expect(found.first.score, isNull);
      expect(engine.similarAyahs.has(2, 255), isTrue);
      expect(engine.similarAyahs.count(), greaterThan(5000));
    });

    test('similar ayahs reads only version 2', () {
      // A version-1 file put the phrase text where a span now sits: read as
      // no data, like the JS.
      expect(SimilarAyahs().count(), 0);
      expect(
          SimilarAyahs({
            '2:255': [
              [3, 2, 'text', 1]
            ]
          }).count(),
          0);
      expect(
          SimilarAyahs({
            'v': 1,
            'ayahs': {
              '2:255': [
                [3, 2, 1, [], [], null]
              ]
            }
          }).count(),
          0);
      final two = SimilarAyahs({
        'v': 2,
        'ayahs': {
          '2:255': [
            [
              3,
              2,
              1,
              [
                [0, 6]
              ],
              [],
              null
            ]
          ]
        }
      });
      expect(two.count(), 1);
      expect(two.has(2, 255), isTrue);
      expect(two.has(3, 2), isFalse);
      final match = two.matches(2, 255).single;
      expect(match.surah, 3);
      expect(match.ayah, 2);
      expect(match.verified, isTrue);
      expect(match.labels, isEmpty);
      expect(match.spans, [
        [0, 6]
      ]);
      expect(match.score, isNull);
    });

    test('themes index both ways', () {
      expect(engine.themes.all().length, greaterThanOrEqualTo(300));
      expect(engine.themes.topic('tawheed')!.ayahs, contains('2:255'));
      expect(engine.themes.topicsFor(2, 255).any((t) => t.id == 'tawheed'), isTrue);
      expect(engine.themes.domains().length, greaterThanOrEqualTo(2));
    });

    test('lessons walk in course order', () {
      final lessons = engine.tajweedLessons.allLessons();
      expect(lessons.length, greaterThanOrEqualTo(30));
      expect(engine.tajweedLessons.previous(lessons[0].id), isNull);
      expect(engine.tajweedLessons.next(lessons[0].id)?.id, lessons[1].id);
      expect(engine.tajweedLessons.chapterOf(lessons[0].id), isNotNull);
      // Version 3 examples point at their words by span; the data carries no
      // copy of the words.
      final example = lessons
          .expand((l) => l.examples)
          .firstWhere((e) => e.wordSpan != null);
      expect(example.surahId, 112);
      expect(example.ayahNumber, 1);
      expect(example.wordSpan, [1, 3]);
      expect(const TajweedExample(112, 1, 'focus').wordSpan, isNull);
      expect(
          TajweedExample.fromJson({'surahId': 112, 'ayahNumber': 1, 'focus': ''})
              .wordSpan,
          isNull);
    });

    test("lesson Quran references resolve to the engine's own text", () {
      // Version 4: a drill or rule-card fragment whose Arabic IS Quran carries
      // an `ayah` reference and no text at all, so a port that ignores the
      // field shows an empty row rather than a verse. This reads one back out
      // of the Quran to prove the whole path.
      final lessons = engine.tajweedLessons.allLessons();
      final drill =
          lessons.expand((l) => l.drills).firstWhere((d) => d.ayah != null);
      final reference = drill.ayah!;
      expect(reference.surahId, 110);
      expect(reference.ayahNumber, 1);
      expect([reference.first, reference.last], [0, 4]);
      expect(drill.text, isEmpty,
          reason: 'a referenced drill carries no copy of the words');

      // The span names the whole of an-Nasr 1, so the words it cuts are the
      // ayah itself. Compared against the engine's own text rather than a
      // pasted literal: a copy here would have to be kept in the file's exact
      // normalization, the drift this version removed.
      final words = engine.quran.ayah(110, 1)!.textArabic.split(RegExp(r'\s+'));
      expect(words.length, 5);
      expect(words.sublist(reference.first, reference.last + 1).join(' '),
          words.join(' '));

      // Every reference across drills and rule cards lands inside its ayah.
      var referenced = 0;
      for (final lesson in lessons) {
        final fragments = lesson.ruleCard?.fragments ?? const [];
        for (final row in [...lesson.drills, ...fragments]) {
          final span = row.ayah;
          if (span == null) continue;
          referenced += 1;
          final tokens = engine.quran
              .ayah(span.surahId, span.ayahNumber)!
              .textArabic
              .split(RegExp(r'\s+'));
          expect(span.last, lessThan(tokens.length));
        }
      }
      expect(referenced, 28,
          reason: '7 drills and 21 rule-card fragments reference the Quran');

      // The card itself is `ruleCard`; it was declared as `mushafCard` and so
      // decoded to nothing.
      expect(lessons.where((l) => l.ruleCard != null).length, 32);
    });
  });

  // ---- meaning search ------------------------------------------------------

  test('MaxSim ranks by meaning', () {
    // A toy embedder: enough to prove the scoring, without shipping a model.
    const vectors = <String, List<double>>{
      'patience': [1.0, 0.0, 0.0],
      'hardship': [0.9, 0.1, 0.0],
      'sabr': [0.95, 0.05, 0.0],
      'steadfast': [0.9, 0.05, 0.0],
      'dawn': [0.0, 1.0, 0.0],
      'prayer': [0.0, 0.95, 0.0],
    };
    final semantic = Semantic((word) => vectors[word]).index(const [
      SemanticDocument('sabr', 'sabr and steadfast endurance'),
      SemanticDocument('fajr', 'prayer at dawn'),
    ]);
    final hits = semantic.search('patience hardship');
    expect(hits.first.id, 'sabr');
    expect(hits[0].score, greaterThan(hits[1].score));
  });

  // ---- ask AI --------------------------------------------------------------

  group('ask AI', () {
    test('named verse is the subject', () {
      final passages = engine.askAI.retrieve('explain ayat al-kursi');
      expect(passages.first.reference, '2:255');
      expect(passages.first.isSubject, isTrue);
    });

    test('named surah answers with its background', () {
      final passages = engine.askAI.retrieve('what is surah al-kahf about');
      expect(passages.first.reference, 'Surah Al-Kahf');
      expect(passages.first.kind, PassageKind.surah);
    });

    test('keyword lane is weighted', () {
      final passages =
          engine.askAI.retrieve('what does the Quran say about patience in hardship');
      expect(passages.any((p) => p.reference == '2:153'), isTrue);
      for (final passage in passages) {
        if (passage.kind == PassageKind.ayah) {
          expect(engine.quran.ayah(passage.surah!, passage.ayah!), isNotNull);
        }
      }
    });

    test('bare follow-up uses the previous question', () {
      final carried = engine.askAI.retrieve('tell me about 2:153');
      expect(engine.askAI.retrieve('why?'), isEmpty);
      final withContext = engine.askAI.retrieve(
        'why?',
        previousQuestion: 'tell me about 2:153',
        carried: carried,
      );
      expect(withContext.any((p) => p.reference == '2:153'), isTrue);
    });

    test('prompt shape', () {
      final passages = engine.askAI.retrieve('explain 2:153');
      final built = chatPrompt('explain 2:153', passages);
      expect(built.instructions, contains('Never issue a religious ruling'));
      expect(built.prompt, contains('SUBJECT OF THE QUESTION [2:153]'));
      expect(built.prompt.trimRight(), endsWith('QUESTION: explain 2:153'));
      expect(questionWords, contains('what'));
    });
  });

  // ---- surah sections -----------------------------------------------------

  group('surah sections', () {
    test('111 surahs carry an outline, and it reads as a chain', () {
      expect(engine.surahSections.count(), 111);
      expect(engine.surahSections.overview(1).length, greaterThan(20));
      expect(engine.surahSections.hasSections(1), isFalse);

      // Hud opens with a broad passage and the sections inside it - an ayah has
      // a chain, not a row.
      expect(engine.surahSections.sectionsFor(11, 3).map((s) => s.english).toList(),
          ['Doctrine facts', 'Calling to Allah']);
      expect(engine.surahSections.sectionFor(11, 3)?.english, 'Calling to Allah');
    });

    test('the outline rebuilds the nesting the flat list encodes', () {
      final roots = engine.surahSections.outline(11);
      expect(roots.length, greaterThanOrEqualTo(2));
      expect(roots[0].section.english, 'Doctrine facts');
      expect(roots[0].children.length, 5);
      expect(
        roots[0].children.every((c) =>
            c.section.from >= roots[0].section.from &&
            c.section.to <= roots[0].section.to),
        isTrue,
      );
    });

    test('every range is inside its surah, and search finds a story', () {
      for (final surah in engine.quran.all()) {
        for (final section in engine.surahSections.sections(surah.id)) {
          expect(section.from, greaterThanOrEqualTo(1));
          expect(section.to, lessThanOrEqualTo(surah.numberOfAyahs));
          expect(section.from, lessThanOrEqualTo(section.to));
          expect(section.english, isNotEmpty);
          expect(section.arabic, isNotEmpty);
        }
      }
      final nuh = engine.surahSections.search('Story of Nuh');
      expect(nuh.length, greaterThanOrEqualTo(2));
      expect(nuh.any((hit) => hit.surah == 11), isTrue);
    });
  });

  // ---- arabic alphabet ----------------------------------------------------

  group('arabic alphabet', () {
    test('28 letters, each with a tajweed weight the catalogue explains', () {
      final letters = engine.alphabet.letters();
      expect(letters.length, 28);
      final weights = engine.alphabet.weightDescriptions();
      for (final letter in letters) {
        expect(letter.letter, isNotEmpty);
        expect(letter.name, isNotEmpty);
        expect(letter.weight, isNotNull, reason: '${letter.letter} has no weight');
        expect(weights[letter.weight], isNotNull,
            reason: 'no description for weight ${letter.weight}');
      }
      // Alif is the one letter with no weight of its own - the fact the whole
      // field exists for.
      expect(engine.alphabet.weight('ا'), 'followsPrevious');
      expect(engine.alphabet.weight('ص'), 'heavy');
      expect(engine.alphabet.weight('س'), 'light');
    });

    test('a letter resolves from any of its joining forms', () {
      expect(engine.alphabet.letter('ـصـ')?.transliteration, 'Saad');
      expect(engine.alphabet.letterById(1)?.letter, 'ا');
      expect(engine.alphabet.letter('nope'), isNull);
    });

    test('tashkeel, numerals and the waqf signs', () {
      expect(engine.alphabet.tashkeel().length, greaterThanOrEqualTo(8));
      expect(engine.alphabet.numbers().length, 11);
      expect(engine.alphabet.stoppingSign('۩')?.title, 'Make Sujood');
      expect(engine.alphabet.heavyLetters().length, greaterThanOrEqualTo(7));
    });
  });

  // ---- qiraat comparison --------------------------------------------------

  group('qiraat comparison', () {
    test('only the published readings, hafs included', () {
      expect(engine.qiraatComparison.available(),
          ['buzzi', 'duri', 'hafs', 'qaloon', 'qunbul', 'shubah', 'susi', 'warsh']);
    });

    test('a reading against itself is entirely identical', () {
      final same = engine.qiraatComparison.compareSurah(2, 'hafs');
      expect(same.identical, same.words);
      expect(same.sameSkeleton, 0);
      expect(same.different, 0);
      expect(same.added, 0);
      expect(same.dropped, 0);
      expect(same.identicalPercent, 100);
    });

    test('the buckets add up, and Shubah is nearer to Hafs than Warsh is', () {
      final warsh = engine.qiraatComparison.compareSurah(2, 'warsh');
      final shubah = engine.qiraatComparison.compareSurah(2, 'shubah');
      for (final totals in [warsh, shubah]) {
        expect(
          totals.identical + totals.sameSkeleton + totals.different + totals.dropped,
          totals.words,
        );
      }
      // Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam.
      expect(shubah.identicalPercent, greaterThan(warsh.identicalPercent));
      expect(shubah.identicalPercent, greaterThan(95));
    });

    test('differences are the non-identical rows, in reading order', () {
      final rows = engine.qiraatComparison.differences(2, 'warsh', limit: 20);
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row.base != row.other), isTrue);
      final positions = rows.map((row) => row.position).toList();
      expect(positions, orderedEquals(positions.toList()..sort()));
    });

    test("word streams follow the reading's own verse count", () {
      // Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id
      // would compare different verses; the comparison walks the words instead.
      expect(engine.quran.numberOfAyahsInQiraah(2, 'warsh'), 285);
      expect(engine.quran.qiraahVerses(2, 'warsh').length, 285);
      expect(engine.qiraatComparison.words(2, 'warsh').length, greaterThan(6000));
    });
  });
}
