# 02 · Tajweed engine

A scalar-driven engine that classifies and colors tajweed rules directly from the Uthmani text — no
pre-annotated corpus required. This is the most intricate part of the engine; this document is the full
specification so it can be re-implemented in any language. The canonical reference implementation is
Al-Islam's `QuranData.swift` + `TajweedRules.swift`; the JS port lives in
[`src/tajweed.js`](../packages/quran-engine-js/src/tajweed.js).

The rule catalogue (categories, canonical colors, trigger letters) is shipped as data in
[`data/tajweed-rules.json`](../data/tajweed-rules.json).

## Output model

The engine turns an ayah's Arabic string into a list of **paint operations**, then resolves them into
non-overlapping **colored spans**:

```js
engine.tajweed("بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ");
// → [ { start, end, category: "hamzatWaslSilent", color: "#B4B4B4", text: "ٱ" },
//     { start, end, category: "lamShamsiyah",    color: "#B4B4B4", text: "ل" },
//     { start, end, category: "tafkhim",         color: "#3B85C2", text: "رَّ" }, ... ]
```

`start`/`end` are UTF-16 offsets into the input string, so `text.slice(start, end) === span.text`.

## Pipeline

1. **Cluster** the ayah into Unicode extended grapheme clusters (one base Arabic letter + its trailing
   combining marks). Use a UAX-#29 grapheme segmenter (`Intl.Segmenter` in JS, `Character` in Swift).
2. Each producer emits `PaintOp`s — a UTF-16 range, an integer **priority**, and a **category**.
3. Sort ops ascending by priority and apply per UTF-16 unit, so the **highest priority wins** on overlap.
4. A category is painted only if enabled and not stop-based (`maddSukoon` is computed but not painted by default).

The engine is **scalar-driven, never glyph-driven** — every decision is based on Unicode scalar values,
so results are font-independent and identical across platforms.

## Rule catalogue (17 categories)

Grouped into four sections. Each has a canonical color (see `data/tajweed-rules.json` for full copy).

### Silent / joining (gray `#B4B4B4`)
- **lamShamsiyah** — the `ل` of `ال` before a sun letter (`ت ث د ذ ر ز س ش ص ض ط ظ ل ن`).
- **droppedLetter** — written in the Uthmani script but not pronounced.
- **hamzatWaslSilent** — `ٱ` (U+0671), silent when connecting from a previous word.
- **idghamBilaGhunnah** — noon/tanwin merged without nasalization, before `ل ر`.

### Ghunnah / nasal (2 counts)
- **idghamGhunnah** `#45BC73` — merge with nasal, before `ي ن م و`.
- **generalGhunnah** `#45BC73` — `ن`/`م` with shadda; also nasal-merge targets.
- **ikhfaaLight** `#45BC73` — partial hide before `ت ث ج د ذ ز س ش ف ك`.
- **ikhfaaHeavy** `#1FAA94` — partial hide before `ص ض ط ظ ق`.
- **iqlaab** `#75B233` — noon/tanwin → meem sound before `ب`.

### Sifaat / articulation
- **qalqalah** `#78CCF9` — bounce on `ق ط ب ج د` when sukoon or stopped.
- **tafkhim** `#3B85C2` — heavy articulation on istila letters `خ ص ض ط ظ غ ق` (+ contextual `ر`).

### Madd / elongation
- **maddNatural** `#B98C2F` — 2 counts, on `ا و ي` after a matching vowel.
- **maddNaturalMiniature** `#B98C2F` — 2 counts, on superscript madd marks (dagger alif, small waw/yaa).
- **maddSukoon** `#E37935` — 2/4/6 counts, stop-based (aarid lis-sukoon / leen). *Detected, not painted by default.*
- **maddSeparated (Munfasil)** `#EB51AA` — 2/4/5 counts, madd letter ending a word + hamza starting the next.
- **maddConnected (Muttasil)** `#D9453E` — 4/5 counts, madd letter + hamza in the same word.
- **maddNecessary (Lazim)** `#AE2517` — 6 counts, madd + permanent sukoon/shadda.

## Key Unicode scalars

```
Madd letters (full):        alif U+0627, waw U+0648, yaa U+064A; alif-maqsura U+0649; alif-madda U+0622
Madd letters (superscript): dagger alif U+0670, small waw U+06E5, small yaa U+06E6, small high yaa U+06E7
Maddah (explicit madd):     U+0653
Hamza (base):               U+0621 U+0623 U+0624 U+0625 U+0626
Hamzat al-wasl:             U+0671 ٱ
Harakat / shadda / sukoon:  fatha U+064E, damma U+064F, kasra U+0650, shadda U+0651, sukoon U+0652
Tanwin:                     U+064B U+064C U+064D (+ Uthmani U+0657 U+065E U+0656)
Iqlaab/ikhfaa tiny marks:   small high meem U+06E2, small low meem U+06ED
Waqf ornaments:             U+06D6…U+06ED skipped for coloring EXCEPT {U+06E1,U+06E2,U+06E5,U+06E6,U+06ED}
```

