# quran-engine-kotlin

The **Kotlin** port of the open-source *Quran Tajweed Engine* — usable on **Android & JVM**. It is a thin, idiomatic wrapper over the JSON data in [`../../data`](../../data) plus a handful of pure functions. No network calls, no database, no framework.

This port follows the shared contract in [`../../docs/PORTING.md`](../../docs/PORTING.md) and the per-feature specs in `../../docs/01…08`. The reference implementation is the JS port in [`../quran-engine-js`](../quran-engine-js).

## Requirements

- Kotlin 1.9+, JVM 17+ (Android `minSdk` with desugaring as needed)
- [`kotlinx-serialization-json`](https://github.com/Kotlin/kotlinx.serialization)

## Install / build

This is a standard Gradle Kotlin (JVM) project:

```bash
./gradlew build      # compile
./gradlew test       # run the canonical-cases test
```

To consume it in another project, either depend on this module or copy the `src/main/kotlin/com/quranengine` sources in.

## Usage

```kotlin
import com.quranengine.*
import java.io.File

// Locate the repo /data automatically (walks up for data/quran.json), or pass a File.
val engine = Engine.load()                       // or Engine.load(File("/path/to/data"))

// --- Quran ---
engine.quran.totalAyahs                           // 6236
engine.quran.surah(1)?.nameEnglish                // "The Opener"
engine.quran.ayah(2, 255)?.textArabic             // Ayat al-Kursi
engine.quran.globalAyahNumber(2, 1)               // 8
engine.quran.arabicText(1, 1)                     // Hafs text (or a riwayah override)
engine.quran.cleanArabicText(1, 1)                // diacritics stripped

// --- Juz / Page ---
engine.juzPage.juz(30)?.endSurah                  // 114
engine.juzPage.firstAyahOfJuz(2)
engine.juzPage.totalPages()

// --- Audio URLs ---
val alafasy = engine.reciters.all().first { it.ayahIdentifier == "ar.alafasy" }
surahAudioUrl(alafasy, 1)                          // https://server8.mp3quran.net/afs/001.mp3
ayahAudioUrl(alafasy, 8)                           // https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3

// --- Sorting ---
sortSurahs(engine.quran.all(), "ayahs", "descending")[0].id   // 2 (Al-Baqarah, 286 ayahs)
filterByRevelationType(engine.quran.all(), "makkan")

// --- Search ---
engine.search.searchVerses("mercy")               // verses (mushaf order, unranked)
engine.search.searchSurahs("baqarah")             // surahs by name / number / makkan-madani
engine.search.parseReference("2:255")             // AyahReference(surah=2, ayah=255)

// --- Tajweed (strategy A: pre-computed annotations + rule -> colorHex) ---
for (span in engine.tajweed(1, 1)) {
    println("${span.rule} ${span.colorHex} '${span.text}'")
}

// --- Caching paths (storage backend is host-specific) ---
sanitizeReciterDir(alafasy.id)
localSurahPath(alafasy, 1)                         // "<sanitized-id>/001.mp3"
```

### Android / bundled data

Ports locate `/data` relative to the repo root *or* accept an injected directory, so the same code works when the data is bundled as an app asset: copy the `data` files into the app's files dir and call `Engine.load(File(context.filesDir, "data"))`.

## Tajweed strategy

This port uses **strategy (A)** from `docs/PORTING.md`: it loads the pre-computed annotation corpus (`data/tajweed-annotations.json`, also available per-surah under `data/tajweed/NNN.json`) and maps each annotation `rule` to its `colorHex` in `data/tajweed-rules.json`. Annotation `start`/`end` are UTF-16 code-unit offsets; Kotlin/JVM `String` is UTF-16, so `text.substring(start, end)` slices on exactly the same units the reference engine uses — no conversion is required. The full detector (strategy B) is not ported here.

## What is omitted

The **core** search path is implemented: the Arabic/English fold (`cleanSearch`), substring + phrase-prefix matching, digit-rejection for verse search, mushaf-order results, and surah search by name / number / `2:255` reference / makkan-madani. Per `docs/PORTING.md`, the following are intentionally **not** ported (a minimal port may skip them):

- the **boolean grammar** (`& | ! # ^ % $`);
- the **lenient "silent letters ignored"** Arabic search variant;
- the exact-phrase / tashkeel blob indices.

Everything else in the "core" contract (Load, Quran, Tajweed via annotations, Juz/Page, audio URLs, sorting, reference parsing) is implemented.

## Canonical cases

`src/test/kotlin/com/quranengine/EngineTest.kt` asserts the reference cases from `docs/PORTING.md` (`totalAyahs == 6236`; global ayah numbers; the two audio URLs; juz boundaries; `sortSurahs("ayahs", "descending")[0].id == 2`; `parseReference("2:255")`; and that every tajweed span's `text` equals the recorded UTF-16 slice). The test locates the data dir by walking up from the working directory.

## License & attribution

MIT. See [`../../LICENSE`](../../LICENSE).

All data and algorithms are extracted from the open-source **Al-Islam | Islamic Pillars** app by **Abubakr Elmallah** (MIT, © 2025). Please preserve the attribution in [`../../CREDITS.md`](../../CREDITS.md) in any redistribution — including the Quran text (Hafs an Asim Uthmani), translations (Saheeh International; Dr. Mustafa Khattab, *The Clear Quran*), and the audio CDN providers (mp3quran.net; alquran.cloud / cdn.islamic.network).
