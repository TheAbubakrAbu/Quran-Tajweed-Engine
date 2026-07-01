# 01 · Quran (text, translations, qiraat)

The foundation. Everything else builds on this data. The engine is **data-first**: the canonical artifact is the JSON in [`/data`](../data), and any language that can parse JSON can use it.

## Data files

| File | Size | What it is |
|------|------|------------|
| [`data/quran.json`](../data/quran.json) | ~5.3 MB | All 114 surahs, 6236 ayahs, Arabic (Hafs Uthmani) + transliteration + 2 English translations + per-ayah juz/page/word/letter counts. |
| [`data/surah-info.json`](../data/surah-info.json) | ~1.8 MB | "About this surah" write-ups (Maududi, Ibn Ashur) as light Markdown. |
| [`data/names-of-allah.json`](../data/names-of-allah.json) | ~32 KB | The 99 Names of Allah with meanings, descriptions, and where they occur. |
| [`data/muqattaat.json`](../data/muqattaat.json) | ~8 KB | The disconnected opening letters (muqaṭṭaʿāt) of 29 surahs: letters, transliteration, and fully-vocalized Arabic spelling (with madd-lāzim marks). |
| [`data/qiraat/*.json`](../data/qiraat) | ~1.6 MB each | Seven alternate readings (riwayat): Warsh, Qaloon, Duri, Susi, al-Bazzi, Qunbul, Shubah. |
| [`data/qiraat-counts.json`](../data/qiraat-counts.json) | ~6.5 KB | Per-riwayah × per-surah ayah counts (generated from the qiraah feeds) — powers `existsInQiraah` / `numberOfAyahsInQiraah` without loading the full qiraah text. |

## `quran.json` schema

Top-level is a JSON **array** of surah objects:

```jsonc
{
  "id": 1,                          // 1..114
  "type": "makkan",                 // "makkan" | "madinan"  (revelation place)
  "nameArabic": "الفَاتِحَة",
  "nameTransliteration": "Al-Fatihah",
  "nameEnglish": "The Opener",
  "numberOfAyahs": 7,
  "pageStart": 1, "pageEnd": 1, "numberOfPages": 1,
  "firstJuz": 1, "lastJuz": 1, "juzs": [1],
  "revelationOrder": 5,             // chronological order of revelation
  "revelationExceptions": "",
  "similarNames": ["al fatiha", "fatihah", ...],   // search aliases
  "ayahs": [
    {
      "id": 1,                      // ayah number within the surah
      "textArabic": "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ",   // Hafs Uthmani, full diacritics
      "textTransliteration": "Bismi Allahi alrrahmani alrraheemi",
      "textEnglishSaheeh": "In the name of Allah, ...",          // Saheeh International
      "textEnglishMustafa": "In the Name of Allah—...",          // Mustafa Khattab (The Clear Quran)
      "juz": 1, "page": 1,
      "wordCount": 4, "letterCount": 19
    }
  ]
}
```

The **global ayah number** (1..6236) — used by the ayah-audio CDN and as a stable verse key — is the cumulative ayah index across the whole mushaf:

```
globalAyahNumber(surah, ayah) = (sum of numberOfAyahs for all surahs before `surah`) + ayah
```

## Qiraat (riwayat) schema

Each qiraah file is an **object** keyed by surah id (as a string), mapping to an array of ayahs:

```jsonc
// data/qiraat/qiraah-warsh.json
{
  "1": [
    { "id": 1, "text": "اِ۬لۡحَمۡدُ لِلهِ رَبِّ اِ۬لۡعَٰلَمِينَ" },
    { "id": 2, "text": "..." }
  ],
  "2": [ ... ]
}
```

To display an ayah in a non-default reading, look up `qiraat[riwayah][surahId][ayahIndex].text`, falling back to `textArabic` (Hafs) when no override exists. The riwayah keys used by the JS package are: `warsh`, `qaloon`, `duri`, `susi`, `buzzi`, `qunbul`, `shubah`.

### Qiraah existence & counts (no full-text load needed)

Riwayat merge/split some ayahs, so a Hafs ayah doesn't always exist as its own verse elsewhere (Baqarah is 286 in Hafs, 285 in Warsh). The qiraah feeds are numbered contiguously `1..count` per surah, so a Hafs ayah `N` exists in a riwayah iff `N ≤ count` — captured compactly in [`data/qiraat-counts.json`](../data/qiraat-counts.json), which loads by default:

```js
engine.quran.existsInQiraah(2, 285, "warsh");        // true
engine.quran.existsInQiraah(2, 286, "warsh");        // false — Baqarah is 285 in Warsh
engine.quran.existsInQiraah(2, 286, "shubah");       // true  — Shubah matches Hafs (6236)
engine.quran.numberOfAyahsInQiraah(2, "warsh");      // 285
engine.quran.numberOfAyahsInQiraah(2);               // 286   (Hafs, when riwayah omitted)
```

An unknown/unloaded riwayah falls back to Hafs (exists / full count). This mirrors `Ayah.existsInQiraah(_:)` / `Surah.numberOfAyahs(for:)` in the app, whose merge is the same id-match.

## `surah-info.json` schema

```jsonc
{ "id": 1, "sources": [ { "name": "Maududi", "contents": "## Name\n\nThis Surah is named ..." } ] }
```

`contents` is pre-converted Markdown (`##` headings + paragraphs) so it renders without HTML parsing. Source names present: `Maududi`, `Ibn Ashur`, and `ابن عاشور` (Ibn Ashur, Arabic).

## Reference implementation

JS: [`src/quran.js`](../packages/quran-engine-js/src/quran.js) — `Quran` class.

```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk({ loadQiraat: true }); // surah-info + names-of-allah load by default

engine.quran.surah(2).nameEnglish;                 // "The Cow"
engine.quran.ayah(2, 255).textArabic;              // Ayat al-Kursi
engine.quran.globalAyahNumber(2, 1);               // 8
engine.quran.arabicText(1, 1, "warsh");            // Warsh reading of al-Fatiha:1
engine.quran.info(1)[0].contents;                  // Maududi intro (Markdown)
engine.quran.surahFromEnd(1).id;                   // 114  (An-Nas; companion to juzPage.juzFromEnd)
engine.quran.sajdahAyahs().length;                 // 15   (prostration ayahs, by the ۩ U+06E9 mark)
engine.quran.isSajdahAyah(32, 15);                 // true
engine.namesOfAllah.byNumber(1).transliteration;   // "Ar-Rahman"  (99 Names of Allah)
```

### Sajdah, surah-from-end, names of Allah

- **`sajdahAyahs()`** returns the 15 prostration ayahs in mushaf order, detected by the **۩ (U+06E9)** mark in the Arabic text; **`isSajdahAyah(s, a)`** tests one ayah.
- **`surahFromEnd(n)`** counts surahs backward from the end: `1 → 114`, `2 → 113` … `114 → 1`; `undefined` outside `1..114`. (Page-from-end is `firstAyahOfPage(totalPages() + 1 - n)`.)
- **`engine.namesOfAllah`** — `all()` (99 names, ordered) and `byNumber(n)`; each name has `name` (Arabic), `transliteration`, `number`, `found`, `meaning`, `desc`, `otherNames`.

## Provenance

See [CREDITS.md](../CREDITS.md). Arabic text is the Hafs an Asim Uthmani script; English translations are Saheeh International and Dr. Mustafa Khattab's *The Clear Quran*. All data is extracted, unmodified, from the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars) app.
