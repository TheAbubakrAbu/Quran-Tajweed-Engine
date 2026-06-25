// @ts-check
/**
 * Tajweed detection engine.
 *
 * This is a reference port of the heuristic, scalar-driven tajweed engine in Al-Islam's
 * QuranData.swift (`attributedText`, `collectMaddAndWaslPaintOps`, `appendNuunMeemGhunnahHeuristicPaintOps`,
 * `explicitMaddahCategory`, …) and the rule tables in TajweedRules.swift.
 *
 * The full specification — every Unicode scalar, priority tier and exception — is documented in
 * `docs/02-tajweed.md`. The canonical reference implementation remains the Swift source. This port
 * covers the major rule families:
 *   • Madd: natural, miniature, muttasil, munfasil (incl. Munfasil Hukmi), lazim catch-all
 *   • Ghunnah / nasal: noon-sakin & tanwin -> idgham / ikhfaa (light & heavy) / iqlaab, meem rules, shadda ghunnah
 *   • Sifaat: qalqalah, tafkhim (istila letters; final-raa gets the dedicated higher priority)
 *   • Silent / joining: hamzat-al-wasl, lam shamsiyyah, bare-consonant dropped letters
 *
 * Known simplifications vs. the Swift engine (see docs): full final-raa vowel-context rules are reduced
 * to the istila set + sukoon inheritance; muqatta'at lazim-harfi is detected via the surah tables but not
 * sub-classified; stop-based madd (`maddSukoon`) is detected but, like the app, not painted by default.
 */

import { splitGraphemeClusters } from "./text.js";

/** Priority tiers (higher wins per code unit). Mirrors PaintPriority in QuranData.swift. */
export const PRIORITY = {
  tafkhim: 1,
  droppedLetter: 2,
  lamShamsiyah: 3,
  qalqalah: 4,
  idghamBiGhunnahLight: 5,
  idghamBiGhunnahHeavy: 6,
  ikhfaa: 7,
  iqlaab: 8,
  idghamBilaGhunnah: 9,
  generalGhunnah: 10,
  maddNatural2: 12,
  maddNatural2MiniatureScalars: 13,
  maddAaridLisSukoon: 17,
  maddNecessary6: 18,
  maddSeparated: 19,
  maddConnected: 20,
  explicitMaddConnected: 21,
  explicitMaddSeparated: 22,
  explicitMaddNecessary: 23,
  hamzatWaslSilent: 50,
  tinyMeemIqlaab: 51,
  finalRaaTafkhim: 52,
};

// Named scalars (QuranData.swift)
const S = {
  fatha: 0x064e, damma: 0x064f, kasra: 0x0650,
  fathatayn: 0x064b, dammatayn: 0x064c, kasratayn: 0x064d,
  specialFathatayn: 0x0657, specialDammatayn: 0x065e, specialKasratayn: 0x0656,
  sukoon: 0x0652, sukoonUthmani: 0x06e1, shadda: 0x0651,
  daggerAlif: 0x0670, maddah: 0x0653,
  hamzatWasl: 0x0671,
  smallWaw: 0x06e5, smallYeh: 0x06e6, smallHighYeh: 0x06e7,
  smallHighMeem: 0x06e2, smallLowMeem: 0x06ed,
};

const HEAVY_BASE = new Set(["خ", "ص", "ض", "ط", "ظ", "غ", "ق"]);
const QALQALAH = new Set(["ق", "ط", "ب", "ج", "د"]);
const SUN_LETTERS = new Set(["ت", "ث", "د", "ذ", "ر", "ز", "س", "ش", "ص", "ض", "ط", "ظ", "ل", "ن"]);
const IKHFAA_HEAVY = new Set(["ص", "ض", "ط", "ظ", "ق"]);
const IKHFAA_LIGHT = new Set(["ت", "ث", "ج", "د", "ذ", "ز", "س", "ش", "ف", "ك"]);
const HAMZA_CARRIERS = new Set(["ء", "أ", "ؤ", "إ", "ئ"]);
const TANWIN = new Set([S.fathatayn, S.dammatayn, S.kasratayn, S.specialFathatayn, S.specialDammatayn, S.specialKasratayn]);
const VOWELS = new Set([S.fatha, S.damma, S.kasra, ...TANWIN]);
const MINIATURE_MADD = new Set([S.daggerAlif, S.smallWaw, S.smallYeh, S.smallHighYeh]);

