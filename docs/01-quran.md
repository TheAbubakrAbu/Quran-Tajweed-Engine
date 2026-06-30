# 01 · Quran (text, translations, qiraat)

The foundation. Everything else builds on this data. The engine is **data-first**: the canonical artifact is the JSON in [`/data`](../data), and any language that can parse JSON can use it.

## Data files

| File | Size | What it is |
|------|------|------------|
| [`data/quran.json`](../data/quran.json) | ~5.3 MB | All 114 surahs, 6236 ayahs, Arabic (Hafs Uthmani) + transliteration + 2 English translations + per-ayah juz/page/word/letter counts. |
| [`data/surah-info.json`](../data/surah-info.json) | ~1.8 MB | "About this surah" write-ups (Maududi, Ibn Ashur) as light Markdown. |
| [`data/names-of-allah.json`](../data/names-of-allah.json) | ~32 KB | The 99 Names of Allah with meanings, descriptions, and where they occur. |
| [`data/qiraat/*.json`](../data/qiraat) | ~1.6 MB each | Seven alternate readings (riwayat): Warsh, Qaloon, Duri, Susi, al-Bazzi, Qunbul, Shubah. |

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

## `surah-info.json` schema

```jsonc
{ "id": 1, "sources": [ { "name": "Maududi", "contents": "## Name\n\nThis Surah is named ..." } ] }
```

`contents` is pre-converted Markdown (`##` headings + paragraphs) so it renders without HTML parsing. Source names present: `Maududi`, `Ibn Ashur`, and `ابن عاشور` (Ibn Ashur, Arabic).

## Reference implementation

JS: [`src/quran.js`](../packages/quran-engine-js/src/quran.js) — `Quran` class.

```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk({ loadQiraat: true, loadSurahInfo: true });

engine.quran.surah(2).nameEnglish;                 // "The Cow"
engine.quran.ayah(2, 255).textArabic;              // Ayat al-Kursi
engine.quran.globalAyahNumber(2, 1);               // 8
engine.quran.arabicText(1, 1, "warsh");            // Warsh reading of al-Fatiha:1
engine.quran.info(1)[0].contents;                  // Maududi intro (Markdown)
```

## Provenance

See [CREDITS.md](../CREDITS.md). Arabic text is the Hafs an Asim Uthmani script; English translations are Saheeh International and Dr. Mustafa Khattab's *The Clear Quran*. All data is extracted, unmodified, from the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars) app.
