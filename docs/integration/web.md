# Web (browser / bundler)

Use **`quran-engine-js`** in a browser app — Vite, webpack, Rollup, or plain `<script type="module">`. The package is pure ESM with **zero runtime dependencies**. In the browser you *bring your own JSON*: import the data from [`/data`](../../data) (bundled or served as static assets) and call `createEngine(...)`.

## Setup

```bash
# inside the monorepo, the package is at packages/quran-engine-js
# in your own project, depend on it (path/workspace dep) or copy src/ in:
npm i @quran-tajweed-engine/core   # if/when published; otherwise use a path/workspace dependency
```

Copy or symlink the `/data` JSON into a place your bundler can import (e.g. `src/data/`) **or** serve it as static assets (e.g. `public/data/`). Two import styles:

- **Bundle the JSON** — `import quran from "./data/quran.json"`. Modern bundlers (Vite, webpack 5) support JSON imports out of the box; the JSON is inlined/code-split into your bundle.
- **Serve as static assets** — drop the files in `public/data/` and `fetch("/data/quran.json")` at runtime. Best for the big files and for **lazy per-surah loading** (below).

## Minimal working example (framework-agnostic)

```js
import { createEngine, surahAudioUrl, ayahAudioUrl } from "@quran-tajweed-engine/core";

// Bring your own JSON. tajweedRules is what gives each span its color.
import quran from "./data/quran.json";
import juz from "./data/juz.json";
import reciters from "./data/reciters.json";
import tajweedRules from "./data/tajweed-rules.json";

const engine = createEngine({ quran, juz, reciters, tajweedRules });

const ayah = engine.quran.ayah(2, 255);          // Ayat al-Kursi
console.log(ayah.textArabic);
console.log(ayah.textEnglishSaheeh);

const reciter = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");
console.log(surahAudioUrl(reciter, 2));                                   // full surah
console.log(ayahAudioUrl(reciter, engine.quran.globalAyahNumber(2, 255)));// single ayah
```

> `quran.json` is ~5 MB. For a list/menu you only need `data/surahs/index.json` (no verse text); for a reading view, lazy-load `data/surahs/NNN.json` on demand — see below.

## Lazy-loading per-surah files

Serve `data/surahs/` (and optionally `data/tajweed/`) as static assets and fetch only what you render:

```js
// data/surahs/index.json → lightweight list (id, names, ayah count, pages) for a menu
const surahList = await fetch("/data/surahs/index.json").then((r) => r.json());

// data/surahs/057.json → full ayah text for one surah, on demand (zero-padded to 3 digits)
const pad3 = (n) => String(n).padStart(3, "0");
async function loadSurah(id) {
  return fetch(`/data/surahs/${pad3(id)}.json`).then((r) => r.json());
}
const alHadid = await loadSurah(57);
alHadid.ayahs[0].textArabic;
```

This avoids shipping the 5 MB `quran.json` to the client. Tajweed still works: `engine.tajweed(text)` operates on any Arabic string, so pass the per-surah ayah text straight in. (If you prefer the pre-computed corpus, fetch `data/tajweed/NNN.json` instead — see [02-tajweed.md](../02-tajweed.md).)

## Tajweed rendering (colored RTL spans)

