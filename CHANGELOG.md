# Changelog

All notable changes to the Quran Tajweed Engine are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.2.1]

### Added: documentation

- **[docs/whats-new.md](docs/whats-new.md)**: what each release added, newest first, at the level the GitHub releases describe rather than the corpus-by-corpus detail this file carries. Worth knowing while reading it: `v1.1` and `v1.2.0` tag the SAME commit (`c81b28a`), so everything the 1.2.0 notes list landed between 1.0 and that commit, and 1.2.0 is the version to cite.

### Added: parity batch 7, the scientific miracles

One new corpus and one new module, all seven ports, from Al-Islam 4.6.5.

- **Scientific miracles**: `engine.miracles`, over the new `data/miracles.json`: **202 articles across 15 categories**, each a short run of typed blocks (a claim, a lead, body text, third-party quotes with their own source label and link, and a closing line) anchored to **278 ayah references**. The cross-link is `citing(surah, ayah)`, which answers "what does this corpus say about this verse" from anywhere else in the engine. Spec: [docs/25-miracles.md](docs/25-miracles.md).
  Three things worth knowing before you use it. An **`ayah` block is a range, not a verse**: 49 of the 278 span more than one, so treating it as a scalar silently loses about a fifth of the coverage, and it carries no text at all, by design, so the verses come from this engine's own `quran.json` rather than a second copy. An **article's `level` is its own, not its category's**, and the two differ for 147 of the 202 (a category's level is the hardest science it covers), so anything that filters or sorts must read the article; the ordering is simple, intermediate, advanced, extreme, which is not the alphabetical sort, so every port exports the rank rather than leaving it to be guessed. And `text()` joins the article's own prose but **leaves the quotes out**, because folding a third-party excerpt into the article's voice would both misattribute it and break the citation off from what it cites; `search()` does look inside them, which is a deliberate asymmetry.
- **The illustrations are deliberately not published.** The prose is rights-waived by its author, but the pictures stream from Tilawa's server under permission granted for the Al-Islam app rather than for a public library. The importer drops every `image` block and never publishes `imageBase`, and `imagesIncluded: false` records that in the data itself so a consumer can tell the absence from an oversight. See [CREDITS.md](CREDITS.md).

### Added — parity batch 6: the 99 Names in depth, and the chains of transmission

Two new corpora and two new modules, all seven ports, from Al-Islam 4.6.5.

- **The 99 Names in depth** — `engine.namesDepth`, over the new `data/names-depth.json`: the **root each Name is built on, one of nine themes, an explanation, a line on living by it, and the 194 ayahs the Names appear in**. It is the layer under `namesOfAllah`, joined on the same 1…99 number. Two things worth knowing before you use it: a root prints spaced (`"ر ح م"`) while `morphology.json` stores it closed up, so `rootKey()` is exported and `byRoot` accepts either; and ten occurrences across four Names carry `token: null`, meaning the corpus knows the ayah but could not place the word in it, so a consumer shows the verse whole rather than guessing. Spec: [docs/23-names-depth.md](docs/23-names-depth.md).
- **Chains of transmission** — `engine.isnad`, over `data/isnad.json`: the **isnād of each of the Ten Readings**, from the Prophet ﷺ through the Companions, each imam's teachers, the imam, the links between him and each narrator, and the students who carried the narration on — 10 imams, 20 narrators, 13 Companions. Returned as layers, top to bottom, which is how a diagram draws it. The trap the API removes: **ask `imamOf` rather than splitting the tag**, because four tags name the imam in the Arabic genitive (`"ad-Duri an Abi Amr"`) while his key is the nominative (`"Abu Amr"`). And Abu Jafar genuinely has no teachers layer: he was a Successor who read on Companions himself. Spec: [docs/24-isnad.md](docs/24-isnad.md).

## [1.2.0] - 8 September 2026

The release that made the engine answer questions about words, not just verses. `v1.1` tags the same commit, so it is the same tree.


Synced from upstream **Al-Islam** search/navigation updates.

### Added — parity batch 5: morphology, the repeated phrases, the QUL indexes, and who reads what

Nine new corpora and six new modules, all seven ports, from Al-Islam 4.6.4. `scripts/import-al-islam-data.py` grew the extractors, so a future app-side correction stays one command away.

