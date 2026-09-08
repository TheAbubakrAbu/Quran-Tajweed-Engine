// @ts-check
/**
 * The other divisions of the mushaf: hizb, ruku and manzil.
 *
 * `juzPage` already covers the two divisions a reader meets on the page. These are the three a
 * reader meets in a schedule: 60 hizb (the juz halved, the unit a memorisation plan is usually
 * written in), 558 ruku (thematic sections, printed in the margin of South Asian mushafs), and
 * 7 manzil (the week-long division for reading the Quran in seven days).
 *
 * Each is stored as its start keys in order, "surah:ayah", so a lookup is a binary search over
 * a sorted list rather than a table with one row per ayah.
 */

/** Sort key for "surah:ayah": surah * 1000 + ayah is unambiguous (no surah has 1000 ayahs). */
function rank(key) {
  const [surah, ayah] = String(key).split(":").map(Number);
  return surah * 1000 + ayah;
}

/**
 * @typedef {Object} Division
 * @property {number} number    1-based
 * @property {number} surah     where it starts
 * @property {number} ayah
 * @property {string} key       "surah:ayah"
 */

class Table {
  /** @param {string[]} starts */
  constructor(starts) {
    this._starts = starts ?? [];
    this._ranks = this._starts.map(rank);
  }

  get length() {
    return this._starts.length;
  }

  /** The 1-based number containing an ayah, or 0 when there is no table. */
  numberFor(surahId, ayahId) {
    const target = surahId * 1000 + ayahId;
    let lo = 0, hi = this._ranks.length - 1, found = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (this._ranks[mid] <= target) { found = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    return found + 1;
  }

  /** @param {number} number @returns {Division|null} */
  start(number) {
    const key = this._starts[number - 1];
    if (!key) return null;
    const [surah, ayah] = key.split(":").map(Number);
    return { number, surah, ayah, key };
  }

  /** Every start, in order. @returns {Division[]} */
  all() {
    return this._starts.map((_, i) => /** @type Division */ (this.start(i + 1)));
  }

  /**
   * The half-open range a division covers: its own start, and the start of the next one, which
   * is null for the last. A range is honest about the end being exclusive, because the last
   * division ends at the end of the Quran and no start key says so.
   */
  range(number) {
    const from = this.start(number);
    if (!from) return null;
    return { from, until: this.start(number + 1) };
  }
}

export class QuranMetadata {
  /**
   * @param {Object} [data] data/quran-metadata.json
   * @param {string[]} [data.hizb]
   * @param {string[]} [data.ruku]
   * @param {string[]} [data.manzil]
   */
  constructor(data = {}) {
    this.hizb = new Table(data.hizb ?? []);
    this.ruku = new Table(data.ruku ?? []);
    this.manzil = new Table(data.manzil ?? []);
  }

  get isLoaded() {
    return this.hizb.length > 0;
  }

  /**
   * All three at once, which is what a "where am I" line under an ayah actually wants.
   * @param {number} surahId @param {number} ayahId
   */
  for(surahId, ayahId) {
    return {
      hizb: this.hizb.numberFor(surahId, ayahId),
      ruku: this.ruku.numberFor(surahId, ayahId),
      manzil: this.manzil.numberFor(surahId, ayahId),
    };
  }

  count() {
    return { hizb: this.hizb.length, ruku: this.ruku.length, manzil: this.manzil.length };
  }
}