## Priorities (highest wins)

```
tafkhim 1 · droppedLetter 2 · lamShamsiyah 3 · qalqalah 4 ·
idghamGhunnahLight 5 · idghamGhunnahHeavy 6 · ikhfaa 7 · iqlaab 8 · idghamBilaGhunnah 9 · generalGhunnah 10 ·
maddNatural2 12 · maddNaturalMiniature 13 · maddAarid 17 · maddNecessary6 18 · maddSeparated 19 · maddConnected 20 ·
explicitMuttasil 21 · explicitMunfasil 22 · explicitLazim 23 ·
hamzatWaslSilent 50 · tinyMeemIqlaab 51 · finalRaaTafkhim 52
```

## Noon / tanwin & meem tables

After **noon-sakin / tanwin**:

| Following letter | Rule |
|---|---|
| `ن` | idgham with ghunnah (target colored) |
| `م ي و` | idgham (split handling) |
| `ل ر` | idgham without ghunnah |
| `ب` | iqlaab |
| `ص ض ط ظ ق` | ikhfaa heavy |
| `ت ث ج د ذ ز س ش ف ك` | ikhfaa light |

After **meem-sakin**: `ب` → iqlaab (shafawi), `م` → idgham ghunnah. A helper alif/alif-maqsura after
fathatayn is skipped when looking for the governed letter.

## The explicit-maddah classifier

For any cluster carrying a maddah (U+0653) that isn't a final-aarid carrier or a tiny mark:

1. If the **next non-space cluster has a shadda** → Lazim (`maddNecessary`).
2. Else scan forward, skipping transparent marks and hamzat-wasl, tracking whether a word break occurred:
   - first hamza found → word break before it = **Munfasil**, else = **Muttasil**.
   - **Hukmi exception**: if the word is one of the 21 vocative/demonstrative `يَا`/`هَا` proper words
     *and* the carrier is a superscript madd letter, force **Munfasil** even inside one written word.
3. Else, superscript carrier → miniature natural madd.
4. Else → Lazim catch-all.

## Exceptions (what a naive engine gets wrong)

The full list is documented inline in `TajweedRules.swift` (the `TAJWEED ENGINE REFERENCE` block). The key ones:

- **Madd Munfasil Hukmi** — 21 exact words (`يَٰٓأَيُّهَا`, `هَٰٓؤُلَآءِ`, …) where a superscript carrier + hamza
  inside one word is recited Munfasil. A *real* madd letter + hamza elsewhere in the same word stays Muttasil.
- **Genuine Muttasil with a dagger alif** — `أُوْلَٰٓئِكَ`, `مَلَٰٓئِكَة`, `إِسۡرَٰٓءِيل` are ordinary Muttasil; the override is
  gated by the exact-word set, not the dagger alif alone.
- **Ayah-final lone madd** — read as natural madd at waqf, not the Lazim catch-all.
- **Madd 'Iwad** — a word ending in tanwin-fath has a silent final alif (2-count 'iwad at waqf, not aarid).
- **Muqatta'at** — disconnected opening letters; surah tables in `data/tajweed-rules.json`. Ash-Shura's
  letters span two ayahs.
- **Lazim Kalimi** — a madd letter immediately before shadda/permanent sukoon (`ٱلضَّآلِّينَ`) → 6 counts.
- **Final Raa tafkhim** — a word-final `ر` with tafkhim uses a dedicated higher priority.
- **Stop-based madd not painted** — `maddSukoon` is detected but kept out of painted text by default.

## Length summary (counts)

```
Natural · Miniature · Badal · 'Iwad · Tamkin · Silah-sughra ......... 2
Munfasil · Munfasil-Hukmi · Silah-kubra ............................ 2 / 4 / 5
Muttasil .......................................................... 4 / 5
Aarid lis-sukoon · Leen ........................................... 2 / 4 / 6
Lazim (Harfi & Kalimi) ............................................ 6 (fixed)
```

## Optional pre-annotated layer (`TajweedRules.json`)

The Swift engine also supports an optional bundled annotation file that overrides/augments the heuristic
output. Each entry is `{ surah, ayah, annotations: [{ start, end, rule }] }` where `start`/`end` are UTF-16
offsets and `rule` is a tag mapped via `treeDrivenRuleMap` (`madd_2`, `ikhfa`, `iqlaab`, …; see
`data/tajweed-rules.json`). **This file is not bundled** — the shipped engine is fully self-contained on
the heuristic path. If you generate such a corpus, the loader prefers it; otherwise the heuristics are authoritative.

## Port fidelity notes

The JS reference port covers all rule families above. Two areas are simplified relative to the Swift
source and should be validated before production use where exactness matters:

- **Final-raa vowel context** — reduced to the istila set + sukoon-inheritance (the Swift version has a
  fuller stopped-context rule).
- **Muqatta'at lazim-harfi sub-classification** — surahs are tracked via the tables but letter-name madd is
  not separately sub-typed.

For pixel-exact parity with the app, port the remaining helpers from `QuranData.swift` listed in the
inline reference. Everything needed to do so is enumerated there.
