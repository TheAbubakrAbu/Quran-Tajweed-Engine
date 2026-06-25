# Arabic alphabet & reading reference

A complete reference for the Arabic script as used in the Quran — the 28 letters (with their tajweed
weight), extra/special letters, non-Arabic letters that appear in some scripts, Eastern-Arabic numerals,
the tashkeel (diacritics), and the waqf (stopping) signs.

All of it is data: [`data/arabic-alphabet.json`](../data/arabic-alphabet.json). Load it like any other file.

## The 28 letters

Each entry has the letter, its joining `forms` (final / medial / initial), its Arabic `name`,
`transliteration`, whether it `showTashkeel` in teaching views, its `sound`, and its tajweed `weight`.

```jsonc
{
  "id": 1, "letter": "ا", "forms": ["ـا", "ـا ـ", "ا ـ"],
  "name": "اَلِف", "transliteration": "alif", "showTashkeel": false, "sound": "a",
  "weight": "followsPrevious",
  "weightRule": "Alif has no weight of its own; it follows the heaviness or lightness of the previous letter."
}
```

### Tajweed weight (heavy vs light)

Weight is the [tafkhim / tarqiq](glossary.md) property — whether a letter is pronounced full and heavy or
thin and light. This drives the engine's `tafkhim` coloring.

| Weight | Meaning | Letters |
|---|---|---|
| `light` (tarqiq) | thin / light | most letters |
| `heavy` (tafkhim) | full / heavy — the *istiʿla* letters | خ ص ض ط ظ غ ق |
| `conditional` | depends on its vowel/context | ر (by its vowel), ل (heavy only in *Allah* after fatha/damma) |
| `followsPrevious` | no weight of its own | ا (inherits the previous letter's weight) |

The two `conditional` letters carry a `weightRule` string explaining exactly when they are heavy vs light.

## Extra & special letters (`otherLetters`)

Beyond the 28: taa marbuuTah (ة), the hamza family (ء أ إ ئ ؤ), hamzatul-wasl (ٱ), alif madd (آ),
yaa/waaw madd (يٓ وٓ), alif maqsuurah (ى), the laam-alif ligature (لا), and tatweel (ـ, the kashida
elongation connector). These are the forms a reader meets in the mushaf that aren't one of the base 28.

## Non-Arabic letters (`nonArabicScriptLetters`)

Letters used in Arabic-script languages (Urdu, Persian, etc.) but not in Quranic Arabic — included so a
keyboard/letter-learning UI can show them: پ (pe), چ (che), ڤ (ve), گ (gaaf), ڭ (ngaf), ژ (zhe).

## Numerals (`numbers`)

Eastern-Arabic digits ٠–٩ plus ١٠, with names and their Western equivalents. (The engine's search also
converts these to Western digits — see [docs/06](06-ayah-search.md).)

## Tashkeel — diacritics (`tashkeel`)

The 21 vowel and pronunciation marks: the short vowels (fatha/kasra/damma), tanwin (fathatayn/kasratayn/
dammatayn), the long-vowel combinations, the miniature/superscript madd marks (dagger alif, small waw/yaa,
and their madd variants), shaddah, and the two sukoon forms (standard ْ and Uthmani ۡ).

```jsonc
{ "english": "Shaddah", "arabic": "شَدَّة", "mark": "ّ", "transliteration": "" }
```

These are exactly the marks the [tajweed engine](02-tajweed.md) reads to detect madd, ghunnah, qalqalah,
and the rest.

## Waqf — stopping signs (`stoppingSigns`)

The small symbols printed in the mushaf that tell the reciter where (and whether) to pause. Knowing them is
part of correct recitation — see the **[detailed tajweed rules → Waqf](tajweed-rules-explained.md#waqf--stopping)**.

| Symbol | Meaning |
|---|---|
| ۩ | Make sujood (prostration) |
| ۞ | Hizb marker (a section division) |
| مـ | Mandatory stop |
| قلى | Preferred stop |
| ج | Permissible stop |
| س | Short pause (saktah) |
| ∴ ∴ | Stop at one of the two marks (not both) |
| صلى | Continuing is preferred |
| لا | Do not stop (must continue) |

Source for the stopping-sign meanings:
[Studio Arabiya — Tajweed rules for stopping & pausing](https://studioarabiya.com/blog/tajweed-rules-stopping-pausing-signs/).

## Using it

```js
import alphabet from "../../data/arabic-alphabet.json" assert { type: "json" };
alphabet.standardLetters.find(l => l.transliteration === "qaaf").weight;  // "heavy"
alphabet.stoppingSigns;                                                    // the waqf legend
alphabet.tashkeel;                                                         // diacritics for a keyboard UI
```

Great for: an alphabet/letter-learning screen, a tajweed-weight reference, a waqf-sign legend, or an Arabic
keyboard. Provenance: [CREDITS.md](../CREDITS.md).