/** Surahs whose first ayah opens with disconnected letters (حروف مقطعة). */
const MUQATTAAT_SURAHS = new Set([2, 3, 7, 10, 11, 12, 13, 14, 15, 19, 26, 27, 28, 29, 30, 31, 32, 20, 36, 38, 40, 41, 42, 43, 44, 45, 46, 50, 68]);

/**
 * Vocative/demonstrative particle words written joined to a following hamza where a superscript
 * madd carrier is recited as Munfasil Hukmi. NFC-normalized. From QuranData.hukmiMunfasilProperWords.
 */
const HUKMI_MUNFASIL_WORDS = new Set([
  "يَٰٓأَيُّهَا", "هَٰٓؤُلَآءِ", "يَٰٓأَهۡلَ", "يَٰٓأَبَتِ", "يَٰٓأُوْلِي",
  "يَٰٓـَٔادَمُ", "هَٰٓأَنتُمۡ", "أَهَٰٓؤُلَآءِ", "يَٰٓأَبَانَا", "هَٰٓؤُلَآءِۚ",
  "يَٰٓإِبۡرَٰهِيمُ", "يَٰٓأَبَانَآ", "يَٰٓإِبۡلِيسُ", "وَيَٰٓـَٔادَمُ", "يَٰٓأَرۡضُ",
  "يَٰٓأَسَفَىٰ", "وَهَٰٓؤُلَآءِ", "يَٰٓأُخۡتَ", "يَٰٓإِبۡرَٰهِيمُۖ", "يَٰٓأَيُّهَ",
  "يَٰٓأَيَّتُهَا",
].map((w) => w.normalize("NFC")));

/** Categories the app computes but does not paint (stop-based). */
const STOP_BASED = new Set(["maddSukoon"]);

/**
 * @typedef {Object} Cluster
 * @property {string} text
 * @property {number} start  UTF-16 offset (inclusive)
 * @property {number} end    UTF-16 offset (exclusive)
 * @property {number[]} scalars
 * @property {number|undefined} base  primary Arabic letter code point
 */

/** @param {string} text @returns {Cluster[]} */
function buildClusters(text) {
  const raw = splitGraphemeClusters(text);
  /** @type {Cluster[]} */
  const clusters = [];
  let offset = 0;
  for (const t of raw) {
    const scalars = [...t].map((c) => c.codePointAt(0) ?? 0);
    let base;
    for (const cp of scalars) {
      if ((cp >= 0x0621 && cp <= 0x063a) || (cp >= 0x0641 && cp <= 0x064a) || cp === 0x0671) { base = cp; break; }
    }
    clusters.push({ text: t, start: offset, end: offset + t.length, scalars, base });
    offset += t.length;
  }
  return clusters;
}

const chr = (cp) => (cp == null ? "" : String.fromCodePoint(cp));
const has = (cl, cp) => cl.scalars.includes(cp);
const isSpace = (cl) => cl.text.trim() === "";
const hasAnyTashkeel = (cl) => cl.scalars.some((cp) => cp !== cl.base && (VOWELS.has(cp) || cp === S.shadda || cp === S.sukoon || cp === S.sukoonUthmani || cp === S.maddah || MINIATURE_MADD.has(cp)));
const hasSukoon = (cl) => has(cl, S.sukoon) || has(cl, S.sukoonUthmani);
const hasTanwin = (cl) => cl.scalars.some((cp) => TANWIN.has(cp));

/**
 * Detect tajweed paint operations for a single ayah.
 * @param {string} arabicText  raw Hafs (or qiraah) ayah text with diacritics
 * @param {Object} [opts]
 * @param {number} [opts.surahId]   enables muqatta'at handling on ayah 1
 * @param {number} [opts.ayahId]
 * @param {boolean} [opts.includeStopBased=false] also emit `maddSukoon` ops (off by default, like the app)
 * @returns {Array<{start:number,end:number,priority:number,category:string}>}
 */