- **Morphology** — `engine.morphology`, over the new `data/morphology.json`: the **root and dictionary form of all 77,629 words** (Quranic Arabic Corpus via QUL), indexed both ways. It is what lets a search box answer a bare root: `رحم` as text finds only the surface forms spelled that way, while `occurrencesOfRoot` finds all 980 words of `ر ب ب` because they share an id. Ids are 1-based and `0` means the token genuinely has neither, which is the right answer for a particle. Spec: [docs/18-morphology.md](docs/18-morphology.md).
- **Mutashabihat** — `engine.mutashabihat`, over `data/mutashabihat.json`: **814 repeated phrases across 2,232 ayahs**, each with the exact token span carrying it *in every ayah it occurs in*. A different question from `similarAyahs`, and the memoriser's one: two nearly identical ayahs sit side by side and the point is the single word that differs, which a whole-ayah similarity score cannot show and a token span can. Spec: [docs/19-mutashabihat.md](docs/19-mutashabihat.md).
- **QUL topics and passage themes** — `engine.quranTopics` and `engine.ayahThemes`: **2,512 topics in three indexes** (the Clear Quran thematic tree, the Corpus ontology, a general A-Z), and **1,049 passages**, one sentence per run of ayahs. Written up carefully because the shape is easy to get wrong: they are **three independent trees over one pool of topics**, not three partitions. 17 topics are nodes in two of them at once, so every hierarchy accessor takes the tree you mean, and the per-index counts deliberately sum to 2,529 against 2,512 topics. Spec: [docs/20-topics-and-metadata.md](docs/20-topics-and-metadata.md).
- **Mushaf divisions** — `engine.quranMetadata`: 60 hizb, 558 ruku, 7 manzil. `juzPage` covers the divisions a reader meets on the page; these are the three met in a schedule. `range()` reports `until: null` for the last of each rather than inventing a boundary the data does not carry.
- **Qiraat variants** — the new `engine.qiraatVariants`, over three files: **1,634 junctures across 1,409 ayahs, 3,503 readings**, each with who reads it, a transliteration, an English rendering and usually a grammarian's note. The layer the texts cannot supply: `qiraatComparison` says *what* Warsh reads, this says the form is Ḥamzah's and why it matters. Attribution distinguishes an imam whose two narrators agree from a lone narrator whose partner reads otherwise, which is the actual grammar of the printed sources. Plus `places` (where a riwayah differs from Hafs at all, split into word-level and letter-level, because a folded diff finds one kind and only the printed muṣḥaf's khilaf wash finds the other) and `audio` (one reciter reading a verse both ways, for the four riwayat where such a recording exists). Spec: [docs/21-qiraat-variants.md](docs/21-qiraat-variants.md).
- **Word of the day** — `engine.wordOfDay`: 149 curated words with every ayah the same written form appears in. The day mapping is a walk rather than a hash because the corpus is ordered so consecutive days feel varied. Spec: [docs/22-word-of-day.md](docs/22-word-of-day.md).
- **`sources/`** — the upstream JSON the packs and this `data/` were both built from, published here rather than carried in a phone app: the Quran text, "About this Surah", the 99 Names, the seven verified qiraah overlays, the QUL downloads, and the twelve beta riwayat with their whole extraction pipeline. Provenance, not API. See [sources/README.md](sources/README.md).

### Changed

- **`similar-ayahs.json` is version 2 and carries no Quran text; `phrase` is gone from `SimilarMatch` in all seven ports.** The file is now `{ "v": 2, "ayahs": { "2:255": [[surah, ayah, verifiedFlag, spans, labels, score], …] } }`, every row six fields long. The shared wording every source records was located in the matched ayah when the data was built and kept as `spans` (QUL's own placement where its table lists the pair, else the corpus's phrase found in the text), so **41,392 of the 50,782 rows now carry spans** where 2,824 did before, and the words a consumer shows are cut from `quran.json` rather than read from a second copy. The reason is the reason a copy is always wrong eventually: version 1 held 44,000 phrase strings in the sources' own spelling, and they had drifted from the text in their sukoon marks. Fourteen rows whose recorded phrase is a different form of the target's words (لَعْنَةَ ٱللَّهِ against لَّعَنَهُ ٱللَّهُ) carry no span, as they tinted nothing before either. Consumers that displayed `phrase` slice the ayah's tokens by `spans` instead; the recipe is in [docs/13](docs/13-similar-and-themes.md). The file shrank from 4.5 MB to 2.9 MB.
- **`tajweed-lessons.json` is version 4: the lesson body references the Quran too, and the rule card is `ruleCard`.** Version 3 stopped copying the words an *example* points at; version 4 does the same for the Arabic inside the lesson. A drill, a rule-card fragment or a quiz question now holds its Arabic in exactly one of two places: `text` (or `arabic`, on a quiz) when a tutor wrote it, which is the case for the invented drill syllables, the single letters and the isti'adhah; or `ayah`, `[surah, ayahNumber, first, last]`, when the Arabic **is** Quran, and then there is no text field at all. Forty of the 289 rows are references: 7 drills, 21 fragments and 12 quiz questions. Worth stating plainly, because it is not a graceful degradation: **a consumer that ignores `ayah` renders an empty row, not a wrong one.** Cut the words from `quran.json` by the span, exactly as for `wordSpan`; the recipe is in [docs/13](docs/13-similar-and-themes.md).
  Two things came out of teaching the ports to read it, both recorded in [docs/PORTING.md](docs/PORTING.md). Rust and Swift had `text` as a required string, so the file stopped parsing outright rather than showing a blank, and because Rust loads its corpora eagerly that took the whole engine down with it: 30 of 32 parity tests failed on a corpus none of them were testing. And **the rule card has always been `ruleCard`, but all six typed ports declared it as `mushafCard`**, a name the data has never used, so an optional field quietly decoded to nothing and the card's `trigger`, `action`, `hold`, `mnemonic` and fragments were invisible to every consumer since batch 3. It is `ruleCard` everywhere now, the 32 lessons that carry one are pinned by a test, and `mnemonic` is an object of `{arabic, gloss}` rather than a string. `scripts/import-al-islam-data.py` refuses a pack whose references do not resolve against the engine's own text, so a broken span cannot enter the data at all.
- **`tajweed-lessons.json` is version 3: an example's words to listen at are `wordSpan`, not `word`.** The token range into the ayah's raw text replaces the copied words (310 examples, 11 of them cut inside a word, which now span the whole token). Same reasoning as above; the drills, letter sets, quiz and rule cards are Tilawa's own teaching Arabic and are unchanged.
- **`word-of-day.json` keeps `arabic`, now derived by the importer from `quran.json`** at each word's anchor: the app's pack (version 2) no longer stores the form, and the 149 forms the importer derives are byte-identical to the ones the file carried.
- **`qiraat-variants.json` reading and juncture text now follows the Uthmani sukoon convention of `quran.json`.** Quran.com's matrix wrote a real sukoon as U+0652 (ARABIC SUKUN) in its rows for surahs 1 to 18 and as U+06E1 (the head-of-khah the muṣḥaf prints) from surah 19 on, sometimes both inside one word, and typed a sukoon onto long vowels; `quran.json` uses U+06E1 for a consonant, U+0652 only for a silent letter, and nothing on a long vowel, so the two disagreed in the same sheet. Upstream, Al-Islam's pack builder now normalizes each mark by the letter it sits on (a rule proven against the Ḥafṣ text: 77,629 words unchanged and round-tripped), and this file is re-imported from it: 2,373 of 5,137 strings changed, and the 551 juncture headwords that differed from their Ḥafṣ tokens only in sukoon marks now match them. Three strings keep a U+0652 on the alif of وَلَاْ, a typo the rule cannot tell from the real silent alif of سَلَٰسِلَاْ without knowing the word. `places` compares skeletons and is unaffected; a consumer that compared reading text byte for byte against its own copy of the source should re-import. Spec: [docs/21-qiraat-variants.md](docs/21-qiraat-variants.md).
- **`quran.json` transliteration refreshed**, moving **6,235 of the 6,236 ayahs**: the app replaced its own scheme with QUL's *English Transliteration (Tajweed)*. `import-al-islam-data.py` now refreshes the ayah text fields in place rather than leaving them to drift, and the per-surah splits were regenerated.
- **`similar-ayahs.json` gained two fields per row**, and every port was taught to read them: `spans`, the exact token ranges of the shared words in the matched ayah, and `score`, QUL's 0-100 similarity. Tint the spans where they exist and fall back to locating `phrase` where they do not. The refreshed corpus is 5,446 source ayahs over 50,782 rows.
- **`tajweed-lessons.json` refreshed**: 8 chapters and 34 lessons became **10 and 57**.
- **CREDITS.md now names the corpora it always shipped.** Tilawa (Jamil Hammoudeh), qurani.ai, the Quranic Universal Library, QSAC and Quranpedia were behind the word-by-word glosses, the similar ayahs, the themes, the sections and the tajweed course before this release and were not credited here. That is fixed, along with attribution for everything new.

Recorded because each cost real time: the JS `cleanSearch`'s `whitespace` option only *trims*, so a morphology fold built on it silently finds nothing for a spaced root; an untagged union has to try `[String]` before a span shape, because the routinely-empty field is the label list and `[]` decodes as either; and Dart cannot name an enum value `index`, since every Dart enum already has that getter. All three are in [docs/PORTING.md](docs/PORTING.md).

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
