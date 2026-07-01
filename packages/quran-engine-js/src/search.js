// @ts-check
/**
 * Ayah & surah search. Faithful port of the search system in QuranData.swift.
 *
 * Verse matching is unranked — results come back in mushaf order (surah, then ayah). Each verse is
 * indexed into three Arabic/English blobs plus token lists; a query matches a verse when the whole
 * cleaned query is a substring of the blob OR the query tokens phrase-prefix-match the verse tokens.
 *
 * Arabic searching also supports a "silent letters ignored" lenient variant, and a small boolean
 * grammar (`&` AND, `|` OR, `!` NOT, `#` exact, `^` starts-with, `%`/`$` ends-with).
 */

import {
  cleanSearch,
  searchTokens,
  arabicTashkeelBlob,
  exactPhraseBlob,
  containsArabicLetters,
  removingSilentArabicLettersForSearch,
  removingArabicMarks,
  arabicDigitsToWestern,
} from "./text.js";

/**
 * @typedef {Object} VerseIndexEntry
 * @property {string} id      "surah:ayah"
 * @property {number} surah
 * @property {number} ayah
 * @property {string} arabicTashkeelBlob
 * @property {string} englishExactBlob
 * @property {string} arabicBlob
 * @property {string} silentArabicBlob
 * @property {string} englishBlob
 * @property {string[]} arabicTokens
 * @property {string[]} silentArabicTokens
 * @property {string[]} englishTokens
 */

