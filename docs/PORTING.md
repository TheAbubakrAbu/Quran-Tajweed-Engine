# Porting guide, the shared contract

This is the single contract that **every language port** (`packages/quran-engine-*`) implements, so the API feels the same everywhere. If you're adding a new language, follow this document and the per-feature specs in `docs/01…08`.

The philosophy: **the data is the engine.** A port is a thin, idiomatic wrapper over the JSON in `/data` plus a handful of pure functions. Nothing here needs a network call, a database, or a framework.

## What a "core" port must provide

| Area | Functions / methods | Spec |
|---|---|---|
| **Load** | parse `quran.json`, `juz.json`, `reciters.json`, `tajweed-rules.json` (+ optional `surah-info.json`, `qiraat/*`, `tajweed-annotations.json`) | 01 |
| **Quran** | `surah(id)`, `ayah(surah, ayah)`, `globalAyahNumber(surah, ayah)`, `arabicText(surah, ayah, riwayah?)`, `cleanArabicText(...)`, iterate ayahs, `info(surah)`, `surahFromEnd(n)`, `isSajdahAyah(s,a)`, `sajdahAyahs()`, `pageChangesWithinSurah(id)`, `juzChangesWithinSurah(id)`, `pageOrJuzChangesWithinSurah(id)`, `existsInQiraah(s,a,riwayah)`, `numberOfAyahsInQiraah(s,riwayah)` | 01 |
| **Tajweed** | `tajweedSpans(surah, ayah)` → colored spans, by loading the pre-computed annotations and mapping `rule`→`colorHex`. (Full detector port is optional, see "Tajweed strategy".) | 02 |
| **Juz/Page** | `juz(id)`, `ayahsInJuz(n)`, `ayahsOnPage(n)`, `firstAyahOfJuz(n)`, `firstAyahOfPage(n)`, `juzForAyah(...)`, `pageForAyah(...)`, `totalPages()`, `juzFromEnd(n)`, `juzStats(n)` | 03 |
| **Surah audio** | `surahAudioUrl(reciter, surah)` = `surahLink + zeroPad3(surah) + ".mp3"` | 04 |
| **Ayah audio** | `ayahAudioUrl(reciter, globalAyah)` = `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3` | 05 |
| **Search** | `searchVerses(query, opts)`, `searchSurahs(query)`, `parseReference("2:255")` | 06 |
| **Sorting** | `sortSurahs(mode, direction)`, `filterByRevelationType(type)`, `filterByCounts({ayahs, pages})` | 07 |
| **Names of Allah** | `namesOfAllah.all()`, `byNumber(n)` over `names-of-allah.json` | 01 |
| **Muqaṭṭaʿāt** | `muqattaat.all()`, `pronunciation(s,a)`, `letterName(c)` over `muqattaat.json` | 01 |
| **Caching** | `localSurahPath(reciter, surah)`, `sanitizeReciterDir(id)` (storage backend is host-specific) | 08 |

A port is "complete" when it implements Load + Quran + Tajweed(via annotations) + Juz/Page + audio URLs + sorting + reference parsing. Search (full normalization) and caching are "extended", nice to have.

## Canonical formulas (copy these exactly)

```
zeroPad3(n)                  → "001", "057", "114"
globalAyahNumber(s, a)       → (Σ numberOfAyahs of surahs with id < s) + a       # 1..6236
surahAudioUrl(r, s)          → r.surahLink + zeroPad3(s) + ".mp3"
ayahAudioUrl(r, g)           → "https://cdn.islamic.network/quran/audio/" + r.ayahBitrate + "/" + r.ayahIdentifier + "/" + g + ".mp3"
sanitizeReciterDir(id)       → replace every char not in [A-Za-z0-9-_] with "_", cap 180 chars (fallback "reciter")
localSurahPath(r, s)         → sanitizeReciterDir(r.id) + "/" + zeroPad3(s) + ".mp3"
```

