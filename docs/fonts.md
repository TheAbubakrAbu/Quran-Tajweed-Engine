# Fonts

The engine bundles three Quran display fonts in [`data/fonts/`](../data/fonts) so your app renders the Arabic exactly as intended. Metadata (file, PostScript name, credit) is in [`data/fonts/fonts.json`](../data/fonts/fonts.json).

| Font | File | PostScript name | Script | Best for |
|---|---|---|---|---|
| **Uthmani (Hafs)** | `Uthmani.ttf` | `KFGQPCHAFSUthmanicScript-Regula` | Uthmani | Default · **tajweed coloring** |
| **Qiraat (Qunbul)** | `Qiraat.ttf` | `KFGQPCQUMBULUthmanicScript-Regu` | Uthmani | The 7 alternate **qiraat readings** |
| **Indopak (Nastaliq)** | `Indopak.ttf` | `Al_Mushaf` | Indopak | South-Asian readers |

## Which font should I use?

### Uthmani — the default, and best for tajweed
`Uthmani.ttf` (KFGQPC Hafs Uthmanic Script) has **crisp, well-separated letters and marks**, which makes per-letter tajweed coloring clean: each colored span lands on exactly the glyph it should. Use it for the bundled Hafs text and anywhere you apply the [tajweed engine](02-tajweed.md). The pre-computed tajweed corpus and its UTF-16 offsets are calibrated against this text.

### Qiraat — for the non-Hafs readings
The standard `Uthmani.ttf` doesn't contain every glyph/mark used by the other qiraat. `Qiraat.ttf` (KFGQPC Qunbul Uthmanic Script) is an Uthmani-style font that **does** support those characters, so it can display the readings in [`data/qiraat/`](../data/qiraat) (Warsh, Qaloon, Duri, Susi, al-Bazzi, Qunbul, Shubah) correctly.

> **Trade-off:** because Qiraat.ttf packs more marks per glyph, its diacritics tend to **blend/overlap**, which makes per-letter tajweed coloring messier than with Uthmani.ttf. Rule of thumb: **Uthmani for Hafs + tajweed colors; Qiraat when you need to show another riwayah.**

### Indopak — the South-Asian style
`Indopak.ttf` (Al Mushaf / Nastaliq) is the writing style familiar across the Indian subcontinent. It uses different orthographic conventions, and the bundled tajweed offsets are computed against the Uthmani text, so treat Indopak as a reading font rather than a tajweed-coloring font.

## How to register and use a font

The key is the **PostScript name** — that's what you pass to your text API after loading the TTF.

### Web / CSS
```css
@font-face {
  font-family: "QuranUthmani";
  src: url("/fonts/Uthmani.ttf") format("truetype");
}
.ayah { font-family: "QuranUthmani"; direction: rtl; font-size: 2rem; line-height: 2.4; }
```

### iOS / SwiftUI
Add the TTF to the app bundle (and list it under `UIAppFonts` in Info.plist), then:
```swift
Text(ayah.textArabic)
    .font(.custom("KFGQPCHAFSUthmanicScript-Regula", size: 28))
```

### Android / Compose
Place the TTF in `res/font/` and:
```kotlin
val uthmani = FontFamily(Font(R.font.uthmani))
Text(text = ayahText, fontFamily = uthmani, fontSize = 28.sp)
```

### Flutter
Declare the font in `pubspec.yaml` under `flutter: fonts:` and:
```dart
Text(ayahText, style: TextStyle(fontFamily: 'Uthmani', fontSize: 28));
```

## Pairing fonts with tajweed coloring

1. Render the ayah with **Uthmani.ttf**.
2. Get the spans from the [tajweed engine / corpus](02-tajweed.md).
3. Color each span's slice (see [recipes #2](recipes.md)). Because the offsets match the Uthmani text, the colors land precisely.

For the qiraat readings, render with **Qiraat.ttf** and color more coarsely (word-level), since the marks blend.

## Licensing

These fonts are the work of their authors and are included for convenience under the terms by which they were published for Quranic use:

- **Uthmani & Qiraat** — King Fahd Glorious Quran Printing Complex (KFGQPC). Source: [qul.tarteel.ai/resources/font/245](https://qul.tarteel.ai/resources/font/245), [quran-data-kfgqpc](https://github.com/thetruetruth/quran-data-kfgqpc).
- **Indopak (Al Mushaf)** — Ayman Siddiqui and R. Siddiqua. Source: [qul.tarteel.ai/resources/font/242](https://qul.tarteel.ai/resources/font/242).

See [CREDITS.md](../CREDITS.md). If you redistribute the fonts, follow the original publishers' terms.
