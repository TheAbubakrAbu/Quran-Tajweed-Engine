# iOS / macOS (SwiftUI)

Use **`quran-engine-swift`** in a SwiftUI app. It's a thin, idiomatic wrapper over the JSON in [`/data`](../../data) plus a few pure functions — no network, database, or framework required. Tajweed uses the pre-computed annotation corpus (strategy A), so coloring is exact and offsets slice natively.

## Setup

Add the SwiftPM package. As a local package dependency:

```swift
// Package.swift
dependencies: [
    .package(path: "../quran-engine-swift")
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and point at the `quran-engine-swift` directory (or its git URL). Then `import QuranEngine`.

Bundle the `/data` JSON in your app target (drag the `data` folder into Xcode as a *folder reference* so it keeps its structure) and point the loader at it with `dataDirectory:`.

## Minimal working example (canonical load + a SwiftUI view)

`Engine.load` resolves `/data` from an explicit `dataDirectory:`, the `QURAN_ENGINE_DATA` env var, or the repo path. In an app, pass the bundle URL of your bundled data folder:

```swift
import SwiftUI
import QuranEngine

@MainActor
final class QuranStore: ObservableObject {
    let engine: Engine
    init() {
        // `data` bundled as a folder reference → Bundle.main.url(forResource:withExtension:)
        let dataURL = Bundle.main.url(forResource: "data", withExtension: nil)
        engine = try! Engine.load(dataDirectory: dataURL)
    }
}

struct AyahScreen: View {
    @StateObject private var store = QuranStore()
    let surah = 1, ayah = 1

    var body: some View {
        let q = store.engine.quran
        VStack(alignment: .trailing, spacing: 12) {
            Text(q.surah(surah)?.nameEnglish ?? "")
                .font(.headline)
            TajweedText(engine: store.engine, surah: surah, ayah: ayah)
            Text(q.ayah(surah, ayah)?.textEnglishSaheeh ?? "")
                .font(.subheadline)
        }
        .padding()
    }
}
```

## Tajweed rendering with `AttributedString`

`engine.tajweed.tajweedSpans(surah, ayah)` returns `[TajweedSpan]`, each with `start`, `end`, `rule`, `colorHex` (`"#RRGGBB"`, optional), and the reconstructed `text`. The spans cover only the *colored* parts, in order and non-overlapping — fill the gaps with the surrounding text. Build an `AttributedString` and set the foreground color per run:

```swift
import SwiftUI
import QuranEngine

extension Color {
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct TajweedText: View {
    let engine: Engine
    let surah: Int
    let ayah: Int

    var body: some View {
        // Build the string segment-by-segment so gaps and colored runs stay in order.
        Text(buildAttributed())
            .font(.system(size: 30))
            .multilineTextAlignment(.trailing)
            .environment(\.layoutDirection, .rightToLeft)   // RTL
    }

    private func buildAttributed() -> AttributedString {
        let text = engine.quran.arabicText(surah, ayah) ?? ""
        let utf16 = Array(text.utf16)
        var out = AttributedString()
        var cursor = 0
        for span in engine.tajweed.tajweedSpans(surah, ayah) {
            if span.start > cursor {
                out += AttributedString(String(decoding: utf16[cursor..<span.start], as: UTF16.self))
            }
            var run = AttributedString(span.text)            // already the [start,end) slice
            if let hex = span.colorHex, let color = Color(hex: hex) { run.foregroundColor = color }
            out += run
            cursor = span.end
        }
        if cursor < utf16.count {
            out += AttributedString(String(decoding: utf16[cursor...], as: UTF16.self))
        }
        return out
    }
}
```

`TajweedSpan.start`/`end` are UTF-16 offsets and `span.text` is already the reconstructed `[start, end)` slice — Swift `String` indexes natively via `String.Index(utf16Offset:in:)`, so no conversion is needed. See [02-tajweed.md](../02-tajweed.md).

## Audio with `AVPlayer`

URLs come from the free functions `surahAudioURL` / `ayahAudioURL`. The engine never fetches audio.

```swift
import AVFoundation
import QuranEngine

final class AudioController: ObservableObject {
    private var player: AVPlayer?

    func playSurah(_ engine: Engine, _ surah: Int) throws {
        guard let reciter = engine.reciters.all().first(where: { $0.name == "Mishary Alafasy" }) else { return }
        let url = try surahAudioURL(reciter, surah)              // full-surah mp3
        player = AVPlayer(url: URL(string: url)!)
        player?.play()
    }

    func playAyah(_ engine: Engine, surah: Int, ayah: Int) {
        guard let reciter = engine.reciters.all().first(where: { $0.name == "Mishary Alafasy" }) else { return }
        let g = engine.quran.globalAyahNumber(surah, ayah)
        let url = ayahAudioURL(reciter, g)                       // single-ayah mp3
        player = AVPlayer(url: URL(string: url)!)
        player?.play()
    }
}
```

For verse-by-verse auto-advance, observe `AVPlayerItemDidPlayToEndTime` and load the next global ayah's URL.

## See also

- [recipes.md](../recipes.md) — #2 (tajweed), #4–6 (audio).
- [02-tajweed.md](../02-tajweed.md) · [01-quran.md](../01-quran.md) · [06-ayah-search.md](../06-ayah-search.md)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md) · [08-caching.md](../08-caching.md)
- [`quran-engine-swift` README](../../packages/quran-engine-swift/README.md)
