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
engine.juzPage.juzFromEnd(1);             // juz 30 ('Amma) — counts juz from the END of the Quran
engine.juzPage.juzStats(30);              // { surahCount, ayahCount, wordCount, letterCount, pageCount }
```

### Juz from the end

`juzFromEnd(n)` resolves a juz counted backwards from the end of the Quran: `1 → juz 30`, `2 → juz 29`, … `30 → juz 1`. It returns the same `JuzEntry` as `juz(31 - n)` and is `undefined`/`null` for `n` outside `1..30`. This mirrors the search-bar `-N` shorthand in the Al-Islam app (typing `-1` jumps to juz 30) — see [06 · Ayah search](06-ayah-search.md).

### Per-juz statistics

`juzStats(juz)` returns aggregate counts for a single juz — `surahCount`, `ayahCount`, `wordCount`, `letterCount`, `pageCount` — or `undefined`/`null` for an unknown juz id. Counts are computed from the ayahs **actually assigned** to the juz (`ayah.juz === juz`), so a surah that straddles a boundary is split correctly between the two juz it touches. Because the boundary partition is exhaustive and disjoint, summing `ayahCount` across all 30 juz yields exactly 6236.

## Reimplementation notes

- Page/juz membership is a **linear scan** over ayahs filtering on `ayah.page` / `ayah.juz`; for hot paths build a `{ page: [ayahs] }` / `{ juz: [ayahs] }` index once at load.
- "First ayah of page/juz" is the first ayah (mushaf order) carrying that value.
- Surahs-in-juz uses the boundary range `startSurah..endSurah` from `juz.json`.
- `juzStats` aggregates `wordCount` / `letterCount` per ayah (treat a missing count as 0) and counts **distinct** surahs and pages via sets; `pageCount` is the number of distinct mushaf pages the juz touches.
- `juzFromEnd(n)` is pure arithmetic over the juz id space: `juz(31 - n)`.

Reference: [`src/juzPage.js`](../packages/quran-engine-js/src/juzPage.js).
