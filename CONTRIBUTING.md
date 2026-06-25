# Contributing

Thank you for helping make the Quran more accessible. Contributions of all kinds are welcome —
bug fixes, new language ports, better tajweed accuracy, more data, docs, and examples.

## Ground rules

1. **Never alter the Quranic Arabic text.** `quran.json` and `qiraat/*` are sacred and shipped verbatim.
   Fixes to the text must come from an authoritative source and be flagged clearly.
2. **Keep attribution intact.** Preserve [CREDITS.md](CREDITS.md) and the data provenance.
3. **Data-first.** Prefer adding data + a spec over hard-coding behavior in one port.
4. **Every port follows [docs/PORTING.md](docs/PORTING.md)** and ships a test asserting the canonical cases.

## Ways to contribute

### Fix a bug or improve a feature
- Reproduce it against the data. Add or update a test in the relevant port.
- If it's a shared-behavior bug, fix the reference JS port first, then mirror it.

### Add a new language port
1. Read [docs/PORTING.md](docs/PORTING.md) — the full contract.
2. Create `packages/quran-engine-<lang>/`.
3. Implement: Load + Quran + Tajweed (via the annotation corpus) + JuzPage + audio URLs + sorting +
   reference parsing. Search and caching are "extended" (nice to have).
4. Use the pre-computed tajweed corpus (strategy A) unless you have a reason to port the detector.
5. Ship a test asserting the canonical cases (totalAyahs 6236, the audio URLs, juz boundaries,
   sort order, `2:255` parsing, tajweed UTF-16 slice reconstruction). See any existing port's test.
6. Add a package `README.md` and link it from the root README + getting-started.

### Improve tajweed accuracy
- The detector is `packages/quran-engine-js/src/tajweed.js`; the spec is [docs/02-tajweed.md](docs/02-tajweed.md).
- Known gaps: full final-`ر` vowel context, muqatta'at lazim-harfi sub-typing (see the doc).
- After changing it, regenerate the corpus: `node scripts/build-data.mjs`, and note the change in the changelog.

### Add data
- New translation, tafsir, word-by-word, audio source, etc.: add a JSON file under `/data`, document its
  schema in a new `docs/` page, and surface it in the ports. Keep files reasonably sized (consider per-surah splits).

## Development

- **Reference port (JS):** `cd packages/quran-engine-js && node --test test/*.test.js`
- **Python:** `cd packages/quran-engine-py && python tests/test_engine.py`
- **Swift:** `cd packages/quran-engine-swift && swift test`
- **Go:** `cd packages/quran-engine-go && go test ./...`
- **Rust:** `cd packages/quran-engine-rust && cargo test`
- **Regenerate derived data:** `node scripts/build-data.mjs`

## Style

- Match the surrounding code. Keep comments meaningful and tie engine logic back to the specs.
- No heavyweight dependencies in the core ports — they should stay pure and offline.

## Reporting issues

Include the input (surah:ayah or query), what you expected, what you got, and which port/version. For
tajweed, paste the ayah and the spans you received.