Reciter `id` = `"{name}|{qiraah or 'Hafs'}|{surahLink}"`. `qiraah` is null/absent for Hafs.

## Tajweed strategy (important)

Two ways to get tajweed colors. **Prefer (A)** for new ports, it's small, correct, and consistent:

- **(A) Consume the pre-computed corpus.** Load `data/tajweed/NNN.json` (or `tajweed-annotations.json`) take the ayah's `annotations`, and map each `rule` to `tajweed-rules.json → categories[].colorHex`. The `start`/`end` are UTF-16 offsets, see "String indexing" below. This needs ~30 lines of code.
- **(B) Port the detector.** Re-implement `docs/02-tajweed.md` from scratch. Only do this if you need to color text the corpus doesn't cover (other qiraat, user input) or you want zero data dependency.

## String indexing (UTF-16 offsets)

The annotation `start`/`end` are **UTF-16 code-unit offsets**, because the source Quran text and the reference engine are UTF-16. Arabic letters in the Quran are in the Basic Multilingual Plane (1 UTF-16 unit each), but **combining marks and a few symbols can matter**, so handle this precisely:

- **JS, Swift (`NSString`/`utf16`), Java, Kotlin, Dart, C#**: native UTF-16. Use offsets directly.
- **Python**: strings are code-point indexed. Convert: build the slice via `text.encode("utf-16-le")` and slice on `2*start: 2*end`, or precompute a code-point↔UTF-16 map. The Python port includes a helper (`utf16_slice`).
- **Rust**: strings are UTF-8/byte indexed. Decode to `Vec<u16>` (`text.encode_utf16()`), slice, and re-encode with `String::from_utf16`.
- **Go**: strings are bytes; use `utf16.Encode([]rune(text))`, slice, `utf16.Decode`.

When in doubt, the test for any port: for every annotation, the reconstructed slice must equal the same slice the JS engine produces. The JS test suite and the Python port both assert this.

## Sorting rules (exact)

- Comparators are **ascending with `id` as the tiebreaker**.
- **Descending** = reverse of the ascending array.
- `mode = "surah"` or `direction = "surahOrder"` → natural 1..114, no sort.
- Direction-aware modes: `revelation`, `ayahs`, `page`, `words`, `letters`. Others are intrinsic.

## Search normalization (exact)

The Arabic/English fold is the load-bearing part. Implement `cleanSearch` precisely (see `docs/06`): fold hamza/alif/waw/yaa variants → strip punctuation + symbols + combining marks (keep `& | ! #`) → lowercase → collapse whitespace. Verse search returns **mushaf order** (unranked) and **rejects any query containing a digit**. A minimal port may implement substring matching on the folded blobs and skip the boolean grammar; document what you skipped.

## Reference behaviors to match (test cases)

```
quran.totalAyahs                         == 6236
globalAyahNumber(1, 1)                    == 1
globalAyahNumber(2, 1)                    == 8
globalAyahNumber(114, 6)                  == 6236
surahAudioUrl(Alafasy, 1)                 == "https://server8.mp3quran.net/afs/001.mp3"
ayahAudioUrl(Alafasy, 8)                  == "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3"
juz(1).startSurah/startAyah               == 1 / 1
juz(30).endSurah/endAyah                  == 114 / 6
sortSurahs("ayahs","descending")[0].id    == 2     (Al-Baqarah, 286 ayahs)
parseReference("2:255")                   == { surah: 2, ayah: 255 }
```

Every port should ship a tiny test asserting these.

## Conformance vectors, the single source of behavioral truth

`/conformance/vectors.json` is a language-agnostic file of `input → expected output` cases (verse search, `juzFromEnd`, `juzStats`, tajweed checkpoints). It exists so a behavior is specified **once** instead of being re-asserted by hand in seven test files, the thing that lets the ports drift apart.

