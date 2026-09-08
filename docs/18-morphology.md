# 18 · Morphology

The root and the dictionary form of every word of the Quran, so a reader can ask "what else comes from this root" and a search box can answer a bare root.

> **Key fact:** one id per whitespace token of the ayah's raw Ḥafṣ text, in the text's own order. Nothing here matches or normalizes text; the alignment happened at build time.

## What it answers

Two questions the text alone cannot. Given a word, what is its root and its dictionary form, and where else does that root appear. Given a typed root, which ayahs carry it.

That second one is the reason this corpus is worth shipping. Searching for رحم as text finds only the surface forms spelled that way; searching by root finds `ٱلرَّحۡمَٰنِ`, `رَحۡمَةً`, `يَرۡحَمُ` and the rest, because they share an id.

```js
engine.morphology.rootOf(1, 2, 2);
// { id: 1356, root: { letters: "ر ب ب", buckwalter: "rbb", joined: "ربب" } }

engine.morphology.occurrencesOfRoot(1356).length;   // 980
engine.morphology.occurrencesOfRoot(1356)[0];       // { surah: 1, ayah: 2, token: 2 }
```

The five busiest roots, which are about what you would expect of this book:

| Root | Words |
|---|---:|
| ا ل ه | 2,851 |
| ق و ل | 1,722 |
| ك و ن | 1,390 |
| ر ب ب | 980 |
| ا م ن | 879 |

## The shape

`data/morphology.json` stays compact on purpose. This is one small integer per token of the Quran, twice over; inflating 155,258 ids into objects would multiply the file for nothing.

```json
{
  "roots":    [["د ع و", "dEw"], ["ر ج ل", "rjl"], ...],
  "lemmas":   [["كَذَّاب", "كذاب"], ["ضِعْف", "ضعف"], ...],
  "rootIds":  { "1": [[462, 1217, 1356, 1356], ...], ... },
  "lemmaIds": { "1": [[1834, 2562, 1471, 1950], ...], ... }
}
```

`rootIds` is keyed by surah, then indexed by ayah, then by whitespace token, which is exactly how `word-by-word.json` is indexed: a consumer splits the ayah on whitespace and indexes straight in.

**Ids are 1-based, and `0` means the token has neither a root nor a lemma.** That is the honest answer for particles and for the sajdah mark, not a missing-data placeholder, so `root(0)` returns nothing rather than throwing.

## Searching for a root

A root is *printed* with spaces between its letters (`"ر ب ب"`, the way a lexicon sets it) and *typed* closed up (`"ربب"`). Both have to find it, and so does Buckwalter:

```js
engine.morphology.findRoots("ربب");    // [{ id: 1356, root: {...} }]
engine.morphology.findRoots("ر ب ب");  // the same
engine.morphology.findRoots("rbb");    // the same
```

The fold that makes those meet strips marks *and* closes every space. Note that this is stricter than the engine's general `cleanSearch`, whose whitespace option only trims the ends: a search fold that merely trimmed would leave `"ر ب ب"` three tokens long and no query would ever match it. Ports expose it as `foldForMorphology` (`Morphology.fold` where the language prefers a static).

## API

| Call | Answers |
|---|---|
| `root(id)` / `lemma(id)` | the entry with that 1-based id |
| `ids(surah, ayah)` | every token's root and lemma id, or nothing when uncovered |
| `rootOf(surah, ayah, token)` | one token's root |
| `lemmaOf(surah, ayah, token)` | one token's dictionary form |
| `occurrencesOfRoot(id)` | every word of that root, in mushaf order |
| `occurrencesOfLemma(id)` | every word of that lemma, in mushaf order |
| `findRoots(query)` / `findLemmas(query)` | prefix search, folded |
| `count()` | 1,642 roots · 4,817 lemmas · 77,629 tokens |

The two occurrence indexes are built on first use and kept. Walking 77,629 tokens is quick, but a caller asking about ten roots should not pay for it ten times, and building them by walking the corpus in mushaf order means the lists come out ordered without a sort.

## Loading

Opt in: `loadMorphology` (~776 KB). Without it `engine.morphology` answers nothing and `isLoaded` is false, rather than throwing.

## Provenance

The Quranic Arabic Corpus morphology (Kais Dukes), as redistributed by the Quranic Universal Library. QUL's word positions are Quran.com's; the app's build maps them onto its own tokens and gates the result, so what ships is already in this engine's numbering. See [`sources/README.md`](../sources/README.md).
