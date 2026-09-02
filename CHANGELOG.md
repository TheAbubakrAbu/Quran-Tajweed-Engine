# Changelog

All notable changes to the Quran Tajweed Engine are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

Synced from upstream **Al-Islam** search/navigation updates.

### Added — parity batch 4: surah sections, the alphabet, and a measured qiraat comparison

Three modules that close a gap the last batch left: `data/` shipped files no accessor could reach.

- **Surah sections** — `engine.surahSections`, over the already-shipped `data/surah-sections.json`: **741 titled passages across 111 surahs**, answering "what is this passage doing here" in one lookup. The outline is a **tree stored flat** — a broad passage followed by the sections inside it — and it does *not* tile the surah, so an ayah has a *chain* of sections (`sectionsFor`), or none. `outline` rebuilds the tree; `search` turns the titles into a table of contents for the whole book. Spec: [docs/15-surah-sections.md](docs/15-surah-sections.md).
- **The Arabic alphabet** — `engine.alphabet`, over the already-shipped `data/arabic-alphabet.json`: the 28 letters with their joining forms and, the reason it belongs in a *tajweed* engine, their **weight** — thin, full, conditional, or (alif alone) inheriting the letter before it. Plus the tashkeel marks, the waqf signs, and the Eastern-Arabic numerals. `letter()` resolves a medial or final form, so a letter sliced out of a word still looks up. Spec: [docs/16-arabic-alphabet.md](docs/16-arabic-alphabet.md).
- **Qiraat comparison** — the new `engine.qiraatComparison`: two readings **aligned word by word** and sorted into identical / same-skeleton / different. Warsh against Ḥafṣ is 63.5% identical, 27,546 words sharing a skeleton, and **717 words — under 1% — differing in skeleton**: the readings differ in sound, not in wording, which is exactly what the Uthmanic rasm was built to allow. Alignment, never indexing: Warsh's al-Baqarah has 285 verses to Ḥafṣ' 286, so a two-pointer walk over the surah's word stream with one-sided lookahead is the only honest way to pair them. Needs the qiraah text (`loadQiraat`); only the eight published readings can be compared. Spec: [docs/17-qiraat-comparison.md](docs/17-qiraat-comparison.md).
- `Quran.qiraahVerses(surah, riwayah)` and `loadedRiwayat()` — a reading's own verses in ITS numbering, which the per-ayah text accessor cannot give you (it falls back to Ḥafṣ for ids a reading does not have).
- A test pins **`surah-stats.json` to `quran.json`**. It ships as an 8 KB index for consumers who do not want to parse 30 MB of text, so nothing reads it through the API — which is precisely why it needed something to keep it honest.

Recorded while writing the comparison, because both cost real time: allowing the resync to skip on *both* sides at once silently reclassifies every substitution as an insertion plus a deletion, and pins `different` at zero for every riwayah. And of the three surahs with no outline, two carry the literal placeholder `"Surah overview"` upstream — the engine mirrors it rather than papering over it, and [the spec](docs/15-surah-sections.md) says so.

### Added — parity batch 3: the printed mushaf, word by word, and Ask AI

The largest data drop since 1.0. Six new corpora, six new engine modules, and five new specs. Everything is extracted from the app by the new [`scripts/import-al-islam-data.py`](scripts/import-al-islam-data.py), which decompresses the packs the app ships them in and reshapes them as plain JSON — so a future app-side correction is one command away.

