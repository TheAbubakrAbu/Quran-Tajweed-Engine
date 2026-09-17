# 23 · The 99 Names in depth

The layer under [`namesOfAllah`](../data/names-of-allah.json): the root each Name is built on, one of nine themes, a paragraph on what it means, one line on living by it, and the ayahs where the Name itself appears.

> **Key fact:** a root prints **spaced** (`"ر ح م"`) and `morphology.json` stores it **closed up** (`"رحم"`). Use `rootKey()` before matching the two, or every lookup misses.

## One Name

```js
engine.namesDepth.byNumber(1);
// { number: 1, root: "ر ح م", theme: "mercy",
//   explanation: "Rahmah shares its root with the womb: …",
//   living: "Meet people with more mercy than they have earned from you, …",
//   occurrences: [{ surah: 1, ayah: 3, token: 0, tokens: 1 },
//                 { surah: 17, ayah: 110, token: 5, tokens: 1 }] }
```

`number` is the same 1…99 as `namesOfAllah.byNumber`, so the two join without a lookup table: one gives you the Name, its meaning and its short description, the other everything under that.

## The nine themes

```js
engine.namesDepth.themes();        // [{ id: "mercy", label: "Mercy" }, …]
engine.namesDepth.byTheme("mercy") // the ten Names of mercy, by number
```

Every Name carries exactly one theme and every theme has members, so the nine **partition** the 99: a test pins the total at 99 with nothing left over.

## Roots

```js
engine.namesDepth.byRoot("رحم"); // [1, 2], Ar-Raḥmān and Ar-Raḥīm
engine.namesDepth.byRoot("ر ح م");   // the same; either spelling is accepted
rootKey("ر ح م");                    // "رحم"
```

`byRoot` folds both sides, so you never have to think about it. `rootKey` is exported for when you are joining against [morphology](18-morphology.md) yourself: that corpus stores roots closed up, and comparing the spaced form to it silently matches nothing.

## Where a Name appears

```js
engine.namesDepth.inAyah(1, 3);
// [{ name: {number: 1, …}, occurrence: {surah: 1, ayah: 3, token: 0, tokens: 1} },
//  { name: {number: 2, …}, occurrence: {surah: 1, ayah: 3, token: 1, tokens: 1} }]
```

Results come back in **token order**, which is reading order, so highlighting them in a rendered ayah needs no further sorting.

`token` is a 0-based index into the ayah's whitespace tokens, and `tokens` is how many of them the Name spans. Ten occurrences across four Names (60 al-Ḥayy, 77 al-Waliyy, 81 al-Muntaqim, 97 al-Wārith) have **`token: null` and `tokens: 0`**: the corpus knows the ayah but could not place the word in it. The ayah is still right, so show the verse whole and highlight nothing rather than guessing a position. Unplaced occurrences sort last, so a highlighted list stays in reading order either way.

If you verify occurrences against the text yourself, **fold both sides** the way [word of the day](22-word-of-day.md) describes: the placements were made against folded text, and comparing literally calls every pause mark a mismatch.

## Search

```js
engine.namesDepth.search("رحم");     // by root, either spelling
engine.namesDepth.search("mercy");   // by explanation or living line
```

Arabic is compared as written with the spaces closed; the prose case-insensitively. An empty query returns nothing rather than everything.

## Counts

| | |
|---|---|
| Names | 99 |
| Themes | 9 |
| Occurrences | 194 (184 placed, 10 not) |

## Credit

The roots, themes, explanations and living lines are **Tilawa**'s, by **Jamil Hammoudeh**, used with permission. The occurrences are derived against this engine's own Ḥafṣ text. The Names themselves, with their meanings and descriptions, are `names-of-allah.json` and credited separately.
