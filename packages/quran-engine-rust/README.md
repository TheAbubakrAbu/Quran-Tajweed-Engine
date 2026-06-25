# quran-engine (Rust)

A Rust port of the open-source **Quran Tajweed Engine**. The engine is *data-first*: it is a
thin, idiomatic wrapper over the JSON corpus in the repository's [`/data`](../../data) directory
plus a handful of pure functions. No network, database, or framework is required.

This crate follows the shared porting contract in [`../../docs/PORTING.md`](../../docs/PORTING.md)
and the per-feature specs in [`../../docs/01-quran.md`](../../docs/01-quran.md) …
[`../../docs/08-caching.md`](../../docs/08-caching.md). The reference implementation is the JS
package in [`../quran-engine-js`](../quran-engine-js).

## Install

This crate lives inside the monorepo and loads the bundled `/data`. Add it as a path dependency:

```toml
[dependencies]
quran-engine = { path = "../quran-engine-rust" }
```

## Quick start

```rust
use quran_engine::{Engine, SearchOpts};

// Ascends from CARGO_MANIFEST_DIR / cwd to find <repo>/data/quran.json.
let engine = Engine::load_default()?;
// ...or point at a specific data directory:
// let engine = Engine::load(std::path::Path::new("/path/to/data"))?;

// Quran
engine.surah(2).unwrap().name_english;          // "The Cow"
engine.ayah(2, 255).unwrap().text_arabic;        // Ayat al-Kursi
engine.global_ayah_number(2, 1);                 // Some(8)
engine.total_ayahs();                            // 6236
engine.arabic_text(1, 1);                        // Hafs text of al-Fatiha:1

// Juz / Page
engine.juz(5).unwrap().name_transliteration;     // "Wal-Muhsanat"
engine.ayahs_in_juz(30);                          // every ayah in juz 30
engine.first_ayah_of_page(50);                    // jump target
engine.juz_for_ayah(2, 255);                      // Some(3)
engine.total_pages();                             // 604

// Audio
let reciter = engine.reciter_by_id("Mishary Alafasy|Hafs|https://server8.mp3quran.net/afs/").unwrap();
engine.surah_audio_url(reciter, 1)?;             // ".../afs/001.mp3"
let g = engine.global_ayah_number(2, 1).unwrap();
engine.ayah_audio_url(reciter, g);               // cdn.islamic.network/.../8.mp3

// Sorting
engine.sort_surahs("ayahs", "descending")[0].id; // 2 (Al-Baqarah)
engine.filter_by_revelation_type("makkan");

// Search (core path)
engine.search_verses("lord of the worlds", &SearchOpts::default());
engine.search_surahs("fatihah");                 // [1]
engine.parse_reference("2:255");                 // Reference { surah: 2, ayah: Some(255) }

// Tajweed (colored spans from the pre-computed annotation corpus)
for span in engine.tajweed(1, 1) {
    println!("{}..{} {} {:?} {:?}", span.start, span.end, span.rule, span.color, span.text);
}
# Ok::<(), quran_engine::LoadError>(())
```

## Tajweed strategy (A)

Tajweed coloring uses **strategy (A)** from the porting guide: it consumes the pre-computed
corpus in [`data/tajweed-annotations.json`](../../data/tajweed-annotations.json) and maps each
annotation's `rule` to the category color (`colorHex`) in
[`data/tajweed-rules.json`](../../data/tajweed-rules.json).

Annotation `start`/`end` are **UTF-16 code-unit offsets** (the reference engine is UTF-16). Rust
strings are UTF-8/byte indexed, so [`utf16_slice`](src/util.rs) decodes the ayah to `Vec<u16>`,
slices, and re-encodes with `String::from_utf16`. The test suite asserts that every span's
reconstructed slice equals its recorded text.

The full heuristic tajweed detector (strategy B in
[`docs/02-tajweed.md`](../../docs/02-tajweed.md)) is **not** ported here.

## Search: what is implemented and what is omitted

The **core search path** is implemented:

- `search_verses` — unranked verse-text search in mushaf order. A verse matches when the cleaned
  query is a substring of the relevant (Arabic or English) folded blob, **or** the query tokens
  phrase-prefix-match the verse tokens. Verse search rejects any query containing a digit.
- `search_surahs` — name / alias / number / `"2:255"` / makkan-madani lookup.
- `parse_reference` — `"2:255"`, `"2 255"`, `"baqarah 10"`, and Arabic-digit forms.

**Omitted (documented divergence):** the **boolean grammar** (`& | ! # ^ % $`) and its dedicated
tashkeel / exact-phrase / silent-letter index blobs are not ported. A query containing a boolean
operator is treated as plain text. This matches the "minimal port" allowance in the porting guide.

## Layout

| File | Area |
|---|---|
| `src/model.rs` | serde structs (`Surah`, `Ayah`, `JuzEntry`, `Reciter`, `TajweedSpan`) |
| `src/lib.rs` | the `Engine` facade + Quran / Juz / Page / tajweed |
| `src/audio.rs` | surah & ayah audio URL builders |
| `src/sorting.rs` | surah sorting & filtering |
| `src/search.rs` | verse / surah / reference search (core path) |
| `src/text.rs` | Arabic/English search normalization |
| `src/cache.rs` | offline cache path helpers |
| `src/util.rs` | `zero_pad3`, `utf16_slice` |

## Tests

```sh
cargo test
```

The test module asserts the canonical cases from the porting guide: `total_ayahs == 6236`;
`global_ayah_number` for `(1,1)`, `(2,1)`, `(114,6)`; the Alafasy surah/ayah audio URLs; juz 1/30
boundaries; `sort_surahs("ayahs","descending")[0].id == 2`; `parse_reference("2:255")`; and that
each tajweed span's reconstructed UTF-16 slice equals its recorded text.

## License & attribution

MIT. All data and algorithms are extracted from the open-source **Al-Islam | Islamic Pillars** app
by Abubakr Elmallah. Please preserve the attribution in [`../../CREDITS.md`](../../CREDITS.md).
The Quran's Arabic text must be preserved exactly and never altered.
