# 22 · Word of the day

149 curated words of Quranic vocabulary, each with every ayah the same written form appears in.

> **Key fact:** the day mapping is a **walk, not a hash**. The corpus is ordered so consecutive days feel varied, and hashing would scatter that ordering.

## One word, all its occurrences

```js
engine.wordOfDay.forDayIndex(0);
// { id: "wod-001", arabic: "ٱلۡحَمۡدُ", transliteration: "al-ḥamdu",
//   meaning: "All praises and thanks",
//   surah: 1, ayah: 2, token: 0, count: 26,
//   occurrences: [{ surah: 1, ayah: 2, tokens: [0] },
//                 { surah: 6, ayah: 1, tokens: [0] }, ...] }
```

`surah`/`ayah`/`token` are the **anchor**: where the form first appears, which is also the first entry of `occurrences`. `count` is the total across the whole Quran, and it is the sum of the token counts in `occurrences`, not a separately recorded number, so the figure on a card and the list behind it cannot disagree. A test pins that for all 149.

`tokens` is plural because a form can repeat inside one ayah (al-mulk three times in 3:26).

## The fold

Occurrences were matched **folded**: harakat and the waqf marks removed, alif waṣla and the hamza seats normalized. So `ٱلۡحَمۡدُۖ` at 64:1 counts as the same form as `ٱلۡحَمۡدُ`, and it should: a pause mark is not a different word. If you verify occurrences against the text yourself, fold both sides, or you will call every pause mark a mismatch.

## Picking today's word

```js
engine.wordOfDay.forDayIndex(n);   // the corpus walked in order, wrapping
engine.wordOfDay.forDate(date);    // the same, by local midnight
```

`forDayIndex` is the primitive and the one to reach for if your app has its own idea of when a day turns over. The upstream app rolls at Fajr rather than midnight, shared with every other "of the day" feature it has; hand this your own day number and the mapping is identical. Negative indices wrap correctly, so a day boundary that lands before the epoch still resolves.

## API

| Call | Answers |
|---|---|
| `all()` | the corpus, in curation order |
| `word(id)` | one word by id |
| `forDayIndex(n)` / `forDate(date)` | the word for a day |
| `search(query)` | by written form, transliteration or gloss |
| `wordsIn(surah, ayah)` | every curated word appearing in an ayah |
| `count()` | 149 words · 3,030 occurrences |

## Loading

Loaded by default (128 KB), like the metadata and the passage themes.

## Provenance

The curation, transliterations and glosses are Tilawa's (Jamil Hammoudeh), used with permission. The occurrences are derived from this engine's own Ḥafṣ text, and so is `arabic`: the upstream pack stores no copy of the word, only the anchor, and the importer reads the token at that anchor out of `quran.json`, so the form on a card is the text's own. See [CREDITS.md](../CREDITS.md).
