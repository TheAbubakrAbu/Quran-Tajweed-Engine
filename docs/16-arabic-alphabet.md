# 16 · Arabic alphabet

Every letter with its joining forms, its name and transliteration, and (the part that earns it a place in a *tajweed* engine), its **weight**.

> **Key fact:** weight is a property of the letter, not of the verse. Alif has no weight of its own at all: it inherits the letter before it.

## Why weight is the point

Every Arabic letter is pronounced thin (*tarqīq*) or full (*tafkhīm*). Seven are always full (the *istiʿlāʾ* letters خ ص ض ط ظ غ ق), most are always thin, two depend on context (rāʾ, and the lām of the divine name), and alif has no weight of its own: it takes the weight of whatever precedes it. That last rule is behind a large share of beginner mistakes, and it cannot live in the annotation corpus, because it is not a fact about any particular ayah.

```js
engine.alphabet.weight("ص");   // "heavy"          - istiʿlāʾ
engine.alphabet.weight("س");   // "light"
engine.alphabet.weight("ر");   // "conditional"    - depends on its vowel
engine.alphabet.weight("ا");   // "followsPrevious"

engine.alphabet.weightDescriptions()["followsPrevious"];
// "has no weight of its own; inherits the previous letter's weight (alif)"
```

Every one of the 28 carries a weight, and every weight name has a one-line description; the parity suites assert both, so a data edit that drops one fails a test.

## Letters resolve from any joining form

A letter lifted out of a word arrives in its medial or final shape. `letter()` accepts those too, so you can hand it what you sliced:

```js
engine.alphabet.letter("ـصـ")?.transliteration;   // "Saad"
engine.alphabet.letter("ص")?.forms;               // ["ـص", "ـصـ", "صـ"]
```

## What else is in the reference

| Accessor | Contents |
|---|---|
| `letters()` | the 28, in alphabet order |
| `otherLetters()` | hamza, tāʾ marbūṭa, lām-alif and the rest, written forms outside the 28 |
| `nonArabicScriptLetters()` | پ چ ڤ گ ڭ ژ: the Persian/Urdu letters some printed mushafs use |
| `tashkeel()` | the vowel and sukūn marks, with the sound each writes |
| `stoppingSigns()` | the waqf signs, with what each tells the reciter to do |
| `numbers()` | the Eastern-Arabic numerals ٠–١٠ |

The waqf signs are the ones a reader must **obey** rather than sound out, which is why they are here rather than in the tajweed rules:

```js
engine.alphabet.stoppingSign("۩");    // { symbol: "۩",  title: "Make Sujood" }
engine.alphabet.stoppingSign("مـ");   // { symbol: "مـ", title: "Mandatory Stop" }
engine.alphabet.stoppingSign("قلى");  // { symbol: "قلى", title: "Preferred Stop" }
```

The hizb marker ۞ is in this list too, which is worth knowing: it is a *navigation* mark, not an instruction, and it is also the token the word-by-word pack leaves unglossed (see **[12 · Word by word](12-word-by-word.md)**).

## Data

`data/arabic-alphabet.json`: 18 KB, loaded by default (no flag). One object with `standardLetters`, `otherLetters`, `nonArabicScriptLetters`, `numbers`, `tashkeel`, `stoppingSigns`, and the `weights` catalogue that explains the four weight names.

**[arabic-alphabet.md](arabic-alphabet.md)** documents that file field by field, for a consumer reading the JSON directly rather than going through the engine.

## Related

- **[02 · Tajweed](02-tajweed.md)**: the rules that fire *inside* a verse. Weight is what a letter brings to them.
- **[tajweed-rules-explained.md](tajweed-rules-explained.md)**: what each rule is, in prose.