- **The printed mushaf** — `engine.mushaf`, over the new `data/mushaf/`: all **20 riwayat of the Ten Qiraat as page-exact 604-page facsimiles** (`pdfs/*.pdf.xz`, ~23 MB for the set as solid xz streams, losslessly a third of the plain PDFs), each with **its own `ayah → page` table** and, for the eight whose text ships, its **line-break table**. A riwayah is not paginated like Ḥafṣ — readings merge ayahs and spell words differently — so paging a Warsh reader by Madani page numbers drifts; this fixes that. `page` / `ayahsOnPage` / `firstAyahOfPage` / `lineBreaks` / `pdfPath`. Spec: [docs/10-mushaf.md](docs/10-mushaf.md).
- **Riwayah tajweed** — `engine.qiraatTajweed`, over `data/tajweed-qiraat/`: seven packs carrying each printed muṣḥaf's **own coloured marks and its own legend** (Warsh's taqlīl and raa/lam rules, al-Bazzī's doubled tāʾ, the ṣilah mīm, the sakt places…), plus a **shared rule catalogue** explaining all 17 rule keys once for all seven. A different layer from `tajweed.js`: these differences cannot be detected from the text, because they *are* the text's difference. `legend` / `wordRules` / `khilafAyahs` / `describe`. Spec: [docs/11-qiraat-tajweed.md](docs/11-qiraat-tajweed.md).
- **Word by word, now with transliteration** — `engine.wordByWord`, over `data/word-by-word.json`: **77,629 tokens carrying both an English gloss and a Latin transliteration**, aligned by the same build-time walk to the *ayah's own whitespace tokens*, so a consumer splits on whitespace and indexes straight in. The transliteration layer is new in this batch (fetched and aligned upstream in the app, then imported). `words` / `glosses` / `transliterations` / `find`. Spec: [docs/12-word-by-word.md](docs/12-word-by-word.md).
- **Similar ayahs** — `engine.similarAyahs`, over `data/similar-ayahs.json`: the mutashābihāt corpus for **5,446 ayahs**, merged and ranked at build time, each row flagged `verified` (the classical corpus) or carrying the labels that explain a generated match.
- **Themes** — `engine.themes`, over `data/themes.json`: **323 curated topics** across categories and domains, indexed both ways (`topic(id).ayahs` and `topicsFor(surah, ayah)`). Loaded by default.
- **The tajweed course** — `engine.tajweedLessons`, over `data/tajweed-lessons.json`: 8 chapters, 34 lessons with prose, drills and Quranic examples. Loaded by default. Also `data/surah-sections.json` (per-surah outlines) and `data/surah-stats.json`.
- **Meaning search** — the new `Semantic` module: **word-vector MaxSim**, not sentence embeddings, because a single vector per verse ranks this corpus close to randomly (measured, not assumed). Embedder-agnostic: hand it `embed(word)` and it does the rest, so the engine ships no model.
- **Ask AI** — `engine.askAI` + `chatPrompt`: the **retrieval and the prompt** behind a grounded question box, with no model shipped. Four lanes, interleaved round-robin so each gets a voice: what the question *names* (marked `isSubject` — the fix for a model explaining the wrong verse), **IDF-weighted** keywords (plain term counting ranked questions by whichever verse said "the" most), the curated themes, and — only when you supply a semantic index — meaning. `CHAT_INSTRUCTIONS` is the system prompt whose rules 2, 3 and 5 stop a model inventing verse numbers, "quoting" scripture it half-remembers, and issuing rulings. Spec: [docs/14-ask-ai.md](docs/14-ask-ai.md).
- **The app's build tooling** — `scripts/al-islam/`: the Python (and one Swift) scripts that produce these corpora, copied verbatim from the app with a [README](scripts/al-islam/README.md) mapping each one to the data it feeds. Provenance and reproducibility, not part of the API.

### Changed — the qiraat text feeds

- **ad-Duri, as-Susi and Qalun refreshed** from the app: the imālah/taqlīl mark on ad-Duri and as-Susi was corrected across **1,213 and 1,085 ayahs** respectively, and Qalun in one (9:110). al-Bazzī, Qunbul, Shubah and Warsh were already byte-identical. `qiraat-counts.json` regenerated.

### Ports

The batch landed in **all seven ports**. Each ships a deliberate translation of the same ~20 cases (`test/parity.test.js`, `tests/test_parity.py`, `ParityTests.swift`, `tests/parity.rs`, `parity_test.go`, `ParityTest.kt`, `test/parity_test.dart`), so a divergence between them fails a test rather than surprising an app.