**Every port should ship a `conformance` test that loads `/conformance/vectors.json` and runs it against its own engine.** The JS reference consumer is [`packages/quran-engine-js/test/conformance.test.js`](../packages/quran-engine-js/src/), mirror its tiny interpreter (each section maps to one engine call; assert `contains` / `excludes` / `empty` / scalar equality). When you change behavior, add or edit a vector here and *every* port's conformance test picks it up, no per-language test edits.

Field guide: `searchVerses[].query` with `contains` (ids that must appear), `excludes` (must not), or `empty:true`; `juzFromEnd[]` `{n,id}` (`id:null` = out of range); `juzStats[]` exact counts or `{juz,isNull:true}`; `tajweed[]` `{surah,ayah,excludesRule,lastSpanRule}` (a port maps "rule" to whatever field its spans expose, the JS port calls it `category`).

## Module coverage per port

The core modules (Quran, tajweed, juz/page, audio, search, sorting, caching, names, muqattaat) are in **all seven** ports and are covered by the conformance vectors.

Everything beyond the core is in **all seven** too: the mushaf, riwayah tajweed, word by word, similar ayahs, themes, the tajweed course, meaning search and Ask AI retrieval (batch 3), then surah sections, the alphabet reference and the qiraat comparison (batch 4), then morphology, mutashabihat, the QUL topic indexes, the mushaf divisions, the qiraat variant matrix and the word of the day (batch 5). Each port carries parity suites that are deliberate translations of the same cases:

| Port | Core | Beyond the core | Batch 3-4 parity | Batch 5 parity |
|---|---|---|---|---|
| JavaScript | ✓ | ✓ | `test/parity.test.js` | `test/batch5.test.js` |
| Python | ✓ | ✓ | `tests/test_parity.py` | `tests/test_batch5.py` |
| Swift | ✓ | ✓ | `ParityTests.swift` | `Batch5Tests.swift` |
| Rust | ✓ | ✓ | `tests/parity.rs` | `tests/batch5.rs` |
| Go | ✓ | ✓ | `parity_test.go` | `batch5_test.go` |
| Kotlin | ✓ | ✓ | `ParityTest.kt` | `Batch5Test.kt` |
| Dart | ✓ | ✓ | `test/parity_test.dart` | `test/batch5_test.dart` |

A divergence between the ports fails a test rather than surprising an app. Several the suites caught, all worth knowing if you write an eighth port:

- **Java's `\s` is ASCII-only.** 2:26 separates two of its words with U+00A0, so Kotlin tokenized one word short of the pack and every Arabic token after it shifted by one. `Regex("(?U)\\s+")` fixes it. Go's `strings.Fields`, Rust's `split_whitespace`, and JS, Dart and Python's `\s` are Unicode-aware already.
- **Go's RE2 has no lookbehind**, so the `(?<![\d:])(\d{1,3}):(\d{1,3})` reference scanner cannot be a regexp there. Go and Rust both hand-roll it; the code is short and the tests pin it.
- **A value-type tree needs a path, not a pointer.** The surah outline is a flat list that nests, so rebuilding the tree means appending into the node currently being filled. Rust will not lend you two mutable borrows of one tree, and Swift/Go trees are values that move when a slice grows: all three track the open chain as a *path of indices* and walk back down on each insert. JS, Python, Kotlin and Dart keep a stack of references.
- **Dart reserves `index` on every enum.** The three QUL topic indexes are `thematic` / `ontology` / `index` everywhere else; Dart cannot have an enum value named `index` because `Enum.index` already exists, so its value is `generalIndex` and `topicTreeWireName` maps it back to the wire name. Nothing else about the shape changes, and the JSON is untouched.
- **The morphology fold closes spaces; `cleanSearch` only trims them.** A root is printed spaced (`"ر ب ب"`) and typed closed up (`"ربب"`), and both have to find it. Every port therefore wraps `cleanSearch(removingArabicDiacriticsAndSigns(q))` in a whitespace *strip*, not the library's `whitespace: true` option, which trims the ends only. Getting this wrong makes root search silently return nothing for the spaced form, which no type checker will catch.
- **A row with a fixed shape wants positional decoding, not a union.** `similar-ayahs.json` rows are always six fields, `[surah, ayah, verifiedFlag, spans, labels, score]`, with `spans` at 3 and `labels` at 4 both possibly `[]`. Decode each position as its own type (a list of int pairs, a list of strings, an optional number). The version-1 rows were variable-length, which forced Rust and Swift into an untagged union whose variants had to be ordered so that an empty `[]` landed in the right slot; that trap is gone with the fixed shape, and the ports that keep a union must still read position 3 as spans and 4 as labels whatever the union decoded an empty array as.

