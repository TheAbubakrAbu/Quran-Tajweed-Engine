// Batch 6: the 99 Names in depth, and the chains of transmission of the Ten
// Readings.
//
// Mirrors the JS `test/batch6.test.js`, the Python `tests/test_batch6.py`, the
// Go `batch6_test.go`, the Rust `tests/batch6.rs`, the Swift `Batch6Tests.swift`
// and the Kotlin `Batch6Test.kt` case for case.

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

/// The upstream fold, as in batch 5: harakat and waqf marks gone, alif wasla and
/// the hamza seats normalized.
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
    engine = await Engine.load();
  });

  // ---- the Names in depth --------------------------------------------------

  test('namesDepth: all 99 Names carry depth, under nine themes', () {
    expect(engine.namesDepth.count(),
        {'names': 99, 'themes': 9, 'occurrences': 194});
    expect(engine.namesDepth.all().map((n) => n.number).toList(),
        List<int>.generate(99, (i) => i + 1));
  });

  test('namesDepth: every Name has a root, a known theme, and prose', () {
    final ids = engine.namesDepth.themes().map((t) => t.id).toSet();
    for (final name in engine.namesDepth.all()) {
      expect(name.root, isNotEmpty, reason: 'name ${name.number}');
      expect(ids, contains(name.theme), reason: 'name ${name.number}');
      expect(name.explanation.length, greaterThan(40),
          reason: 'name ${name.number}');
      expect(name.living.length, greaterThan(20), reason: 'name ${name.number}');
    }
  });

  test('namesDepth: the themes partition the 99', () {
    var total = 0;
    for (final theme in engine.namesDepth.themes()) {
      final members = engine.namesDepth.byTheme(theme.id);
      expect(members, isNotEmpty, reason: theme.id);
      total += members.length;
    }
    expect(total, 99);
  });

  test('namesDepth: a root is spaced in the corpus and closed up for morphology',
      () {
    final rahman = engine.namesDepth.byNumber(1)!;
    expect(rahman.root, 'ر ح م');
    expect(rootKey(rahman.root), 'رحم');
    for (final spelling in ['رحم', 'ر ح م']) {
      expect(engine.namesDepth.byRoot(spelling).map((n) => n.number).toList(),
          [1, 2]);
    }
  });

  test('namesDepth: a placed occurrence really is that ayah\'s token', () {
    var placed = 0;
    var unplaced = 0;
    for (final name in engine.namesDepth.all()) {
      for (final o in name.occurrences) {
        final ayah = engine.quran.ayah(o.surah, o.ayah);
        expect(ayah, isNotNull, reason: 'name ${name.number}');
        if (o.token == null) {
          expect(o.tokens, 0, reason: 'name ${name.number}');
          unplaced += 1;
          continue;
        }
        final tokens = ayah!.textArabic
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();
        expect(o.token!, lessThan(tokens.length), reason: 'name ${name.number}');
        expect(_fold(tokens[o.token!]), isNotEmpty);
        placed += 1;
      }
    }
    expect(placed, 184);
    expect(unplaced, 10);
  });

  test('namesDepth: the two Names of the Basmalah are found in 1:3, in order',
      () {
    final hits = engine.namesDepth.inAyah(1, 3);
    expect(hits.map((h) => h.name.number).toList(), [1, 2]);
    expect(hits.map((h) => h.occurrence.token).toList(), [0, 1]);
  });

  test('namesDepth: a Name can be found by root, explanation or living line',
      () {
    expect(engine.namesDepth.search('رحم').any((n) => n.number == 1), isTrue);
    final first = engine.namesDepth.byNumber(1)!;
    final word =
        first.living.split(RegExp(r'\s+')).firstWhere((w) => w.length > 6);
    expect(engine.namesDepth.search(word), isNotEmpty);
    expect(engine.namesDepth.search(''), isEmpty);
  });

  // ---- the chains of transmission ------------------------------------------

  test('isnad: ten imams, twenty narrators, thirteen Companions', () {
    expect(engine.isnad.count(),
        {'imams': 10, 'narrators': 20, 'companions': 13});
    expect(engine.isnad.prophet(), isNotNull);
  });

  test('isnad: every riwayah resolves to one of the ten imams, two apiece', () {
    final per = <String, int>{
      for (final k in engine.isnad.imamKeys()) k: 0,
    };
    for (final tag in engine.isnad.narratorKeys()) {
      final imam = engine.isnad.imamOf(tag);
      expect(imam, isNotNull, reason: tag);
      per[imam!] = per[imam]! + 1;
    }
    per.forEach((imam, n) => expect(n, 2, reason: imam));
  });

  test('isnad: every imam reaches Companions, through Successors or directly',
      () {
    for (final imam in engine.isnad.imamKeys()) {
      final chain = engine.isnad.imam(imam)!;
      // Abu Jafar WAS a Successor and read on Companions himself, so he has no
      // teachers layer.
      if (imam != 'Abu Jafar') {
        expect(chain.teachers, isNotEmpty, reason: imam);
      }
      expect(chain.companions, isNotEmpty, reason: imam);
      for (final node in chain.teachers) {
        expect(node.role, 'successor');
        expect(node.detail, startsWith('d.'), reason: node.name);
      }
      for (final node in chain.companions) {
        expect(node.role, 'companion');
      }
    }
  });

  test('isnad: a chain runs from the Prophet down to the narrator', () {
    for (final tag in engine.isnad.narratorKeys()) {
      final layers = engine.isnad.chain(tag);
      expect(layers.length, greaterThanOrEqualTo(4), reason: tag);
      expect(layers.first.title, 'THE PROPHET');
      expect(layers[1].title, 'THE COMPANIONS');
      final titles = layers.map((l) => l.title).toList();
      expect(titles, contains('THE IMAM'));
      expect(titles, contains('THE NARRATOR'));
      expect(titles.indexOf('THE IMAM'),
          lessThan(titles.indexOf('THE NARRATOR')),
          reason: tag);
    }
  });

  test('isnad: an imam\'s chain ends at his two narrators', () {
    for (final imam in engine.isnad.imamKeys()) {
      final last = engine.isnad.chain(imam).last;
      expect(last.title, 'HIS TWO NARRATORS', reason: imam);
      expect(last.nodes.length, 2, reason: imam);
    }
  });

  test('isnad: reading directly is exactly having no links between', () {
    for (final tag in engine.isnad.narratorKeys()) {
      final chain = engine.isnad.narrator(tag)!;
      expect(engine.isnad.readsDirectly(tag), chain.links.isEmpty, reason: tag);
      final sentence = engine.isnad.sentence(tag);
      expect(sentence, isNotEmpty, reason: tag);
      expect(sentence.contains('did not meet'), chain.links.isNotEmpty,
          reason: tag);
    }
  });

  test('isnad: Hafs read on Asim himself; Qunbul did not meet Ibn Kathir', () {
    expect(engine.isnad.imamOf('Hafs an Asim'), 'Asim');
    expect(engine.isnad.readsDirectly('Hafs an Asim'), isTrue);
    expect(engine.isnad.sentence('Hafs an Asim'),
        startsWith('Hafs read on Asim himself'));

    expect(engine.isnad.imamOf('Qunbul an Ibn Kathir'), 'Ibn Kathir');
    expect(engine.isnad.readsDirectly('Qunbul an Ibn Kathir'), isFalse);
    expect(engine.isnad.narrator('Qunbul an Ibn Kathir')!.links.length, 3);
  });

  test('isnad: an unknown key answers nothing rather than throwing', () {
    expect(engine.isnad.chain('Nobody an Nobody'), isEmpty);
    expect(engine.isnad.sentence('Nobody an Nobody'), '');
    expect(engine.isnad.imamOf('no separator here'), isNull);
  });
}
