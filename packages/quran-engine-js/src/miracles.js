// @ts-check
/**
 * The scientific-miracles corpus: 202 short articles, each making one claim about the Quran and
 * anchoring it to the ayahs it rests on.
 *
 * An article is a list of BLOCKS in reading order rather than one field of prose, because the
 * layout matters: the claim is a headline, the lead sets it up, a quote carries somebody else's
 * words with the source next to them, an ayah block is a hole the consumer fills from
 * `quran.json`, and the closer asks the rhetorical question the article was built toward.
 *
 * An `ayah` block carries NO text, by design: surah, ayah and endAyah only. The verse belongs to
 * this engine's own Ḥafṣ text, so duplicating it here would be a second copy to keep in step and
 * would pin the article to one riwayah. `citing()` and `ayahRefs()` are the two ends of that
 * link: which articles reach an ayah, and which ayahs one article reaches.
 *
 * There are NO `image` blocks and `imagesIncluded` is false: the site's illustrations are not
 * republished here for licensing reasons, and the prose is written to stand without them. A
 * consumer that leaves a gap for a picture will be waiting forever.
 *
 * Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
 * science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters
 * or sorts by has to come off the ARTICLE. `byLevel` and `levels` both do.
 *
 * @typedef {Object} MiracleCategory
 * @property {string} id      e.g. "cosmology"
 * @property {string} level   a `MiracleLevel`
 *
 * @typedef {Object} MiracleLink
 * @property {string} label
 * @property {string} [url]   an outside page
 * @property {string} [slug]  another article in this corpus; exactly one of the two is set
 *
 * @typedef {Object} MiracleBlock
 * @property {"claim"|"lead"|"text"|"quote"|"ayah"|"closer"} kind
 * @property {string} [text]         claim, lead, text, quote and closer
 * @property {MiracleLink[]} [links] lead and text only
 * @property {string} [sourceLabel]  quote only
 * @property {string} [sourceUrl]    quote only
 * @property {number} [surah]        ayah only
 * @property {number} [ayah]         ayah only, the first of the range
 * @property {number} [endAyah]      ayah only, the last; always present, equal to `ayah` for one
 *
 * @typedef {Object} MiracleArticle
 * @property {string} slug
 * @property {string} title
 * @property {string} category   a `MiracleCategory` id
 * @property {string} level      this article's own level, not its category's
 * @property {MiracleBlock[]} blocks
 *
 * @typedef {Object} MiracleAyahRef
 * @property {number} surah
 * @property {number} ayah
 * @property {number} endAyah
 */

/**
 * The four levels, easiest first. Hard-coded because this is the app's own ordering and nothing in
 * the file states it: alphabetically "extreme" would sort second, which is precisely backwards.
 * @type {string[]}
 */
export const MIRACLE_LEVELS = ["simple", "intermediate", "advanced", "extreme"];

/** The blocks that carry the article's OWN prose. A quote is somebody else's words and an ayah
 * block has no text at all, so neither belongs in `text()`. */
const PROSE_KINDS = new Set(["claim", "lead", "text", "closer"]);

/** Where a level sorts, or past the end for one the corpus invents later. @param {string} level */
function levelRank(level) {
  const i = MIRACLE_LEVELS.indexOf(level);
  return i === -1 ? MIRACLE_LEVELS.length : i;
}

export class Miracles {
  /**
   * @param {Object} [data] parsed data/miracles.json
   * @param {string} [data.source]
   * @param {boolean} [data.imagesIncluded]
   * @param {MiracleCategory[]} [data.categories]
   * @param {MiracleArticle[]} [data.articles]
   */
  constructor(data = {}) {
    /** @type {MiracleArticle[]} */
    this._articles = data.articles ?? [];
    /** @type {MiracleCategory[]} */
    this._categories = data.categories ?? [];
    /** @type {Map<string, MiracleArticle>} */
    this._bySlug = new Map(this._articles.map((a) => [a.slug, a]));
    this._source = data.source ?? "";
    this._imagesIncluded = data.imagesIncluded ?? false;
  }

