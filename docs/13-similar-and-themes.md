# 13 · Similar ayahs, themes, and the tajweed course

Three curated corpora that answer questions the text alone cannot: *where else does the Quran say this*, *what does it say about X*, and *how do I learn to recite it*.

## Similar ayahs (mutashābihāt)

Pick an ayah, see the other places the Quran says something close to it. Rows are **merged and ranked at build time**, so nothing at runtime scores or sorts:

```js
engine.similarAyahs.matches(2, 255);
// [{ surah: 42, ayah: 4,  verified: true,  labels: [], spans: [],       score: null },
//  { surah: 3,  ayah: 2,  verified: true,  labels: [], spans: [[0, 6]], score: null },
//  { surah: 35, ayah: 31, verified: false, labels: ["Divine Knowledge", "Root xbr"], spans: [], score: null }]
```

Two kinds of row, and the difference matters:

- **`verified: true`** — the classical mutashābihāt corpus. Listed first.
- **`verified: false`** — phrase-overlap matches, each carrying the `labels` that explain *why* it matched. A reading aid, not a scholarly claim.

Gate on `verified` if you show only one kind. `has(surah, ayah)` is a dictionary hit, so it is cheap enough to decide whether to offer the button at all — most short ayahs have no matches.

**The shared wording is `spans`, never text.** Each pair is 0-based inclusive token indices into the *matched* ayah's raw text: the Quranic Universal Library's own placement where its table lists the pair (those rows also carry its 0-100 `score`), else the wording the corpus recorded, located in the ayah when the data was built. 41,392 of the 50,782 rows carry one. To show the words, read them out of the text you already have:

```js
const tokens = engine.quran.ayah(3, 2).textArabic.split(/\s+/);
match.spans.map(([a, b]) => tokens.slice(a, b + 1).join(" "));   // ["ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَيُّ ٱلۡقَيُّومُ"]
```

There is no `phrase` field any more (version 2, September 2026). Version 1 carried the shared wording as a string, 44,000 copies of the sources' own spelling of the Quran, and they had drifted from `quran.json` in their sukoon marks; a span cannot drift, because the words it names are the text's own.

`data/similar-ayahs.json` is ~2.9 MB over 5,446 ayahs: `{ "v": 2, "ayahs": { "2:255": [[surah, ayah, verifiedFlag, spans, labels, score], …], … } }`, every row six fields long (`spans` and `labels` may be `[]`, `score` may be `null`). Opt-in via `loadSimilarAyahs` / `load_similar_ayahs`.

## Themes

323 curated topics, each under a category and a domain, each listing the ayahs that speak to it — and the inverse, which is what lets an ayah screen say what it belongs to:

```js
engine.themes.topic("tawheed").ayahs;      // ["2:22", "2:107", "2:116", …]
engine.themes.topicsFor(2, 255);           // [Tawheed, Names and Attributes of Allah, Divine Majesty, …]
engine.themes.domains();                   // ["Aqeedah (Islamic Creed)", …]
engine.themes.inCategory("Tawheed (Oneness of Allah)");
engine.themes.search("mercy");
```

The lists are **curated, not derived**, which is the point: a topic is a reading path someone assembled, not a keyword hit list. That also makes it a genuinely independent retrieval lane — it reaches ayahs that share no wording with the query at all, which is why [14 · Ask AI](14-ask-ai.md) uses it as one.

`data/themes.json`, ~200 KB. Loaded **by default** — a topic list is the kind of thing a consumer wants without having to know it needed a flag.

## The tajweed course

Eight chapters from the Arabic alphabet to the rules of stopping; 34 lessons, each with prose, drills, and Quranic examples to hear the rule in.

```js
engine.tajweedLessons.chapters().map((c) => c.id);
// ["noorania", "foundations", "sifat", "madd", "nun-sakin", "mim-sakin", "special-rules", "waqf"]
engine.tajweedLessons.lesson("alphabet").drills;
engine.tajweedLessons.next("alphabet");    // walks across chapter boundaries
```

Content rather than algorithm — but it belongs here for the same reason the rule catalogue does: every app that teaches tajwīd otherwise rewrites the same curriculum, and a lesson that cites 2:255 should cite the same ayah everywhere. Pair it with [02 · Tajweed](02-tajweed.md) for the colouring and [tajweed-rules-explained](tajweed-rules-explained.md) for the reference prose.

Each example carries `surahId`, `ayahNumber`, a `focus` line, and, where the lesson points at particular words, `wordSpan`: the 0-based inclusive token range of those words in the ayah's raw text (version 3). The data carries no copy of the words; cut them from `engine.quran` by the span, the same way as the similar-ayah spans above.

**Version 4 carries the same idea into the lesson body.** A drill, a rule-card fragment or a quiz question holds its Arabic in exactly one of two places:

- `text` (or `arabic`, on a quiz question) when a tutor wrote it. That covers the invented drill syllables, the single letters, the isti'adhah: teaching Arabic that is not in the muṣḥaf and so has nothing to reference.
- `ayah` when the Arabic **is** Quran, and then there is no text field at all. The shape is `[surah, ayahNumber, first, last]`, the span again 0-based and inclusive over the ayah's whitespace-separated tokens.

Forty of the 289 rows are references: 7 drills, 21 rule-card fragments and 12 quiz questions. The consequence for a consumer is worth stating plainly, because it is not a graceful degradation: a port that ignores `ayah` renders an **empty** row, not a wrong one.

```js
const drill = engine.tajweedLessons.lesson("levels-of-recitation").drills.find((d) => d.ayah);
const [surah, ayah, first, last] = drill.ayah;                       // [110, 1, 0, 4]
const words = engine.quran.ayah(surah, ayah).textArabic.split(/\s+/);
words.slice(first, last + 1).join(" ");                              // the whole of an-Nasr 1
```

The rule card is `ruleCard` (`trigger`, `action`, `hold`, a `mnemonic` of `{arabic, gloss}`, `fragments`, and the counts). Note for anyone upgrading a consumer written against an earlier release: the typed ports called this `mushafCard` and the data has never used that name, so the field decoded to nothing. It is `ruleCard` in every port now.

`data/tajweed-lessons.json`, ~460 KB. Loaded by default.

## Also shipped

`data/surah-sections.json` — per-surah section outlines (`[startAyah, endAyah, englishTitle, arabicTitle]`, nested), and an `overview` line where the source has one. Useful as an in-surah table of contents. `data/surah-stats.json` — per-surah ayah / word / letter counts plus juz list and revelation type, in one small file for when you need the numbers without loading the Quran.
