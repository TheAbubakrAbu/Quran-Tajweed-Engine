# 21 · Qiraat variants

Who among the Ten reads a word differently, what they read, and what the difference means.

> **Key fact:** a reading lists **readers** when both of an imam's transmitters follow it, and **transmitters** when the two part company. That distinction is the whole grammar of an attribution.

## The layer the texts cannot give

`data/qiraat/` gives each reading its own words, and [`qiraatComparison`](17-qiraat-comparison.md) will align two of them: together they answer **what** each riwayah reads. Neither can say that a form is Ḥamzah's rather than Nāfiʿ's, that it is a passive where Ḥafṣ has an active, or that al-Mahdawī held the two to mean the same thing. That is this module, over the Quran.com qiraat matrix: **1,634 junctures across 1,409 ayahs, 3,503 readings in all**.

```js
const [juncture] = engine.qiraatVariants.junctures(2, 184);
juncture.word;   // "فِدْيَةٌۭ طَعَامُ مِسْكِينٍۢ ۖ"

juncture.readings.map((r) => [r.text, engine.qiraatVariants.attribution(r)]);
// ["فِدْيَةٌ طَعَامُ مِسْكِينٍ",  "Ḥamzah, Ibn Kathīr, Khalaf, Abū ʿAmr, al-Kisāʾī, Yaʿqūb, ʿĀṣim"]
// ["فِدْيَةٌ طَعَامُ مَسَاكِينَ", "Hishām (Ibn ʿĀmir)"]
// ["فِدْيَةُ طَعَامِ مَسَاكِينَ", "Abū Jaʿfar, Nāfiʿ · Ibn Dhakwān (Ibn ʿĀmir)"]

juncture.note;
// "The variation of singular/plural amounts to the same meaning, as it is agreed
//  that each person is liable (per missed fast) [al-Mahdawi]."
```

Read the third line carefully: `Abū Jaʿfar, Nāfiʿ` are whole imams, both of their narrators agreeing, while `Ibn Dhakwān (Ibn ʿĀmir)` is one narrator of an imam whose other narrator, Hishām, reads the line above. That is what the readers/transmitters split encodes, and `attribution` renders it the way the printed sources do: imams first in canonical order, then lone transmitters with their imam in parentheses.

## Segments

Each juncture carries the token positions of the word at issue:

```js
juncture.segments;   // [{ ayah: "2:184", span: [16, 18] }]
```

Spans are **0-based inclusive token indices of the raw Ḥafṣ text**, and `span` is `null` where the builder could not place the word. A consumer shows the word untinted in that case; guessing a position would be worse than showing none.

## Reading text · sukoon marks

`text` on a reading and on a juncture follows the convention of `quran.json`, not the source's. Two codepoints read as a sukoon: **U+06E1** (the small head-of-khah the muṣḥaf prints) marks a consonant with no vowel; **U+0652** (ARABIC SUKUN) marks a letter that is written but not pronounced (the alif of كَانُواْ, the waw of أُوْلَٰٓئِكَ, the yaa of وَمَلَإِيْهِۦ); and a long vowel carries nothing. Quran.com's matrix mixed the first two by surah and typed a sukoon onto long vowels. Since 2026-09-16 the pack is built with each mark normalized by the letter it sits on, with the rule proven against the Ḥafṣ text (77,629 words unchanged and round-tripped), and every juncture headword that differed from its Ḥafṣ tokens only in those marks now matches them. So a byte comparison of a headword against `quran.json` is meaningful, which it was not before. Three readings keep a U+0652 on the alif of وَلَاْ, a typo the rule cannot tell from the real silent alif of سَلَٰسِلَاْ without knowing the word.

## `category` · what kind of difference

Each juncture carries the source's category code (`"A"`, `"B"`, `"AM"`, `"BM"`, or `""` for twenty junctures), which the source publishes without a legend. The matrix itself fixes the meaning: every **A** juncture's readings render differently in English (630 of 630), while **B** junctures render alike (864 of 900), so A marks a difference of *sense* and B a difference of form or pronunciation only. The **M** suffix marks a word the early codices (the Uthmanic masahif) themselves spell differently, which the commentary at those junctures says in so many words. Show it as a caption on the juncture, never as a verdict on a reading.

