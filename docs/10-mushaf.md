# 10 · The printed mushaf

Twenty riwayat of the Ten Qiraat as **page-exact facsimiles**, each with the page table it is actually paginated by, and — where the text ships — where it breaks its lines.

> **Key facts:** every facsimile is exactly **604 pages** on the Madani page division, so PDF page N is mushaf page N with no offset table. A riwayah's pagination is **not** Hafs' pagination. **Eight** of the twenty publish their text; the other twelve ship the facsimile and the page table only.

## Why a riwayah needs its own page table

`quran.json` carries a `page` on every ayah. Those are the **Madani (Hafs)** page numbers, and they do not hold for another reading. Readings merge and split ayahs (al-Baqarah is 286 ayahs in Hafs, 285 in Warsh) and spell words differently, so the same ayah lands on a different page in Warsh's print. Paging a Warsh reader by Hafs page numbers drifts, and the drift compounds down the mushaf.

So each riwayah ships its own `ayah → page` table, taken from its own printed edition:

```js
engine.mushaf.page(2, 255, "hafs");    // 42
engine.mushaf.page(2, 255, "warsh");   // that riwayah's own page
engine.mushaf.ayahsOnPage(42, "hafs"); // [{surah:2, ayah:251}, ...] in mushaf order
engine.mushaf.firstAyahOfPage(213, "warsh");
```

## The twelve without text

The twelve riwayat outside the eight verified ones (Ibn Amir's, Hamzah's, al-Kisai's, Abu Jafar's, Yaqub's and Khalaf al-Ashir's transmissions) have never been published as digital text by the King Fahd Complex. The Al-Islam app carries a machine extraction of them from printed mushafs, marked beta and gated behind an explicit consent screen; **this engine does not publish it.** Text that has not been proofread word by word is not something to hand other developers as engine data.

What they do ship is the thing that is exact regardless: **the printed mushaf itself**, plus its page table. So a reader can open, page through, and jump to any ayah in all twenty — it simply renders the facsimile rather than composing text. `riwayah(slug).textIncluded` is the flag:

```js
engine.mushaf.riwayat().length;           // 20
engine.mushaf.riwayatWithText().length;   // 8
engine.mushaf.riwayah("hisham").textIncluded;  // false — facsimile + pages only
```

Their **line tables and tajweed packs** are absent for the same reason: both index into that text, so publishing them without it would be publishing offsets into nothing.

## Files

```
data/mushaf/
├── index.json              the 20 riwayat: names, imam, PDF, what ships for each
├── pdfs/NN-<imam>-<narrator>.pdf.xz    the facsimiles, in the classical order
├── pages/<slug>.json       ayah → page, for all 20
└── lines/<slug>.json       line breaks, for the 8 whose text ships
```

### `index.json`

```json
{
  "totalPages": 604,
  "riwayat": [
    {
      "riwayah": "warsh",
      "tag": "Warsh an Nafi",
      "name": "Warsh an Nafi",
      "nameArabic": "وَرش عَن نَافِع",
      "imam": "Nafi",
      "imamArabic": "نَافِع",
      "narratorDiedAH": 197,
      "pdf": "pdfs/02-nafi-warsh.pdf.xz",
      "pdfBytes": 1089176,
      "pages": "pages/warsh.json",
      "lines": "lines/warsh.json",
      "tajweed": "../tajweed-qiraat/warsh.json",
      "textIncluded": true
    }
  ]
}
```

`tag` is what the Al-Islam app stores for the riwayah (`""` for Hafs) — carried so an app migrating onto the engine can map its own persisted setting without a translation table.

### The PDFs are `.pdf.xz`

Each file is one **solid xz stream** over the PDF, not per-stream compression. The originals are pure vector with Flate on each content stream; re-doing the whole file as a single xz stream is about a third of the size and fully lossless (66 MB → 22 MB across the set). Decompress before handing the bytes to a PDF renderer:

```bash
xz -d < data/mushaf/pdfs/02-nafi-warsh.pdf.xz > warsh.pdf
```

```swift
// Apple platforms: COMPRESSION_LZMA reads the xz container directly.
let pdf = try (compressed as NSData).decompressed(using: .lzma)
```

### `pages/<slug>.json`

```json
{ "riwayah": "warsh", "totalPages": 604, "pages": { "1": { "1": 1, "2": 1 }, "2": { "1": 2 } } }
```

Surah id → ayah id → page. Every riwayah's table covers all 6,236 Hafs ayah ids; where a reading merges two ayahs, both ids point at the page the merged text is printed on.

### `lines/<slug>.json`

```json
{ "riwayah": "warsh", "version": 1, "lineBreaks": { "1": { "1": [0, 4] } } }
```

Surah → ayah → **character offsets into that ayah's own text** at which the printed mushaf starts a new line. This is what lets a text renderer reproduce the page's line breaks rather than reflowing them: lay out the ayah, break where the table says, and the composed page matches the print.

Only the eight riwayat whose text ships have one — an offset into text you do not have is meaningless.

## API

| Method | Returns |
|---|---|
| `riwayat()` | all 20, in the classical order of the Ten Qiraat |
| `riwayatWithText()` | the 8 whose text this engine publishes |
| `riwayah(slug)` | one entry, or null |
| `totalPages()` | 604 |
| `pdfPath(slug)` | path to the facsimile, relative to `data/mushaf/` |
| `page(surah, ayah, riwayah)` | the page in that riwayah's own print |
| `ayahsOnPage(page, riwayah)` | every ayah on a page, in mushaf order |
| `firstAyahOfPage(page, riwayah)` | what a "go to page N" jump lands on |
| `lineBreaks(surah, ayah, riwayah)` | line-break offsets, or null |
| `hasTajweedPack(riwayah)` | whether `tajweed-qiraat/<slug>.json` exists |

`riwayah` defaults to `"hafs"` everywhere it appears.

Loading is opt-in — the tables are ~2 MB and the PDFs are never loaded by the engine at all:

```js
const engine = await loadFromDisk({ loadMushaf: true });
```

```python
engine = Engine.load(load_mushaf=True)
```

## See also

- [11 · Riwayah tajweed](11-qiraat-tajweed.md) — where a reading differs from Hafs, and why
- [01 · Quran](01-quran.md) — the qiraat text feeds and `existsInQiraah`
