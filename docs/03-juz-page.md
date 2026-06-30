# 03 · Juz & Page

Two parallel ways to navigate the mushaf: by **juz** (30 paras) and by **page** (~604 pages of the standard Madani mushaf).

## Data sources

- **Juz boundary names + ranges** are static: [`data/juz.json`](../data/juz.json) (30 entries, mirrors `QuranData.juzList`).
- **Per-ayah membership** comes from the `juz` and `page` fields on each ayah in `quran.json`.

So `juz.json` answers "what is juz 5 called and where does it start/end", while the per-ayah fields answer "which juz/page is *this* ayah in".

## `juz.json` schema

```jsonc
{
  "id": 1,
  "nameArabic": "الم",
  "nameTransliteration": "Alif Lam Meem",
  "startSurah": 1, "startAyah": 1,
  "endSurah": 2,  "endAyah": 141
}
```

The 30 boundaries: Juz 1 starts at 1:1; Juz 30 ends at 114:6. Notable ones — Juz 2 `Sayaqoolu` (2:142), Juz 15 `Subhana Al-Ladhee` (17:1), Juz 26 `Ha Meem` (46:1), Juz 30 `'Amma` (78:1).

## Operations

```js
engine.juzPage.juzes();                  // all 30 boundary entries
engine.juzPage.juz(5);                    // { id:5, nameTransliteration:"Wal-Muhsanat", startSurah:4, ... }
engine.juzPage.ayahsInJuz(30);            // every ayah in juz 30, mushaf order
engine.juzPage.ayahsOnPage(1);            // every ayah on mushaf page 1
engine.juzPage.firstAyahOfJuz(5);         // jump target: { surah, ayah }
engine.juzPage.firstAyahOfPage(50);       // jump target
engine.juzPage.juzForAyah(2, 255);        // 3
engine.juzPage.pageForAyah(2, 255);       // 42
engine.juzPage.totalPages();              // 604 (depends on bundled page numbering)
engine.juzPage.surahsInJuz(1);            // [1, 2]
```

## Reimplementation notes

- Page/juz membership is a **linear scan** over ayahs filtering on `ayah.page` / `ayah.juz`; for hot paths build a `{ page: [ayahs] }` / `{ juz: [ayahs] }` index once at load.
- "First ayah of page/juz" is the first ayah (mushaf order) carrying that value.
- Surahs-in-juz uses the boundary range `startSurah..endSurah` from `juz.json`.

Reference: [`src/juzPage.js`](../packages/quran-engine-js/src/juzPage.js).