```js
engine.qiraatVariants.junctures(1, 4)[0].category;    // "A"  ·  مَالِكِ / مَلِكِ differ in sense
engine.qiraatVariants.junctures(104, 3)[0].category;  // "B"  ·  يَحْسَبُ / يَحْسِبُ, one sense
engine.qiraatVariants.junctures(18, 86)[0].category;  // "AM" ·  حَمِئَةٍ / حَامِيَةٍ, and the codices differ
```

## `places` · where a riwayah differs at all

The comparison answers "how does this riwayah read this ayah". This answers the question before it, so a reader can step from one difference to the next instead of hunting:

```js
engine.qiraatVariants.places("warsh", 1);
// [{ ayah: 4, word: [0], letter: [] }]
```

**Two kinds, because they are found two ways**, and a consumer may want only the first:

- a `word` index is a word dropped, added, or spelled differently, which a folded diff of the two texts finds;
- a `letter` index is a word the printed muṣḥaf marks as read with other vowels over the **same skeleton**, which no text diff can see. مَلِكِ against مَٰلِكِ in al-Fātiḥah is the classic case, and it is invisible to every method except reading the print.

The totals show how differently the two kinds distribute:

| Riwayah | Ayahs | Word-level | Letter-level |
|---|---:|---:|---:|
| Qunbul | 3,783 | 266 | 8,228 |
| al-Bazzī | 3,754 | 266 | 8,182 |
| Warsh | 3,737 | 794 | 7,761 |
| as-Sūsī | 2,303 | 982 | 2,292 |
| ad-Dūrī | 1,628 | 2,054 | 47 |
| Qālūn | 1,453 | 651 | 1,244 |
| Shuʿbah | 473 | 117 | 438 |

ad-Dūrī is the outlier and the reason the split is worth keeping: its print inks almost no vowel differences, so nearly everything it reports is word-level, while the Makkī pair are almost entirely the other way round.

Only the **seven published non-Ḥafṣ riwayat** are indexed here (Ḥafṣ is the reference and indexes nothing against itself). The other twelve still appear as *attributions* above, which is right: attributing a reading to Ibn Dhakwān says nothing about the state of his extracted text.

## `audio` · hearing the difference

For four riwayat there is a recording of **the same reciter reading the verse both ways**:

```js
engine.qiraatVariants.audio("warsh", 1, 4);
// { reciter: "Abdul Basit",
//   hafs:    { url: "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/001004.mp3",
//              startMs: null, endMs: null },
//   riwayah: { url: "https://everyayah.com/data/warsh/warsh_Abdul_Basit_128kbps/001004.mp3",
//              startMs: null, endMs: null } }
```

One reciter, because a pair drawn from two shaykhs would differ in voice, pace and maqām as well, and teach nothing about the variant. A `file` source is a whole per-verse recording and ignores the offsets; a `span` source is a seek inside a full-surah one, and both sides carry their own start and end.

`riwayatWithAudio()` returns four. al-Bazzī, Qunbul, as-Sūsī and the rest carry none, because no reciter published both sides with timings. That is a fact about the world; render it as "no recording", never as a button that does nothing.

## API

| Call | Answers |
|---|---|
| `junctures(surah, ayah)` | the words the Ten read differently here |
| `has(surah, ayah)` | whether there are any (only 1,409 of 6,236 ayahs) |
| `reader(id)` / `transmitter(id)` | one of the ten imams / twenty riwayat |
| `transmittersFollowing(reading)` | every narrator reading that form |
| `readingFor(juncture, riwayah)` | what one riwayah reads here, by engine slug |
| `attribution(reading)` | who reads it, rendered as the sources do |
| `places(riwayah, surah)` | where that riwayah differs from Ḥafṣ |
| `audio(riwayah, surah, ayah)` | the paired recording, or nothing |
| `count()` | 1,409 ayahs · 1,634 junctures · 3,503 readings |

## Loading

Opt in: `loadQiraatVariants` pulls the matrix, the place index and the recording table together (~1.9 MB).

## Provenance

The Quran.com qiraat matrix (Quran Foundation) for the variants; the place index is computed from the texts and the printed muṣḥafs; the recording table is Tilawa's (Jamil Hammoudeh), used with permission. See [CREDITS.md](../CREDITS.md).
