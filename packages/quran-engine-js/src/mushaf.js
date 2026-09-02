// @ts-check
/**
 * The printed mushaf: twenty riwayat as page-exact facsimiles, and the page table each one is
 * actually paginated by.
 *
 * A riwayah's pagination is NOT Hafs' pagination. Readings merge and split ayahs and spell words
 * differently, so the same ayah sits on a different page in Warsh's print than in Hafs'. The page
 * numbers on `quran.json`'s ayahs are the Madani (Hafs) ones; `page(s, a, riwayah)` here is that
 * riwayah's own. Every facsimile is exactly 604 pages on the Madani division, so PDF page N is
 * mushaf page N with no offset table.
 *
 * Twelve of the twenty ship their printed mushaf and page table but no text: their text is
 * machine-extracted and not yet proofread, so it is not published, and the line and tajweed data
 * that index into it stay out with it. `riwayah(slug).textIncluded` says which is which.
 */

/**
 * @typedef {Object} RiwayahEntry
 * @property {string} riwayah        slug, e.g. "warsh"
 * @property {string} tag            the tag the Al-Islam app stores ("" for Hafs)
 * @property {string} name           "Warsh an Nafi"
 * @property {string} nameArabic
 * @property {string} imam           the qiraah's imam, e.g. "Nafi"
 * @property {string} imamArabic
 * @property {number} narratorDiedAH
 * @property {string} pdf            path to the facsimile, relative to data/mushaf/
 * @property {number} pdfBytes
 * @property {string} pages          path to the page table
 * @property {string|null} lines     path to the line table, when the text ships
 * @property {string|null} tajweed   path to the riwayah tajweed pack, when one exists
 * @property {boolean} textIncluded
 */

export class Mushaf {
  /**
   * @param {Object} [data]
   * @param {{ totalPages:number, note?:string, riwayat:RiwayahEntry[] }} [data.index] data/mushaf/index.json
   * @param {Record<string, {riwayah:string,totalPages:number,pages:Record<string,Record<string,number>>}>} [data.pages]
   *        slug -> data/mushaf/pages/<slug>.json
   * @param {Record<string, {riwayah:string,version:number,lineBreaks:Record<string,Record<string,number[]>>}>} [data.lines]
   *        slug -> data/mushaf/lines/<slug>.json
   */
  constructor({ index, pages = {}, lines = {} } = /** @type any */ ({})) {
    /** @type {RiwayahEntry[]} */
    this._riwayat = index?.riwayat ?? [];
    this._totalPages = index?.totalPages ?? 604;
    this._byRiwayah = new Map(this._riwayat.map((r) => [r.riwayah, r]));
    this._pages = pages;
    this._lines = lines;
    /** Inverted page -> ayahs, built the first time a riwayah is asked. @type {Map<string, Map<number, {surah:number,ayah:number}[]>>} */
    this._onPage = new Map();
  }

  /** Every riwayah, in the classical order of the Ten Qiraat. */
  riwayat() {
    return this._riwayat;
  }

  /** Only the riwayat whose text this engine publishes (the eight verified ones). */
  riwayatWithText() {
    return this._riwayat.filter((r) => r.textIncluded);
  }

  /** @param {string} slug */
  riwayah(slug) {
    return this._byRiwayah.get(slug) ?? null;
  }

  /** Every facsimile has this many pages. */
  totalPages() {
    return this._totalPages;
  }

  /**
   * Path to a riwayah's facsimile, relative to `data/mushaf/`. The file is one solid xz stream over
   * the PDF (a third of the plain size, fully lossless): decompress it before handing it to a PDF
   * renderer.
   * @param {string} slug
   */
  pdfPath(slug) {
    return this._byRiwayah.get(slug)?.pdf ?? null;
  }

  /**
   * The page an ayah is printed on in this riwayah's own mushaf.
   * @param {number} surahId
   * @param {number} ayahId
   * @param {string} [riwayah="hafs"]
   */
  page(surahId, ayahId, riwayah = "hafs") {
    const table = this._pages[riwayah]?.pages;
    const page = table?.[String(surahId)]?.[String(ayahId)];
    return typeof page === "number" ? page : null;
  }

  /**
   * Every ayah printed on a page, in mushaf order.
   * @param {number} page
   * @param {string} [riwayah="hafs"]
   */
  ayahsOnPage(page, riwayah = "hafs") {
    return this._pageIndex(riwayah).get(page) ?? [];
  }

  /**
   * The first ayah of a page - what a "go to page 213" jump lands on.
   * @param {number} page
   * @param {string} [riwayah="hafs"]
   */
  firstAyahOfPage(page, riwayah = "hafs") {
    return this.ayahsOnPage(page, riwayah)[0] ?? null;
  }

  /**
   * Where this riwayah's printed mushaf breaks the ayah across lines: character offsets into the
   * ayah's own text at which a new line starts. Null when the riwayah's text (and so its line
   * table) is not published.
   * @param {number} surahId
   * @param {number} ayahId
   * @param {string} [riwayah="hafs"]
   */
  lineBreaks(surahId, ayahId, riwayah = "hafs") {
    const breaks = this._lines[riwayah]?.lineBreaks?.[String(surahId)]?.[String(ayahId)];
    return Array.isArray(breaks) ? breaks : null;
  }

  /**
   * The ayahs a riwayah marks as reading differently from Hafs somewhere - a quick "is there
   * anything to compare here" check. Needs the riwayah tajweed pack; see `engine.qiraatTajweed`.
   * @param {string} riwayah
   */
  hasTajweedPack(riwayah) {
    return this._byRiwayah.get(riwayah)?.tajweed != null;
  }

  /** @param {string} riwayah */
  _pageIndex(riwayah) {
    const cached = this._onPage.get(riwayah);
    if (cached) return cached;
    /** @type {Map<number, {surah:number,ayah:number}[]>} */
    const index = new Map();
    const table = this._pages[riwayah]?.pages ?? {};
    const surahs = Object.keys(table).map(Number).sort((a, b) => a - b);
    for (const surah of surahs) {
      const ayahs = Object.keys(table[String(surah)]).map(Number).sort((a, b) => a - b);
      for (const ayah of ayahs) {
        const page = table[String(surah)][String(ayah)];
        const bucket = index.get(page);
        if (bucket) bucket.push({ surah, ayah });
        else index.set(page, [{ surah, ayah }]);
      }
    }
    this._onPage.set(riwayah, index);
    return index;
  }
}
