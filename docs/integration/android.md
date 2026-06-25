# Android (Jetpack Compose)

Use **`quran-engine-kotlin`** in an Android app. It's a thin, idiomatic wrapper over the JSON in
[`/data`](../../data) plus a few pure functions — no network, database, or framework required (audio is just
URL strings). Tajweed uses the pre-computed annotation corpus (strategy A); JVM `String` is UTF-16, so
offsets slice directly.

## Setup

Depend on the module (or copy the `com.quranengine` sources in). The port needs
`kotlinx-serialization-json`:

```kotlin
// app/build.gradle.kts
plugins { kotlin("plugin.serialization") }
dependencies {
    implementation(project(":quran-engine-kotlin"))   // or your module/coordinate
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
}
```

On older `minSdk`, enable core-library desugaring for `java.time`/`Charsets` as needed.

## Loading data from `assets/`

`Engine.load(dataDir: File?)` reads from a filesystem directory, so copy the bundled assets into the app's
files dir on first launch, then load from there. Put the `/data` JSON under `app/src/main/assets/data/`.

```kotlin
import android.content.Context
import com.quranengine.Engine
import java.io.File

fun loadEngine(context: Context): Engine {
    val dataDir = File(context.filesDir, "data")
    if (!dataDir.exists()) copyAssetDir(context, "data", dataDir)
    return Engine.load(dataDir)
}

private fun copyAssetDir(context: Context, assetPath: String, outDir: File) {
    val am = context.assets
    val children = am.list(assetPath) ?: emptyArray()
    if (children.isEmpty()) {                       // it's a file
        outDir.parentFile?.mkdirs()
        am.open(assetPath).use { input -> outDir.outputStream().use { input.copyTo(it) } }
        return
    }
    outDir.mkdirs()                                 // it's a directory
    for (c in children) copyAssetDir(context, "$assetPath/$c", File(outDir, c))
}
```

Build the engine once (e.g. in your `Application`, a DI singleton, or a `remember`/`ViewModel`) and reuse
it — decoding `quran.json` is the heaviest step.

## Minimal working example (Compose)

```kotlin
import androidx.compose.runtime.*
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.*
import androidx.compose.ui.platform.LocalContext

@Composable
fun AyahScreen(surah: Int = 1, ayah: Int = 1) {
    val context = LocalContext.current
    val engine = remember { loadEngine(context) }

    Column(Modifier.padding(16.dp)) {
        Text(engine.quran.surah(surah)?.nameEnglish ?: "")
        TajweedAyah(engine, surah, ayah)
        Text(engine.quran.ayah(surah, ayah)?.textEnglishSaheeh ?: "")
    }
}
```

## Tajweed rendering with `AnnotatedString`

`engine.tajweed(surah, ayah)` returns `List<TajweedSpan>`, each with `start`, `end`, `rule`, `colorHex`
(`"#RRGGBB"`, nullable), and the reconstructed `text`. Spans cover only the colored parts, in order and
non-overlapping — fill the gaps. Build an `AnnotatedString` and color each run with a `SpanStyle`:

```kotlin
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextAlign
import com.quranengine.Engine

@Composable
fun TajweedAyah(engine: Engine, surah: Int, ayah: Int) {
    val text = engine.quran.ayah(surah, ayah)?.textArabic ?: ""
    val spans = engine.tajweed(surah, ayah)        // [{ start, end, rule, colorHex, text }]

    val annotated: AnnotatedString = buildAnnotatedString {
        var cursor = 0
        for (s in spans) {
            if (s.start > cursor) append(text.substring(cursor, s.start))   // uncolored gap
            val hex = s.colorHex
            if (hex != null) {
                withStyle(SpanStyle(color = Color(android.graphics.Color.parseColor(hex)))) {
                    append(text.substring(s.start, s.end))
                }
            } else {
                append(text.substring(s.start, s.end))
            }
            cursor = s.end
        }
        if (cursor < text.length) append(text.substring(cursor))
    }

    BasicText(
        text = annotated,
        style = TextStyle(fontSize = 28.sp, textAlign = TextAlign.End, textDirection = TextDirection.Rtl),
    )
}
```

`TajweedSpan.start`/`end` are UTF-16 code-unit offsets; Kotlin/JVM `String` is UTF-16, so
`text.substring(start, end)` slices on the same units — no conversion. See [02-tajweed.md](../02-tajweed.md).

## Audio with `ExoPlayer` (or `MediaPlayer`)

URLs come from the free functions `surahAudioUrl` / `ayahAudioUrl`. The engine never fetches audio.

```kotlin
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.MediaItem
import com.quranengine.Engine
import com.quranengine.surahAudioUrl
import com.quranengine.ayahAudioUrl

fun playSurah(player: ExoPlayer, engine: Engine, surah: Int) {
    val reciter = engine.reciters.all().first { it.name == "Mishary Alafasy" }
    player.setMediaItem(MediaItem.fromUri(surahAudioUrl(reciter, surah)))  // full-surah mp3
    player.prepare()
    player.play()
}

fun playAyahByAyah(player: ExoPlayer, engine: Engine, surahId: Int) {
    val reciter = engine.reciters.all().first { it.name == "Mishary Alafasy" }
    val surah = engine.quran.surah(surahId)!!
    val items = surah.ayahs.map { a ->
        MediaItem.fromUri(ayahAudioUrl(reciter, engine.quran.globalAyahNumber(surahId, a.id)))
    }
    player.setMediaItems(items)          // ExoPlayer auto-advances through the playlist
    player.prepare()
    player.play()
}
```

With `MediaPlayer` the equivalent is `MediaPlayer().apply { setDataSource(surahAudioUrl(reciter, surah)); prepareAsync(); setOnPreparedListener { it.start() } }`.

## See also

- [recipes.md](../recipes.md) — #2 (tajweed), #4–6 (audio).
- [02-tajweed.md](../02-tajweed.md) · [01-quran.md](../01-quran.md) · [06-ayah-search.md](../06-ayah-search.md)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md) · [08-caching.md](../08-caching.md)
- [`quran-engine-kotlin` README](../../packages/quran-engine-kotlin/README.md)
