# FAQ

## General

**What is this?** A reusable, open-source Quran engine: the data (Quran text, translations, 7 readings, tajweed rules, reciters) plus code to use it (Quran browsing, tajweed coloring, juz/page nav, audio, search, sorting, caching). It powers a Quran app without you re-solving the hard parts.

**What can I build with it?** Quran readers, tajweed learning tools, memorization (hifz) apps, audio players, search tools, widgets, research/NLP pipelines — on web, mobile, desktop, or server.

**Which languages/frameworks are supported?** Officially: JavaScript/TypeScript, Python, Swift, Kotlin, Dart, Go, Rust (in [`/packages`](../packages)). Anything else: read the JSON in [`/data`](../data) and follow [PORTING.md](PORTING.md) — it's designed so a new port is a day's work.

**Is it free?** Yes. MIT licensed. See [licensing](#licensing--attribution) below.

## Data

**Where does the data come from?** Extracted, with attribution, from the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars) app by Abubakr Elmallah. Full provenance in [CREDITS.md](../CREDITS.md).

**How big is it?** `quran.json` ≈ 5 MB; each qiraah file ≈ 1.6 MB; `surah-info.json` ≈ 1.8 MB; the tajweed corpus ≈ 5 MB. For web, use the per-surah files in `data/surahs/` and `data/tajweed/` and load on demand; the lightweight `data/surahs/index.json` (no verse text) is enough for a surah list.

**Can I trust the Quran text / is it certified?** The Arabic is the Hafs an Asim Uthmani text from the upstream app and must be preserved unmodified. For a production *mushaf*, validate against an authoritative source (e.g. the King Fahd Complex text). The **tajweed coloring** is a high-quality heuristic teaching aid, not a certified mushaf — see below.

**How accurate is the tajweed?** The engine implements the rules in [docs/02](02-tajweed.md) faithfully, with two documented simplifications (full final-`ر` vowel context; muqatta'at lazim-harfi sub-typing). It's excellent for learning and display. If you need scholar-certified coloring, treat this as a starting point and review against a trusted mushaf.

**Can I add my own translation / tafsir / word-by-word data?** Yes — add a JSON file under `/data`, document its schema in `docs/`, and surface it in your port. Keep the Arabic text untouched.

## Tajweed

**Do I need to run the detection engine?** Usually no. The pre-computed corpus (`data/tajweed-annotations.json`) already has every ayah's spans — just map each `rule` to a color. Run the detector only to color text outside the bundled Hafs (other qiraat, user input). See [architecture → two ways to do tajweed](architecture.md#two-ways-to-do-tajweed).

**Why are my colored slices off by a character?** You're probably indexing by code point or byte instead of UTF-16. Annotation offsets are UTF-16 units; convert in Python/Rust/Go (each port has a `utf16_slice` helper). See [PORTING.md → String indexing](PORTING.md#string-indexing-utf-16-offsets).

**Can I change the colors?** Yes — they live in `data/tajweed-rules.json` (`categories[].colorHex`). Override them in your UI or edit the file.

## Audio

**Are audio files included?** No. The engine builds **URLs** to third-party CDNs (mp3quran.net for full surahs, alquran.cloud for ayah-by-ayah). You fetch/stream them with your platform's audio player. Respect each provider's terms.

**How do I play a whole surah continuously, or repeat an ayah?** The engine gives you URLs; build the queue/repeat logic in your player (a few lines). See [recipes](recipes.md) and [docs/05](05-ayah-recitations.md).

**Can it work offline?** Yes. The text/tajweed data is fully local. For offline *audio*, download surah files and cache them using the paths in [docs/08](08-caching.md); the JS package includes an `AudioCache` helper.

**A reciter has no ayah-by-ayah audio — what happens?** It falls back to the Minshawi (Murattal) ayah feed automatically; show the fallback name during ayah playback (`ayahNowPlayingName`). See [docs/05](05-ayah-recitations.md).

## Search

**Why does searching "2:255" return nothing in verse search?** Verse-text search rejects any query with a digit by design. Numeric/reference queries go through *surah* search: `searchSurahs("2:255")` / `parseReference("2:255")`. See [docs/06](06-ayah-search.md).

**Are results ranked?** No — verse search returns matches in mushaf order (surah, then ayah). Paginate with offset/limit.

**Does Arabic search ignore diacritics?** Yes. The normalizer folds hamza/alif/waw/yaa variants and strips marks, so users can type with or without tashkeel. There's also an optional "ignore silent letters" mode.

## Licensing & attribution

**What's the license?** MIT (see [LICENSE](../LICENSE)). You may use, modify, sell, and redistribute — **with attribution**.

**What must I attribute?** Credit this engine and the upstream Al-Islam project / Abubakr Elmallah, and preserve the data provenance in [CREDITS.md](../CREDITS.md). The translations (Saheeh International; Mustafa Khattab) and tafsir (Maududi; Ibn Ashur) remain their authors' work — check their terms for redistribution beyond educational use.

**Can I use it in a paid app?** Yes, MIT permits commercial use. Keep the attribution and the Arabic text unaltered.

## Contributing

**How do I add a language port or fix a bug?** See [CONTRIBUTING.md](../CONTRIBUTING.md). New ports follow [PORTING.md](PORTING.md) and ship a test asserting the canonical cases.
