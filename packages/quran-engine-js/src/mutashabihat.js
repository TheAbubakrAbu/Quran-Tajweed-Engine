// @ts-check
/**
 * Mutashabihat: the phrases the Quran repeats, and every place each one occurs.
 *
 * A different thing from `similarAyahs`, and worth keeping apart. Similar ayahs answers "what
 * else reads like this verse" with whole-ayah matches, ranked. This answers "which exact run of
 * words does this verse share with others, and which words are they" - the memoriser's question,
 * where two nearly identical ayahs sit side by side and the one word that differs is the whole
 * point. 814 phrases from the Quranic Universal Library's Mutashabihat ul Quran set.
 *
 * Spans are 0-based inclusive token ranges of the ayah's raw Hafs text, mapped at build time, so
 * a consumer splits the ayah on whitespace and slices straight in without matching anything.
 */

/**
 * @typedef {Object} Phrase
 * @property {number} id
 * @property {string} source        the ayah the phrase is defined from, "9:87"
 * @property {[number, number]} span  inclusive token range inside that ayah
 * @property {number} count         total occurrences across the Quran
 * @property {number} ayahCount     ayahs carrying it
 * @property {number} surahCount    surahs carrying it
 * @property {Record<string, Array<[number, number]>>} occurrences  ayah key -> spans in that ayah
 * @property {number} wordCount     how long the phrase is, in words
 */

/** Mushaf order for "surah:ayah" keys. */
function compareKeys(a, b) {
  const [sa, aa] = a.split(":").map(Number);
  const [sb, ab] = b.split(":").map(Number);
  if (!Number.isFinite(sa) || !Number.isFinite(sb)) return a < b ? -1 : a > b ? 1 : 0;
  return sa !== sb ? sa - sb : aa - ab;
}

export class Mutashabihat {
  /**
   * @param {Object} [data] data/mutashabihat.json
   * @param {Record<string, any>} [data.phrases]
   * @param {Record<string, number[]>} [data.index]
   */
  constructor(data = {}) {
    this._phrases = data.phrases ?? {};
    this._index = data.index ?? {};
  }

  /** Whether a corpus was supplied. */
  get isLoaded() {
    return Object.keys(this._phrases).length > 0;
  }

  /**
   * The phrases this ayah carries, longest first so the most distinctive shared wording leads.
   * @param {number} surahId @param {number} ayahId
   * @returns {Phrase[]}
   */
  phrasesFor(surahId, ayahId) {
    const ids = this._index[`${surahId}:${ayahId}`] ?? [];
    const out = [];
    for (const id of ids) {
      const phrase = this.phrase(id);
      if (phrase) out.push(phrase);
    }
    return out.sort((a, b) => b.wordCount - a.wordCount || a.id - b.id);
  }

  /** @param {number} id @returns {Phrase|null} */
  phrase(id) {
    const row = this._phrases[String(id)];
    if (!row) return null;
    const span = /** @type {[number, number]} */ (row.span);
    return {
      id,
      source: row.source,
      span,
      count: row.count,
      ayahCount: row.ayahCount,
      surahCount: row.surahCount,
      occurrences: row.occurrences ?? {},
      wordCount: span[1] - span[0] + 1,
    };
  }

  /**
   * Whether the ayah carries any: a dictionary hit, cheap enough to gate a button on.
   * @param {number} surahId @param {number} ayahId
   */
  has(surahId, ayahId) {
    return (this._index[`${surahId}:${ayahId}`]?.length ?? 0) > 0;
  }

  /**
   * A phrase's occurrences in mushaf order, each with the spans carrying it there.
   * @param {number} id
   * @returns {Array<{surah: number, ayah: number, key: string, spans: Array<[number, number]>}>}
   */
  occurrences(id) {
    const phrase = this.phrase(id);
    if (!phrase) return [];
    return Object.keys(phrase.occurrences).sort(compareKeys).map((key) => {
      const [surah, ayah] = key.split(":").map(Number);
      return { surah, ayah, key, spans: phrase.occurrences[key] };
    });
  }

  /**
   * The phrase's own words, sliced out of the ayah text you hand it. The engine does not carry
   * the text into this module, because the caller already has the ayah it is displaying.
   * @param {number} id @param {string} sourceAyahText  the raw text of `phrase.source`
   */
  textOf(id, sourceAyahText) {
    const phrase = this.phrase(id);
    if (!phrase) return "";
    const tokens = String(sourceAyahText ?? "").split(/\s+/).filter(Boolean);
    return tokens.slice(phrase.span[0], phrase.span[1] + 1).join(" ");
  }

  /** How many phrases, and how many ayahs carry at least one. */
  count() {
    return { phrases: Object.keys(this._phrases).length, ayahs: Object.keys(this._index).length };
  }
}
