// @ts-check
/**
 * Batch 6: the 99 Names in depth, and the chains of transmission of the Ten Readings.
 *
 * The counts are pinned against the app's own packs, so a corpus that reaches the engine
 * half-imported fails loudly rather than quietly answering less than it should. The chains are
 * checked for SHAPE as well as size: every riwayah must resolve to one of the ten imams, and
 * every chain must start at the Prophet and end at a narrator or his students.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadFromDisk } from "../src/node.js";
import { rootKey } from "../src/namesDepth.js";

const engine = await loadFromDisk();

// ---- the Names in depth ----------------------------------------------------------

test("namesDepth: all 99 Names carry depth, under nine themes", () => {
  const { names, themes, occurrences } = engine.namesDepth.count();
  assert.equal(names, 99);
  assert.equal(themes, 9);
  assert.equal(occurrences, 194);
  // Every number 1..99 is present exactly once, and they are in order.
  assert.deepEqual(engine.namesDepth.all().map((n) => n.number),
                   Array.from({ length: 99 }, (_, i) => i + 1));
});

test("namesDepth: every Name has a root, a theme the theme list knows, and prose", () => {
  const ids = new Set(engine.namesDepth.themes().map((t) => t.id));
  for (const name of engine.namesDepth.all()) {
    assert.ok(name.root.length > 0, `name ${name.number} has no root`);
    assert.ok(ids.has(name.theme), `name ${name.number} theme ${name.theme} is not in the list`);
    assert.ok(name.explanation.length > 40, `name ${name.number} explanation is too short`);
    assert.ok(name.living.length > 20, `name ${name.number} living line is too short`);
  }
});

test("namesDepth: the themes partition the 99 with nothing left over", () => {
  let total = 0;
  for (const theme of engine.namesDepth.themes()) {
    const members = engine.namesDepth.byTheme(theme.id);
    assert.ok(members.length > 0, `theme ${theme.id} has no Names`);
    total += members.length;
  }
  assert.equal(total, 99);
});

test("namesDepth: a root is spaced in the corpus and closed up for morphology", () => {
  const rahman = engine.namesDepth.byNumber(1);
  assert.ok(rahman);
  assert.equal(rahman.root, "ر ح م");
  assert.equal(rootKey(rahman.root), "رحم");
  // Ar-Rahman and Ar-Raheem are the same root, and `byRoot` takes either spelling.
  assert.deepEqual(engine.namesDepth.byRoot("رحم").map((n) => n.number), [1, 2]);
  assert.deepEqual(engine.namesDepth.byRoot("ر ح م").map((n) => n.number), [1, 2]);
});

test("namesDepth: a placed occurrence really is that ayah's token", () => {
  // The Names were placed against the app's own Hafs text, folded. Comparing literally would
  // call a pause mark a mismatch, so fold both sides the way batch 5 does.
  const marks = /[ً-ٰٟۖ-ۭـ]/g;
  const fold = (s) => s.replace(marks, "")
    .replace(/ٱ/g, "ا").replace(/[أإ]/g, "ا")
    .replace(/ؤ/g, "و").replace(/ئ/g, "ي");
  let placed = 0;
  let unplaced = 0;
  for (const name of engine.namesDepth.all()) {
    for (const o of name.occurrences) {
      const ayah = engine.quran.ayah(o.surah, o.ayah);
      assert.ok(ayah, `name ${name.number} points at ${o.surah}:${o.ayah}, which is not an ayah`);
      if (o.token === null) {
        // An unplaced occurrence names no token and spans none.
        assert.equal(o.tokens, 0, `name ${name.number} unplaced but spans ${o.tokens}`);
        unplaced += 1;
        continue;
      }
      const tokens = (ayah.textArabic ?? "").split(/\s+/).filter(Boolean);
      assert.ok(o.token < tokens.length,
                `name ${name.number} token ${o.token} past the end of ${o.surah}:${o.ayah}`);
      assert.ok(fold(tokens[o.token]).length > 0);
      placed += 1;
    }
  }
  assert.equal(placed, 184);
  assert.equal(unplaced, 10);
});

test("namesDepth: the two Names of the Basmalah are both found in 1:3, in token order", () => {
  const hits = engine.namesDepth.inAyah(1, 3);
  assert.deepEqual(hits.map((h) => h.name.number), [1, 2]);
  assert.deepEqual(hits.map((h) => h.occurrence.token), [0, 1]);
});

test("namesDepth: a Name can be found by root, explanation or living line", () => {
  assert.ok(engine.namesDepth.search("رحم").some((n) => n.number === 1));
  const first = engine.namesDepth.byNumber(1);
  const word = first.living.split(/\s+/).find((w) => w.length > 6);
  assert.ok(engine.namesDepth.search(word).length > 0);
  assert.deepEqual(engine.namesDepth.search(""), []);
});

// ---- the chains of transmission --------------------------------------------------

test("isnad: ten imams, twenty narrators, thirteen Companions", () => {
  const { imams, narrators, companions } = engine.isnad.count();
  assert.equal(imams, 10);
  assert.equal(narrators, 20);
  assert.equal(companions, 13);
  assert.ok(engine.isnad.prophet());
});

test("isnad: every riwayah resolves to one of the ten imams, two apiece", () => {
  const perImam = new Map(engine.isnad.imamKeys().map((k) => [k, 0]));
  for (const tag of engine.isnad.narratorKeys()) {
    const imam = engine.isnad.imamOf(tag);
    assert.ok(imam, `${tag} resolves to no imam`);
    perImam.set(imam, perImam.get(imam) + 1);
  }
  // The Ten Readings are each carried by exactly two narrators: that is what makes them twenty.
  for (const [imam, n] of perImam) assert.equal(n, 2, `${imam} has ${n} narrators`);
});

test("isnad: every imam reaches Companions, through Successors or directly", () => {
  for (const imam of engine.isnad.imamKeys()) {
    const chain = engine.isnad.imam(imam);
    // Abu Jafar is the one imam with no Successors between him and the Companions: he WAS a
    // Successor, who read on Ibn Abbas and Abu Hurayrah themselves. So teachers may be empty;
    // reaching a Companion may not.
    if (imam !== "Abu Jafar") assert.ok(chain.teachers.length > 0, `${imam} has no teachers`);
    assert.ok(chain.companions.length > 0, `${imam} reaches no Companion`);
    for (const node of chain.teachers) {
      assert.equal(node.role, "successor");
      assert.match(node.detail, /^d\./, `${node.name} has no death year`);
    }
    for (const node of chain.companions) assert.equal(node.role, "companion");
  }
});

test("isnad: a chain runs from the Prophet down to the narrator", () => {
  for (const tag of engine.isnad.narratorKeys()) {
    const layers = engine.isnad.chain(tag);
    // At least the Prophet, the Companions, the imam and the narrator: Abu Jafar's two have no
    // Successors layer, which is why the floor is four and not five.
    assert.ok(layers.length >= 4, `${tag} chain is only ${layers.length} layers`);
    assert.equal(layers[0].title, "THE PROPHET");
    assert.equal(layers[1].title, "THE COMPANIONS");
    // The narrator himself is always in there, and the imam always above him.
    const titles = layers.map((l) => l.title);
    assert.ok(titles.includes("THE IMAM"));
    assert.ok(titles.includes("THE NARRATOR"));
    assert.ok(titles.indexOf("THE IMAM") < titles.indexOf("THE NARRATOR"));
  }
});

test("isnad: an imam's chain ends at his two narrators", () => {
  for (const imam of engine.isnad.imamKeys()) {
    const layers = engine.isnad.chain(imam);
    const last = layers[layers.length - 1];
    assert.equal(last.title, "HIS TWO NARRATORS");
    assert.equal(last.nodes.length, 2, `${imam} does not end at two narrators`);
  }
});

test("isnad: reading directly is exactly having no links between", () => {
  for (const tag of engine.isnad.narratorKeys()) {
    const chain = engine.isnad.narrator(tag);
    assert.equal(engine.isnad.readsDirectly(tag), chain.links.length === 0, tag);
    // The sentence says which of the two it is, in so many words.
    const sentence = engine.isnad.sentence(tag);
    assert.ok(sentence.length > 0, tag);
    assert.equal(sentence.includes("did not meet"), chain.links.length > 0, tag);
  }
});

test("isnad: Hafs read on Asim himself; Qunbul did not meet Ibn Kathir", () => {
  assert.equal(engine.isnad.imamOf("Hafs an Asim"), "Asim");
  assert.ok(engine.isnad.readsDirectly("Hafs an Asim"));
  assert.match(engine.isnad.sentence("Hafs an Asim"), /^Hafs read on Asim himself/);

  assert.equal(engine.isnad.imamOf("Qunbul an Ibn Kathir"), "Ibn Kathir");
  assert.ok(!engine.isnad.readsDirectly("Qunbul an Ibn Kathir"));
  assert.equal(engine.isnad.narrator("Qunbul an Ibn Kathir").links.length, 3);
});

test("isnad: an unknown key answers nothing rather than throwing", () => {
  assert.deepEqual(engine.isnad.chain("Nobody an Nobody"), []);
  assert.equal(engine.isnad.sentence("Nobody an Nobody"), "");
  assert.equal(engine.isnad.imamOf("no separator here"), null);
});
