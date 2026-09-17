# What's new

Every release, newest first. Each one is tagged on GitHub; the [releases page](https://github.com/TheAbubakrAbu/Quran-Tajweed-Engine/releases) carries the same notes.

This page is the short version, written to be read. [CHANGELOG.md](../CHANGELOG.md) is the long one: every corpus, every API, and the traps each new shape sets for a consumer. A version here describes the **data and the seven ports together**: a release is only cut once JS, Python, Swift, Kotlin, Dart, Go and Rust all pass the same parity suite, so "available across all seven language ports" is a statement about the tests, not a plan.

---

## 1.2.0 (8 September 2026)

The release that made the engine answer questions about *words*, not just verses.

- **Root and dictionary-form lookups across all 77,629 words** (Quranic Arabic Corpus, via QUL). This is what lets a search box answer a bare root: `رحم` as plain text finds only the surface forms spelled that way, while a root lookup finds every word built on it. → [docs/18](18-morphology.md)
- **814 repeated phrases** with the exact token span carrying each one, in every ayah it occurs in. A different question from similar-ayah matching, and the memoriser's one: two nearly identical ayahs sit side by side and the point is the single word that differs. → [docs/19](19-mutashabihat.md)
- **2,512 topics, 1,049 passage themes**, and hizb, ruku and manzil navigation. The topics are three independent trees over one pool, not three partitions, so the per-index counts deliberately do not sum to the total. → [docs/20](20-topics-and-metadata.md)
- **Qiraat variants** with reader attribution, and audio comparisons for the supported riwayat. → [docs/21](21-qiraat-variants.md)
- **Word of the Day**: 149 curated words. → [docs/22](22-word-of-day.md)
- **The Tajweed course expanded to 57 lessons across 10 chapters.** → [docs/02](02-tajweed.md)
- **Refreshed transliteration**, and similar-ayah matches that now carry word spans and a similarity score rather than a bare pairing. → [docs/13](13-similar-and-themes.md)

> `v1.1` and `v1.2.0` are the same tree: both tags point at commit `c81b28a`. Everything above landed between 1.0 and that commit, and 1.2.0 is the version to cite.

## 1.0 (29 June 2026)

The first release: the Quran text, the tajweed engine, and the seven ports.

- **The complete Quran** with translations and transliteration, plus seven qiraat beside Hafs. → [docs/01](01-quran.md)
- **Scalar-driven tajweed colouring**, specified precisely enough to reimplement from the document alone. → [docs/02](02-tajweed.md)
- **Juz and page navigation**, and **ayah search** in Arabic and English, by reference and boolean. → [docs/03](03-juz-page.md), [docs/06](06-ayah-search.md)
- **Recitation audio**, full-surah and ayah-by-ayah. → [docs/04](04-surah-recitations.md), [docs/05](05-ayah-recitations.md)
- **The 99 Names**, the Arabic alphabet, surah sorting and a caching contract. → [docs/07](07-surah-sorting.md), [docs/08](08-caching.md)
- **All seven ports** (JS, Python, Swift, Kotlin, Dart, Go, Rust) against one parity suite, with integration guides for iOS, Android, Flutter and React Native.
