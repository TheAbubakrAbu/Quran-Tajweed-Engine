import Foundation

/// Tajweed coloring via strategy (A): consume the pre-computed corpus.
///
/// Loads `tajweed-annotations.json` (an array of per-ayah records), and maps each annotation's
/// `rule` to a color from `tajweed-rules.json` → `categories[].colorHex`. Annotation `start`/`end`
/// are UTF-16 code-unit offsets into the ayah's `textArabic`; we slice with `String.Index`
/// constructed from UTF-16 offsets, which Swift handles natively.
public final class Tajweed {
    private let quran: Quran
    /// rule id -> colorHex
    private let colorByRule: [String: String]
    /// "surah:ayah" -> annotations
    private let annotationsByVerse: [String: [TajweedAnnotation]]

    init(quran: Quran, categories: [TajweedCategory], records: [TajweedAyahRecord]) {
        self.quran = quran
        var colors = [String: String]()
        for c in categories { colors[c.id] = c.colorHex }
        self.colorByRule = colors
        var byVerse = [String: [TajweedAnnotation]]()
        for r in records { byVerse["\(r.surah):\(r.ayah)"] = r.annotations }
        self.annotationsByVerse = byVerse
    }

    /// All tajweed categories' colors keyed by rule id.
    public func colorHex(forRule rule: String) -> String? { colorByRule[rule] }

    /// Colored spans for an ayah, in annotation order. Each span's `text` is the reconstructed
    /// UTF-16 slice `[start, end)` of the ayah's Arabic text — equal to what the JS engine produces.
    public func tajweedSpans(_ surahId: Int, _ ayahId: Int, riwayah: String? = nil) -> [TajweedSpan] {
        guard let text = quran.arabicText(surahId, ayahId, riwayah: riwayah),
              let annotations = annotationsByVerse["\(surahId):\(ayahId)"] else { return [] }

        let utf16Count = text.utf16.count
        var spans = [TajweedSpan]()
        spans.reserveCapacity(annotations.count)
        for a in annotations {
            let lo = max(0, min(a.start, utf16Count))
            let hi = max(lo, min(a.end, utf16Count))
            let slice: String
            if let s = String.Index(utf16Offset: lo, in: text) as String.Index?,
               let e = String.Index(utf16Offset: hi, in: text) as String.Index?,
               s <= e, e <= text.endIndex {
                slice = String(text[s..<e])
            } else {
                slice = ""
            }
            spans.append(TajweedSpan(start: a.start, end: a.end, rule: a.rule,
                                     colorHex: colorByRule[a.rule], text: slice))
        }
        return spans
    }
}
