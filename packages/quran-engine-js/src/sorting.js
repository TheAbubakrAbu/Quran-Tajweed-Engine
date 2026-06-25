// @ts-check
/**
 * Surah sorting & filtering. Mirrors orderedQuranSurahs / supportsSurahSortDirection in QuranView.swift.
 *
 * Every comparator is ascending with `id` as the tiebreaker; descending is the reverse of that array
 * (so ties stay id-ascending within a reversed block). The "surah" natural order bypasses sorting.
 */

/** @typedef {'surah'|'revelation'|'ayahs'|'page'|'words'|'letters'} SortMode */
/** @typedef {'surahOrder'|'ascending'|'descending'} SortDirection */

/** Sort modes that honour a direction. Others are intrinsically ordered. */
const DIRECTIONAL = new Set(["revelation", "page", "ayahs", "words", "letters"]);

/**
 * @param {import('./quran.js').Surah[]} surahs
 * @param {SortMode} mode
 * @param {SortDirection} [direction='ascending']
 * @returns {import('./quran.js').Surah[]}
 */
export function sortSurahs(surahs, mode = "surah", direction = "ascending") {
  if (direction === "surahOrder" || mode === "surah") {
    return [...surahs].sort((a, b) => a.id - b.id);
  }

  /** @param {import('./quran.js').Surah} s */
  const key = (s) => {
    switch (mode) {
      case "revelation": return s.revelationOrder ?? Number.MAX_SAFE_INTEGER;
      case "ayahs": return s.numberOfAyahs;
      case "page": return s.numberOfPages ?? 0;
      case "words": return s.wordCount ?? 0;
      case "letters": return s.letterCount ?? 0;
      default: return s.id;
    }
  };

  const asc = [...surahs].sort((a, b) => {
    const ka = key(a), kb = key(b);
    if (ka === kb) return a.id - b.id;
    return ka - kb;
  });

  // revelation always behaves as its intrinsic order unless explicitly descending.
  if (direction === "descending" && DIRECTIONAL.has(mode)) return asc.reverse();
  return asc;
}

/** @param {SortMode} mode */
export function supportsDirection(mode) {
  return DIRECTIONAL.has(mode);
}

/**
 * Filter by revelation type. Mirrors the makkan/madani query filter.
 * @param {import('./quran.js').Surah[]} surahs
 * @param {'makkan'|'madinan'} type
 */
export function filterByRevelationType(surahs, type) {
  return surahs.filter((s) => s.type === type);
}
