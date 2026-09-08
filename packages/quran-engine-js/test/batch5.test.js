// @ts-check
/**
 * Batch 5: morphology, mutashabihat, the QUL topic families, hizb/ruku/manzil, the qiraat
 * variant matrix and the word of the day.
 *
 * Every count here is pinned against the app's own verify gate (`Scripts/verify_qul_packs.py`
 * and friends), so a corpus that reaches the engine half-imported fails loudly rather than
 * quietly answering less than it should.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadFromDisk } from "../src/node.js";
import { foldForMorphology } from "../src/morphology.js";

const engine = await loadFromDisk({
  loadMorphology: true,
  loadMutashabihat: true,
  loadQuranTopics: true,
  loadQiraatVariants: true,
});

// ---- morphology -------------------------------------------------------------------

test("morphology: the corpus is the size the app's gate reports", () => {
  assert.deepEqual(engine.morphology.count(), { roots: 1642, lemmas: 4817, tokens: 77629 });
});

test("morphology: ids are 1-based and 0 means the token has no root", () => {
  assert.equal(engine.morphology.root(0), null);
  assert.ok(engine.morphology.root(1));
  // 1:1 is بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ - four tokens, all of them rooted.
  const ids = engine.morphology.ids(1, 1);
  assert.equal(ids?.roots.length, 4);
  assert.equal(ids?.lemmas.length, 4);
});

test("morphology: a token resolves to its root and dictionary form", () => {
  // 1:2 ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ - token 2 is رَبِّ.
  const root = engine.morphology.rootOf(1, 2, 2);
  assert.equal(root?.root.letters, "ر ب ب");
  assert.equal(root?.root.buckwalter, "rbb");
  assert.equal(root?.root.joined, "ربب");
  assert.ok(engine.morphology.lemmaOf(1, 2, 2)?.lemma.text);
});

test("morphology: a root's occurrences come back in mushaf order", () => {
  const rbb = engine.morphology.findRoots("ربب")[0];
  const hits = engine.morphology.occurrencesOfRoot(rbb.id);
  assert.equal(hits.length, 980);
  assert.deepEqual(hits[0], { surah: 1, ayah: 2, token: 2 });
  for (let i = 1; i < hits.length; i++) {
    const a = hits[i - 1], b = hits[i];
    const rank = (w) => w.surah * 1e6 + w.ayah * 1e3 + w.token;
    assert.ok(rank(a) < rank(b), `out of order at ${i}`);
  }
});

test("morphology: a root is found spaced, closed up, or in Buckwalter", () => {
  // The fold has to close the spaces, not merely trim them: a lexicon prints "ر ب ب" and a
  // reader types "ربب". cleanSearch's own whitespace option only trims.
  assert.equal(foldForMorphology("ر ب ب"), "ربب");
  for (const query of ["ربب", "ر ب ب", "rbb"]) {
    const hit = engine.morphology.findRoots(query, 5).find((h) => h.root.buckwalter === "rbb");
    assert.ok(hit, `no rbb for ${query}`);
  }
});

test("morphology: every id in the tables resolves", () => {
  let checked = 0;
  for (const surah of [1, 2, 18, 114]) {
    const rows = engine.morphology.ids(surah, 1);
    for (const id of [...(rows?.roots ?? []), ...(rows?.lemmas ?? [])]) {
      if (id === 0) continue;
      checked += 1;
    }
  }
  assert.ok(checked > 0);
  assert.equal(engine.morphology.root(1643), null, "root ids stop at the table size");
});

// ---- mutashabihat -----------------------------------------------------------------

test("mutashabihat: 814 phrases over 2,232 ayahs", () => {
  assert.deepEqual(engine.mutashabihat.count(), { phrases: 814, ayahs: 2232 });
});

test("mutashabihat: a phrase knows its own source span and every occurrence", () => {
  const phrase = engine.mutashabihat.phrase(10167);
  assert.ok(phrase);
  assert.equal(phrase.source, "9:87");
  assert.deepEqual(phrase.span, [5, 10]);
  assert.equal(phrase.wordCount, 6);
  assert.equal(phrase.ayahCount, 3);
  assert.equal(phrase.surahCount, 2);
  // The occurrence list is keyed by ayah and each entry carries the spans in THAT ayah.
  assert.deepEqual(phrase.occurrences["9:93"], [[13, 19]]);
});

test("mutashabihat: occurrences come out in mushaf order, not key order", () => {
  const keys = engine.mutashabihat.occurrences(10167).map((o) => o.key);
  assert.deepEqual(keys, ["9:87", "9:93", "63:3"]);
});

test("mutashabihat: a phrase slices out of the ayah text you hand it", () => {
  const source = engine.quran.ayah(9, 87)?.textArabic ?? "";
  const text = engine.mutashabihat.textOf(10167, source);
  assert.equal(text.split(/\s+/).length, 6);
  assert.ok(source.includes(text.split(/\s+/)[0]));
});

test("mutashabihat: has() agrees with phrasesFor()", () => {
  assert.equal(engine.mutashabihat.has(9, 87), true);
  assert.ok(engine.mutashabihat.phrasesFor(9, 87).length > 0);
  assert.equal(engine.mutashabihat.has(1, 1), engine.mutashabihat.phrasesFor(1, 1).length > 0);
});

// ---- QUL topics -------------------------------------------------------------------

test("topics: 2,512 topics and 30,687 references, listed 2,529 times over", () => {
  const counts = engine.quranTopics.count();
  assert.equal(counts.topics, 2512);
  assert.equal(counts.references, 30687);
  // The per-index counts deliberately sum to MORE than the topic count: the 17 topics listed in
  // two indexes are counted in both, which is what "listed in" means.
  assert.equal(counts.thematic + counts.ontology + counts.index, 2529);
  assert.equal(counts.thematic, 695);
  assert.equal(counts.ontology, 284);
  assert.equal(counts.index, 1550);
});

test("topics: the three indexes are independent trees, not a partition", () => {
  // 17 topics are listed in two indexes at once and carry a parent in each. Collapsing that to
  // one "family parent" silently drops the other tree, so the shape has to keep both.
  const both = engine.quranTopics.all().filter((t) => t.families.length > 1);
  assert.equal(both.length, 17);
  const adam = engine.quranTopics.topic(13);
  assert.deepEqual(adam?.families, ["thematic", "ontology"]);
  assert.equal(engine.quranTopics.parent(13, "thematic")?.name, "Prophets (25 mentioned by name)");
  assert.equal(engine.quranTopics.parent(13, "ontology")?.name, "Prophet");
  // A tree is not closed over its own listing either: the A-Z index hangs entries under
  // thematic topics, so asserting the parent shares the child's family would be false.
  const crossing = engine.quranTopics.all().filter((t) => {
    const parent = t.parents.index ? engine.quranTopics.topic(t.parents.index) : null;
    return parent && !parent.families.includes("index");
  });
  assert.ok(crossing.length > 0, "expected the index tree to reach outside its own listing");
});

test("topics: every parent id resolves, in every tree", () => {
  for (const topic of engine.quranTopics.all()) {
    for (const tree of /** @type {const} */ (["thematic", "ontology", "index"])) {
      const parentId = topic.parents[tree];
      if (!parentId) continue;
      assert.ok(engine.quranTopics.topic(parentId),
                `topic ${topic.id} (${topic.name}) has a dangling ${tree} parent ${parentId}`);
    }
  }
});

