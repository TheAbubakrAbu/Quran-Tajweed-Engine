# 07 · Surah sorting & filtering

Order the 114 surahs by different keys, and filter by revelation place. Mirrors `orderedQuranSurahs` / `supportsSurahSortDirection` in `QuranView.swift`.

## Sort modes

| Mode | Key | Direction-aware? |
|---|---|---|
| `surah` | natural mushaf order (1..114) | no (intrinsic) |
| `revelation` | `revelationOrder` (chronological) | yes |
| `ayahs` | `numberOfAyahs` | yes |
| `page` | `numberOfPages` | yes |
| `words` | `wordCount` | yes |
| `letters` | `letterCount` | yes |

The reference app exposes additional browse buckets (`juz`, `khatm`, `sajdah`, `muqattaat`, `pages`) that are groupings rather than pure sorts; the JS port implements the six comparator modes above.

## Rules

- Every comparator is **ascending with `id` as the tiebreaker**.
- **Descending** = the reverse of that ascending array (so ties remain id-ascending within a reversed block).
- `direction: "surahOrder"` (and `mode: "surah"`) bypass sorting entirely → natural 1..114.
- `revelation` always sorts by `revelationOrder ?? MAX` with id tiebreak.

```js
import { sortSurahs, supportsDirection, filterByRevelationType, filterByCounts } from "@quran-tajweed-engine/core";

sortSurahs(surahs, "ayahs", "descending")[0].id;   // 2  (Al-Baqarah, 286 ayahs — longest)
sortSurahs(surahs, "revelation", "ascending");      // chronological order of revelation
sortSurahs(surahs, "surah");                         // natural mushaf order
supportsDirection("ayahs");                          // true
supportsDirection("surah");                          // false

filterByRevelationType(surahs, "makkan");            // Makkan surahs only

// Count filters — mirror the search-bar "286 ayahs" / "<10 pages". op ∈ "<" "<=" ">" ">=" "==".
filterByCounts(surahs, { ayahs: { op: "==", value: 286 } }).map(s => s.id);   // [2]
filterByCounts(surahs, { ayahs: { op: ">", value: 200 } }).map(s => s.id);    // [2, 7, 26]
filterByCounts(surahs, { pages: { op: "<=", value: 1 } });                     // surahs that fit on ≤1 page
```

Reference: [`src/sorting.js`](../packages/quran-engine-js/src/sorting.js).
