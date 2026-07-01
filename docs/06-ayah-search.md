# 06 · Ayah search

Search Quran text in Arabic (with or without diacritics) and English (Saheeh, Mustafa, transliteration), plus surah-name and reference (`2:255`) lookup. Faithful port of the search system in `QuranData.swift`.

> **Key behaviours:** verse search is **unranked** — results come back in mushaf order. Verse-text search **rejects any query containing a digit** (numeric / reference queries go through *surah* search instead) — and that digit check runs **before** the boolean path, so even `allah & 2` returns nothing. Regular (non-boolean) matching is **pure substring**: word and sentence boundaries don't matter (`رب` matches inside `ربهم`). Whole-word / phrase matching is opt-in via the `=` operator.

## The verse index

Each ayah is indexed into three blobs + token lists:

| Field | Source | Normalization |
|---|---|---|
| `arabicBlob` | raw + clean Arabic | fold hamza/alif/waw/yaa variants → strip all marks & punctuation → lowercase → collapse spaces |
| `silentArabicBlob` | raw + clean Arabic | remove silent letters (sukoon'd alif/waw/yaa/lam, hamzat-wasl), then the Arabic fold above |
| `englishBlob` | Saheeh + Mustafa + transliteration | the same fold (no marks) |
| `arabicTashkeelBlob` | raw Arabic | keep **only** diacritics (inverse) — used by exact `#` boolean matches |
| `englishExactBlob` | english joined | lowercase + collapse spaces, **no** mark stripping |
| `*Tokens` | each blob | split on spaces |

The Arabic fold map (carriers → bare letters): `ٱ أ إ آ ى → ا`, `ؤ → و`, `ئ ى → ي`, `ة → ه`, dagger-alif → `ا`, hamza → removed. The four boolean operators `& | ! #` survive the strip.

## Query flow

1. `cleaned = cleanSearch(query)`. Empty → no results.
2. If `cleaned` contains a digit → return `[]` (numeric/refs are surah search). **This is checked before the boolean path.**
3. If the query contains a boolean operator → boolean path (below).
4. `useArabic = containsArabicLetters(query)`.
5. A verse matches when the whole `cleaned` query is a **substring** of the relevant blob (`arabicBlob` or `englishBlob`). Pure `contains` — no token/phrase logic in the regular path.
6. For Arabic with "ignore silent letters" on, the `silentArabicBlob` is also consulted (substring) when the main blob misses.
7. Results are returned in mushaf order; paginate with `offset`/`limit`.

```js
engine.search.searchVerses("lord of the worlds");        // → matches 1:2 (and others), mushaf order
engine.search.searchVerses("الرحمن الرحيم");              // Arabic substring/token match
engine.search.searchVerses("2 255");                      // [] — digits rejected in verse search
engine.search.searchVerses("rahm", { ignoreSilentLetters: true, limit: 20 });
```

## Boolean / advanced grammar

Triggered when the query contains any of `& | ! # ^ % $ =`. Split into OR-groups on `|`, each group into AND-terms on `&` (`&&`/`||` collapse to single). A term whose cleaned value is empty is dropped. Per-term prefixes/suffixes (stripped in this order: `!`, then `#`, then `=`, then `^`, then trailing `%`/`$`):

| Token | Meaning |
|---|---|
| `!term` | negate (toggles; `!!` cancels) |
| `#term` | exact match (Arabic: diacritic-sensitive via the tashkeel blob; English: exact-phrase blob). Combines with the mode below. |
| `=term` | **whole-word** — `term`'s words must appear as a consecutive run of whole words (`=رب` matches the word رب but not ربهم) |
| `^term` | starts-with (whole string or any token prefix) |
| `term%` / `term$` | ends-with |
| `^term%` | exact (whole string or a whole token) |
| `term` | contains (substring) |

`#` sets diacritic/exact-phrase sensitivity and is orthogonal to the match mode (`=`/`^`/`%`/plain), so `#=الله` is a whole-word, tashkeel-sensitive match.

```js
engine.search.searchVerses("allah & lord");      // verses containing both
engine.search.searchVerses("light | noor");      // either
engine.search.searchVerses("allah & !lord");     // allah but not lord
```

## Page / juz quick-jump shorthands

Verse search rejects digits (above), so numeric and reference queries are routed elsewhere by the host app's search bar. The Al-Islam app recognizes a few quick-jump forms that map onto engine primitives rather than verse search:

| Typed query | Resolves to | Engine call |
|---|---|---|
| `page 50` / `50` | mushaf page 50 | `juzPage.firstAyahOfPage(50)` |
| `juz 5` / `5` | juz 5 | `juzPage.firstAyahOfJuz(5)` |
| `-1`, `-2` … `-30` | **juz counted from the end** (`-1` → juz 30, `-30` → juz 1) | `juzPage.juzFromEnd(n)` → `firstAyahOfJuz(...)` |

`juzFromEnd` is documented in [03 · Juz & Page](03-juz-page.md#juz-from-the-end). The engine ships these as navigation primitives; the exact search-box parsing (which keyword maps to which) is the host app's concern.

## Surah & reference search

Separate from verse search:

```js
engine.search.searchSurahs("fatihah");      // → [surah 1]   (name, alias, number, or "2:255")
engine.search.searchSurahs("makki");        // → all makkan surahs
engine.search.parseReference("2:255");      // → { surah: 2, ayah: 255 }
engine.search.parseReference("baqarah 10"); // → { surah: 2, ayah: 10 }
```

Surah matching uses a per-surah blob of `nameArabic + nameTransliteration + nameEnglish + similarNames + id` (folded), plus a compact spaceless variant, plus makkan/madani aliases.

## Performance note

The reference Swift build also maintains inverted token + prefix indexes (prefix length 2 for Arabic, 3 for English) to avoid scanning all 6236 verses, AND-intersecting candidate sets across query tokens. The JS port filters linearly (fast enough for 6236 short blobs); add the inverted index if you need it.

Reference: [`src/search.js`](../packages/quran-engine-js/src/search.js), [`src/text.js`](../packages/quran-engine-js/src/text.js).
