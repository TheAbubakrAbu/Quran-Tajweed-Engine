// The scientific-miracles corpus: 202 articles under 15 categories.
//
// Mirrors the JS `test/miracles.test.js`, the Python `tests/test_miracles.py`,
// the Go `miracles_test.go`, the Rust `tests/miracles.rs`, the Swift
// `MiraclesTests.swift` and the Kotlin `MiraclesTest.kt` case for case.

import 'package:quran_engine/quran_engine.dart';
import 'package:test/test.dart';

void main() {
  late Engine engine;
  late Miracles m;

  setUpAll(() async {
    engine = await Engine.load();
    m = engine.miracles;
  });

  test('202 articles under 15 categories, citing 278 ayah ranges', () {
    final c = m.count();
    expect(c.articles, 202);
    expect(c.categories, 15);
    expect(c.ayahRefs, 278);
    expect(m.all().length, 202);
    expect(m.categories().length, 15);
  });

  test('a slug round-trips, with its title, category and level intact', () {
    final article = m.bySlug('big_bang_crunch');
    expect(article, isNotNull);
    expect(article!.title, 'Big Bang');
    expect(article.category, 'cosmology');
    expect(article.level, 'extreme');
    expect(m.bySlug('no_such_article'), isNull);
    // Every slug is unique, which is what makes the lookup a round-trip and not
    // a first-match.
    expect(m.all().map((a) => a.slug).toSet().length, 202);
  });

  test('the categories partition the 202 with nothing left over', () {
    var total = 0;
    for (final category in m.categories()) {
      final members = m.byCategory(category.id);
      expect(members, isNotEmpty, reason: category.id);
      total += members.length;
    }
    expect(total, 202);
    expect(m.byCategory('cosmology').length, 18);
    expect(m.byCategory('no_such_category'), isEmpty);
  });

  test('a category is found by id, and its level is the category\'s own', () {
    final cosmology = m.category('cosmology');
    expect(cosmology, isNotNull);
    expect(cosmology!.id, 'cosmology');
    expect(cosmology.level, 'advanced');
    expect(m.category('no_such_category'), isNull);
  });

  test('an article\'s level is its own, not its category\'s', () {
    // Big Bang is filed under cosmology, which the corpus rates "advanced",
    // while the article itself is "extreme". Filtering on the category's level
    // would put it in the wrong bucket, and it is not one article out of place:
    // most of the corpus disagrees with its category.
    expect(m.category('cosmology')!.level, 'advanced');
    expect(m.bySlug('big_bang_crunch')!.level, 'extreme');
    final catLevel = {for (final c in m.categories()) c.id: c.level};
    final differing =
        m.all().where((a) => a.level != catLevel[a.category]).length;
    expect(differing, 147);
  });

  test('the levels run simple to extreme, which is not alphabetical', () {
    expect(m.levels(), ['simple', 'intermediate', 'advanced', 'extreme']);
    expect(m.levels(), miracleLevels);
    // Sorted as strings, "extreme" would come second. That is the whole reason
    // the rank is hard-coded.
    final alphabetical = [...m.levels()]..sort();
    expect(m.levels(), isNot(alphabetical));
    expect(m.byLevel('simple').length, 6);
    expect(m.byLevel('intermediate').length, 103);
    expect(m.byLevel('advanced').length, 37);
    expect(m.byLevel('extreme').length, 56);
    final total = miracleLevels.fold<int>(
        0, (n, level) => n + m.byLevel(level).length);
    expect(total, m.all().length);
  });

  test('every article names a category and a level the lists know', () {
    final ids = m.categories().map((c) => c.id).toSet();
    for (final article in m.all()) {
      expect(article.slug, isNotEmpty);
      expect(article.title, isNotEmpty, reason: article.slug);
      expect(ids, contains(article.category), reason: article.slug);
      expect(miracleLevels, contains(article.level), reason: article.slug);
      expect(article.blocks, isNotEmpty, reason: article.slug);
    }
  });

  test('citing() finds the articles that reach an ayah', () {
    // 21:30 is cited by exactly two: Big Bang and Exoplanets.
    expect(m.citing(21, 30).map((a) => a.slug).toList(),
        ['big_bang_crunch', 'exoplanets']);
    // 23:14, the embryology verse, by three.
    expect(m.citing(23, 14).map((a) => a.slug).toList(),
        ['bones', 'fetal_development', 'human_embryo']);
    expect(m.citing(21, 999), isEmpty);
    expect(m.citing(999, 1), isEmpty);
  });

  test('an ayah block is a RANGE, so citing() answers for the middle of it', () {
    // Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches
    // it, and 111:6, one past the end, does not (Surah al-Masad has five ayahs,
    // so this also checks the range end is what bounds the search, not the
    // surah).
    expect(m.ayahRefs('abjad_numerals'), [const MiracleAyahRef(111, 1, 5)]);
    for (final ayah in [1, 2, 3, 4, 5]) {
      expect(m.citing(111, ayah).any((a) => a.slug == 'abjad_numerals'), isTrue,
          reason: '111:$ayah');
    }
    expect(m.citing(111, 6).any((a) => a.slug == 'abjad_numerals'), isFalse);
    expect(m.ayahRefs('no_such_article'), isEmpty);
  });

  test('every ayah ref points at a real ayah of this engine\'s Quran', () {
    var refs = 0;
    var ranges = 0;
    for (final article in m.all()) {
      for (final ref in m.ayahRefs(article.slug)) {
        expect(ref.endAyah, greaterThanOrEqualTo(ref.ayah),
            reason: article.slug);
        // Both ends resolve, which is the point of storing the reference rather
        // than the text.
        expect(engine.quran.ayah(ref.surah, ref.ayah), isNotNull,
            reason: '${article.slug} -> ${ref.surah}:${ref.ayah}');
        expect(engine.quran.ayah(ref.surah, ref.endAyah), isNotNull,
            reason: '${article.slug} -> ${ref.surah}:${ref.endAyah}');
        refs++;
        if (ref.endAyah > ref.ayah) ranges++;
      }
    }
    expect(refs, 278);
    expect(ranges, 49);
  });

  test('no block anywhere is an image, and the corpus says so itself', () {
    // The site's illustrations are deliberately not republished. A consumer that
    // leaves a gap for a picture would wait forever, so the corpus states it and
    // the blocks bear it out.
    expect(m.imagesIncluded, isFalse);
    final kinds =
        m.all().expand((a) => a.blocks.map((b) => b.kind)).toSet().toList()
          ..sort();
    expect(kinds, isNot(contains('image')));
    expect(kinds, ['ayah', 'claim', 'closer', 'lead', 'quote', 'text']);
    expect(m.source(), contains('miracles-of-quran.com'));
  });

  test('a link is either an outside url or an internal slug, never both', () {
    var urls = 0;
    var slugs = 0;
    final known = m.all().map((a) => a.slug).toSet();
    for (final article in m.all()) {
      for (final block in article.blocks) {
        for (final link in block.links) {
          expect(link.label, isNotEmpty, reason: article.slug);
          expect((link.url == null) != (link.slug == null), isTrue,
              reason: '${article.slug}: ${link.label}');
          if (link.url != null) {
            urls++;
          } else {
            // An internal cross-reference resolves, so following one is
            // `bySlug` and nothing more.
            expect(known, contains(link.slug),
                reason: '${article.slug} -> ${link.slug}');
            expect(m.bySlug(link.slug!), isNotNull);
            slugs++;
          }
        }
      }
    }
    expect(urls, 73);
    expect(slugs, 12);
    // One of each form, named, so a port that models only one of them fails
    // here.
    final internal =
        m.bySlug('big_bang_crunch')!.blocks.expand((b) => b.links).toList();
    expect(internal.length, 1);
    expect(internal.first.label, 'Dark Energy');
    expect(internal.first.slug, 'dark_energy');
    expect(internal.first.url, isNull);
    final external = m
        .bySlug('atoms')!
        .blocks
        .expand((b) => b.links)
        .where((l) => l.url != null)
        .toList();
    expect(external, isNotEmpty);
    expect(external.every((l) => l.url!.startsWith('http')), isTrue);
  });

  test('text() joins the article\'s own prose and leaves the quotes out', () {
    final abjad = m.bySlug('abjad_numerals')!;
    final quote = abjad.blocks.firstWhere((b) => b.kind == 'quote');
    expect(quote.sourceLabel, 'Wikipedia, Abjad Numerals, 2021');
    final text = m.text('abjad_numerals');
    // The quote sits between the lead and the first text block, and none of it
    // comes through: it is somebody else's words next to a source label, not the
    // article's voice.
    expect(text, isNot(contains(quote.text.substring(0, 40))));
    expect(text, isNot(contains('Wikipedia')));
    // What does come through is claim, lead, text and closer, in reading order.
    expect(text.startsWith('Alphanumeric code.'), isTrue);
    expect(text,
        contains('We found this ancient numeral system encoded in the Quran.'));
    expect(text.split('\n\n').length, 6);
    expect(m.text('big_bang_crunch').split('\n\n').length, 4);
    expect(m.text('no_such_article'), '');
  });

  test('search matches a title or the prose, case-insensitively', () {
    final hits = m.search('big bang').map((a) => a.slug).toList();
    expect(hits, contains('big_bang_crunch'));
    expect(m.search('BIG BANG').map((a) => a.slug).toList(), hits);
    expect(m.search('cosmology', 3).length, lessThanOrEqualTo(3));
    expect(m.search(''), isEmpty);
    expect(m.search('   '), isEmpty);
    expect(m.search('zzzznotaword'), isEmpty);
  });

  test('an empty corpus answers nothing rather than throwing', () {
    // `Engine` builds this module empty when the file is absent, and every call
    // has to survive that: a consumer without the pack sees an empty corpus, not
    // a crash.
    final empty = Miracles();
    expect(empty.isLoaded, isFalse);
    expect(empty.all(), isEmpty);
    expect(empty.categories(), isEmpty);
    expect(empty.bySlug('big_bang_crunch'), isNull);
    expect(empty.category('cosmology'), isNull);
    expect(empty.levels(), isEmpty);
    expect(empty.citing(21, 30), isEmpty);
    expect(empty.ayahRefs('big_bang_crunch'), isEmpty);
    expect(empty.text('big_bang_crunch'), '');
    expect(empty.search('big bang'), isEmpty);
    expect(empty.imagesIncluded, isFalse);
    final c = empty.count();
    expect([c.articles, c.categories, c.ayahRefs], [0, 0, 0]);
    expect(m.isLoaded, isTrue);
  });
}