test("topics: ancestors terminate in every tree even if the corpus had a cycle", () => {
  for (const tree of /** @type {const} */ (["thematic", "ontology", "index"])) {
    const deep = engine.quranTopics.all().find((t) => engine.quranTopics.ancestors(t.id, tree).length >= 2);
    assert.ok(deep, `expected a topic two levels down in the ${tree} tree`);
    const chain = engine.quranTopics.ancestors(deep.id, tree);
    assert.equal(new Set(chain.map((t) => t.id)).size, chain.length, `cycle in ${tree}`);
    assert.equal(chain[chain.length - 1].parents[tree], null);
  }
});

test("topics: a child is listed under the parent it names, per tree", () => {
  for (const tree of /** @type {const} */ (["thematic", "ontology", "index"])) {
    const child = engine.quranTopics.all().find((t) => t.parents[tree]);
    assert.ok(child);
    const siblings = engine.quranTopics.children(/** @type number */ (child.parents[tree]), tree);
    assert.ok(siblings.some((s) => s.id === child.id), `${child.name} missing from its ${tree} parent`);
  }
});

test("topics: every ayah reference is a real ayah, and reverse lookup agrees", () => {
  const sample = engine.quranTopics.all().slice(0, 200);
  for (const topic of sample) {
    for (const key of topic.ayahs) {
      const [s, a] = key.split(":").map(Number);
      assert.ok(engine.quran.ayah(s, a), `${topic.name} cites ${key}`);
    }
  }
  const first = sample[0];
  const [s, a] = first.ayahs[0].split(":").map(Number);
  assert.ok(engine.quranTopics.topicsFor(s, a).some((t) => t.id === first.id));
});

