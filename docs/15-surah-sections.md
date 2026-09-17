# 15 · Surah sections

Where a surah changes subject: each surah as a handful of titled ayah ranges.

> **Key fact:** the outline is a **tree, stored flat**. A broad passage is followed by the sections inside it, parent before children. Ranges do **not** tile the surah, so an ayah can sit in several sections at once, or in none.

## The question it answers

"I am at 18:60: what is this passage doing here?" Neither the translation nor the tafsir answers that quickly, because both are written per ayah. The outline answers it in one lookup:

```js
engine.surahSections.sectionFor(18, 60);
// { from: 60, to: 82, english: "Musa and Khidr", arabic: "رحلة موسى والخَضِر" }
```

111 of the 114 surahs carry an outline. Al-Fatihah, ash-Shura and ad-Dukhan do not.

### `overview` is a near-empty field, on purpose

The source pairs each surah with *either* an outline *or* a one-sentence overview, and it has an overview for exactly the three surahs it has no outline for. Worse, only al-Fatihah's is real prose: ash-Shura's and ad-Dukhan's are the literal string `"Surah overview"`; the heading of the page it was extracted from, not its content.

The engine mirrors the source rather than papering over it, so `overview(42)` hands you `"Surah overview"`. Treat a `<= 20` character overview as absent, and prefer `hasSections` to decide whether there is anything to show at all.

## Sections nest

Hud opens with a broad passage and then the sections inside it:

```
1–24   Doctrine facts
  1–4    Calling to Allah
  5–6    A unique scene that makes hearts tremble
  7–11   Disturbing the souls of unbelievers
  12–17  Entertaining the Messenger
  18–24  The situation of the two groups
25–99  Doctrine Truths Movement
  25–49  Story of Nuh and His People
  …
```

The JSON stores that as one flat list, parent immediately before its children. Two accessors read it back:

```js
engine.surahSections.sectionsFor(11, 3);
// [{ from: 1, to: 24, english: "Doctrine facts", … },
//  { from: 1, to: 4,  english: "Calling to Allah", … }]     // outermost first

engine.surahSections.outline(11);
// [{ section: {…"Doctrine facts"}, children: [ …5 nodes… ] }, …]
```

`sectionFor` is the innermost of the chain (the heading to put beside the verse. `sectionsFor` is the whole chain), the breadcrumb.

Nesting is real but not common: 630 top-level sections across the corpus, 107 nested one level, 4 deeper.

## They do not tile

Do not assume every ayah has a section. Some fall between ranges, and `sectionFor` returns `null` there: which is not the same as "the surah has no outline". Check `hasSections(surah)` for that.

## Titles are bilingual, and searchable

Every section carries an English and an Arabic title. `search` matches either, across all 114 surahs, which turns the outline into a table of contents for the whole book:

```js
engine.surahSections.search("Story of Nuh");
// [{ surah: 7, … }, { surah: 11, … }, { surah: 26, … }, …]
```

## Data

`data/surah-sections.json`: 80 KB, loaded by default (no flag).

```jsonc
{
  "11": {
    "overview": "",                                        // empty for all 111 outlined surahs
    "sections": [[1, 24, "Doctrine facts", "حقائق العقيدة"],
                 [1, 4,  "Calling to Allah", "أصول الدعوة الإسلامية"], …]
  }
}
```

Rows are `[from, to, english, arabic]`: a positional array, not an object, because there are 741 of them and the keys would triple the file.

## Related

- **[01 · Quran](01-quran.md)**: the ayahs the ranges point at.
- **[13 · Similar ayahs and themes](13-similar-and-themes.md)**, themes group ayahs *across* surahs by subject; sections divide *one* surah by subject. Different questions.
