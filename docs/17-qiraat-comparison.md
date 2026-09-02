# 17 · Qiraat comparison

How far apart two readings actually are, measured word by word rather than described in prose.

> **Key fact:** readings merge and split ayahs, so ayah *n* of one is not ayah *n* of the other. The comparison aligns **word streams**, never ayah indices.

## Three buckets

Every word pair lands in one of three:

| Bucket | Meaning |
|---|---|
| `identical` | the same word, written the same way, marks and all |
| `sameSkeleton` | the same consonantal skeleton (*rasm*), different vowels or spelling |
| `different` | a different skeleton — a genuinely different word form |

Plus `added` and `dropped` for words only one reading has.

`sameSkeleton` is the interesting one, and it is the majority of every comparison. It is exactly what the Uthmanic rasm was designed to permit: **one written form, several sound readings**. Al-Baqarah 2:1–2 in Warsh against Hafs is six differences in the first ten words, and every one of them is the same skeleton:

```js
engine.qiraatComparison.differences(2, "warsh", { limit: 3 });
// [{ position: 1, base: "الٓمٓ",       other: "أَلَٓمِّٓۖ",     kind: "sameSkeleton" },
//  { position: 3, base: "ٱلۡكِتَٰبُ",   other: "اَ۬لۡكِتَٰبُ",  kind: "sameSkeleton" },
//  { position: 5, base: "رَيۡبَۛ",      other: "رَيۡبَۖ",       kind: "sameSkeleton" }]
```

## The whole Quran, against Hafs

```js
engine.qiraatComparison.compare("warsh");
// { words: 77629, identical: 49315, sameSkeleton: 27546, different: 717,
//   added: 283, dropped: 51, identicalPercent: 63.5 }
```

| Riwayah | Imam | Identical | Same skeleton | Different |
|---|---|---:|---:|---:|
| Shuʿbah | ʿĀṣim | 99.1% | 603 | 78 |
| Qunbul | Ibn Kathīr | 83.9% | 12,294 | 166 |
| al-Bazzī | Ibn Kathīr | 83.9% | 12,293 | 167 |
| ad-Dūrī | Abū ʿAmr | 78.8% | 15,583 | 779 |
| as-Sūsī | Abū ʿAmr | 71.8% | 21,048 | 820 |
| Qālūn | Nāfiʿ | 66.1% | 25,556 | 721 |
| Warsh | Nāfiʿ | 63.5% | 27,546 | 717 |

The shape of that table is the point. Shuʿbah is Hafs' fellow narrator from ʿĀṣim, so the two are nearly the same text; the two narrators of a shared imam always cluster (al-Bazzī and Qunbul are within one word of each other). And even at the far end, **fewer than 1% of words differ in skeleton** — the readings differ in *sound*, overwhelmingly, not in wording.

## Why alignment, not indexing

Warsh's al-Baqarah has 285 verses to Hafs' 286: it reads الٓمٓ and ذٰلك الكتٰب as one verse. Pair the two by ayah id and everything after 2:1 compares the wrong verses.

So the comparison walks the **surah's whole word stream** on both sides with a two-pointer alignment:

1. words equal → `identical`;
2. skeletons equal → `sameSkeleton`;
3. otherwise look ahead up to 3 words **on one side only** for a resync — that is an insertion or a deletion, reported as `added` / `dropped`;
4. no resync → `different`.

Step 3 is deliberately one-sided. Allowing a skip on both sides at once would resync across a *substitution* — one word standing where another does — and collapse every genuine word difference into an added+dropped pair. When that bug was in, `different` came out at exactly zero for every riwayah.

## What it cannot tell you

It measures the two printed **texts**, not the two **recitations**. A difference that lives only in how a letter is sounded — imālah, taqlīl, ishmām — appears here only where the print marks it. Read the numbers as "how far apart these two printed mushafs are", because that is what they are.

For what a reading's own print marks *as* a rule, see **[11 · Riwayah tajweed](11-qiraat-tajweed.md)**, which carries each mushaf's own legend.

## Availability

Only the **eight riwayat whose text this engine publishes** can be compared: Hafs plus the seven verified. The twelve beta readings ship their facsimile and page table but no text (see **[10 · Mushaf](10-mushaf.md)**), and nothing here can invent it.

```js
engine.qiraatComparison.available();
// ["buzzi", "duri", "hafs", "qaloon", "qunbul", "shubah", "susi", "warsh"]
```

The text is ~11 MB, so it is opt-in everywhere (`loadQiraat`), and the Swift package does not bundle it — a Swift consumer that wants the comparison passes a `dataDirectory`.

## Cost

`compare()` walks ~155,000 words. It runs in a few hundred milliseconds and is meant to be computed once and cached, not called per render. `compareSurah()` is the per-screen unit.