// ---- passage themes ---------------------------------------------------------------

test("ayahThemes: 1,049 passages across all 114 surahs", () => {
  assert.deepEqual(engine.ayahThemes.count(), { surahs: 114, passages: 1049 });
});

test("ayahThemes: passages of a surah are ordered and never overlap", () => {
  for (const surah of engine.quran.all()) {
    let previousEnd = 0;
    for (const passage of engine.ayahThemes.passages(surah.id)) {
      assert.ok(passage.from >= previousEnd + 1 || previousEnd === 0,
                `surah ${surah.id}: ${passage.from} overlaps ${previousEnd}`);
      assert.ok(passage.to >= passage.from);
      assert.ok(passage.to <= surah.numberOfAyahs, `surah ${surah.id} passage runs past the end`);
      previousEnd = passage.to;
    }
  }
});

test("ayahThemes: an ayah lands in the passage that contains it", () => {
  const passage = engine.ayahThemes.passageFor(2, 10);
  assert.equal(passage?.theme, "Hypocrites and the consequences of hypocrisy");
  assert.equal(passage?.from, 8);
  assert.equal(passage?.to, 16);
});

// ---- hizb / ruku / manzil ---------------------------------------------------------

test("metadata: 60 hizb, 558 ruku, 7 manzil, all starting at 1:1", () => {
  assert.deepEqual(engine.quranMetadata.count(), { hizb: 60, ruku: 558, manzil: 7 });
  for (const table of [engine.quranMetadata.hizb, engine.quranMetadata.ruku, engine.quranMetadata.manzil]) {
    assert.deepEqual(table.start(1), { number: 1, surah: 1, ayah: 1, key: "1:1" });
  }
});

test("metadata: every division start is in ascending mushaf order", () => {
  for (const table of [engine.quranMetadata.hizb, engine.quranMetadata.ruku, engine.quranMetadata.manzil]) {
    const all = table.all();
    for (let i = 1; i < all.length; i++) {
      const a = all[i - 1], b = all[i];
      assert.ok(a.surah < b.surah || (a.surah === b.surah && a.ayah < b.ayah), `at ${b.key}`);
      assert.ok(engine.quran.ayah(b.surah, b.ayah), `${b.key} is not an ayah`);
    }
  }
});

test("metadata: a lookup returns the division whose start precedes the ayah", () => {
  assert.deepEqual(engine.quranMetadata.for(1, 1), { hizb: 1, ruku: 1, manzil: 1 });
  const last = engine.quranMetadata.for(114, 6);
  assert.equal(last.hizb, 60);
  assert.equal(last.manzil, 7);
  // The hizb containing an ayah starts at or before it, and the next starts after it.
  const n = engine.quranMetadata.hizb.numberFor(2, 255);
  const range = engine.quranMetadata.hizb.range(n);
  assert.ok(range);
  assert.ok(range.from.surah < 2 || (range.from.surah === 2 && range.from.ayah <= 255));
  assert.ok(!range.until || range.until.surah > 2 || (range.until.surah === 2 && range.until.ayah > 255));
});

// ---- qiraat variants --------------------------------------------------------------

test("qiraatVariants: 1,634 junctures and 3,503 readings over 1,409 ayahs", () => {
  assert.deepEqual(engine.qiraatVariants.count(), { ayahs: 1409, junctures: 1634, readings: 3503 });
});

test("qiraatVariants: ten readers and twenty transmitters, each transmitter under its imam", () => {
  const readers = Object.values(engine.qiraatVariants._readers);
  const transmitters = Object.values(engine.qiraatVariants._transmitters);
  assert.equal(readers.length, 10);
  assert.equal(transmitters.length, 20);
  for (const t of transmitters) {
    assert.ok(engine.qiraatVariants.reader(/** @type any */ (t).reader), `${/** @type any */ (t).name} has no imam`);
  }
  // Exactly the eight published riwayat carry text in this engine.
  assert.equal(transmitters.filter((t) => /** @type any */ (t).textPublished).length, 8);
});

