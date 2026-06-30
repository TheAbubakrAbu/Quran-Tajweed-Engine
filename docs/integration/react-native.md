# React Native / Expo

Use **`quran-engine-js`** in a React Native or Expo app. The package is pure ESM with zero runtime dependencies, so it runs on Hermes — with **one important caveat about tajweed** (below). As in the browser, you bring your own JSON and call `createEngine(...)`.

## Setup

```bash
npm i @quran-tajweed-engine/core   # or a path/workspace dependency to packages/quran-engine-js
```

You have two ways to get the [`/data`](../../data) JSON onto the device:

1. **Bundle as assets** — small/medium files (`juz.json`, `reciters.json`, `tajweed-rules.json`, `surahs/index.json`, per-surah `surahs/NNN.json`) imported with `import x from "./data/x.json"`. Metro bundles JSON natively. Avoid bundling the full ~5 MB `quran.json` if you can lazy-load per-surah files.
2. **Ship via a CDN** — host `/data` (or just `data/surahs/`) on any static host and `fetch()` per-surah files on demand, caching them with `expo-file-system`. Keeps the app binary small.

```js
import { createEngine } from "@quran-tajweed-engine/core";
import quran from "./data/quran.json";        // or load lazily from a CDN (below)
import juz from "./data/juz.json";
import reciters from "./data/reciters.json";
import tajweedRules from "./data/tajweed-rules.json";

export const engine = createEngine({ quran, juz, reciters, tajweedRules });
```

## The Intl.Segmenter caveat (tajweed on Hermes)

The **live tajweed detector** (`engine.tajweed(text)`) needs grapheme clustering via `Intl.Segmenter`, which **Hermes does not implement** by default. Two safe paths:

- **Recommended — consume the pre-computed corpus** instead of the live detector. Bundle/fetch the annotations (`data/tajweed-annotations.json`, or per-surah `data/tajweed/NNN.json`) and map each annotation `rule` to a color from `tajweed-rules.json → categories[].colorHex`. This is exactly what the native ports (Swift/Kotlin/Dart) do — strategy (A) in the [architecture](../architecture.md). It's a dictionary lookup + a UTF-16 slice, so it's tiny, exact, and Hermes-safe. JS strings are UTF-16, so `text.slice(start, end)` uses the same units the annotations record.
- **Or polyfill** `Intl.Segmenter` (e.g. a `intl-segmenter`/`Intl.Segmenter` polyfill, or build Hermes with Intl) and use the live detector as on the web. Heavier; only needed for text the corpus doesn't cover (other qiraat, user input).

### Tajweed from the corpus (Hermes-safe)

```js
import tajweedRules from "./data/tajweed-rules.json";
// per-surah annotations: data/tajweed/NNN.json (array of { surah, ayah, annotations:[{start,end,rule}] })
import surah1Tajweed from "./data/tajweed/001.json";

const colorOf = new Map(tajweedRules.categories.map((c) => [c.id, c.colorHex]));

// Build colored segments for an ayah from its annotations + raw text.
function tajweedSegments(text, annotations) {
  const out = [];
  let cursor = 0;
  for (const a of annotations) {                 // already in order, non-overlapping
    if (a.start > cursor) out.push({ text: text.slice(cursor, a.start), color: null });
    out.push({ text: text.slice(a.start, a.end), color: colorOf.get(a.rule) ?? null, rule: a.rule });
    cursor = a.end;
  }
  if (cursor < text.length) out.push({ text: text.slice(cursor), color: null });
  return out;
}

const entry = surah1Tajweed.find((e) => e.ayah === 1);
const text = engine.quran.ayah(1, 1).textArabic;
const segments = tajweedSegments(text, entry.annotations);
```

## Tajweed rendering (`<Text>`)

Render the segments as nested `<Text>` runs; React Native handles RTL within `<Text>`. Set `writingDirection: "rtl"` and an Arabic-capable font.

```jsx
import { Text } from "react-native";

function TajweedAyah({ surah, ayah, annotations }) {
  const text = engine.quran.ayah(surah, ayah).textArabic;
  const segments = tajweedSegments(text, annotations);
  return (
    <Text style={{ fontSize: 28, writingDirection: "rtl", textAlign: "right" }}>
      {segments.map((s, i) => (
        <Text key={i} style={s.color ? { color: s.color } : undefined}>{s.text}</Text>
      ))}
    </Text>
  );
}
```

