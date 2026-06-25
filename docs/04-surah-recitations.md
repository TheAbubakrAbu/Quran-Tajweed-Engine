# 04 · Surah recitations (full-surah audio)

Stream a whole surah from a reciter. URLs are built from the reciter directory in
[`data/reciters.json`](../data/reciters.json) (62 reciters across 8 riwayat).

## Reciter schema

```jsonc
{
  "id": "Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/",  // "{name}|{qiraah??Hafs}|{surahLink}"
  "name": "Mishary Alafasy",
  "ayahIdentifier": "ar.alafasy",       // used by ayah-by-ayah audio (doc 05)
  "ayahBitrate": "128",                  // string, used verbatim in the ayah URL
  "surahLink": "https://server8.mp3quran.net/afs/",  // full-surah CDN base, trailing slash
  "qiraah": null,                        // null => Hafs; else a riwayah label (e.g. "Warsh an Nafi")
  "group": "Murattal"
}
```

## URL template

```
surahAudioUrl(reciter, surahNumber) = reciter.surahLink + zeroPad3(surahNumber) + ".mp3"
```

`surahNumber` is zero-padded to **3 digits** (`1 → "001"`, `57 → "057"`, `114 → "114"`). `surahLink`
already ends with `/`. Valid range `1..114`.

```js
import { surahAudioUrl } from "@quran-tajweed-engine/core";
surahAudioUrl(alafasy, 1);  // "https://server8.mp3quran.net/afs/001.mp3"
```

## Reciter directory helpers

```js
engine.reciters.all();                 // all 62, sorted by name
engine.reciters.withSurahFeed();       // reciters that have a full-surah feed
engine.reciters.byQiraah("Warsh an Nafi");  // Warsh reciters
engine.reciters.qiraat();              // distinct non-Hafs riwayah labels
engine.reciters.byId(id);              // exact lookup
```

## Riwayat available

Default **Hafs an Asim**, plus **Warsh**, **Qaloon**, **ad-Duri**, **as-Susi**, **al-Bazzi**, **Qunbul**,
**Shubah**, **Khalaf**. Groups in the data: `Minshawi`, `Murattal`, `Mujawwad`, `Muallim`, and the
per-riwayah groups.

## Caveats

- A few rows historically embed a full per-file URL in `surahLink` (ending in `.mp3`). Normalize any
  reciter table you author so `surahLink` is always a directory ending in `/`; `withSurahFeed()` filters
  out the malformed `.mp3`-ending entries.
- All audio is hosted on `mp3quran.net` CDNs. The engine only builds URLs — playback, prefetch, and
  gapless hand-off are the host app's concern (see doc 08 for caching).

Reference: [`src/audio.js`](../packages/quran-engine-js/src/audio.js).
