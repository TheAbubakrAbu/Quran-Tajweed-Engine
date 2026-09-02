// @ts-check
/**
 * Where a surah changes subject: an outline of each surah as titled ayah ranges, plus one sentence
 * saying what the surah as a whole is about.
 *
 * This answers "I am at 18:60 - what is this passage doing here", which neither the translation nor
 * the tafsir answers quickly, because both are written per ayah. 111 of the 114 surahs carry an
 * outline; al-Fatihah, Fussilat and ad-Dukhan do not.
 *
 * THE OUTLINE IS A TREE, FLATTENED. Ranges are inclusive, in mushaf order, and MAY NEST: a broad
 * section is followed by the sections inside it, parent before children (Hud opens with 1-24
 * "Doctrine facts", then 1-4, 5-6, 7-11, 12-17, 18-24 within it). They also do not tile the surah -
 * an ayah can belong to no section at all. So an ayah has a CHAIN of sections, outermost first,
 * which is what `sectionsFor` returns; `outline` rebuilds the same thing as a tree.
 */

/**
 * @typedef {Object} SurahSection
 * @property {number} from     first ayah, inclusive
 * @property {number} to       last ayah, inclusive
 * @property {string} english  the section's title
 * @property {string} arabic   the same, as the source records it
 */

/**
 * @typedef {SurahSection & {children: OutlineNode[]}} OutlineNode
 */

export class SurahSections {
  /**
   * @param {Record<string, {overview?: string, sections?: [number, number, string, string][]}>} [data]
   *        data/surah-sections.json
   */
  constructor(data = {}) {
    this._data = data;
  }

  /** One sentence on what the whole surah is about, "" when none is recorded. */
  overview(surahId) {
    return this._data[String(surahId)]?.overview ?? "";
  }

  /**
   * The surah's sections, flat and in the order the source records them (a parent immediately
   * before the sections inside it).
   * @param {number} surahId
   * @returns {SurahSection[]}
   */
  sections(surahId) {
    const rows = this._data[String(surahId)]?.sections ?? [];
    return rows.map(([from, to, english, arabic]) => ({ from, to, english, arabic }));
  }

  /**
   * The same sections as a tree: top-level passages, each with the sections inside it.
   * @param {number} surahId
   * @returns {OutlineNode[]}
   */
  outline(surahId) {
    /** @type {OutlineNode[]} */
    const roots = [];
    /** @type {OutlineNode[]} */
    const stack = [];
    for (const section of this.sections(surahId)) {
      // A section belongs to the nearest still-open range that fully contains it.
      while (stack.length && !contains(stack[stack.length - 1], section)) stack.pop();
      /** @type {OutlineNode} */
      const node = { ...section, children: [] };
      if (stack.length) stack[stack.length - 1].children.push(node);
      else roots.push(node);
      stack.push(node);
    }
    return roots;
  }

  /**
   * Every section covering an ayah, outermost first - the breadcrumb for "you are here". Empty when
   * the surah has no outline, or when this ayah falls between sections.
   * @param {number} surahId @param {number} ayahId
   * @returns {SurahSection[]}
   */
  sectionsFor(surahId, ayahId) {
    return this.sections(surahId).filter((s) => ayahId >= s.from && ayahId <= s.to);
  }

  /**
   * The most specific section covering an ayah - the innermost of the chain, which is the heading a
   * reader wants beside the verse.
   * @param {number} surahId @param {number} ayahId
   * @returns {SurahSection|null}
   */
  sectionFor(surahId, ayahId) {
    const chain = this.sectionsFor(surahId, ayahId);
    return chain.length ? chain[chain.length - 1] : null;
  }

  /** Whether this surah has an outline at all - cheap enough to gate a UI section on. */
  hasSections(surahId) {
    return (this._data[String(surahId)]?.sections?.length ?? 0) > 0;
  }

  /** How many surahs carry an outline. */
  count() {
    return Object.keys(this._data).filter((id) => this.hasSections(Number(id))).length;
  }

  /**
   * Sections whose title carries `query`, across every surah - "where does the Quran tell the story
   * of Nuh" answered by heading rather than by keyword.
   * @param {string} query
   * @returns {(SurahSection & {surah:number})[]}
   */
  search(query) {
    const trimmed = query.trim();
    const needle = trimmed.toLowerCase();
    if (!needle) return [];
    /** @type {(SurahSection & {surah:number})[]} */
    const out = [];
    for (const id of Object.keys(this._data).map(Number).sort((a, b) => a - b)) {
      for (const section of this.sections(id)) {
        if (section.english.toLowerCase().includes(needle) || section.arabic.includes(trimmed)) {
          out.push({ ...section, surah: id });
        }
      }
    }
    return out;
  }
}

/** @param {SurahSection} outer @param {SurahSection} inner */
function contains(outer, inner) {
  return outer.from <= inner.from && inner.to <= outer.to;
}