Two divergences the suites caught on the way in, both recorded in [docs/PORTING.md](docs/PORTING.md#module-coverage-per-port): Java's `\s` is ASCII-only, so Kotlin tokenized 2:26 (which separates two words with U+00A0) one word short of the pack until the regex was made Unicode-aware; and Go's RE2 has no lookbehind, so its ayah-reference scanner is hand-rolled like Rust's.

The Swift package now bundles the new corpora too (`scripts/sync-package-resources.mjs` keeps subdirectories, so `mushaf/pages/warsh.json` resolves from `Bundle.module`), minus the facsimiles: 23 MB of PDFs the engine never loads itself belong to the consumer, not to the package.

### Not published, on purpose

- **The text of the twelve remaining riwayat.** It is machine-extracted from printed muṣḥafs and not yet proofread word by word; text in that state is not something to hand other developers as engine data. Their **line tables and tajweed packs index into that text**, so those stay out with it. Their **printed muṣḥafs and page tables do ship** — a facsimile is exact whatever the state of the extraction — so all twenty are readable and navigable by ayah. `mushaf.riwayah(slug).textIncluded` is the flag.


### Added — parity batch 2
- **Muqaṭṭaʿāt** — `engine.muqattaat`: the disconnected opening letters of 29 surahs (`all()` = 30 entries, `pronunciation(s,a)`, `letterName(c)`). New `data/muqattaat.json` carries each opening's letters, transliteration, and the fully-vocalized Arabic spelling whose long vowels keep the madd-lāzim maddah (U+0653) so a tajweed pass colours them like the real ayah. Ported from `Muqattaat.swift` to all 7 ports.
- **Surah boundary flags** — `Quran.pageChangesWithinSurah(id)` / `juzChangesWithinSurah(id)` / `pageOrJuzChangesWithinSurah(id)`, for divider layout. All 7 ports.
- **Qiraah existence + per-qiraah ayah counts** — `Quran.existsInQiraah(surah, ayah, riwayah)` and `numberOfAyahsInQiraah(surah, riwayah)` (Baqarah is 286 in Hafs, 285 in Warsh). New compact `data/qiraat-counts.json` (~6.5 KB, generated by `build-data.mjs` from the qiraah feeds) makes this work with **zero extra load** — no 11 MB of qiraah text. Faithful to `QuranData.swift`'s id-matching merge: a Hafs ayah exists in a riwayah iff that riwayah's contiguous `1..count` feed reaches its id, so a per-surah count fully determines it. All 7 ports.
- *(Reciter display name — `ayahNowPlayingName(reciter)` already covered Al-Islam's `displayNameWithEnglishQiraah` / `displayNameForNowPlaying`; no new API needed.)*

### Added — parity batch 1 (toward Al-Islam consuming the engine)
New pure-data/algorithm features the app needs, in all 7 ports + a conformance vector for each:
- **Sajdah** — `Quran.sajdahAyahs()` / `isSajdahAyah(s,a)`: the 15 prostration ayahs, detected by the ۩ mark (U+06E9).
- **Surah from the end** — `Quran.surahFromEnd(n)`: `1 → An-Nās (114)` … `114 → Al-Fātiḥah` (companion to `JuzPage.juzFromEnd`).
- **Names of Allah** — `engine.namesOfAllah` (`all()`, `byNumber(n)`) over the 99 names.
- **Surah info accessor** — `Quran.info(surahId)` exposed in every port (it existed only in JS); `surah-info.json` + `names-of-allah.json` now load by default.
- **Count-based surah filter** — `filterByCounts(surahs, { ayahs, pages })` with `{op,value}` predicates (`< <= > >= ==`), mirroring the app's "286 ayahs" / "<10 pages" search filters.

### Added
- **Juz from the end** — `JuzPage.juzFromEnd(n)`: resolve a juz counted backwards from the end of the Quran (`1 → juz 30`, … `30 → juz 1`). Mirrors the Al-Islam search-bar `-N` shorthand (e.g. typing `-1` jumps to juz 30). Ported to all 7 languages.
- **Per-juz statistics** — `JuzPage.juzStats(juz)`: aggregate `surahCount` / `ayahCount` / `wordCount` / `letterCount` / `pageCount` for a juz, computed from the ayahs actually assigned to it so boundary-straddling surahs split correctly (the 30 juz `ayahCount`s sum to 6236). Mirrors `QuranData.juzStats(for:)`. Ported to all 7 languages.

### Changed — ayah search now byte-for-byte faithful to `QuranData.swift`
All 7 ports reconciled so verse search behaves identically to the Al-Islam app:
- **Regular (non-boolean) search is pure substring** — removed the phrase/token-prefix matching that the ports had added; word boundaries don't matter (`رب` matches inside `ربهم`). Whole-word/phrase matching is the `=` operator's job.
- **New `=` whole-word operator** (`=رب` matches the word رب but not ربهم) — added to the boolean grammar and trigger set.
- **Digit rejection runs before the boolean path** and is Unicode-aware (Arabic-Indic digits too), so `allah & 2` returns nothing.
- **Boolean `#` exact-match** is now mode-aware on both Arabic (tashkeel blob) and English (exact-phrase blob), and empty-valued terms are dropped.
- **Go / Kotlin / Dart** previously lacked the `arabicTashkeelBlob` / `exactPhraseBlob` / silent-letter helpers entirely — added, so `#`/`=`/silent-letter search now works in those ports.
- Each port gained a shared behavioral test (`orld`→1:2 substring; `=lord`→hit, `=lor`→miss, `lor`→hit; `allah & 2`→empty).

### Fixed — tajweed: madd 'iwad in the iqlaab form
- An ayah ending in tanwin-fath written as the Uthmani **iqlaab form** (a fatha + tiny high/low meem, e.g. `رُوَيۡدَۢا` at the end of At-Tariq 86:17) now drops the iqlaab at the stop and elongates the final alif as a 2-count madd 'iwad — matching the plain-fathatayn form. Previously the tiny-meem stayed painted as iqlaab. Regenerated `tajweed-annotations.json` + per-surah files (44 ayahs updated; the only rule removed is `iqlaab`, revealing the qalqalah/tafkhim that legitimately apply at a stop). Fix is in the JS detector (`detectPaintOps`); all 7 ports pick it up via the regenerated corpus.

### Added — conformance vectors (single source of behavioral truth)
- New `/conformance/vectors.json`: language-agnostic `input → expected output` cases (search, juz, tajweed) that every port runs against its own engine, so a behavior is specified once here instead of re-asserted in 7 hand-written test files (the thing that let the search logic drift). **All 7 ports now ship a conformance consumer** (JS/Python/Rust verified passing; Go/Kotlin/Dart written to spec). Contract documented in `docs/PORTING.md`.

### Added — packaging & protection (preparing Al-Islam to consume the engine)
- **Swift package is now self-contained.** The core JSON corpus is bundled as a SwiftPM resource (`packages/quran-engine-swift/Sources/QuranEngine/Resources/`, generated from `/data` by the new `scripts/sync-package-resources.mjs`), and `Engine.load()` reads from `Bundle.module` first — so `try Engine.load()` works as a dependency with **zero filesystem setup** (no `/data` copy needed). Disk discovery remains as a monorepo-dev fallback.
- **CI** (`.github/workflows/ci.yml`): runs every port's test suite + conformance, and fails if the **generated artifacts** (tajweed annotations, bundled package resources) drift from canonical `/data` — protecting the engine once apps depend on it.
- **Al-Islam migration roadmap** — `docs/integration/al-islam-migration.md`: staged plan (protect → close parity gaps → adopt drop-ins → swap tajweed → delete), the `QuranData` → engine API map, the prioritized parity-gap list, and what stays app-side. `docs/integration/ios.md` updated (data is bundled; no app-side `/data` copy).

### Docs
- `docs/03-juz-page.md` — documented `juzFromEnd` and `juzStats`.
- `docs/06-ayah-search.md` — documented the page/juz quick-jump shorthands (including `-N` from-the-end).
- `docs/02-tajweed.md` — expanded the Madd 'Iwad exception to cover the iqlaab form + waqf iqlaab suppression.

## [0.1.0] — Initial release

The first public version: a complete, framework-agnostic Quran engine.

### Data (`/data`)
- `quran.json` — 114 surahs / 6236 ayahs: Hafs Uthmani Arabic, transliteration, two English translations (Saheeh International, Mustafa Khattab), per-ayah juz/page/word/letter counts.
- `surah-info.json` — "About this surah" essays (Maududi, Ibn Ashur).
- `names-of-allah.json` — the 99 Names of Allah.
- `qiraat/qiraah-*.json` — 7 alternate readings (Warsh, Qaloon, Duri, Susi, Bazzi, Qunbul, Shubah).
- `juz.json` — 30 juz boundaries (derived).
- `reciters.json` — 62 reciters across 8 riwayat (derived).
- `tajweed-rules.json` — 17-category rule catalogue with canonical colors and trigger letters (derived).
- `tajweed-annotations.json` + `tajweed/NNN.json` — pre-computed tajweed spans for all 6236 ayahs (113,642 spans).
- `surahs/NNN.json` + `surahs/index.json` — per-surah split for lazy/web loading.

### Specifications (`/docs`)
- Getting started, architecture, glossary, FAQ, recipes, and the porting contract.
- Per-feature specs 01–08: Quran, Tajweed, Juz/Page, Surah recitations, Ayah recitations, Search, Sorting, Caching.
- Platform integration guides.

### Language ports (`/packages`)
- **JavaScript/TypeScript** (`quran-engine-js`) — reference implementation, full tajweed detector, 18 tests.
- **Python** (`quran-engine-py`) — pure stdlib, 9 tests.
- **Swift** (`quran-engine-swift`) — Swift Package, 14 tests.
- **Go** (`quran-engine-go`) — module, 10 tests.
- **Rust** (`quran-engine-rust`) — crate, 10 tests + doctest.
- **Kotlin** (`quran-engine-kotlin`) — JVM/Android, kotlinx-serialization.
- **Dart** (`quran-engine-dart`) — Dart/Flutter.

### Features
- Quran browsing (surahs, ayahs, translations, qiraat text, global ayah number).
- Tajweed coloring — two strategies: consume the annotation corpus, or run the JS detector.
- Juz & mushaf-page navigation.
- Full-surah and ayah-by-ayah recitation URL builders (60+ reciters) with Minshawi fallback.
- Search — Arabic (diacritic-folded, optional silent-letter mode), English, references, boolean grammar (JS).
- Surah sorting (6 modes) and Makkan/Madinan filtering.
- Offline-audio caching helpers (paths + `AudioCache` in JS).

### Added after initial cut
- **Fonts** (`data/fonts/`) — Uthmani (Hafs), Qiraat (Qunbul), and Indopak (Nastaliq) TTFs + `fonts.json`, with [docs/fonts.md](docs/fonts.md) explaining the Uthmani-vs-Qiraat-vs-Indopak trade-offs for tajweed coloring.
- **Arabic alphabet** (`data/arabic-alphabet.json`) — 28 letters with tajweed weight, extra/special letters, non-Arabic letters, Eastern-Arabic numerals, 21 tashkeel marks, and the 9 waqf stopping signs; plus [docs/arabic-alphabet.md](docs/arabic-alphabet.md).
- **Detailed tajweed guide** — [docs/tajweed-rules-explained.md](docs/tajweed-rules-explained.md): plain-English explanations of every rule (idgham, ikhfaa, ghunnah, qalqalah, madd types, tafkhim, waqf …), from the app's "Tajweed Foundations" lessons.
- **Single source of truth for tajweed** — `data/tajweed-rules.json` enriched with literal meanings + long descriptions; `scripts/generate-tajweed.mjs` regenerates per-language constants (`tajweed-rules.generated.*`) in all 7 ports plus `docs/tajweed-rules-reference.md` from that one file.
- Precise upstream-source attribution (KFGQPC, Risan Bagja Pradana, Global Quran, Quran Foundation, MyIslam, font authors, MP3 Quran, alquran.cloud) in [CREDITS.md](CREDITS.md), linking each app's own credits in its repository. Added a *sadaqah jariyah* intent note. (Per-app credits live in each app's own repo.)

### Known limitations
- Tajweed detector simplifies full final-`ر` vowel context and muqatta'at lazim-harfi sub-typing (see [docs/02-tajweed.md](docs/02-tajweed.md)).
- Boolean search grammar is implemented in the JS port; native ports implement the core search path.
- No audio files are bundled; the engine builds URLs to third-party CDNs.