- **A field that becomes optional breaks the strict decoders first, and hardest.** A version-4 drill whose Arabic is Quran carries an `ayah` reference and *no* `text` at all. Rust's serde and Swift's `Decodable` both had `text` as a required `String`, so the file stopped parsing outright, and because Rust loads its corpora eagerly that took down the whole engine, not just the lessons: 30 of 32 parity tests failed on a corpus none of them were testing. Go, Kotlin, Dart, JS and Python were quieter and worse, filling in an empty string and rendering a blank row where a verse belongs. When an upstream field splits into "either this or that", give the decoder a default *and* a test that reads the new branch back out; a test that only walks the old branch passes either way.
- **`mnemonic` is an object, not a string.** It is `{arabic, gloss}` on the rule card. Worth naming because the guess costs a full test cycle in every typed port at once, and the failure (`invalid type: map, expected a string`) points at a byte offset in a 440 KB single-line JSON rather than at a field.
- **The rule card is `ruleCard`, and was never `mushafCard`.** All six typed ports declared an optional `mushafCard` that the data has never carried, so it silently decoded to nothing from the day it was written: the card's `trigger`, `action`, `hold`, `mnemonic` and fragments were simply invisible to every consumer. An optional field with a wrong name cannot fail, which is exactly why it survived four batches. When adding one, assert in a test that it is *present*, not merely that it parses.

### What an eighth port needs

Nothing algorithmically hard; the corpora do the work. In order of effort:

1. **Data accessors**: mushaf (page/line tables + the index), riwayah tajweed (legend + word rules + khilaf markers), word by word (two aligned layers), similar ayahs, themes, lessons, the batch-5 six (morphology, mutashabihat, QUL topics, the mushaf divisions, qiraat variants, the word of the day) and the batch-6 two (the 99 Names in depth, the chains of transmission). Each is a JSON shape and a handful of lookups; see [10](10-mushaf.md)–[13](13-similar-and-themes.md) and [18](18-morphology.md)–[24](24-isnad.md) for the schemas and the invariants that matter (letter indices vs character offsets; the token alignment; which riwayat ship what; that the three topic indexes are independent trees).
2. **`Semantic`**: a word-vector MaxSim index with a pluggable embedder. About 80 lines: tokenize, embed, normalize once, score as the mean over query words of the best-matching document word.
3. **Ask AI retrieval**: four lanes, round-robin interleaved. The only fiddly parts are the reference scanner (`N:M`, `surah <name>`, `verse <n>`, the named verses) and the IDF weighting; the Rust port does both without a regex dependency if yours would rather avoid one.

Keep the method names your language's ports already use (`page` / `mushaf_page` / `mushafPage` as the local convention dictates) but keep the **semantics** identical, and translate the parity suite: a divergence should fail a test, not surprise an app.

## Directory convention

```
packages/
  quran-engine-js/      reference (ESM JS + TS types)
  quran-engine-py/      Python
  quran-engine-swift/   Swift Package
  quran-engine-kotlin/  Kotlin / Android
  quran-engine-dart/    Dart / Flutter
  quran-engine-go/      Go module
  quran-engine-rust/    Rust crate
```

Ports locate `/data` relative to the repo root (or accept an injected data directory / parsed objects, so they also work when the data is bundled as an app asset).
