package com.quranengine

/**
 * Tajweed coloring via strategy (A) from `docs/PORTING.md`: consume the pre-computed annotation corpus
 * (`data/tajweed/NNN.json` / `tajweed-annotations.json`) and map each `rule` to its `colorHex` from
 * `tajweed-rules.json`. No detection logic, so it is small and exactly consistent with the reference.
 *
 * Annotation `start`/`end` are UTF-16 code-unit offsets. Kotlin/JVM `String` is UTF-16 internally, so
 * `text.substring(start, end)` slices on the same units the reference engine uses — no conversion needed.
 */
class Tajweed(
    private val annotationsByKey: Map<Pair<Int, Int>, List<TajweedAnnotation>>,
    private val colorsByRule: Map<String, String>,
) {
    /** Resolve the colored spans for an ayah given its (UTF-16) text. */
    fun spans(surahId: Int, ayahId: Int, ayahText: String): List<TajweedSpan> {
        val anns = annotationsByKey[surahId to ayahId] ?: return emptyList()
        return anns.map { a ->
            // start/end are UTF-16 offsets; JVM String is UTF-16, so substring is a direct slice.
            val safeEnd = minOf(a.end, ayahText.length)
            val safeStart = a.start.coerceIn(0, safeEnd)
            TajweedSpan(
                start = a.start,
                end = a.end,
                rule = a.rule,
                text = ayahText.substring(safeStart, safeEnd),
                colorHex = colorsByRule[a.rule],
            )
        }
    }
}