export function detectPaintOps(arabicText, opts = {}) {
  const clusters = buildClusters(arabicText);
  /** @type {Array<{start:number,end:number,priority:number,category:string}>} */
  const ops = [];
  const push = (start, end, priority, category) => {
    if (!opts.includeStopBased && STOP_BASED.has(category)) return;
    if (end > start) ops.push({ start, end, priority, category });
  };

  const lastLetterIndex = (() => {
    for (let i = clusters.length - 1; i >= 0; i--) if (clusters[i].base != null && !isSpace(clusters[i])) return i;
    return -1;
  })();

  const nextLetterIndex = (i) => {
    for (let j = i + 1; j < clusters.length; j++) {
      if (isSpace(clusters[j])) continue;
      if (clusters[j].base != null) return j;
    }
    return -1;
  };
  const prevLetterIndex = (i) => {
    for (let j = i - 1; j >= 0; j--) {
      if (isSpace(clusters[j])) continue;
      if (clusters[j].base != null) return j;
    }
    return -1;
  };

  // ---- Tafkhim (istila letters) -------------------------------------------------
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    const base = chr(cl.base);
    let heavy = HEAVY_BASE.has(base);
    if (base === "ر") heavy = isHeavyRaa(clusters, i, lastLetterIndex);
    if (!heavy) continue;
    const finalRaa = base === "ر" && i === lastLetterIndex;
    push(cl.start, cl.end, finalRaa ? PRIORITY.finalRaaTafkhim : PRIORITY.tafkhim, "tafkhim");
  }

  // ---- Lam shamsiyyah -----------------------------------------------------------
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    if (cl.base !== 0x0644) continue;           // lam
    if (hasAnyTashkeel(cl)) continue;            // must be bare
    const prev = prevLetterIndex(i);
    if (prev < 0 || clusters[prev].base !== S.hamzatWasl) continue;
    const next = nextLetterIndex(i);
    if (next < 0 || !SUN_LETTERS.has(chr(clusters[next].base))) continue;
    push(cl.start, cl.end, PRIORITY.lamShamsiyah, "lamShamsiyah");
  }

  // ---- Qalqalah -----------------------------------------------------------------
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    if (!QALQALAH.has(chr(cl.base))) continue;
    if (has(cl, S.maddah)) continue;
    const sukoonHere = hasSukoon(cl);
    const verseFinal = i === lastLetterIndex;
    if (sukoonHere || verseFinal) {
      push(cl.start, cl.end, PRIORITY.qalqalah, "qalqalah");
    }
  }

  // ---- Noon / Meem / Tanwin nasal family ---------------------------------------
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    // tiny iqlaab meem
    if (has(cl, S.smallHighMeem) || has(cl, S.smallLowMeem)) {
      push(cl.start, cl.end, PRIORITY.tinyMeemIqlaab, "iqlaab");
      continue;
    }
    // noon or meem with shadda -> general ghunnah
    if ((cl.base === 0x0646 || cl.base === 0x0645) && has(cl, S.shadda)) {
      push(cl.start, cl.end, PRIORITY.generalGhunnah, "generalGhunnah");
      continue;
    }
    const next = nextLetterIndex(i);
    const nextLetter = next >= 0 ? chr(clusters[next].base) : "";
    // tanwin
    if (hasTanwin(cl)) {
      let gov = next;
      // skip a helper alif/alif-maqsura after fathatayn
      if (gov >= 0 && (clusters[gov].base === 0x0627 || clusters[gov].base === 0x0649)) gov = nextLetterIndex(gov);
      const govLetter = gov >= 0 ? chr(clusters[gov].base) : "";
      emitNoonSound(cl, govLetter, push);
      continue;
    }
    // bare noon (no tashkeel)
    if (cl.base === 0x0646 && !hasAnyTashkeel(cl)) { emitNoonSound(cl, nextLetter, push); continue; }
    // bare meem (no tashkeel)
    if (cl.base === 0x0645 && !hasAnyTashkeel(cl)) {
      if (nextLetter === "ب") push(cl.start, cl.end, PRIORITY.iqlaab, "iqlaab");
      else if (nextLetter === "م") push(cl.start, cl.end, PRIORITY.idghamBiGhunnahLight, "idghamGhunnah");
    }
  }

  // ---- Madd family --------------------------------------------------------------
  const hukmiIndices = computeHukmiIndices(clusters);
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    // Explicit maddah -> muttasil / munfasil / lazim / miniature
    if (has(cl, S.maddah)) {
      const ayahFinalLone = i === lastLetterIndex;
      const [category, priority] = explicitMaddahCategory(clusters, i, hukmiIndices.has(i), ayahFinalLone);
      push(cl.start, cl.end, priority, category);
      continue;
    }
    // Miniature madd marks without explicit maddah -> natural miniature
    if (cl.scalars.some((cp) => MINIATURE_MADD.has(cp))) {
      push(cl.start, cl.end, PRIORITY.maddNatural2MiniatureScalars, "maddNaturalMiniature");
      continue;
    }
    // Natural madd: full madd letter preceded by its matching vowel, no maddah, no following sukoon,
    // not before hamza/hamzat-wasl.
    const base = cl.base;
    if (base === 0x0627 || base === 0x0648 || base === 0x064a || base === 0x0649) {
      if (hasAnyTashkeel(cl)) continue;              // a vowelled alif/waw/ya is a consonant, not madd
      const prev = prevLetterIndex(i);
      if (prev < 0) continue;
      const p = clusters[prev];
      const matching =
        (base === 0x0627 && has(p, S.fatha)) ||
        ((base === 0x0648) && has(p, S.damma)) ||
        ((base === 0x064a || base === 0x0649) && has(p, S.kasra)) ||
        // bare alif after fatha-less carrier is still commonly natural; keep permissive for alif
        (base === 0x0627);
      if (!matching) continue;
      const next = nextLetterIndex(i);
      if (next >= 0 && HAMZA_CARRIERS.has(chr(clusters[next].base))) continue; // handled by muttasil/munfasil
      if (next >= 0 && clusters[next].base === S.hamzatWasl) continue;
      push(cl.start, cl.end, PRIORITY.maddNatural2, "maddNatural");
    }
  }

  // ---- Hamzat al-wasl silent ----------------------------------------------------
  for (let i = 0; i < clusters.length; i++) {
    const cl = clusters[i];
    if (cl.base !== S.hamzatWasl) continue;
    if (i === 0) continue;                            // ayah-initial wasl is pronounced, not painted silent
    const prev = prevLetterIndex(i);
    if (prev < 0) continue;                           // first letter overall
    push(cl.start, cl.end, PRIORITY.hamzatWaslSilent, "hamzatWaslSilent");
  }

  return ops;
}