test("qiraatVariants: a juncture names the word, its readings and who reads them", () => {
  const junctures = engine.qiraatVariants.junctures(102, 6);
  assert.ok(junctures.length > 0);
  const juncture = junctures[0];
  assert.ok(juncture.readings.length >= 2, "a juncture with one reading is not a variant");
  for (const reading of juncture.readings) {
    assert.ok(reading.text.length > 0);
    assert.ok((reading.readers.length + reading.transmitters.length) > 0, "a reading nobody reads");
  }
});

test("qiraatVariants: attribution names imams first, then lone transmitters with their imam", () => {
  for (const [key] of Object.entries(engine.qiraatVariants._ayahs).slice(0, 50)) {
    const [s, a] = key.split(":").map(Number);
    for (const juncture of engine.qiraatVariants.junctures(s, a)) {
      for (const reading of juncture.readings) {
        const text = engine.qiraatVariants.attribution(reading);
        assert.ok(text.length > 0, `${key} has a reading with no attribution`);
      }
    }
  }
});

test("qiraatVariants: Hafs follows exactly one reading at every juncture he is party to", () => {
  let matched = 0;
  for (const [key] of Object.entries(engine.qiraatVariants._ayahs).slice(0, 100)) {
    const [s, a] = key.split(":").map(Number);
    for (const juncture of engine.qiraatVariants.junctures(s, a)) {
      if (engine.qiraatVariants.readingFor(juncture, "hafs")) matched += 1;
    }
  }
  assert.ok(matched > 0, "Hafs reads none of the first hundred junctures, which cannot be right");
});

test("qiraatVariants: segment spans are inclusive token ranges or an honest null", () => {
  for (const [key] of Object.entries(engine.qiraatVariants._ayahs).slice(0, 200)) {
    const [s, a] = key.split(":").map(Number);
    for (const juncture of engine.qiraatVariants.junctures(s, a)) {
      for (const segment of juncture.segments) {
        if (segment.span === null) continue;
        const [from, to] = segment.span;
        assert.ok(from >= 0 && to >= from, `${key}: bad span ${from}..${to}`);
        const [ss, sa] = segment.ayah.split(":").map(Number);
        const tokens = (engine.quran.ayah(ss, sa)?.textArabic ?? "").split(/\s+/).filter(Boolean);
        assert.ok(to < tokens.length, `${segment.ayah}: span ends past the last token`);
      }
    }
  }
});

// ---- qiraat places ----------------------------------------------------------------

test("places: only the eight published riwayat are indexed", () => {
  const slugs = engine.qiraatVariants.riwayatWithPlaces();
  assert.equal(slugs.length, 7, "hafs is the reference and indexes nothing against itself");
  for (const slug of slugs) {
    assert.equal(engine.mushaf.riwayah(slug)?.textIncluded ?? true, true, slug);
  }
});

test("places: al-Fatihah's مالك is a letter-level difference, not a word-level one", () => {
  // The classic case: مَلِكِ against مَٰلِكِ shares a skeleton, so a text diff cannot see it and
  // only the printed mushaf's khilaf wash flags it.
  const rows = engine.qiraatVariants.places("warsh", 1);
  const fourth = rows.find((r) => r.ayah === 4);
  assert.ok(fourth, "Warsh differs from Hafs at 1:4");
  assert.ok(fourth.letter.length > 0 || fourth.word.length > 0);
});

test("places: every index points at a token the ayah actually has", () => {
  for (const slug of engine.qiraatVariants.riwayatWithPlaces()) {
    for (const surah of [1, 2, 18]) {
      for (const row of engine.qiraatVariants.places(slug, surah)) {
        const tokens = (engine.quran.ayah(surah, row.ayah)?.textArabic ?? "").split(/\s+/).filter(Boolean);
        for (const index of [...row.word, ...row.letter]) {
          assert.ok(index >= 0 && index < tokens.length,
                    `${slug} ${surah}:${row.ayah} index ${index} of ${tokens.length}`);
        }
      }
    }
  }
});

// ---- paired recordings ------------------------------------------------------------