  get isLoaded() {
    return this._articles.length > 0;
  }

  /** Where the corpus came from and when it was captured. @returns {string} */
  source() {
    return this._source;
  }

  /** False, always: the illustrations are not republished. @returns {boolean} */
  get imagesIncluded() {
    return this._imagesIncluded;
  }

  /** All 202, in corpus order. @returns {MiracleArticle[]} */
  all() {
    return this._articles;
  }

  /** @param {string} slug @returns {MiracleArticle|null} */
  bySlug(slug) {
    return this._bySlug.get(slug) ?? null;
  }

  /** The fifteen categories, in the corpus's own order. @returns {MiracleCategory[]} */
  categories() {
    return this._categories;
  }

  /** @param {string} id @returns {MiracleCategory|null} */
  category(id) {
    return this._categories.find((c) => c.id === id) ?? null;
  }

  /** Every article filed under one category. @param {string} id @returns {MiracleArticle[]} */
  byCategory(id) {
    return this._articles.filter((a) => a.category === id);
  }

  /**
   * Every article at one level. The ARTICLE's level, not its category's: they disagree far more
   * often than they agree, and a reader who picked "simple" means the article.
   * @param {string} level @returns {MiracleArticle[]}
   */
  byLevel(level) {
    return this._articles.filter((a) => a.level === level);
  }

  /** The article levels actually present, easiest first. @returns {string[]} */
  levels() {
    const present = new Set(this._articles.map((a) => a.level));
    return [...present].sort((a, b) => levelRank(a) - levelRank(b) || a.localeCompare(b));
  }

  /**
   * Every article that cites an ayah: the way into this corpus from anywhere else in the engine.
   *
   * An `ayah` block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An article
   * that cites the same ayah in two blocks is still listed once.
   * @param {number} surahId @param {number} ayahId @returns {MiracleArticle[]}
   */
  citing(surahId, ayahId) {
    return this._articles.filter((article) => article.blocks.some((b) => b.kind === "ayah"
      && b.surah === surahId
      && b.ayah !== undefined && b.endAyah !== undefined
      && ayahId >= b.ayah && ayahId <= b.endAyah));
  }

  /**
   * The ayah ranges one article cites, in the order it cites them.
   * @param {string} slug @returns {MiracleAyahRef[]}
   */
  ayahRefs(slug) {
    const article = this._bySlug.get(slug);
    if (!article) return [];
    return article.blocks
      .filter((b) => b.kind === "ayah")
      .map((b) => ({ surah: /** @type {number} */ (b.surah), ayah: /** @type {number} */ (b.ayah), endAyah: /** @type {number} */ (b.endAyah) }));
  }

  /**
   * Articles whose title or prose matches a query, case-insensitively. Quotes are searched as
   * well: a reader looking for a word remembers reading it, not who wrote it.
   * @param {string} query @param {number} [limit] @returns {MiracleArticle[]}
   */
  search(query, limit = 25) {
    const q = String(query ?? "").trim().toLowerCase();
    if (!q) return [];
    return this._articles
      .filter((a) => a.title.toLowerCase().includes(q)
        || a.blocks.some((b) => (b.text ?? "").toLowerCase().includes(q)))
      .slice(0, limit);
  }

  /**
   * One article's own prose, blocks joined with a blank line in reading order.
   *
   * Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
   * folding them in would put somebody else's words into the article's voice and would break a
   * citation off from what it cites. Ayah blocks are skipped because they carry no text at all,
   * only a reference for the consumer to resolve.
   * @param {string} slug @returns {string}
   */
  text(slug) {
    const article = this._bySlug.get(slug);
    if (!article) return "";
    return article.blocks
      .filter((b) => PROSE_KINDS.has(b.kind))
      .map((b) => b.text ?? "")
      .filter(Boolean)
      .join("\n\n");
  }

  count() {
    return {
      articles: this._articles.length,
      categories: this._categories.length,
      ayahRefs: this._articles.reduce(
        (n, a) => n + a.blocks.filter((b) => b.kind === "ayah").length, 0),
    };
  }
}