## Audio with `expo-av`

```bash
npx expo install expo-av
```

```jsx
import { Audio } from "expo-av";
import { surahAudioUrl, ayahAudioUrl } from "@quran-tajweed-engine/core";

async function playSurah(surah) {
  const reciter = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");
  const { sound } = await Audio.Sound.createAsync(
    { uri: surahAudioUrl(reciter, surah) },
    { shouldPlay: true }
  );
  return sound; // remember to sound.unloadAsync() on unmount
}

// Verse-by-verse with auto-advance
async function playAyahByAyah(surahId) {
  const reciter = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");
  const surah = engine.quran.surah(surahId);
  const urls = surah.ayahs.map((a) => ayahAudioUrl(reciter, engine.quran.globalAyahNumber(surahId, a.id)));
  const sound = new Audio.Sound();
  let i = 0;
  const load = async () => { await sound.unloadAsync().catch(() => {}); await sound.loadAsync({ uri: urls[i] }, {}, false); await sound.playAsync(); };
  sound.setOnPlaybackStatusUpdate((st) => { if (st.didJustFinish && ++i < urls.length) load(); });
  await load();
  return sound;
}
```

## Offline caching with `expo-file-system` (the `CacheStore` interface)

The engine's `AudioCache` ([08-caching.md](../08-caching.md)) is storage-agnostic: implement the `CacheStore` interface over `expo-file-system` and the path helpers do the rest. Only **full-surah** audio is cached in the reference app; ayah audio is streamed.

```js
import * as FileSystem from "expo-file-system";
import { AudioCache, surahAudioUrl, localSurahPath } from "@quran-tajweed-engine/core";

const ROOT = FileSystem.documentDirectory + "quran-audio/";

// CacheStore: has / get / put / delete, keyed by the engine's cache path (localSurahPath).
function expoFileStore() {
  const safe = (key) => ROOT + encodeURIComponent(key);          // flatten the path to a single file name
  return {
    async has(key) { return (await FileSystem.getInfoAsync(safe(key))).exists; },
    async get(key) {
      const info = await FileSystem.getInfoAsync(safe(key));
      if (!info.exists) return null;
      const b64 = await FileSystem.readAsStringAsync(safe(key), { encoding: FileSystem.EncodingType.Base64 });
      return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
    },
    async put(key, data) {
      await FileSystem.makeDirectoryAsync(ROOT, { intermediates: true }).catch(() => {});
      const bytes = new Uint8Array(data);
      let bin = ""; for (const b of bytes) bin += String.fromCharCode(b);
      await FileSystem.writeAsStringAsync(safe(key), btoa(bin), { encoding: FileSystem.EncodingType.Base64 });
    },
    async delete(key) { await FileSystem.deleteAsync(safe(key), { idempotent: true }); },
  };
}

const cache = new AudioCache(expoFileStore());     // AudioCache needs a global fetch (RN provides one)
const reciter = engine.reciters.all().find((r) => r.name === "Mishary Alafasy");

// Download once, reuse offline. localSurahPath(reciter, 36) is the canonical cache key.
const bytes = await cache.surah(reciter, 36, surahAudioUrl(reciter, 36));
await cache.hasSurah(reciter, 36);                 // true
// To play from a cached file, write it to a uri expo-av can read, then pass that uri to Audio.Sound.
```

> `AudioCache` uses the global `fetch` (available in RN) and the canonical keys from `localSurahPath`. If you prefer, mirror the on-disk layout in [08-caching.md](../08-caching.md) literally instead of flattening keys.

## See also

- [recipes.md](../recipes.md) — #2 (tajweed), #4–6 (audio), #14 (offline cache).
- [02-tajweed.md](../02-tajweed.md) (corpus strategy A) · [architecture.md](../architecture.md) (two ways to do tajweed)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md) · [08-caching.md](../08-caching.md)
- [`quran-engine-js` README](../../packages/quran-engine-js/README.md)
