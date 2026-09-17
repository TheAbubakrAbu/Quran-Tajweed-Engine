# 12 · Word by word

What each word of an ayah means, and how it is said. Two layers (an English gloss and a Latin transliteration), over the **same tokens**.

> **Key fact:** the tokens are the ayah's own whitespace-separated words in `quran.json`. Split the ayah on whitespace and index straight in. No matching, no normalizing, no fuzzy lookup.

## The invariant

The pack stores **one entry per token, in token order**, for both layers. Index *n* is the *n*th word of the ayah in both. That is the whole contract, and everything else follows from it:

```js
engine.wordByWord.words(112, 1);
// [{ position: 1, arabic: "قُلۡ",   english: "Say",        transliteration: "qul" },
//  { position: 2, arabic: "هُوَ",    english: "He",         transliteration: "huwa" },
//  { position: 3, arabic: "ٱللَّهُ",  english: "(is) Allah", transliteration: "l-lahu" },
//  { position: 4, arabic: "أَحَدٌ",  english: "the One",    transliteration: "aḥadun" }]
```

### Why the alignment is done at build time

The upstream word-by-word corpus tokenizes about two hundred ayahs differently from the Uthmani text this engine ships:

- 199 ayahs where the rub-el-ḥizb mark (۞, U+06DE) is a token of its own here but glued to the following word upstream;
- 3 ayahs where upstream splits a word this text keeps joined (15:7 لَّوۡمَا, 27:20 مَالِيَ, 36:22 وَمَالِيَ);
- 3 ayahs the other way round.

Reconciling that at render time means shipping the Arabic of every word (~2 MB more) and re-deriving the mapping on every ayah, with a **silent wrong-gloss** failure mode: the reader sees a real word's meaning, just the neighbouring word's. So it is resolved once, by a greedy two-pointer walk with bounded lookahead over the consonantal skeleton, and the pack stores glosses in *this* text's token order. Every one of the 6,236 ayahs must align or the build fails and writes nothing.

### Empty entries are real

A token with no word of its own (the ۞ ornament, the tail of a word the corpus writes as two), carries `""` in **both** layers. Show nothing for it; do not fall back to a neighbour.

The two layers always agree on which entries are empty, so a word that has a meaning has a pronunciation.

## Transliteration

The Latin layer is the same corpus's transliteration, aligned by the same walk against the same tokens. It is a pronunciation aid with full diacritics (`aḥadun`, `l-raḥmāni`), not a transliteration *scheme* you can round-trip back to Arabic.

77,426 of the 77,629 tokens carry both a gloss and a transliteration; the remaining 203 are the ornament and merged-tail tokens described above.

## Word-level English search

Glosses are a literal word-for-word rendering, not an excerpt of a flowing translation: which makes them a *different* index from the translation search. `find` reaches ayahs a translation search misses because no translator happened to use that phrasing:

```js
engine.wordByWord.find("the Ever-Living", { limit: 5 });
// [{ surah: 2, ayah: 255, position: 6, english: "the Ever-Living", transliteration: "l-ḥayu" }, …]
```

It matches on the gloss only. Treat it as a lookup, not as a ranked search, results come back in mushaf order.

## Files

`data/word-by-word.json`:

```json
{
  "english":         { "1": [["In (the) name", "(of) Allah", "the Most Gracious", "the Most Merciful"]] },
  "transliteration": { "1": [["bis'mi", "l-lahi", "l-raḥmāni", "l-raḥīmi"]] }
}
```

Layer → surah id → ayahs in id order → one entry per token. ~1.8 MB, opt-in:

```js
const engine = await loadFromDisk({ loadWordByWord: true });
```

```python
engine = Engine.load(load_word_by_word=True)
```

## Where it does *not* apply

The alignment is against **Ḥafṣ ʿan ʿĀṣim**. Another riwayah words the ayah differently, so its tokens do not line up and the glosses would be off by one from the first difference onward. Gate the feature on the reader's riwayah, and on anything else that changes the token count, letter-by-letter beginner spacing, for instance, or a display mode that strips the ۞ mark (which deletes a token from 199 ayahs).

## API

| Method | Returns |
|---|---|
| `words(surah, ayah)` | every word: position, arabic, english, transliteration |
| `word(surah, ayah, position)` | one word, 1-based |
| `glosses(surah, ayah)` | the English layer alone |
| `transliterations(surah, ayah)` | the Latin layer alone |
| `find(term, { limit })` | ayahs with a word whose gloss carries `term` |
| `isLoaded` | whether a pack is loaded at all, cheap enough to gate UI on |
