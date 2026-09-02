// @ts-check
/**
 * The modules beyond the core: the mushaf / word-by-word / Ask AI batch, and the surah outlines,
 * alphabet reference and qiraat comparison that followed it.
 *
 * They load their own engine with every optional corpus on, because that is exactly what these
 * tests are for: proving the flags actually reach the modules and the data behind them is shaped
 * the way the accessors assume.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadFromDisk } from "../src/node.js";
import { Semantic } from "../src/semantic.js";
import { chatPrompt, QUESTION_WORDS } from "../src/askAI.js";
import { readJson } from "../src/node.js";

const engine = await loadFromDisk({
  loadMushaf: true,
  loadQiraatTajweed: true,
  loadWordByWord: true,
  loadSimilarAyahs: true,
  loadQiraat: true,
});

// ---- mushaf -----------------------------------------------------------------------

test("mushaf: twenty riwayat, eight with published text", () => {
  assert.equal(engine.mushaf.riwayat().length, 20);
  assert.equal(engine.mushaf.riwayatWithText().length, 8);
  assert.equal(engine.mushaf.totalPages(), 604);
  assert.equal(engine.mushaf.riwayah("warsh")?.imam, "Nafi");
  assert.equal(engine.mushaf.riwayah("hisham")?.textIncluded, false);
});

test("mushaf: every riwayah ships a facsimile and a full page table", () => {
  for (const entry of engine.mushaf.riwayat()) {
    assert.match(entry.pdf, /^pdfs\/.+\.pdf\.xz$/, entry.riwayah);
    assert.ok(entry.pdfBytes > 100_000, entry.riwayah);
    // Al-Fatihah opens page 1 and an-Nas closes page 604 in every printed mushaf of the set.
    assert.equal(engine.mushaf.page(1, 1, entry.riwayah), 1, entry.riwayah);
    assert.equal(engine.mushaf.page(114, 6, entry.riwayah), 604, entry.riwayah);
  }
});

test("mushaf: pages resolve back to the ayahs on them", () => {
  const page = engine.mushaf.page(2, 255, "hafs");
  assert.equal(page, 42);
  const onPage = engine.mushaf.ayahsOnPage(page, "hafs");
  assert.ok(onPage.some((a) => a.surah === 2 && a.ayah === 255));
  assert.deepEqual(engine.mushaf.firstAyahOfPage(1, "hafs"), { surah: 1, ayah: 1 });
});

test("mushaf: line tables ship exactly where the text does", () => {
  for (const entry of engine.mushaf.riwayat()) {
    const breaks = engine.mushaf.lineBreaks(1, 1, entry.riwayah);
    if (entry.textIncluded) assert.ok(Array.isArray(breaks), entry.riwayah);
    else assert.equal(breaks, null, entry.riwayah);
  }
});

// ---- riwayah tajweed --------------------------------------------------------------

test("qiraatTajweed: the seven verified non-Hafs riwayat carry a pack", () => {
  assert.deepEqual(engine.qiraatTajweed.available(),
    ["buzzi", "duri", "qaloon", "qunbul", "shubah", "susi", "warsh"]);
});

test("qiraatTajweed: a legend entry carries its shared explanation", () => {
  const legend = engine.qiraatTajweed.legend("warsh");
  assert.ok(legend.length >= 3);
  for (const entry of legend) {
    assert.ok(entry.code.length === 1);
    assert.ok(entry.rule && entry.arabic && entry.english);
    assert.ok(entry.short, `no description for ${entry.rule}`);
  }
});

test("qiraatTajweed: Warsh's rules on 2:3 name real legend codes", () => {
  const rules = engine.qiraatTajweed.wordRules(2, 3, "warsh");
  assert.ok(rules.length >= 1);
  const codes = new Set(engine.qiraatTajweed.legend("warsh").map((e) => e.code));
  for (const rule of rules) {
    assert.ok(codes.has(rule.code), rule.code);
    assert.ok(rule.wholeWord === (rule.firstLetter < 0));
    assert.ok(rule.word >= 1);
  }
});

test("qiraatTajweed: khilaf markers agree with the word rules", () => {
  // Al-Baqarah 253 is the ayah Warsh's own mushaf marks; the marker index and the rules must agree.
  assert.ok(engine.qiraatTajweed.hasKhilaf(2, 253, "warsh"));
  assert.ok(!engine.qiraatTajweed.hasKhilaf(2, 254, "warsh"));
});

// ---- word by word -----------------------------------------------------------------

test("wordByWord: both layers, aligned to the ayah's own tokens", () => {
  const words = engine.wordByWord.words(112, 1);
  assert.equal(words.length, 4);
  assert.deepEqual(words.map((w) => w.transliteration), ["qul", "huwa", "l-lahu", "aḥadun"]);
  assert.equal(words[0].english, "Say");
  assert.equal(words[0].arabic, engine.quran.ayah(112, 1)?.textArabic.split(/\s+/)[0]);
});

test("wordByWord: every ayah's arrays match its token count in both layers", () => {
  for (const surah of engine.quran.all()) {
    for (const ayah of surah.ayahs) {
      const tokens = ayah.textArabic.trim().split(/\s+/).length;
      const english = engine.wordByWord.glosses(surah.id, ayah.id);
      const latin = engine.wordByWord.transliterations(surah.id, ayah.id);
      assert.equal(english?.length, tokens, `${surah.id}:${ayah.id} english`);
      assert.equal(latin?.length, tokens, `${surah.id}:${ayah.id} transliteration`);
    }
  }
});

test("wordByWord: gloss search finds the word, not the translation", () => {
  const hits = engine.wordByWord.find("the Ever-Living", { limit: 5 });
  assert.ok(hits.some((h) => h.surah === 2 && h.ayah === 255));
  assert.ok(hits.every((h) => h.transliteration.length > 0));
});

// ---- similar ayahs, themes, lessons ------------------------------------------------

test("similarAyahs: Ayat al-Kursi matches 3:2, verified", () => {
  const matches = engine.similarAyahs.matches(2, 255);
  const found = matches.find((m) => m.surah === 3 && m.ayah === 2);
  assert.ok(found?.verified);
  assert.ok(engine.similarAyahs.has(2, 255));
  assert.ok(engine.similarAyahs.count() > 5000);
});

test("themes: topics index both ways", () => {
  assert.ok(engine.themes.all().length >= 300);
  const tawheed = engine.themes.topic("tawheed");
  assert.ok(tawheed?.ayahs.includes("2:255"));
  assert.ok(engine.themes.topicsFor(2, 255).some((t) => t.id === "tawheed"));
  assert.ok(engine.themes.domains().length >= 2);
});

test("tajweedLessons: chapters walk in course order", () => {
  const lessons = engine.tajweedLessons.allLessons();
  assert.ok(lessons.length >= 30);
  assert.equal(engine.tajweedLessons.previous(lessons[0].id), null);
  assert.equal(engine.tajweedLessons.next(lessons[0].id)?.id, lessons[1].id);
  assert.ok(engine.tajweedLessons.chapterOf(lessons[0].id));
});

// ---- semantic ---------------------------------------------------------------------

test("semantic: MaxSim ranks by meaning, not by shared words", () => {
  // A toy embedder: enough to prove the scoring, without shipping a model.
  const vectors = {
    patience: [1, 0, 0], hardship: [0.9, 0.1, 0], sabr: [0.95, 0.05, 0],
    steadfast: [0.9, 0.05, 0], dawn: [0, 1, 0], prayer: [0, 0.95, 0],
  };
  const semantic = new Semantic({ embed: (w) => vectors[w] ?? null }).index([
    { id: "sabr", text: "sabr and steadfast endurance" },
    { id: "fajr", text: "prayer at dawn" },
  ]);
  const hits = semantic.search("patience hardship");
  assert.equal(hits[0].id, "sabr");
  assert.ok(hits[0].score > hits[1].score);
});

// ---- ask AI -----------------------------------------------------------------------

test("askAI: a named verse is retrieved as the subject", () => {
  const passages = engine.askAI.retrieve("explain ayat al-kursi");
  assert.equal(passages[0].reference, "2:255");
  assert.equal(passages[0].isSubject, true);
});

test("askAI: a named surah answers with its background", () => {
  const passages = engine.askAI.retrieve("what is surah al-kahf about");
  assert.equal(passages[0].reference, "Surah Al-Kahf");
  assert.equal(passages[0].kind, "surah");
  assert.equal(passages[0].isSubject, true);
});

test("askAI: the keyword lane is weighted, not counted", () => {
  const passages = engine.askAI.retrieve("what does the Quran say about patience in hardship");
  assert.ok(passages.some((p) => p.reference === "2:153"));
  // Every retrieved reference must be citable, i.e. resolve to a real ayah or surah.
  for (const passage of passages) {
    if (passage.kind === "ayah") assert.ok(engine.quran.ayah(passage.surah, passage.ayah));
  }
});

test("askAI: a bare follow-up searches with the previous question", () => {
  const carried = engine.askAI.retrieve("tell me about 2:153");
  const alone = engine.askAI.retrieve("why?");
  const withContext = engine.askAI.retrieve("why?", {
    previousQuestion: "tell me about 2:153",
    carried,
  });
  assert.equal(alone.length, 0);
  assert.ok(withContext.some((p) => p.reference === "2:153"));
});

test("askAI: the prompt marks the subject and carries the question last", () => {
  const passages = engine.askAI.retrieve("explain 2:153");
  const { instructions, prompt } = chatPrompt("explain 2:153", passages);
  assert.match(instructions, /Never issue a religious ruling/);
  assert.match(prompt, /SUBJECT OF THE QUESTION \[2:153\]/);
  assert.ok(prompt.trimEnd().endsWith("QUESTION: explain 2:153"));
  assert.ok(QUESTION_WORDS.has("what"));
});

// ---- surah sections ----------------------------------------------------------------

test("sections: 111 surahs carry an outline, and it reads as a chain", () => {
  assert.equal(engine.surahSections.count(), 111);
  assert.ok(engine.surahSections.overview(1).length > 20);
  assert.equal(engine.surahSections.hasSections(1), false);

  // Hud opens with a broad passage and the sections inside it - so an ayah has a chain, not a row.
  const chain = engine.surahSections.sectionsFor(11, 3).map((s) => s.english);
  assert.deepEqual(chain, ["Doctrine facts", "Calling to Allah"]);
  assert.equal(engine.surahSections.sectionFor(11, 3)?.english, "Calling to Allah");
});

test("sections: the outline rebuilds the nesting the flat list encodes", () => {
  const roots = engine.surahSections.outline(11);
  assert.ok(roots.length >= 2);
  assert.equal(roots[0].english, "Doctrine facts");
  assert.equal(roots[0].children.length, 5);
  assert.ok(roots[0].children.every((c) => c.from >= roots[0].from && c.to <= roots[0].to));
});

test("sections: every range is inside its surah, and search finds a story", () => {
  for (const surah of engine.quran.all()) {
    for (const section of engine.surahSections.sections(surah.id)) {
      assert.ok(section.from >= 1 && section.to <= surah.numberOfAyahs,
        `${surah.id}: ${section.from}-${section.to} outside 1-${surah.numberOfAyahs}`);
      assert.ok(section.from <= section.to);
      assert.ok(section.english.length > 0 && section.arabic.length > 0);
    }
  }
  const nuh = engine.surahSections.search("Story of Nuh");
  assert.ok(nuh.length >= 2);
  assert.ok(nuh.some((s) => s.surah === 11));
});

// ---- arabic alphabet ----------------------------------------------------------------

test("alphabet: 28 letters, each with a tajweed weight the catalogue explains", () => {
  const letters = engine.alphabet.letters();
  assert.equal(letters.length, 28);
  const weights = engine.alphabet.weightDescriptions();
  for (const letter of letters) {
    assert.ok(letter.letter.length > 0 && letter.name.length > 0);
    assert.ok(letter.weight, `${letter.letter} has no weight`);
    assert.ok(weights[letter.weight], `no description for weight ${letter.weight}`);
  }
  // Alif is the one letter with no weight of its own - the fact the whole field exists for.
  assert.equal(engine.alphabet.weight("ا"), "followsPrevious");
  assert.equal(engine.alphabet.weight("ص"), "heavy");
  assert.equal(engine.alphabet.weight("س"), "light");
});

test("alphabet: a letter resolves from any of its joining forms", () => {
  assert.equal(engine.alphabet.letter("ـصـ")?.transliteration, "Saad");
  assert.equal(engine.alphabet.letterById(1)?.letter, "ا");
  assert.equal(engine.alphabet.letter("nope"), null);
});

test("alphabet: tashkeel, numerals and the waqf signs", () => {
  assert.ok(engine.alphabet.tashkeel().length >= 8);
  assert.equal(engine.alphabet.numbers().length, 11);
  assert.equal(engine.alphabet.stoppingSign("۩")?.title, "Make Sujood");
  assert.ok(engine.alphabet.heavyLetters().length >= 7);
});

// ---- qiraat comparison ---------------------------------------------------------------

test("comparison: only the published readings, hafs included", () => {
  assert.deepEqual(engine.qiraatComparison.available(),
    ["buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh"]);
});

test("comparison: a reading against itself is entirely identical", () => {
  const same = engine.qiraatComparison.compareSurah(2, "hafs");
  assert.equal(same.identical, same.words);
  assert.equal(same.sameSkeleton, 0);
  assert.equal(same.different, 0);
  assert.equal(same.added, 0);
  assert.equal(same.dropped, 0);
  assert.equal(same.identicalPercent, 100);
});

test("comparison: the buckets add up, and Shubah is nearer to Hafs than Warsh is", () => {
  const warsh = engine.qiraatComparison.compareSurah(2, "warsh");
  const shubah = engine.qiraatComparison.compareSurah(2, "shubah");
  for (const totals of [warsh, shubah]) {
    assert.equal(totals.identical + totals.sameSkeleton + totals.different + totals.dropped,
      totals.words);
  }
  // Shu'bah and Hafs are the two narrators of Asim; Warsh is a different imam entirely.
  assert.ok(shubah.identicalPercent > warsh.identicalPercent);
  assert.ok(shubah.identicalPercent > 95);
});

test("comparison: differences are the non-identical rows, in reading order", () => {
  const rows = engine.qiraatComparison.differences(2, "warsh", { limit: 20 });
  assert.ok(rows.length > 0);
  assert.ok(rows.every((row) => ["sameSkeleton", "different", "added", "dropped"].includes(row.kind)));
  assert.ok(rows.every((row) => row.base !== row.other));
  const positions = rows.map((row) => row.position);
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
});

test("comparison: word streams follow the reading's own verse count", () => {
  // Warsh reads al-Baqarah as 285 verses to Hafs' 286, so pairing by ayah id would compare
  // different verses from that point on; the comparison walks the surah's words instead.
  assert.equal(engine.quran.numberOfAyahsInQiraah(2, "warsh"), 285);
  assert.equal(engine.quran.qiraahVerses(2, "warsh").length, 285);
  assert.ok(engine.qiraatComparison.words(2, "warsh").length > 6000);
});

// ---- the standalone stats index --------------------------------------------------------

test("surah-stats.json still agrees with quran.json", async () => {
  // It ships as an 8 KB index for consumers who want the counts without parsing 30 MB of text, so
  // nothing reads it through the API - which is exactly why it needs a test to keep it honest.
  const stats = await readJson("surah-stats.json");
  assert.equal(Object.keys(stats).length, 114);
  for (const surah of engine.quran.all()) {
    const row = stats[String(surah.id)];
    assert.deepEqual(
      [row.ayahs, row.words, row.letters, row.type, row.juz],
      [surah.numberOfAyahs, surah.wordCount, surah.letterCount, surah.type, surah.juzs],
      `surah ${surah.id}`,
    );
  }
});