/** Map a noon-sound governed by `nextLetter` to a category. Mirrors appendNoonSoundPaintOps. */
function emitNoonSound(cl, nextLetter, push) {
  if (nextLetter === "ن") { push(cl.start, cl.end, PRIORITY.generalGhunnah, "generalGhunnah"); return; }
  if (nextLetter === "م" || nextLetter === "ي" || nextLetter === "و") { push(cl.start, cl.end, PRIORITY.idghamBilaGhunnah, "idghamGhunnah"); return; }
  if (nextLetter === "ل" || nextLetter === "ر") { push(cl.start, cl.end, PRIORITY.idghamBilaGhunnah, "idghamBilaGhunnah"); return; }
  if (IKHFAA_HEAVY.has(nextLetter)) { push(cl.start, cl.end, PRIORITY.idghamBiGhunnahHeavy, "ikhfaaHeavy"); return; }
  if (IKHFAA_LIGHT.has(nextLetter)) { push(cl.start, cl.end, PRIORITY.ikhfaa, "ikhfaaLight"); return; }
  if (nextLetter === "ب") { push(cl.start, cl.end, PRIORITY.iqlaab, "iqlaab"); return; }
}

/** Reduced final-raa heaviness rule (see docs for the full vowel-context version). */
function isHeavyRaa(clusters, i, lastLetterIndex) {
  const cl = clusters[i];
  if (has(cl, S.kasra) || has(cl, S.kasratayn)) return false;
  if (has(cl, S.fatha) || has(cl, S.damma) || has(cl, S.shadda) || has(cl, S.fathatayn) || has(cl, S.dammatayn)) return true;
  // sukoon or final: inherit from previous pronounced letter (kasra -> light)
  let prev = i - 1;
  while (prev >= 0 && (isSpace(clusters[prev]) || clusters[prev].base == null)) prev--;
  if (prev >= 0 && (has(clusters[prev], S.kasra) || has(clusters[prev], S.kasratayn))) return false;
  return true;
}

