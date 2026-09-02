// @ts-check
/**
 * Browse the Quran by theme: 323 topics, each grouped under a category and a domain, each listing
 * the ayahs that speak to it.
 *
 * The ayah lists are curated, not derived, so a topic is a real reading path rather than a keyword
 * hit list. `topicsFor` inverts them, which is how an ayah screen can say "this ayah appears under
 * Tawheed and Divine Mercy".
 */

/**
 * @typedef {Object} Topic
 * @property {string} id
 * @property {string} name
 * @property {string} description
 * @property {string} category
 * @property {string} domain
 * @property {string[]} ayahs   "2:255" references, in mushaf order
 */

export class Themes {
  /** @param {{topics: Topic[]}} [data] data/themes.json */
  constructor(data = /** @type any */ ({})) {
    /** @type {Topic[]} */
    this._topics = data?.topics ?? [];
    this._byId = new Map(this._topics.map((t) => [t.id, t]));
    /** @type {Map<string, Topic[]>|null} */
    this._byAyah = null;
  }

  /** Every topic, in the order the corpus lists them. */
  all() {
    return this._topics;
  }

  /** @param {string} id */
  topic(id) {
    return this._byId.get(id) ?? null;
  }

  /** The distinct domains ("Aqeedah (Islamic Creed)", ...), in first-seen order. */
  domains() {
    return [...new Set(this._topics.map((t) => t.domain))];
  }

  /** The distinct categories, optionally within one domain. @param {string} [domain] */
  categories(domain) {
    const scope = domain ? this._topics.filter((t) => t.domain === domain) : this._topics;
    return [...new Set(scope.map((t) => t.category))];
  }

  /** @param {string} domain */
  inDomain(domain) {
    return this._topics.filter((t) => t.domain === domain);
  }

  /** @param {string} category */
  inCategory(category) {
    return this._topics.filter((t) => t.category === category);
  }

  /**
   * The topics an ayah appears under.
   * @param {number} surahId @param {number} ayahId
   * @returns {Topic[]}
   */
  topicsFor(surahId, ayahId) {
    if (!this._byAyah) {
      this._byAyah = new Map();
      for (const topic of this._topics) {
        for (const ref of topic.ayahs) {
          const bucket = this._byAyah.get(ref);
          if (bucket) bucket.push(topic);
          else this._byAyah.set(ref, [topic]);
        }
      }
    }
    return this._byAyah.get(`${surahId}:${ayahId}`) ?? [];
  }

  /**
   * Topics whose name, description, category or domain carries `query`.
   * @param {string} query
   */
  search(query) {
    const needle = query.trim().toLowerCase();
    if (!needle) return [];
    return this._topics.filter((t) =>
      [t.name, t.description, t.category, t.domain].some((f) => f.toLowerCase().includes(needle))
    );
  }
}
