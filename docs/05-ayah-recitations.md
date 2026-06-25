# 05 · Ayah recitations (ayah-by-ayah audio)

Play a single ayah — for verse-by-verse listening, repeat drills, and custom ranges. This feed is
**separate** from full-surah audio (doc 04) and uses a different CDN.

## URL template

```
ayahAudioUrl(reciter, globalAyahNumber) =
  "https://cdn.islamic.network/quran/audio/" + reciter.ayahBitrate + "/" + reciter.ayahIdentifier + "/" + globalAyahNumber + ".mp3"
```

The CDN is **alquran.cloud** (`cdn.islamic.network`). Unlike everyayah.com (which uses zero-padded
`SSSAAA.mp3`), this CDN addresses each ayah by its **global number** (1..6236) with **no padding**:

```
globalAyahNumber(surah, ayah) = (sum of numberOfAyahs of all surahs before `surah`) + ayah
```

```js
import { ayahAudioUrl } from "@quran-tajweed-engine/core";
const g = engine.quran.globalAyahNumber(2, 1);          // 8  (after al-Fatiha's 7 ayahs)
ayahAudioUrl(alafasy, g);  // "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"
```

`ayahBitrate` and `ayahIdentifier` are inserted verbatim as strings.

## Minshawi fallback

Many reciters have a full-surah feed but **no ayah-by-ayah feed of their own**. In the data these are
defined with `ayahIdentifier: "ar.minshawi"` and `ayahBitrate: "128"`, so their ayah URLs resolve to
the **Minshawi (Murattal)** feed automatically.

To keep the now-playing label honest, display the fallback name during ayah playback:

```js
import { defaultsToMinshawi, ayahNowPlayingName } from "@quran-tajweed-engine/core";
defaultsToMinshawi(reciter);     // true if ayahIdentifier contains "minshawi" and name doesn't
ayahNowPlayingName(reciter);     // "Muhammad Al-Minshawi (Murattal)" when falling back
```

## Playback features (host-app responsibilities)

The engine builds URLs; the reference app layers on:

- **Continuous ayah play** — auto-advance ayah→ayah within a surah (queue depth ≥ 2 buffered).
- **Repeat** — per-ayah and per-section repeat counts.
- **Custom range** — play ayahs `[start..end]`, each repeated *n* times, the whole section repeated *m* times.
- **Resume** — persist last-listened ayah and seek back to it.

These are straightforward to build on top of `ayahAudioUrl` + a queueing audio player in any framework
(`<audio>`, AVQueuePlayer, ExoPlayer, expo-av, Web Audio).

Reference: [`src/audio.js`](../packages/quran-engine-js/src/audio.js).
