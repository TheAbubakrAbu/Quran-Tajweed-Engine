# 06 · Ayah search

Search Quran text in Arabic (with or without diacritics) and English (Saheeh, Mustafa, transliteration), plus surah-name and reference (`2:255`) lookup. Faithful port of the search system in `QuranData.swift`.

> **Key behaviours:** verse search is **unranked** — results come back in mushaf order. Verse-text search **rejects any query containing a digit** (numeric / reference queries go through *surah* search instead).

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
2. If the query contains a boolean operator → boolean path (below).
3. If `cleaned` contains a digit → return `[]` (numeric/refs are surah search).
4. `useArabic = containsArabicLetters(query)`.
5. A verse matches when **either**:
   - the whole `cleaned` query is a **substring** of the relevant blob, **or**
   - the query tokens **phrase-prefix-match** the verse tokens (all but the last token exact-equal, last is a prefix).
6. For Arabic with "ignore silent letters" on, the silent variant is also consulted.
7. Results are returned in mushaf order; paginate with `offset`/`limit`.

```js
engine.search.searchVerses("lord of the worlds");        // → matches 1:2 (and others), mushaf order
engine.search.searchVerses("الرحمن الرحيم");              // Arabic substring/token match
engine.search.searchVerses("2 255");                      // [] — digits rejected in verse search
engine.search.searchVerses("rahm", { ignoreSilentLetters: true, limit: 20 });
```

## Boolean / advanced grammar

Triggered when the query contains any of `& | ! # ^ % $`. Split into OR-groups on `|`, each group into AND-terms on `&`. Per-term prefixes/suffixes:

| Token | Meaning |
|---|---|
| `!term` | negate |
| `#term` | exact match (Arabic: diacritic-sensitive via the tashkeel blob; English: exact phrase) |
| `^term` | starts-with (string or any token prefix) |
| `term%` / `term$` | ends-with |
| `^term%` | exact |
| `term` | contains |

```js
engine.search.searchVerses("allah & lord");      // verses containing both
engine.search.searchVerses("light | noor");      // either
engine.search.searchVerses("allah & !lord");     // allah but not lord
```

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
