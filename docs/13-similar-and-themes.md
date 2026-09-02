# 13 · Similar ayahs, themes, and the tajweed course

Three curated corpora that answer questions the text alone cannot: *where else does the Quran say this*, *what does it say about X*, and *how do I learn to recite it*.

## Similar ayahs (mutashābihāt)

Pick an ayah, see the other places the Quran says something close to it. Rows are **merged and ranked at build time**, so nothing at runtime scores or sorts:

```js
engine.similarAyahs.matches(2, 255);
// [{ surah: 42, ayah: 4,  phrase: "",                                    verified: true,  labels: [] },
//  { surah: 3,  ayah: 2,  phrase: "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَىُّ ٱلۡقَيُّومُ", verified: true,  labels: [] },
//  { surah: 35, ayah: 31, phrase: "",  verified: false, labels: ["Divine Knowledge", "Root xbr"] }]
```

Two kinds of row, and the difference matters:

- **`verified: true`** — the classical mutashābihāt corpus. Listed first. `phrase` is the shared wording where the corpus records it.
- **`verified: false`** — phrase-overlap matches, each carrying the `labels` that explain *why* it matched. A reading aid, not a scholarly claim.

Gate on `verified` if you show only one kind. `has(surah, ayah)` is a dictionary hit, so it is cheap enough to decide whether to offer the button at all — most short ayahs have no matches.

`data/similar-ayahs.json` is ~3.5 MB over 5,446 ayahs, keyed `"2:255"`, each row `[surah, ayah, phrase, verified, labels?]`. Opt-in via `loadSimilarAyahs` / `load_similar_ayahs`.

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

`data/tajweed-lessons.json`, ~45 KB. Loaded by default.

## Also shipped

`data/surah-sections.json` — per-surah section outlines (`[startAyah, endAyah, englishTitle, arabicTitle]`, nested), and an `overview` line where the source has one. Useful as an in-surah table of contents. `data/surah-stats.json` — per-surah ayah / word / letter counts plus juz list and revelation type, in one small file for when you need the numbers without loading the Quran.
