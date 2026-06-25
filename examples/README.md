# Examples

Runnable examples for the **Quran Tajweed Engine**. The Node examples import the
engine straight from source (`../packages/quran-engine-js/src/...`), so they run
with **zero install** on Node 18+ — no `npm install`, no build step. They read the
canonical JSON from the repo's `/data` directory.

| File | What it shows | How to run |
|------|---------------|------------|
| [`node-quickstart.mjs`](./node-quickstart.mjs) | A guided tour of every major feature: load the engine, surah/ayah metadata, all translations, tajweed spans with colors, global ayah numbers, juz/page navigation, audio URLs, search, and sorting. | `node examples/node-quickstart.mjs` |
| [`tajweed-terminal.mjs`](./tajweed-terminal.mjs) | Renders an ayah (or a whole surah) to the terminal with 24-bit ANSI color, using each tajweed span's canonical rule color. | `node examples/tajweed-terminal.mjs 2 255` |
| [`browser/index.html`](./browser/index.html) | A single self-contained HTML page (no build step) with a surah dropdown and tajweed-colored ayahs rendered RTL, plus per-ayah play buttons. | serve + open (see below) |
| [`react-ayah.jsx`](./react-ayah.jsx) | A `<AyahView surah ayah />` React component: tajweed coloring, translation, and a play button. A correct snippet against the real API (not executed). | drop into your React app |

Run all commands from the **repository root**.

## Node examples

```sh
node examples/node-quickstart.mjs
node examples/tajweed-terminal.mjs            # defaults to 1:1
node examples/tajweed-terminal.mjs 2 255      # one ayah (Ayat al-Kursi)
node examples/tajweed-terminal.mjs 112        # a whole surah (al-Ikhlas)
```

`tajweed-terminal.mjs` needs a terminal with 24-bit ("true color") support —
iTerm2, Apple Terminal, the VS Code terminal, GNOME Terminal, and Windows
Terminal all qualify.

## Browser example

Browsers can't read the filesystem, so the `/data` JSON must be **served over
HTTP**. Start a static server from the repo root:

```sh
python3 -m http.server 8000
```

then open <http://localhost:8000/examples/browser/index.html>.

The page imports the engine via a native `<script type="module">` (no bundler)
and fetches the data with relative `../../data/...` paths. It loads the small
`data/surahs/index.json` for the dropdown and lazily fetches one surah file
(`data/surahs/NNN.json`) when selected.

## React example

`react-ayah.jsx` is a snippet for a bundler (Vite/Next/CRA). Build the engine
once at app scope with `createEngine({ quran, juz, reciters, tajweedRules })` and
pass it to `<AyahView engine={engine} surah={2} ayah={255} />`. See the comment
block at the bottom of the file.

## The API in one minute

```js
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
const engine = await loadFromDisk();

engine.quran.surah(1).nameEnglish;            // "The Opener"
engine.quran.ayah(2, 255).textArabic;         // Ayat al-Kursi
engine.tajweed(text);                         // → [{ start, end, category, text, color }]
engine.quran.globalAyahNumber(2, 255);        // 262  (1..6236)
engine.juzPage.firstAyahOfJuz(30);            // { surah, ayah }
engine.search.searchVerses("mercy");          // verse hits, mushaf order
engine.search.searchSurahs("2:255");          // surah jump
```

See [`../docs/recipes.md`](../docs/recipes.md) for the full cookbook.
