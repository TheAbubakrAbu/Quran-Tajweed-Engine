// @ts-check
/**
 * The scientific-miracles corpus: 202 articles under 15 categories.
 *
 * The counts are pinned against the app's own pack, so a corpus that reaches the engine
 * half-imported fails loudly rather than quietly answering less than it should. Two facts about
 * the SHAPE are pinned too, because both are promises this module makes in its doc comment and
 * neither is enforced by the JSON itself: that no block anywhere is an image, and that an article's
 * level is its own rather than its category's.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadFromDisk } from "../src/node.js";
import { Miracles, MIRACLE_LEVELS } from "../src/miracles.js";

const engine = await loadFromDisk();
const m = engine.miracles;

test("miracles: 202 articles under 15 categories, citing 278 ayah ranges", () => {
  const { articles, categories, ayahRefs } = m.count();
  assert.equal(articles, 202);
  assert.equal(categories, 15);
  assert.equal(ayahRefs, 278);
  assert.equal(m.all().length, 202);
  assert.equal(m.categories().length, 15);
});

test("miracles: a slug round-trips, with its title, category and level intact", () => {
  const article = m.bySlug("big_bang_crunch");
  assert.ok(article);
  assert.equal(article.title, "Big Bang");
  assert.equal(article.category, "cosmology");
  assert.equal(article.level, "extreme");
  assert.equal(m.bySlug("no_such_article"), null);
  // Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
  assert.equal(new Set(m.all().map((a) => a.slug)).size, 202);
});

test("miracles: the categories partition the 202 with nothing left over", () => {
  let total = 0;
  for (const category of m.categories()) {
    const members = m.byCategory(category.id);
    assert.ok(members.length > 0, `category ${category.id} has no articles`);
    total += members.length;
  }
  assert.equal(total, 202);
  assert.equal(m.byCategory("cosmology").length, 18);
  assert.deepEqual(m.byCategory("no_such_category"), []);
});

test("miracles: a category is found by id, and its level is the category's own", () => {
  const cosmology = m.category("cosmology");
  assert.ok(cosmology);
  assert.equal(cosmology.id, "cosmology");
  assert.equal(cosmology.level, "advanced");
  assert.equal(m.category("no_such_category"), null);
});

test("miracles: an article's level is its own, not its category's", () => {
  // Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
  // itself is "extreme". Filtering on the category's level would put it in the wrong bucket, and
  // it is not one article out of place: most of the corpus disagrees with its category.
  assert.equal(m.category("cosmology").level, "advanced");
  assert.equal(m.bySlug("big_bang_crunch").level, "extreme");
  const catLevel = new Map(m.categories().map((c) => [c.id, c.level]));
  const differing = m.all().filter((a) => a.level !== catLevel.get(a.category));
  assert.equal(differing.length, 147);
});

test("miracles: the levels run simple to extreme, which is not alphabetical", () => {
  assert.deepEqual(m.levels(), ["simple", "intermediate", "advanced", "extreme"]);
  assert.deepEqual(m.levels(), MIRACLE_LEVELS);
  // Sorted as strings, "extreme" would come second. That is the whole reason the rank is hard-coded.
  assert.notDeepEqual(m.levels(), [...m.levels()].sort());
  assert.equal(m.byLevel("simple").length, 6);
  assert.equal(m.byLevel("intermediate").length, 103);
  assert.equal(m.byLevel("advanced").length, 37);
  assert.equal(m.byLevel("extreme").length, 56);
  assert.equal(m.all().length, MIRACLE_LEVELS.reduce((n, l) => n + m.byLevel(l).length, 0));
});

test("miracles: every article names a category and a level the lists know", () => {
  const ids = new Set(m.categories().map((c) => c.id));
  for (const article of m.all()) {
    assert.ok(article.slug.length > 0);
    assert.ok(article.title.length > 0, article.slug);
    assert.ok(ids.has(article.category), `${article.slug} is filed under ${article.category}`);
    assert.ok(MIRACLE_LEVELS.includes(article.level), `${article.slug} is at ${article.level}`);
    assert.ok(article.blocks.length > 0, article.slug);
  }
});

test("miracles: citing() finds the articles that reach an ayah", () => {
  // 21:30 is cited by exactly two: Big Bang and Exoplanets.
  assert.deepEqual(m.citing(21, 30).map((a) => a.slug), ["big_bang_crunch", "exoplanets"]);
  // 23:14, the embryology verse, by three.
  assert.deepEqual(m.citing(23, 14).map((a) => a.slug), ["bones", "fetal_development", "human_embryo"]);
  assert.deepEqual(m.citing(21, 999), []);
  assert.deepEqual(m.citing(999, 1), []);
});

test("miracles: an ayah block is a RANGE, so citing() answers for the middle of it", () => {
  // Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
  // one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range end
  // is what bounds the search, not the surah).
  assert.deepEqual(m.ayahRefs("abjad_numerals"), [{ surah: 111, ayah: 1, endAyah: 5 }]);
  for (const ayah of [1, 2, 3, 4, 5]) {
    assert.ok(m.citing(111, ayah).some((a) => a.slug === "abjad_numerals"), `111:${ayah}`);
  }
  assert.ok(!m.citing(111, 6).some((a) => a.slug === "abjad_numerals"));
  assert.deepEqual(m.ayahRefs("no_such_article"), []);
});

test("miracles: every ayah ref points at a real ayah of this engine's Quran", () => {
  let refs = 0;
  let ranges = 0;
  for (const article of m.all()) {
    for (const ref of m.ayahRefs(article.slug)) {
      assert.ok(ref.endAyah >= ref.ayah, `${article.slug} cites ${ref.surah}:${ref.ayah}-${ref.endAyah}`);
      // Both ends resolve, which is the point of storing the reference rather than the text.
      assert.ok(engine.quran.ayah(ref.surah, ref.ayah), `${article.slug} -> ${ref.surah}:${ref.ayah}`);
      assert.ok(engine.quran.ayah(ref.surah, ref.endAyah), `${article.slug} -> ${ref.surah}:${ref.endAyah}`);
      refs += 1;
      if (ref.endAyah > ref.ayah) ranges += 1;
    }
  }
  assert.equal(refs, 278);
  assert.equal(ranges, 49);
});

test("miracles: no block anywhere is an image, and the corpus says so itself", () => {
  // The site's illustrations are deliberately not republished. A consumer that leaves a gap for
  // a picture would wait forever, so the corpus states it and the blocks bear it out.
  assert.equal(m.imagesIncluded, false);
  const kinds = new Set(m.all().flatMap((a) => a.blocks.map((b) => b.kind)));
  assert.ok(!kinds.has("image"));
  assert.deepEqual([...kinds].sort(), ["ayah", "claim", "closer", "lead", "quote", "text"]);
  assert.match(m.source(), /miracles-of-quran\.com/);
});

test("miracles: a link is either an outside url or an internal slug, never both", () => {
  let urls = 0;
  let slugs = 0;
  const known = new Set(m.all().map((a) => a.slug));
  for (const article of m.all()) {
    for (const block of article.blocks) {
      for (const link of block.links ?? []) {
        assert.ok(link.label.length > 0, article.slug);
        assert.equal(link.url === undefined, link.slug !== undefined, `${article.slug}: ${link.label}`);
        if (link.url !== undefined) urls += 1;
        else {
          // An internal cross-reference resolves, so following one is `bySlug` and nothing more.
          assert.ok(known.has(link.slug), `${article.slug} -> ${link.slug}`);
          assert.ok(m.bySlug(link.slug));
          slugs += 1;
        }
      }
    }
  }
  assert.equal(urls, 73);
  assert.equal(slugs, 12);
  // One of each form, named, so a port that models only one of them fails here.
  const internal = m.bySlug("big_bang_crunch").blocks.flatMap((b) => b.links ?? []);
  assert.deepEqual(internal, [{ label: "Dark Energy", slug: "dark_energy" }]);
  const external = m.bySlug("atoms").blocks.flatMap((b) => b.links ?? []).filter((l) => l.url);
  assert.ok(external.length > 0);
  assert.ok(external.every((l) => l.url.startsWith("http")));
});

test("miracles: text() joins the article's own prose and leaves the quotes out", () => {
  const abjad = m.bySlug("abjad_numerals");
  const quote = abjad.blocks.find((b) => b.kind === "quote");
  assert.ok(quote);
  assert.equal(quote.sourceLabel, "Wikipedia, Abjad Numerals, 2021");
  const text = m.text("abjad_numerals");
  // The quote sits between the lead and the first text block, and none of it comes through:
  // it is somebody else's words next to a source label, not the article's voice.
  assert.ok(!text.includes(quote.text.slice(0, 40)));
  assert.ok(!text.includes("Wikipedia"));
  // What does come through is claim, lead, text and closer, in reading order.
  assert.ok(text.startsWith("Alphanumeric code."));
  assert.ok(text.includes("We found this ancient numeral system encoded in the Quran."));
  assert.equal(text.split("\n\n").length, 6);
  assert.equal(m.text("big_bang_crunch").split("\n\n").length, 4);
  assert.equal(m.text("no_such_article"), "");
});

test("miracles: search matches a title or the prose, case-insensitively", () => {
  const hits = m.search("big bang");
  assert.ok(hits.some((a) => a.slug === "big_bang_crunch"));
  assert.deepEqual(m.search("BIG BANG").map((a) => a.slug), hits.map((a) => a.slug));
  assert.ok(m.search("cosmology", 3).length <= 3);
  assert.deepEqual(m.search(""), []);
  assert.deepEqual(m.search("   "), []);
  assert.deepEqual(m.search("zzzznotaword"), []);
});

test("miracles: an empty corpus answers nothing rather than throwing", () => {
  // `createEngine` builds this module from `{}` when the file is absent, and every call has to
  // survive that: a consumer without the pack sees an empty corpus, not a crash.
  const empty = new Miracles();
  assert.equal(empty.isLoaded, false);
  assert.deepEqual(empty.all(), []);
  assert.deepEqual(empty.categories(), []);
  assert.equal(empty.bySlug("big_bang_crunch"), null);
  assert.equal(empty.category("cosmology"), null);
  assert.deepEqual(empty.levels(), []);
  assert.deepEqual(empty.citing(21, 30), []);
  assert.deepEqual(empty.ayahRefs("big_bang_crunch"), []);
  assert.equal(empty.text("big_bang_crunch"), "");
  assert.deepEqual(empty.search("big bang"), []);
  assert.deepEqual(empty.count(), { articles: 0, categories: 0, ayahRefs: 0 });
  assert.ok(m.isLoaded);
});
