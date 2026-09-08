# 19 · Mutashabihat

The phrases the Quran repeats, and the exact words carrying each one wherever it occurs.

> **Key fact:** this is not `similarAyahs`. That answers "what else reads like this verse" with whole-ayah matches. This answers "which exact run of words does this verse share, and which words are they".

## Why both exist

They are two different questions, and the memoriser asks the second one. Two nearly identical ayahs sit side by side and the whole point is the one word that differs; a whole-ayah similarity score cannot show you that, but a token span can.

```js
const phrase = engine.mutashabihat.phrase(10167);
// { id: 10167, source: "9:87", span: [5, 10], wordCount: 6,
//   count: 3, ayahCount: 3, surahCount: 2,
//   occurrences: { "9:87": [[5,10]], "9:93": [[13,19]], "63:3": [[5,10]] } }

engine.mutashabihat.occurrences(10167).map((o) => o.key);
// ["9:87", "9:93", "63:3"]   <- mushaf order, not key order
```

Note 9:93, where the same six words start at token 13 rather than token 5. A consumer highlighting the shared wording needs the span *for that ayah*, which is why `occurrences` is a map rather than a list of ayah ids.

## The corpus

814 phrases across 2,232 ayahs. The most repeated is three words long and occurs 71 times over 70 ayahs; most are longer and rarer, which is what makes them useful landmarks.

## Spans

Every span is a **0-based inclusive token range of the ayah's raw Ḥafṣ text**, the same indexing `word-by-word.json` and `morphology.json` use. Split the ayah on whitespace and slice:

```js
const source = engine.quran.ayah(9, 87).textArabic;
engine.mutashabihat.textOf(10167, source);   // the six shared words
```

`textOf` takes the text rather than reading it, because the caller already has the ayah it is displaying, and because a consumer rendering a riwayah other than Ḥafṣ should be the one deciding what text the spans apply to.

## API

| Call | Answers |
|---|---|
| `phrasesFor(surah, ayah)` | the phrases this ayah carries, longest first |
| `phrase(id)` | one phrase |
| `has(surah, ayah)` | whether there are any, cheap enough to gate a button |
| `occurrences(id)` | every place it occurs, in mushaf order |
| `textOf(id, ayahText)` | the phrase's own words, sliced out of text you supply |
| `count()` | 814 phrases · 2,232 ayahs |

`phrasesFor` sorts longest first: a six-word shared phrase says more about where you are than a two-word one.

## Loading

Opt in: `loadMutashabihat` (~178 KB).

## Provenance

The Quranic Universal Library's *Mutashabihat ul Quran* phrase set, mapped onto this engine's tokens at build time.