const BOOLEAN_CHARS = /[&|!#^%$=]/;

export class Search {
  /**
   * @param {import('./quran.js').Quran} quran
   * @param {{ riwayah?: string }} [opts]
   */
  constructor(quran, opts = {}) {
    this.quran = quran;
    this.riwayah = opts.riwayah;
    /** @type {VerseIndexEntry[]} */
    this.index = [];
    this.rebuild();
    this._buildSurahIndex();
  }

  rebuild() {
    /** @type {VerseIndexEntry[]} */
    const idx = [];
    for (const { surah, ayah } of this.quran.eachAyah()) {
      const raw = this.quran.arabicText(surah.id, ayah.id, this.riwayah) ?? "";
      const clean = this.quran.cleanArabicText(surah.id, ayah.id, this.riwayah) ?? "";
      idx.push(makeEntry(surah.id, ayah.id, raw, clean, ayah.textEnglishSaheeh ?? "", ayah.textEnglishMustafa ?? "", ayah.textTransliteration ?? ""));
    }
    this.index = idx;
  }

  /**
   * Search verse text.
   * @param {string} query
   * @param {{ offset?: number, limit?: number, ignoreSilentLetters?: boolean }} [opts]
   * @returns {VerseIndexEntry[]}
   */
  searchVerses(query, opts = {}) {
    const cleaned = cleanSearch(query, { whitespace: true });
    if (!cleaned) return [];

    // Reject any query containing a digit (numeric/refs go via surah search). Done BEFORE the boolean
    // path — exactly as QuranData.search(term:) does — so even a boolean query with a digit returns [].
    if (/\p{Nd}/u.test(cleaned)) return [];

    // Boolean grammar?
    if (BOOLEAN_CHARS.test(query)) return this._booleanSearch(query, opts);

    const useArabic = containsArabicLetters(query);
    const silentQuery = useArabic && opts.ignoreSilentLetters
      ? cleanSearch(removingSilentArabicLettersForSearch(query), { whitespace: true })
      : "";

    // Plain substring search in mushaf order — word/sentence boundaries DON'T matter (a query matches
    // anywhere it appears, e.g. "رب" inside "ربهم"). Whole-word / phrase matching lives in the `=`
    // operator; `#` does an exact (case/tashkeel-sensitive) match. Mirrors regularSearchEntryMatches().
    /** @param {VerseIndexEntry} e */
    const matches = (e) => {
      if (useArabic) {
        if (e.arabicBlob.includes(cleaned)) return true;
        if (!silentQuery) return false;
        return e.silentArabicBlob.includes(silentQuery);
      }
      return e.englishBlob.includes(cleaned);
    };

    return paginate(this.index.filter(matches), opts);
  }

  // ---- Boolean search ----------------------------------------------------------
  _booleanSearch(query, opts) {
    const useArabic = containsArabicLetters(query);
    const normalized = query.replace(/&&/g, "&").replace(/\|\|/g, "|");
    // Drop any term whose cleaned value is empty — booleanAyahSearchTerm() returns nil in that case.
    const orGroups = normalized.split("|").map((g) =>
      g.split("&").map((t) => parseTerm(t)).filter((t) => t.value !== "")
    ).filter((g) => g.length);
    if (!orGroups.length) return [];

    /** @param {VerseIndexEntry} e */
    const matches = (e) => orGroups.some((andTerms) => andTerms.every((term) => {
      const hit = termMatch(e, term, useArabic);
      return term.negate ? !hit : hit;
    }));
    return paginate(this.index.filter(matches), opts);
  }

  // ---- Surah search ------------------------------------------------------------
  _buildSurahIndex() {
    /** @type {Array<{surah:import('./quran.js').Surah, blob:string, compact:string, upper:string}>} */
    this._surahIndex = this.quran.all().map((s) => {
      const names = [s.nameArabic, s.nameTransliteration, s.nameEnglish, ...(s.similarNames ?? [])];
      const blob = cleanSearch([...names, String(s.id), removingArabicMarks(s.nameArabic)].join(" "));
      return { surah: s, blob, compact: blob.replace(/ /g, ""), upper: `${s.nameEnglish} ${s.nameTransliteration}`.toUpperCase() };
    });
  }

  /**
   * Search surahs by name, number, "2:255" reference, or makkan/madani.
   * @param {string} query
   * @returns {import('./quran.js').Surah[]}
   */
  searchSurahs(query) {
    const trimmed = query.trim();
    if (!trimmed) return this.quran.all();

    // makkan/madani filter
    const norm = cleanSearch(trimmed).replace(/ /g, "");
    const MAKKAN = ["makkah", "makkan", "makki"];
    const MADINAN = ["madinah", "madinan", "madina", "madani"];
    const aliasHit = (aliases) => aliases.some((a) => a.startsWith(norm) || norm.startsWith(a));
    if (norm && aliasHit(MAKKAN)) return this.quran.all().filter((s) => s.type === "makkan");
    if (norm && aliasHit(MADINAN)) return this.quran.all().filter((s) => s.type === "madinan");

    const ref = this.parseReference(trimmed);
    const cleaned = cleanSearch(trimmed.replace(/:/g, ""));
    const compact = cleaned.replace(/ /g, "");
    const upper = trimmed.toUpperCase();
    const numeric = ref?.surah ?? toNumber(cleaned);

    return this._surahIndex
      .filter(({ surah, blob, compact: bc, upper: bu }) =>
        numeric === surah.id ||
        (bu && upper.includes(bu)) ||
        (cleaned && blob.includes(cleaned)) ||
        (compact && bc.includes(compact)))
      .map((x) => x.surah);
  }

  /**
   * Parse an ayah reference like "2:255", "2 255", or Arabic-digit forms.
   * @param {string} query
   * @returns {{surah:number, ayah?:number}|null}
   */
  parseReference(query) {
    const parts = arabicDigitsToWestern(query).split(/[:\s]+/).filter(Boolean);
    if (!parts.length) return null;
    // resolve surah part (number or name)
    let surah = toNumber(parts[0]);
    if (surah == null) {
      const cleaned = cleanSearch(parts[0]);
      const m = this._surahIndex.find((x) => x.blob.split(" ").includes(cleaned) || x.compact.includes(cleaned.replace(/ /g, "")));
      surah = m?.surah.id ?? null;
    }
    if (surah == null) return null;
    const ayah = parts.length >= 2 ? toNumber(parts[1]) ?? undefined : undefined;
    return { surah, ayah: ayah == null ? undefined : ayah };
  }
}

// ---- helpers ------------------------------------------------------------------

function makeEntry(surahId, ayahId, raw, clean, saheeh, mustafa, translit) {
  const arabicBlob = [raw, clean].map((t) => cleanSearch(t)).join(" ");
  const silentArabicBlob = [raw, clean].map((t) => cleanSearch(removingSilentArabicLettersForSearch(t))).join(" ");
  const englishBlob = [saheeh, mustafa, translit].map((t) => cleanSearch(t)).join(" ");
  return {
    id: `${surahId}:${ayahId}`, surah: surahId, ayah: ayahId,
    arabicTashkeelBlob: arabicTashkeelBlob(raw),
    englishExactBlob: exactPhraseBlob([saheeh, mustafa, translit].join(" ")),
    arabicBlob, silentArabicBlob, englishBlob,
    arabicTokens: searchTokens(arabicBlob),
    silentArabicTokens: searchTokens(silentArabicBlob),
    englishTokens: searchTokens(englishBlob),
  };
}

/**
 * Consecutive-token match: query tokens appear as a consecutive run of haystack tokens. The leading
 * tokens must match exactly; the final token must match exactly when `lastMustBeExact`, otherwise it
 * only has to be a prefix. Mirrors consecutiveTokenMatch().
 * @param {string[]} haystack @param {string[]} query @param {boolean} lastMustBeExact
 */
function consecutiveTokenMatch(haystack, query, lastMustBeExact) {
  if (!query.length || haystack.length < query.length) return false;
  for (let start = 0; start <= haystack.length - query.length; start++) {
    let ok = true;
    for (let k = 0; k < query.length; k++) {
      const word = haystack[start + k], term = query[k];
      if (k === query.length - 1 && !lastMustBeExact) { if (!word.startsWith(term)) { ok = false; break; } }
      else if (word !== term) { ok = false; break; }
    }
    if (ok) return true;
  }
  return false;
}

/** @param {{offset?:number,limit?:number}} opts */
function paginate(arr, opts) {
  const offset = opts.offset ?? 0;
  const limit = opts.limit;
  return limit == null ? arr.slice(offset) : arr.slice(offset, offset + limit);
}

function toNumber(s) {
  const n = Number(arabicDigitsToWestern(s).trim());
  return Number.isInteger(n) && s.trim() !== "" ? n : null;
}

/**
 * Parse a single boolean term. Mirrors booleanAyahSearchTerm(): strips (in order) leading `!` (negate,
 * toggles), `#` (exact / tashkeel-sensitive), `=` (whole-word), one `^` (starts-with), one trailing
 * `%`/`$` (ends-with); the leftover text becomes the value + the tashkeel/exact-phrase patterns.
 */
function parseTerm(rawTerm) {
  let t = rawTerm.trim();
  let negate = false;
  while (t.startsWith("!")) { negate = !negate; t = t.slice(1).trim(); }
  let requiresTashkeel = false;
  while (t.startsWith("#")) { requiresTashkeel = true; t = t.slice(1).trim(); }
  let wholeWord = false;
  while (t.startsWith("=")) { wholeWord = true; t = t.slice(1).trim(); }
  let startsWith = false;
  if (t.startsWith("^")) { startsWith = true; t = t.slice(1).trim(); }
  let endsWith = false;
  if (t.endsWith("%") || t.endsWith("$")) { endsWith = true; t = t.slice(0, -1).trim(); }

  const value = cleanSearch(t, { whitespace: true });
  let matchMode;
  if (wholeWord) matchMode = "wholeWord";
  else if (startsWith && endsWith) matchMode = "exact";
  else if (startsWith) matchMode = "startsWith";
  else if (endsWith) matchMode = "endsWith";
  else matchMode = "contains";

  const isArabic = containsArabicLetters(t);
  return {
    value,
    negate,
    matchMode,
    requiresTashkeelMatch: requiresTashkeel && isArabic,
    tashkeelPattern: arabicTashkeelBlob(t),
    requiresExactEnglishMatch: requiresTashkeel && !isArabic,
    exactEnglishPhrase: exactPhraseBlob(t),
  };
}

/**
 * Match a single term's value against a blob/token list under one of the five modes. Mirrors
 * ayahTermMatch().
 */
function ayahTermMatch(haystack, tokens, term, mode) {
  switch (mode) {
    case "startsWith": return haystack.startsWith(term) || tokens.some((w) => w.startsWith(term));
    case "endsWith": return haystack.endsWith(term) || tokens.some((w) => w.endsWith(term));
    case "exact": return haystack === term || tokens.includes(term);
    case "wholeWord": return consecutiveTokenMatch(tokens, searchTokens(term), true);
    case "contains":
    default: return haystack.includes(term);
  }
}

/** Per-term match (un-negated). Mirrors the per-term branch of matchesBooleanAyahSearch(). */
function termMatch(e, term, useArabic) {
  if (useArabic && term.requiresTashkeelMatch) {
    const lettersMatch = ayahTermMatch(e.arabicBlob, e.arabicTokens, term.value, term.matchMode);
    const tashkeelMatch = term.tashkeelPattern === "" || e.arabicTashkeelBlob.includes(term.tashkeelPattern);
    return lettersMatch && tashkeelMatch;
  }
  if (!useArabic && term.requiresExactEnglishMatch) {
    const exactTokens = searchTokens(term.exactEnglishPhrase);
    return term.exactEnglishPhrase !== "" && ayahTermMatch(e.englishExactBlob, exactTokens, term.exactEnglishPhrase, term.matchMode);
  }
  const haystack = useArabic ? e.arabicBlob : e.englishBlob;
  const tokens = useArabic ? e.arabicTokens : e.englishTokens;
  return ayahTermMatch(haystack, tokens, term.value, term.matchMode);
}
