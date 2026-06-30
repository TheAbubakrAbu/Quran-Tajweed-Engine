# 08 · Caching & offline downloads

Optional layer for offline full-surah audio. The engine stays **storage-agnostic**: it gives you the canonical cache paths/keys and a small `CacheStore` interface; you plug in any backend (filesystem, IndexedDB, React-Native FS, the browser Cache API). Mirrors `ReciterDownloadManager` in `QuranPlayer.swift`.

> Only **full-surah** audio is cached in the reference app. Ayah-by-ayah audio is streamed.

## Layout

```
<root>/<sanitize(reciter.id)>/<zeroPad3(surah)>.mp3     per-reciter file
<root>/SharedAudio/<sha256hex(content)>.<ext>           content-addressed dedup store
```

- `sanitize(reciter.id)`: keep `[A-Za-z0-9-_]`, replace everything else with `_`, cap at 180 chars. Recall `reciter.id = "{name}|{qiraah??Hafs}|{surahLink}"`, so `|`, `/`, `:`, `.` all become `_`.
- Per-surah filename is the surah number zero-padded to 3 digits.
- **Content-addressed dedup**: each downloaded file is stored once in `SharedAudio/` keyed by the SHA-256 of its bytes, and each reciter's `NNN.mp3` is a hard link to it. Identical audio shared across reciters is stored once. (Hard-linking is a filesystem optimization; a browser/IndexedDB backend can skip it.)

## Path helpers

```js
import { localSurahPath, sharedAudioPath, sanitizeReciterDir } from "@quran-tajweed-engine/core";

localSurahPath(reciter, 57);                 // "Mishary_Alafasy_Hafs_https___.../057.mp3"
sanitizeReciterDir(reciter.id);              // filesystem-safe folder name
sharedAudioPath("<sha256hex>");              // "SharedAudio/<sha256hex>.mp3"
```

## `CacheStore` interface + `AudioCache`

```ts
interface CacheStore {
  has(key: string): Promise<boolean>;
  get(key: string): Promise<ArrayBuffer | Uint8Array | null>;
  put(key: string, data: ArrayBuffer | Uint8Array): Promise<void>;
  delete(key: string): Promise<void>;
}
```

```js
import { AudioCache, memoryStore, surahAudioUrl } from "@quran-tajweed-engine/core";

const cache = new AudioCache(memoryStore());               // or your own store
const url = surahAudioUrl(reciter, 57);
const bytes = await cache.surah(reciter, 57, url);          // cached → returned; else fetched + stored
await cache.hasSurah(reciter, 57);                          // true
await cache.removeSurah(reciter, 57);
```

`AudioCache` works in any environment with `fetch` (browser, Node 18+, Deno, Bun) — pass `{ fetch }` to inject one explicitly. `memoryStore()` is provided for tests and ephemeral use.

## Backend sketches

- **Browser**: implement `CacheStore` over IndexedDB (key → Blob) or the Cache API.
- **React Native / Expo**: over `expo-file-system` / `react-native-fs`, mirroring the path layout.
- **Node / server**: write files under a root dir using `localSurahPath` as the relative path.

## In-app playback prefetch (not persisted)

For gapless playback the reference app also prewarms the next surah ~10 s before the current ends and keeps current+next ayah items buffered. That's a playback concern, not a cache concern — build it in your player.

Reference: [`src/cache.js`](../packages/quran-engine-js/src/cache.js).