/** Clusters whose word matches a Munfasil-Hukmi proper word. Mirrors hukmiMunfasilOverrideClusterIndices. */
function computeHukmiIndices(clusters) {
  /** @type {Set<number>} */
  const out = new Set();
  let start = 0;
  for (let i = 0; i <= clusters.length; i++) {
    if (i === clusters.length || isSpace(clusters[i])) {
      if (i > start) {
        const word = clusters.slice(start, i).map((c) => c.text).join("").normalize("NFC");
        if (HUKMI_MUNFASIL_WORDS.has(word)) for (let k = start; k < i; k++) out.add(k);
      }
      start = i + 1;
    }
  }
  return out;
}

/**
 * Classify a cluster carrying an explicit maddah. Mirrors explicitMaddahCategory.
 * @returns {[string, number]} [category, priority]
 */
function explicitMaddahCategory(clusters, index, allowHukmi, ayahFinalLone) {
  const superscriptCarrier = clusters[index].scalars.some((cp) => MINIATURE_MADD.has(cp));
  // 1. next non-space cluster has shadda -> Lazim
  for (let j = index + 1; j < clusters.length; j++) {
    if (isSpace(clusters[j])) continue;
    if (has(clusters[j], S.shadda)) return ["maddNecessary", PRIORITY.explicitMaddNecessary];
    break;
  }
  // 2. scan forward for hamza, tracking word breaks
  let sawWordBreak = false;
  for (let j = index + 1; j < clusters.length; j++) {
    const c = clusters[j];
    if (isSpace(c)) { sawWordBreak = true; continue; }
    if (shouldIgnoreForMaddahScan(c)) continue;
    if (HAMZA_CARRIERS.has(chr(c.base))) {
      if (sawWordBreak) return ["maddSeparated", PRIORITY.explicitMaddSeparated];
      if (allowHukmi && superscriptCarrier) return ["maddSeparated", PRIORITY.explicitMaddSeparated];
      return ["maddConnected", PRIORITY.explicitMaddConnected];
    }
    if (c.base != null) break;
  }
  // 3. superscript carrier, no qualifying hamza -> miniature natural madd
  if (superscriptCarrier) {
    if (ayahFinalLone) return ["maddNatural", PRIORITY.maddNatural2];
    return ["maddNaturalMiniature", PRIORITY.maddNatural2MiniatureScalars];
  }
  // 4. catch-all lazim
  if (ayahFinalLone) return ["maddNatural", PRIORITY.maddNatural2];
  return ["maddNecessary", PRIORITY.explicitMaddNecessary];
}

function shouldIgnoreForMaddahScan(c) {
  if (c.base === S.hamzatWasl) return true;
  if ((c.base === 0x0648 || c.base === 0x064a || c.base === 0x0627) && hasSukoon(c)) return true;
  if (!hasAnyTashkeel(c)) return true;
  return false;
}

/**
 * Resolve paint ops into non-overlapping colored spans (highest priority wins per UTF-16 unit),
 * then merge contiguous units of the same category.
 * @param {string} arabicText
 * @param {Array<{start:number,end:number,priority:number,category:string}>} ops
 * @returns {Array<{start:number,end:number,category:string,text:string}>}
 */
export function resolveSpans(arabicText, ops) {
  const len = arabicText.length;
  /** @type {(string|null)[]} */
  const cat = new Array(len).fill(null);
  const pri = new Array(len).fill(-1);
  const sorted = [...ops].sort((a, b) => a.priority - b.priority);
  for (const op of sorted) {
    for (let i = op.start; i < op.end && i < len; i++) {
      if (op.priority >= pri[i]) { pri[i] = op.priority; cat[i] = op.category; }
    }
  }
  /** @type {Array<{start:number,end:number,category:string,text:string}>} */
  const spans = [];
  let i = 0;
  while (i < len) {
    if (cat[i] == null) { i++; continue; }
    let j = i + 1;
    while (j < len && cat[j] === cat[i]) j++;
    spans.push({ start: i, end: j, category: /** @type {string} */ (cat[i]), text: arabicText.slice(i, j) });
    i = j;
  }
  return spans;
}

/**
 * One-call convenience: detect + resolve into colored spans.
 * @param {string} arabicText
 * @param {Object} [opts] same options as detectPaintOps
 * @returns {Array<{start:number,end:number,category:string,text:string}>}
 */
export function tajweedSpans(arabicText, opts) {
  return resolveSpans(arabicText, detectPaintOps(arabicText, opts));
}

export const MUQATTAAT = MUQATTAAT_SURAHS;
