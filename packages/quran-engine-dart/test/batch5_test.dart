// Batch 5: morphology, mutashabihat, the QUL topic indexes, hizb/ruku/manzil,
// the qiraat variant matrix and the word of the day.
//
// Mirrors the JS `test/batch5.test.js`, the Python `tests/test_batch5.py`, the
// Go `batch5_test.go`, the Rust `tests/batch5.rs`, the Swift `Batch5Tests.swift`
// and the Kotlin `Batch5Test.kt` case for case. Every count is pinned against
// the app's own verify gate.

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// The upstream fold: harakat and the waqf marks gone, alif wasla and the hamza
/// seats normalized. Occurrences were matched this way, so ٱلۡحَمۡدُۖ at 64:1 is
/// the same form as ٱلۡحَمۡدُ and a literal comparison would call a pause mark a
/// mismatch.
String _fold(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if ((rune >= 0x064B && rune <= 0x065F) ||
        rune == 0x0670 ||
        (rune >= 0x06D6 && rune <= 0x06ED) ||
        rune == 0x0640) {
      continue;
    }
    if (rune == 0x0671 || rune == 0x0623 || rune == 0x0625) {
      out.write('ا');
    } else if (rune == 0x0624) {
      out.write('و');
    } else if (rune == 0x0626) {
      out.write('ي');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

void main() {
  late Engine engine;

  setUpAll(() async {
    engine = await Engine.load(
      loadMorphology: true,
      loadMutashabihat: true,
      loadQuranTopics: true,
      loadQiraatVariants: true,
    );
  });

  List<String> tokens(int surah, int ayah) =>
      (engine.ayah(surah, ayah)?.textArabic ?? '')
          .split(_whitespace)
          .where((t) => t.isNotEmpty)
          .toList();

  // ---- morphology -----------------------------------------------------------

  test('morphology corpus size matches the app gate', () {
    expect(engine.morphology.count(),
        {'roots': 1642, 'lemmas': 4817, 'tokens': 77629});
  });

  test('morphology ids are one based and zero means no root', () {
    expect(engine.morphology.root(0), isNull,
        reason: 'id 0 means the token has no root');
    expect(engine.morphology.root(1), isNotNull);
    expect(engine.morphology.root(1643), isNull,
        reason: 'root ids stop at the table size');
    final ids = engine.morphology.ids(1, 1);
    expect(ids?.key.length, 4);
    expect(ids?.value.length, 4);
  });

  test('morphology token resolves to root and lemma', () {
    // 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
    final root = engine.morphology.rootOf(1, 2, 2);
    expect(root?.value.letters, 'ر ب ب');
    expect(root?.value.buckwalter, 'rbb');
    expect(root?.value.joined, 'ربب');
    expect(engine.morphology.lemmaOf(1, 2, 2), isNotNull);
  });

  test('morphology occurrences come back in mushaf order', () {
    final hit = engine.morphology.findRoots('ربب', limit: 5).first;
    final found = engine.morphology.occurrencesOfRoot(hit.id);
    expect(found.length, 980);
    expect(found.first, const WordLocation(1, 2, 2));
    final ranks = found
        .map((w) => w.surah * 1000000 + w.ayah * 1000 + w.token)
        .toList();
    expect(ranks, orderedEquals(List.of(ranks)..sort()));
  });

  test('morphology fold closes the spaces', () {
    // A lexicon prints "ر ب ب" and a reader types "ربب"; the fold has to close
    // the spaces, not merely trim them.
    expect(Morphology.fold('ر ب ب'), 'ربب');
    for (final query in ['ربب', 'ر ب ب', 'rbb']) {
      expect(
        engine.morphology
            .findRoots(query, limit: 5)
            .any((h) => h.value.buckwalter == 'rbb'),
        isTrue,
        reason: 'no rbb for $query',
      );
    }
  });

  // ---- mutashabihat ---------------------------------------------------------

  test('mutashabihat counts', () {
    expect(engine.mutashabihat.count(), {'phrases': 814, 'ayahs': 2232});
  });

  test('mutashabihat phrase shape', () {
    final phrase = engine.mutashabihat.phrase(10167);
    expect(phrase, isNotNull);
    expect(phrase!.source, '9:87');
    expect(phrase.span, [5, 10]);
    expect(phrase.wordCount, 6);
    expect(phrase.ayahCount, 3);
    expect(phrase.surahCount, 2);
    expect(phrase.occurrences['9:93'], [
      [13, 19]
    ]);
  });

  test('mutashabihat occurrences are in mushaf order not key order', () {
    expect(engine.mutashabihat.occurrences(10167).map((o) => o.key).toList(),
        ['9:87', '9:93', '63:3']);
  });

  test('mutashabihat phrase slices out of the text you hand it', () {
    final source = engine.ayah(9, 87)!.textArabic;
    final text = engine.mutashabihat.textOf(10167, source);
    expect(text.split(_whitespace).where((t) => t.isNotEmpty).length, 6);
    expect(source.contains(text.split(_whitespace).first), isTrue);
  });

  test('mutashabihat has agrees with the lookup', () {
    expect(engine.mutashabihat.has(9, 87), isTrue);
    expect(engine.mutashabihat.phrasesFor(9, 87), isNotEmpty);
    expect(engine.mutashabihat.has(1, 1),
        engine.mutashabihat.phrasesFor(1, 1).isNotEmpty);
  });

  // ---- QUL topics -----------------------------------------------------------

  test('qul topic counts and the double listing', () {
    final counts = engine.quranTopics.count();
    expect(counts['topics'], 2512);
    expect(counts['references'], 30687);
    expect(counts['thematic'], 695);
    expect(counts['ontology'], 284);
    expect(counts['index'], 1550);
    // Deliberately sums to MORE than the topic count: the 17 topics listed in
    // two indexes are counted in both, which is what "listed in" means.
    expect(counts['thematic']! + counts['ontology']! + counts['index']!, 2529);
  });

  test('qul topics are three independent trees', () {
    expect(engine.quranTopics.topics().where((t) => t.families.length > 1).length,
        17);
    expect(engine.quranTopics.topic(13)?.families,
        [TopicTree.thematic, TopicTree.ontology]);
    expect(engine.quranTopics.parent(13, TopicTree.thematic)?.name,
        'Prophets (25 mentioned by name)');
    expect(engine.quranTopics.parent(13, TopicTree.ontology)?.name, 'Prophet');
    // A tree is not closed over its own listing either: the A-Z index hangs
    // entries under thematic topics, so asserting a parent shares its child's
    // family would be false.
    final crossing = engine.quranTopics.topics().where((topic) {
      final parentId = topic.parentIn(TopicTree.generalIndex);
      if (parentId == null) return false;
      final parent = engine.quranTopics.topic(parentId);
      return parent != null && !parent.isListedIn(TopicTree.generalIndex);
    }).length;
    expect(crossing, greaterThan(0));
  });

  test('qul topic parents all resolve', () {
    for (final topic in engine.quranTopics.topics()) {
      for (final tree in TopicTree.values) {
        final parentId = topic.parentIn(tree);
        if (parentId == null) continue;
        expect(engine.quranTopics.topic(parentId), isNotNull,
            reason: 'topic ${topic.id} (${topic.name}) has a dangling parent');
      }
    }
  });

  test('qul topic ancestors terminate in every tree', () {
    for (final tree in TopicTree.values) {
      final deep = engine.quranTopics
          .topics()
          .firstWhere((t) => engine.quranTopics.ancestors(t.id, tree).length >= 2);
      final chain = engine.quranTopics.ancestors(deep.id, tree);
      expect(chain.map((t) => t.id).toSet().length, chain.length,
          reason: 'cycle in $tree');
      expect(chain.last.parentIn(tree), isNull);
    }
  });

  test('qul topic children list their parent', () {
    for (final tree in TopicTree.values) {
      final child = engine.quranTopics
          .topics()
          .firstWhere((t) => t.parentIn(tree) != null);
      final siblings = engine.quranTopics.children(child.parentIn(tree)!, tree);
      expect(siblings.any((s) => s.id == child.id), isTrue,
          reason: '${child.name} missing from its $tree parent');
    }
  });

  test('qul topic references are real ayahs', () {
    final sample = engine.quranTopics.topics().take(200).toList();
    for (final topic in sample) {
      for (final key in topic.ayahs) {
        final parts = splitAyahKey(key);
        expect(engine.ayah(parts[0], parts[1]), isNotNull,
            reason: '${topic.name} cites $key');
      }
    }
    final first = sample.first;
    final parts = splitAyahKey(first.ayahs.first);
    expect(
        engine.quranTopics
            .topicsFor(parts[0], parts[1])
            .any((t) => t.id == first.id),
        isTrue);
  });

  // ---- passage themes -------------------------------------------------------

  test('passage counts', () {
    expect(engine.ayahThemes.count(), {'surahs': 114, 'passages': 1049});
  });

  test('passages are ordered and never overlap', () {
    for (final surah in engine.quran.all()) {
      var previousEnd = 0;
      for (final passage in engine.ayahThemes.passages(surah.id)) {
        expect(previousEnd == 0 || passage.from > previousEnd, isTrue,
            reason: 'surah ${surah.id}: ${passage.from} overlaps $previousEnd');
        expect(passage.to, greaterThanOrEqualTo(passage.from));
        expect(passage.to, lessThanOrEqualTo(surah.numberOfAyahs));
        previousEnd = passage.to;
      }
    }
  });

  test('passage for finds the containing passage', () {
    final passage = engine.ayahThemes.passageFor(2, 10);
    expect(passage?.theme, 'Hypocrites and the consequences of hypocrisy');
    expect(passage?.from, 8);
    expect(passage?.to, 16);
  });

  // ---- hizb / ruku / manzil -------------------------------------------------

  test('division counts and first starts', () {
    expect(engine.quranMetadata.count(), {'hizb': 60, 'ruku': 558, 'manzil': 7});
    for (final table in [
      engine.quranMetadata.hizb,
      engine.quranMetadata.ruku,
      engine.quranMetadata.manzil
    ]) {
      expect(table.start(1)?.key, '1:1');
    }
  });

  test('division starts ascend and are real ayahs', () {
    for (final table in [
      engine.quranMetadata.hizb,
      engine.quranMetadata.ruku,
      engine.quranMetadata.manzil
    ]) {
      final all = table.all();
      for (var i = 1; i < all.length; i++) {
        final a = all[i - 1], b = all[i];
        expect(a.surah < b.surah || (a.surah == b.surah && a.ayah < b.ayah),
            isTrue,
            reason: 'out of order at ${b.key}');
        expect(engine.ayah(b.surah, b.ayah), isNotNull,
            reason: '${b.key} is not an ayah');
      }
    }
  });

  test('division lookup contains the ayah', () {
    expect(engine.quranMetadata.divisionsFor(1, 1),
        {'hizb': 1, 'ruku': 1, 'manzil': 1});
    final last = engine.quranMetadata.divisionsFor(114, 6);
    expect(last['hizb'], 60);
    expect(last['manzil'], 7);
    final n = engine.quranMetadata.hizb.numberFor(2, 255);
    final span = engine.quranMetadata.hizb.range(n)!;
    expect(span.key.surah < 2 || (span.key.surah == 2 && span.key.ayah <= 255),
        isTrue);
    final until = span.value;
    if (until != null) {
      expect(until.surah > 2 || (until.surah == 2 && until.ayah > 255), isTrue);
    }
  });

  // ---- qiraat variants ------------------------------------------------------

  test('qiraat variant counts', () {
    expect(engine.qiraatVariants.count(),
        {'ayahs': 1409, 'junctures': 1634, 'readings': 3503});
  });

  test('juncture names word readings and who reads them', () {
    final junctures = engine.qiraatVariants.junctures(102, 6);
    expect(junctures, isNotEmpty);
    for (final juncture in junctures) {
      expect(juncture.readings.length, greaterThanOrEqualTo(2),
          reason: 'a juncture with one reading is not a variant');
      for (final reading in juncture.readings) {
        expect(reading.text, isNotEmpty);
        expect(reading.readers.isEmpty && reading.transmitters.isEmpty, isFalse,
            reason: 'a reading nobody reads');
        expect(engine.qiraatVariants.attribution(reading), isNotEmpty);
      }
    }
  });

  test('hafs follows a reading at junctures he is party to', () {
    var matched = 0;
    for (var surah = 1; surah <= 20; surah++) {
      for (var ayah = 1; ayah <= 20; ayah++) {
        for (final juncture in engine.qiraatVariants.junctures(surah, ayah)) {
          if (engine.qiraatVariants.readingFor(juncture, 'hafs') != null) {
            matched++;
          }
        }
      }
    }
    expect(matched, greaterThan(0));
  });

  test('segment spans are inclusive or an honest null', () {
    for (var surah = 1; surah <= 30; surah++) {
      for (var ayah = 1; ayah <= 30; ayah++) {
        for (final juncture in engine.qiraatVariants.junctures(surah, ayah)) {
          for (final segment in juncture.segments) {
            final span = segment.span;
            if (span == null) continue;
            expect(span[1], greaterThanOrEqualTo(span[0]));
            final parts = splitAyahKey(segment.ayah);
            expect(span[1], lessThan(tokens(parts[0], parts[1]).length),
                reason: '${segment.ayah} span past the end');
          }
        }
      }
    }
  });

  // ---- qiraat places --------------------------------------------------------

  test('places cover only the published riwayat', () {
    // Hafs is the reference and indexes nothing against itself.
    expect(engine.qiraatVariants.riwayatWithPlaces(),
        ['buzzi', 'duri', 'qaloon', 'qunbul', 'shubah', 'susi', 'warsh']);
  });

  test('places point at tokens the ayah has', () {
    for (final slug in engine.qiraatVariants.riwayatWithPlaces()) {
      for (final surah in [1, 2, 18]) {
        for (final place in engine.qiraatVariants.places(slug, surah)) {
          final count = tokens(surah, place.ayah).length;
          for (final index in [...place.word, ...place.letter]) {
            expect(index >= 0 && index < count, isTrue,
                reason: '$slug $surah:${place.ayah} index $index');
          }
        }
      }
    }
  });

  test('al fatihah carries a difference for warsh', () {
    final fourth = engine.qiraatVariants
        .places('warsh', 1)
        .where((p) => p.ayah == 4)
        .toList();
    expect(fourth, isNotEmpty, reason: 'Warsh differs from Hafs at 1:4');
    expect(fourth.first.word.isNotEmpty || fourth.first.letter.isNotEmpty, isTrue);
  });

  // ---- paired recordings ----------------------------------------------------

  test('audio covers four riwayat and honestly no others', () {
    expect(engine.qiraatVariants.riwayatWithAudio().length, 4);
    expect(engine.qiraatVariants.audio('qunbul', 1, 4), isNull,
        reason: 'Qunbul has no reciter who published both sides with timings');
  });

  test('audio pair is one reciter two urls and matching span kinds', () {
    var found = 0;
    for (final slug in engine.qiraatVariants.riwayatWithAudio()) {
      for (var surah = 1; surah <= 114 && found < 8; surah++) {
        for (var ayah = 1; ayah <= 10; ayah++) {
          final pair = engine.qiraatVariants.audio(slug, surah, ayah);
          if (pair == null) continue;
          found++;
          expect(pair.reciter, isNotEmpty);
          expect(pair.hafs.url.endsWith('.mp3'), isTrue);
          expect(pair.riwayah.url.endsWith('.mp3'), isTrue);
          expect(pair.hafs.url, isNot(pair.riwayah.url));
          expect(pair.hafs.startMs == null, pair.riwayah.startMs == null);
          if (pair.hafs.startMs != null) {
            expect(pair.hafs.endMs!, greaterThan(pair.hafs.startMs!));
          }
          break;
        }
      }
    }
    expect(found, greaterThanOrEqualTo(4));
  });

  // ---- word of the day ------------------------------------------------------

  test('word of day count', () {
    expect(engine.wordOfDay.count()['words'], 149);
  });

  test('word of day walk wraps and handles a negative index', () {
    final all = engine.wordOfDay.all();
    expect(engine.wordOfDay.forDayIndex(0)?.id, all.first.id);
    expect(engine.wordOfDay.forDayIndex(all.length)?.id, all.first.id);
    expect(engine.wordOfDay.forDayIndex(-1)?.id, all.last.id);
    expect(engine.wordOfDay.forDate(DateTime(2026, 9, 8, 12))?.id,
        engine.wordOfDay.forDate(DateTime(2026, 9, 8, 23))?.id);
  });

  test('word of day count is the length of the list behind it', () {
    for (final word in engine.wordOfDay.all()) {
      final total =
          word.occurrences.fold<int>(0, (n, o) => n + o.tokens.length);
      expect(word.count, total, reason: word.id);
    }
  });

  test('word of day anchor and folded tokens', () {
    for (final word in engine.wordOfDay.all()) {
      final first = word.occurrences.first;
      expect(first.surah, word.surah, reason: word.id);
      expect(first.ayah, word.ayah, reason: word.id);
      expect(first.tokens.first, word.token, reason: word.id);
      final target = _fold(word.arabic);
      for (final occurrence in word.occurrences) {
        final row = tokens(occurrence.surah, occurrence.ayah);
        for (final index in occurrence.tokens) {
          expect(_fold(row[index]), target,
              reason: '${word.id} at ${occurrence.surah}:${occurrence.ayah}');
        }
      }
    }
  });

  test('word of day search and reverse lookup', () {
    final first = engine.wordOfDay.all().first;
    expect(engine.wordOfDay.search(first.arabic).any((w) => w.id == first.id),
        isTrue);
    expect(
        engine.wordOfDay
            .wordsIn(first.surah, first.ayah)
            .any((w) => w.id == first.id),
        isTrue);
  });
}
