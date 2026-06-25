# Recipes (cookbook)

Copy-paste solutions to common tasks. Examples are in JavaScript (the reference port); the same calls
exist in every port with idiomatic naming (`globalAyahNumber` ⇄ `global_ayah_number`, etc.).

Assume:
```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();
```

## 1. List all surahs for a menu

```js
engine.quran.all().map(s => ({
  id: s.id,
  name: s.nameEnglish,
  arabic: s.nameArabic,
  ayahs: s.numberOfAyahs,
  place: s.type,            // "makkan" | "madinan"
}));
```
For web, load only `data/surahs/index.json` (no verse text) to render this without the 5 MB file.

## 2. Render one ayah with tajweed colors (HTML)

```js
function ayahToHtml(surah, ayah) {
  const text = engine.quran.ayah(surah, ayah).textArabic;
  const spans = engine.tajweed(text);          // colored, non-overlapping, in order
  let html = "", cursor = 0;
  for (const s of spans) {
    html += escapeHtml(text.slice(cursor, s.start));                 // uncolored gap
    html += `<span style="color:${s.color}" title="${s.category}">${escapeHtml(s.text)}</span>`;
    cursor = s.end;
  }
  html += escapeHtml(text.slice(cursor));
  return `<p dir="rtl" lang="ar">${html}</p>`;
}
```

## 3. Show an ayah in Arabic + both English translations

```js
const a = engine.quran.ayah(2, 255);
console.log(a.textArabic);
console.log("Saheeh:", a.textEnglishSaheeh);
console.log("Khattab:", a.textEnglishMustafa);
console.log("Translit:", a.textTransliteration);
```

## 4. Play a full surah

```js
import { surahAudioUrl } from "@quran-tajweed-engine/core";
const reciter = engine.reciters.all().find(r => r.name === "Mishary Alafasy");
const url = surahAudioUrl(reciter, 36);        // Ya-Sin
// hand `url` to your audio player (<audio>, AVPlayer, ExoPlayer, expo-av, …)
```

## 5. Play verse-by-verse with auto-advance

```js
import { ayahAudioUrl } from "@quran-tajweed-engine/core";
const surah = engine.quran.surah(36);
const urls = surah.ayahs.map(a =>
  ayahAudioUrl(reciter, engine.quran.globalAyahNumber(36, a.id))
);
// play urls[i], on "ended" advance to urls[i+1]
```

## 6. Repeat one ayah N times (memorization)

```js
const url = ayahAudioUrl(reciter, engine.quran.globalAyahNumber(2, 255));
let plays = 0, target = 10;
audio.src = url;
audio.addEventListener("ended", () => { if (++plays < target) audio.play(); });
audio.play();
```

## 7. Build a search box

```js
function onQuery(q) {
  // surah jump first (names, numbers, "2:255")
  const surahs = engine.search.searchSurahs(q);
  const ref = engine.search.parseReference(q);     // → {surah, ayah} or null
  // then verse text (Arabic or English, unranked, mushaf order)
  const verses = engine.search.searchVerses(q, { limit: 50 });
  return { surahs, ref, verses };
}
onQuery("mercy");
onQuery("الرحمن");
onQuery("18:10");
```

## 8. Jump to a juz or page

```js
const j = engine.juzPage.firstAyahOfJuz(30);     // { surah, ayah }
const p = engine.juzPage.firstAyahOfPage(1);
const ayahsOnPage = engine.juzPage.ayahsOnPage(1);
```

## 9. Render a mushaf page

```js
function renderPage(page) {
  const items = engine.juzPage.ayahsOnPage(page);   // [{ surah, ayah }]
  return items.map(({ surah, ayah }) => ({
    ref: `${surah.id}:${ayah.id}`,
    html: ayahToHtml(surah.id, ayah.id),            // recipe #2
  }));
}
```

## 10. Sort the surah list different ways

```js
import { sortSurahs } from "@quran-tajweed-engine/core";
sortSurahs(engine.quran.all(), "revelation", "ascending");   // chronological
sortSurahs(engine.quran.all(), "ayahs", "descending");        // longest first
sortSurahs(engine.quran.all(), "surah");                       // natural 1..114
```

## 11. Filter Makkan vs Madinan

```js
import { filterByRevelationType } from "@quran-tajweed-engine/core";
filterByRevelationType(engine.quran.all(), "makkan");
// or via search:
engine.search.searchSurahs("madani");
```

## 12. Show an ayah in another reading (qiraah)

```js
const engineQ = await loadFromDisk({ loadQiraat: true });
engineQ.quran.arabicText(1, 1, "warsh");      // al-Fatiha:1 in the Warsh reading
engineQ.reciters.byQiraah("Warsh an Nafi");    // reciters for that reading
```

## 13. "About this surah"

```js
const e = await loadFromDisk({ loadSurahInfo: true });
const sources = e.quran.info(1);               // [{ name: "Maududi", contents: "## Name\n..." }]
// `contents` is Markdown — render with any md renderer
```

## 14. Offline audio download + cache (browser/IndexedDB sketch)

```js
import { AudioCache, surahAudioUrl } from "@quran-tajweed-engine/core";
// implement CacheStore over IndexedDB; see docs/08
const cache = new AudioCache(myIndexedDbStore);
const bytes = await cache.surah(reciter, 36, surahAudioUrl(reciter, 36));
const blobUrl = URL.createObjectURL(new Blob([bytes], { type: "audio/mpeg" }));
audio.src = blobUrl;
```

## 15. The 99 Names of Allah

```js
import names from "../../data/names-of-allah.json" assert { type: "json" };
names[0];   // { name: "الرَّحمَٰن", transliteration: "Ar-Rahman", meaning: "The Entirely Merciful", ... }
```

## 16. Word & letter counts (stats / progress)

```js
const s = engine.quran.surah(2);
s.wordCount; s.letterCount; s.numberOfAyahs; s.numberOfPages;
const a = engine.quran.ayah(2, 255);
a.wordCount; a.letterCount;
```

---

Need something not here? The features are small and composable — check the per-feature specs
([01](01-quran.md)–[08](08-caching.md)) or open an issue.