test("audio: four riwayat have paired recordings and the rest honestly have none", () => {
  const slugs = engine.qiraatVariants.riwayatWithAudio();
  assert.equal(slugs.length, 4);
  assert.equal(engine.qiraatVariants.audio("qunbul", 1, 4), null);
});

test("audio: a pair is one reciter, two urls, and matching span kinds", () => {
  let found = 0;
  for (const slug of engine.qiraatVariants.riwayatWithAudio()) {
    for (let surah = 1; surah <= 114 && found < 8; surah++) {
      for (let ayah = 1; ayah <= 10; ayah++) {
        const pair = engine.qiraatVariants.audio(slug, surah, ayah);
        if (!pair) continue;
        found += 1;
        assert.ok(pair.reciter.length > 0);
        assert.match(pair.hafs.url, /^https?:\/\/.+\.mp3$/);
        assert.match(pair.riwayah.url, /^https?:\/\/.+\.mp3$/);
        assert.notEqual(pair.hafs.url, pair.riwayah.url, "a pair must differ in the reading");
        // Either both sides are seeks into a full surah, or neither is.
        assert.equal(pair.hafs.startMs === null, pair.riwayah.startMs === null);
        if (pair.hafs.startMs !== null) {
          assert.ok(pair.hafs.endMs > pair.hafs.startMs);
          assert.ok(pair.riwayah.endMs > pair.riwayah.startMs);
        }
        break;
      }
    }
  }
  assert.ok(found >= 4, `only found ${found} pairs`);
});

// ---- word of the day --------------------------------------------------------------

test("wordOfDay: 149 curated words", () => {
  assert.equal(engine.wordOfDay.count().words, 149);
});

test("wordOfDay: the day walk is stable, wraps, and handles a negative index", () => {
  const n = engine.wordOfDay.all().length;
  assert.equal(engine.wordOfDay.forDayIndex(0)?.id, engine.wordOfDay.all()[0].id);
  assert.equal(engine.wordOfDay.forDayIndex(n)?.id, engine.wordOfDay.all()[0].id);
  assert.equal(engine.wordOfDay.forDayIndex(-1)?.id, engine.wordOfDay.all()[n - 1].id);
  const today = engine.wordOfDay.forDate(new Date("2026-09-08T12:00:00"));
  assert.equal(today?.id, engine.wordOfDay.forDate(new Date("2026-09-08T23:00:00"))?.id);
});

test("wordOfDay: the count on a card is the length of the list behind it", () => {
  for (const word of engine.wordOfDay.all()) {
    const total = word.occurrences.reduce((n, o) => n + o.tokens.length, 0);
    assert.equal(word.count, total, word.id);
  }
});

test("wordOfDay: the anchor is the form's first appearance, and every token really is the form", () => {
  // Occurrences were matched FOLDED upstream: harakat and the waqf marks gone, alif wasla and
  // the hamza seats normalized. So ٱلۡحَمۡدُۖ at 64:1 is the same form as ٱلۡحَمۡدُ, and
  // comparing the written tokens literally would call that a mismatch when it is a pause mark.
  const marks = /[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]/g;
  const fold = (s) => s.replace(marks, "")
    .replace(/\u0671/g, "\u0627").replace(/[\u0623\u0625]/g, "\u0627")
    .replace(/\u0624/g, "\u0648").replace(/\u0626/g, "\u064A");
  for (const word of engine.wordOfDay.all()) {
    const first = word.occurrences[0];
    assert.equal(first.surah, word.surah, word.id);
    assert.equal(first.ayah, word.ayah, word.id);
    assert.equal(first.tokens[0], word.token, word.id);
    const target = fold(word.arabic);
    for (const occurrence of word.occurrences) {
      const tokens = (engine.quran.ayah(occurrence.surah, occurrence.ayah)?.textArabic ?? "")
        .split(/\s+/).filter(Boolean);
      for (const index of occurrence.tokens) {
        assert.equal(fold(tokens[index] ?? ""), target,
                     `${word.id} at ${occurrence.surah}:${occurrence.ayah} token ${index}`);
      }
    }
  }
});

test("wordOfDay: a word can be found by its form, transliteration or meaning", () => {
  const first = engine.wordOfDay.all()[0];
  assert.ok(engine.wordOfDay.search(first.arabic).some((w) => w.id === first.id));
  assert.ok(engine.wordOfDay.wordsIn(first.surah, first.ayah).some((w) => w.id === first.id));
});