`engine.tajweed(text)` returns non-overlapping spans in order, each `{ start, end, category, text, color }`. Walk them and emit `<span style="color:…">` between the uncolored gaps (this is recipe #2):

```js
function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function ayahToHtml(surah, ayah) {
  const text = engine.quran.ayah(surah, ayah).textArabic;
  const spans = engine.tajweed(text);          // colored, non-overlapping, in order
  let html = "", cursor = 0;
  for (const s of spans) {
    html += escapeHtml(text.slice(cursor, s.start));                       // uncolored gap
    html += `<span style="color:${s.color}" title="${s.category}">${escapeHtml(s.text)}</span>`;
    cursor = s.end;
  }
  html += escapeHtml(text.slice(cursor));
  return `<p dir="rtl" lang="ar">${html}</p>`;
}

document.querySelector("#ayah").innerHTML = ayahToHtml(1, 1);
```

The `dir="rtl"` and `lang="ar"` attributes are what give correct right-to-left shaping. `s.color` is the `colorHex` from `tajweed-rules.json` — it's populated only because we passed `tajweedRules` to `createEngine`.

## Search box

```js
function onQuery(q) {
  const surahs = engine.search.searchSurahs(q);        // names, numbers, "2:255", makkan/madani
  const ref = engine.search.parseReference(q);          // → {surah, ayah} or null
  const verses = engine.search.searchVerses(q, { limit: 50 }); // [{ id, surah, ayah }, ...] mushaf order
  return { surahs, ref, verses };
}

const input = document.querySelector("#q");
input.addEventListener("input", () => {
  const { verses } = onQuery(input.value);
  const out = verses.map((v) => `${v.surah}:${v.ayah}`).join("  ");
  document.querySelector("#results").textContent = out;
});
```

Verse search is unranked, mushaf-order, and rejects queries containing a digit (numeric lookups go through `searchSurahs` / `parseReference`). See [06-ayah-search.md](../06-ayah-search.md).

## Audio with `<audio>`

```js
const audio = document.querySelector("#player");
const reciter = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");

// Full surah
audio.src = surahAudioUrl(reciter, 36);   // Ya-Sin
audio.play();

// Verse-by-verse with auto-advance
const surah = engine.quran.surah(36);
const urls = surah.ayahs.map((a) => ayahAudioUrl(reciter, engine.quran.globalAyahNumber(36, a.id)));
let i = 0;
audio.src = urls[i];
audio.addEventListener("ended", () => { if (++i < urls.length) { audio.src = urls[i]; audio.play(); } });
audio.play();
```

```html
<audio id="player" controls></audio>
```

## React component (functional, hooks)

```jsx
import { useEffect, useMemo, useRef, useState } from "react";
import { createEngine, surahAudioUrl } from "@quran-tajweed-engine/core";
import quran from "./data/quran.json";
import juz from "./data/juz.json";
import reciters from "./data/reciters.json";
import tajweedRules from "./data/tajweed-rules.json";

// Build the engine once for the whole app.
const engine = createEngine({ quran, juz, reciters, tajweedRules });

function TajweedAyah({ surah, ayah }) {
  const spans = useMemo(() => {
    const text = engine.quran.ayah(surah, ayah).textArabic;
    const out = [];
    let cursor = 0;
    for (const s of engine.tajweed(text)) {
      if (s.start > cursor) out.push({ text: text.slice(cursor, s.start), color: null });
      out.push({ text: s.text, color: s.color, category: s.category });
      cursor = s.end;
    }
    if (cursor < text.length) out.push({ text: text.slice(cursor), color: null });
    return out;
  }, [surah, ayah]);

  return (
    <p dir="rtl" lang="ar" style={{ fontSize: "2rem" }}>
      {spans.map((p, i) => (
        <span key={i} title={p.category} style={p.color ? { color: p.color } : undefined}>
          {p.text}
        </span>
      ))}
    </p>
  );
}

export default function SurahView({ surah = 1 }) {
  const audioRef = useRef(null);
  const [reciter] = useState(() => engine.reciters.all().find((r) => r.name === "Mishary Alafasy"));
  const s = engine.quran.surah(surah);

  return (
    <div>
      <h2>{s.nameEnglish} — {s.nameArabic}</h2>
      {s.ayahs.map((a) => <TajweedAyah key={a.id} surah={surah} ayah={a.id} />)}
      <button onClick={() => {
        audioRef.current.src = surahAudioUrl(reciter, surah);
        audioRef.current.play();
      }}>Play surah</button>
      <audio ref={audioRef} controls />
    </div>
  );
}
```

For very large apps, lazy-load per-surah JSON (above) and call `engine.tajweed(ayah.textArabic)` on the fetched text instead of importing the full `quran.json`.

## See also

- [recipes.md](../recipes.md) — #1 (surah menu), #2 (tajweed HTML), #7 (search), #4–6 (audio), #14 (browser cache).
- [01-quran.md](../01-quran.md) · [02-tajweed.md](../02-tajweed.md) · [06-ayah-search.md](../06-ayah-search.md)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md) · [08-caching.md](../08-caching.md)
- [`quran-engine-js` README](../../packages/quran-engine-js/README.md)
