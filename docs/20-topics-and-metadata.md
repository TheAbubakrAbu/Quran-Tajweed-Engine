# 20 · QUL topics, passage themes and the mushaf divisions

Three ways of saying *where you are* in the Quran, from the Quranic Universal Library.

> **Key fact:** the topic corpus is **three independent trees over one pool of topics**, not three partitions of it. A topic can be a node in more than one, and a tree's parent need not itself be listed in that tree.

## `engine.quranTopics` · 2,512 topics, three indexes

| Index | What it is | Roots |
|---|---|---|
| `thematic` | the Clear Quran's thematic tree | Doctrine · Stories · The Unseen |
| `ontology` | the Quranic Arabic Corpus ontology | Allah · Living Creation · Location · Event · Holy Book · … (14) |
| `index` | a general A-Z index | 828 entries with no parent |

This is a different corpus from [`themes`](13-similar-and-themes.md), not a newer one: themes is 323 curated topics with domains and categories. Keep both.

### The independence, and why it matters

Adam is listed in two indexes and has a parent in each:

```js
engine.quranTopics.topic(13).families;                   // ["thematic", "ontology"]
engine.quranTopics.parent(13, "thematic").name;          // "Prophets (25 mentioned by name)"
engine.quranTopics.parent(13, "ontology").name;          // "Prophet"
```

17 topics are listed twice like this. Collapsing them to a single "family parent" would silently drop one of the two trees, which is exactly the bug this shape exists to prevent, so **every hierarchy accessor takes the tree you mean**: `parent`, `children`, `ancestors`, `roots`. Passing no tree uses the topic's first listed index, which is a convenience for a caller that does not care, not a fact about the data.

The trees are not closed over their own listings either. The A-Z index hangs "House of" under Moses, and Moses is a thematic topic. So do not assert that a parent shares its child's family; it often will not.

Because the per-index counts count a doubly-listed topic twice, they deliberately sum to **2,529** against 2,512 topics. That is what "listed in" means, and a test pins it so nobody quietly "fixes" it.

```js
engine.quranTopics.count();
// { topics: 2512, thematic: 695, ontology: 284, index: 1550, references: 30687 }
engine.quranTopics.topicsFor(2, 255);   // every topic annotating this ayah, all three indexes
```

## `engine.ayahThemes` · 1,049 passages

The other shape entirely: one short sentence per **run of ayahs**.

```js
engine.ayahThemes.passageFor(2, 10);
// { surah: 2, from: 8, to: 16,
//   theme: "Hypocrites and the consequences of hypocrisy", topic: "" }
```

Passages run in order through a surah and do not nest, which is what makes them the right thing to print under an ayah as "what is going on here" where a topic list would just be a pile of labels. They do **not** tile the surah: an ayah between two passages has none, and `passageFor` returns nothing rather than reaching for the nearest.

## `engine.quranMetadata` · hizb, ruku, manzil

[`juzPage`](03-juz-page.md) covers the two divisions a reader meets on the page. These are the three met in a *schedule*:

| Division | Count | What it is |
|---|---:|---|
| hizb | 60 | the juz halved: the unit a memorisation plan is usually written in |
| ruku | 558 | thematic sections, printed in the margin of South Asian mushafs |
| manzil | 7 | the seven-day division for reading the Quran in a week |

```js
engine.quranMetadata.for(2, 255);      // { hizb: 5, ruku: 35, manzil: 1 }
engine.quranMetadata.hizb.start(5);    // { number: 5, surah: 2, ayah: 253, key: "2:253" }
engine.quranMetadata.hizb.range(5);    // { from: 2:253, until: 3:15 }
```

Each is stored as its start keys in order, so a lookup is a binary search rather than a table with one row per ayah. `range` gives a division's start and the **start of the next one**, and `until` is null for the last: it runs to the end of the Quran, no start key says so, and inventing that boundary would be a lie about the data.

## Loading

`quran-metadata.json` (8 KB) and `ayah-themes.json` (142 KB) load by default, like the sections and the alphabet: small, and each answers a question a consumer should not have to opt into. `quran-topics.json` (~730 KB) is opt-in via `loadQuranTopics`.
