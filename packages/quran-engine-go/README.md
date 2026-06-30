# quran-engine-go

The **Go** port of the open-source Quran Tajweed Engine. It is a thin, idiomatic wrapper over the JSON data in the repository's `/data` directory plus a handful of pure functions — no network call, database, or framework required. *The data is the engine.*

This port implements the shared contract in [`../../docs/PORTING.md`](../../docs/PORTING.md) and the per-feature specs in `../../docs/01…08`.

- Module: `github.com/quran-tajweed-engine/go`
- Package: `quranengine`
- Go: 1.23+

## Install / use in this monorepo

```go
import quranengine "github.com/quran-tajweed-engine/go"

// Locate /data automatically: QURAN_ENGINE_DATA env var, else walk up from CWD
// looking for data/quran.json.
e, err := quranengine.Load()
if err != nil { panic(err) }

// Or pass the data directory explicitly (e.g. when bundled as an app asset):
e, err = quranengine.LoadFrom("/path/to/data")
```

## What it provides

| Area | API |
|---|---|
| **Load** | `Load()`, `LoadFrom(dataDir)`, `FindDataDir()` |
| **Quran** | `Surahs()`, `Surah(id)`, `Ayah(s,a)`, `GlobalAyahNumber(s,a)`, `ArabicText(s,a,riwayah)`, `CleanArabicText(...)`, `EachAyah(fn)`, `TotalAyahs()` |
| **Tajweed** | `TajweedSpans(s,a)` → colored spans (strategy A: pre-computed annotations + `rule`→`colorHex`), `RuleColor(rule)` |
| **Juz/Page** | `Juzes()`, `Juz(id)`, `AyahsInJuz(n)`, `AyahsOnPage(n)`, `FirstAyahOfJuz(n)`, `FirstAyahOfPage(n)`, `JuzForAyah(s,a)`, `PageForAyah(s,a)`, `TotalPages()` |
| **Audio** | `SurahAudioURL(r,s)`, `AyahAudioURL(r,globalAyah)`, `Reciters()`, `ReciterByID(id)`, `AyahNowPlayingName(r)`, `DefaultsToMinshawi(r)` |
| **Search** | `SearchVerses(q,opts)`, `SearchSurahs(q)`, `ParseReference("2:255")` |
| **Sorting** | `SortSurahs(mode,direction)`, `FilterByRevelationType(type)`, `SupportsDirection(mode)` |
| **Caching** | `SanitizeReciterDir(id)`, `LocalSurahPath(r,s)`, `SharedAudioPath(hash,ext)` |

### Canonical formulas (from PORTING.md)

```
pad3(n)                  → "001", "057", "114"
GlobalAyahNumber(s, a)   → (Σ NumberOfAyahs of surahs id < s) + a       # 1..6236
SurahAudioURL(r, s)      → r.SurahLink + pad3(s) + ".mp3"
AyahAudioURL(r, g)       → "https://cdn.islamic.network/quran/audio/" + r.AyahBitrate + "/" + r.AyahIdentifier + "/" + g + ".mp3"
SanitizeReciterDir(id)   → non [A-Za-z0-9-_] → "_", cap 180 (fallback "reciter")
LocalSurahPath(r, s)     → SanitizeReciterDir(r.ID) + "/" + pad3(s) + ".mp3"
```

## Tajweed (strategy A) and UTF-16 offsets

`TajweedSpans` loads `data/tajweed-annotations.json`, takes the ayah's annotations, and maps each `rule` to its `colorHex` from `data/tajweed-rules.json` (`categories[].colorHex`).

The annotation `start`/`end` are **UTF-16 code-unit offsets**, because the source text and reference engine are UTF-16. Go strings are UTF-8/byte indexed, so each span's text is reconstructed via the standard `unicode/utf16` package: `utf16.Encode([]rune(text))`, slice `[start:end]`, `string(utf16.Decode(...))`. The test suite asserts every reconstructed slice equals the recorded text.

## Search scope (what is implemented vs omitted)

This is the **core** search path:

- folded substring match plus **phrase-prefix** token match (all-but-last token exact, last token a prefix);
- verse results in **mushaf order** (unranked);
- verse queries containing a **digit are rejected** (numeric/reference lookups go through `SearchSurahs` / `ParseReference`);
- surah lookup by **name / number / `"2:255"` reference / makkan-madani**.

**Omitted:** the boolean grammar from the JS reference (`& | ! # ^ % $` operators) and the "silent letters ignored" lenient Arabic variant. Queries containing those operators are treated as plain text (the operators are stripped during normalization, except `& | ! #` which are kept but not interpreted).

## Test

```sh
cd packages/quran-engine-go
go test ./...
```

The tests assert the canonical cases from PORTING.md: `TotalAyahs()==6236`; `GlobalAyahNumber` for (1,1)=1, (2,1)=8, (114,6)=6236; the Alafasy surah/ayah audio URLs; juz 1/30 boundaries; `SortSurahs("ayahs","descending")[0].ID==2`; `ParseReference("2:255")=={2,255}`; and tajweed span UTF-16 reconstruction.

## License & attribution

MIT. All data and algorithms are ported from the open-source **Al-Islam | Islamic Pillars** app by **Abubakr Elmallah**. Please preserve the attribution in [`../../CREDITS.md`](../../CREDITS.md) in any redistribution.
