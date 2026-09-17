# 25 · The scientific-miracles corpus

202 short articles, each making one claim about the Quran and anchoring it to the ayahs it rests on, filed under 15 categories.

> **Key fact:** filter on the **article's** level, not its category's. A category carries a level (the hardest science it covers) and so does an article, and **147 of the 202 disagree**. `byLevel` and `levels` both read the article's own.

## An article is blocks, not prose

```js
engine.miracles.bySlug("big_bang_crunch").blocks.map((b) => b.kind);
// ["claim", "text", "ayah", "text", "closer"]
```

The layout is the point: the **claim** is a headline, the **lead** sets it up, a **quote** carries somebody else's words with `sourceLabel` and `sourceUrl` next to them, an **ayah** block is a hole you fill from `quran.json`, and the **closer** asks the rhetorical question the article was built toward. Render them in order and you have the article.

| kind | fields |
|---|---|
| `claim`, `closer` | `text` |
| `lead`, `text` | `text`, optionally `links` |
| `quote` | `text`, `sourceLabel`, `sourceUrl` |
| `ayah` | `surah`, `ayah`, `endAyah`, and **no text at all** |

## An ayah block carries no text, on purpose

```js
engine.miracles.ayahRefs("abjad_numerals");
// [{ surah: 111, ayah: 1, endAyah: 5 }]
```

The verse belongs to this engine's own text, so shipping a copy inside the article would be a second copy to keep in step and would pin the article to one riwayah. Resolve the reference yourself: `engine.quran.ayah(111, 1)`, and so on to `endAyah`.

Every ayah block is a **range**, with `endAyah` always present and equal to `ayah` for a single verse. `citing` searches the range, inclusive at both ends:

```js
engine.miracles.citing(21, 30).map((a) => a.slug);  // ["big_bang_crunch", "exoplanets"]
engine.miracles.citing(111, 3).map((a) => a.slug);  // includes "abjad_numerals" (mid-range)
```

`citing` is the main way in from the rest of the engine: you have an ayah on screen, and this says what has been written about it.

## The levels are not alphabetical

```js
engine.miracles.levels();  // ["simple", "intermediate", "advanced", "extreme"]
```

That is the app's own ordering, and nothing in the file states it, so every port hard-codes the rank. Sorted as strings, `"extreme"` would land second, which is precisely backwards.

| level | articles |
|---|---|
| simple | 6 |
| intermediate | 103 |
| advanced | 37 |
| extreme | 56 |

## Links come in two forms

```jsonc
{ "label": "Revelation 8:10", "url": "https://…" }   // 73 of them: an outside page
{ "label": "Dark Energy", "slug": "dark_energy" }     // 12 of them: another article here
```

Exactly one of the two is set. A model that keeps only `url` silently drops the twelve internal cross-references, and every internal slug resolves, so following one is `bySlug` and nothing more.

## `text()` leaves the quotes out

```js
engine.miracles.text("abjad_numerals").startsWith("Alphanumeric code.");  // true
engine.miracles.text("abjad_numerals").includes("Wikipedia");             // false
```

Claim, lead, text and closer, joined with a blank line in reading order. Quote blocks are **skipped**: they are third-party excerpts sitting next to a source label, so folding them in would put somebody else's words into the article's voice and would break a citation off from what it cites. Ayah blocks are skipped because they have no text to join.

Note that `search` is the other way round: it *does* look inside quotes, because a reader hunting for a word remembers reading it and not who wrote it.

## No images, and the corpus says so

`imagesIncluded` is `false` and **no block anywhere has kind `"image"`**. The site's illustrations are not republished here for licensing reasons, and the prose is written to stand without them. A consumer that leaves a gap for a picture will be waiting forever.

## Counts

| | |
|---|---|
| Articles | 202 |
| Categories | 15 |
| Ayah refs | 278 (49 of them spanning more than one verse) |
| Links | 73 external, 12 internal |

## Sourcing

Captured from miracles-of-quran.com by Tilawa. The `source` field records the site and the capture date.
