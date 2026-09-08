// @ts-check
/**
 * Two more ways to find your way around the Quran, both from the Quranic Universal Library.
 *
 * `QuranTopics` is 2,512 topics indexed **three independent ways**, and the independence is the
 * thing to understand before using it:
 *
 *  * `thematic` - the Clear Quran's thematic tree (Doctrine, Stories, The Unseen)
 *  * `ontology` - the Quranic Arabic Corpus ontology (Living Creation, Location, Event)
 *  * `index`    - a general A-Z index
 *
 * These are three trees over ONE pool of topics, not three partitions of it. A topic can be a
 * node in more than one (Adam sits in the thematic tree and in the ontology, 17 topics do), and
 * a tree's parent need not itself be listed in that tree (the A-Z index hangs "House of" under
 * Moses, a thematic topic). So every accessor that walks the hierarchy takes the tree you mean:
 * `parent(id, "ontology")` is a different question from `parent(id, "thematic")`, and both can
 * have an answer for the same topic. `families` says which indexes list a topic; passing no tree
 * uses the first of them, which is a convenience, not a fact about the data.
 *
 * `AyahThemes` is the other shape entirely: 1,049 **passages**, one short sentence describing a
 * run of ayahs ("Hypocrites and the consequences of hypocrisy", 2:8-16). Passages run in order
 * through a surah and do not nest, which is what makes them the right thing to print under an
 * ayah as "what is going on here", where a topic list would just be a pile of labels. They do
 * not tile the surah either: an ayah between two passages has none.
 *
 * This is a different corpus from `themes`, not a newer one. `themes` is 323 curated topics with
 * domains and categories; keep both, they answer differently.
 */

/**
 * @typedef {"thematic"|"ontology"|"index"} TopicTree
 */

/**
 * @typedef {Object} QulTopic
 * @property {number} id
 * @property {string} name
 * @property {string} arabic
 * @property {TopicTree[]} families                 the indexes listing this topic; 17 have two
 * @property {Record<TopicTree, number|null>} parents  one parent per tree, independently
 * @property {string} description
 * @property {string} wiki
 * @property {string[]} ayahs                       "surah:ayah" keys, in the corpus's order
 * @property {number[]} related
 */

/**
 * @typedef {Object} Passage
 * @property {number} surah
 * @property {number} from   first ayah
 * @property {number} to     last ayah
 * @property {string} theme  one sentence
 * @property {string} topic  the topic it sits under, "" when none
 */

export const TOPIC_FAMILIES = /** @type {const} */ (["thematic", "ontology", "index"]);

export class QuranTopics {
  /** @param {Object} [data] data/quran-topics.json @param {QulTopic[]} [data.topics] */
  constructor(data = {}) {
    this._topics = data.topics ?? [];
    /** @type {Map<number, QulTopic>} */
    this._byId = new Map(this._topics.map((t) => [t.id, t]));
    /** @type {Map<string, Map<number, number[]>>} */
    this._children = new Map();
    /** @type {Map<string, number[]>|null} */
    this._byAyah = null;
  }

  get isLoaded() {
    return this._topics.length > 0;
  }

  /** Every topic, in corpus order. @returns {QulTopic[]} */
  all() {
    return this._topics;
  }

  /** @param {number} id @returns {QulTopic|null} */
  topic(id) {
    return this._byId.get(id) ?? null;
  }

  /** The topics an index lists. @param {TopicTree} tree @returns {QulTopic[]} */
  inFamily(tree) {
    return this._topics.filter((t) => t.families.includes(tree));
  }

  /**
   * A tree's roots: topics it lists that have no parent in that same tree.
   * @param {TopicTree} tree @returns {QulTopic[]}
   */
  roots(tree) {
    return this._topics.filter((t) => t.families.includes(tree) && !t.parents[tree]);
  }

  /**
   * The parent in one tree. Defaults to the topic's first listed index, which is a convenience
   * for a caller that does not care; pass the tree explicitly when it matters.
   * @param {number} id @param {TopicTree} [tree] @returns {QulTopic|null}
   */
  parent(id, tree) {
    const topic = this.topic(id);
    if (!topic) return null;
    const which = tree ?? topic.families[0];
    const parentId = topic.parents[which];
    return parentId ? this.topic(parentId) : null;
  }

  /**
   * Direct children in one tree, in id order.
   * @param {number} id @param {TopicTree} [tree] @returns {QulTopic[]}
   */
  children(id, tree) {
    const which = tree ?? this.topic(id)?.families[0];
    if (!which) return [];
    return (this._childIndex(which).get(id) ?? []).map((cid) => /** @type QulTopic */ (this._byId.get(cid)));
  }

  /**
   * The chain from a topic up to its root in one tree, nearest first. Guards against a cycle in
   * the corpus rather than trusting it not to have one.
   * @param {number} id @param {TopicTree} [tree] @returns {QulTopic[]}
   */
  ancestors(id, tree) {
    const which = tree ?? this.topic(id)?.families[0];
    if (!which) return [];
    const out = [];
    const seen = new Set([id]);
    let current = this.parent(id, which);
    while (current && !seen.has(current.id)) {
      seen.add(current.id);
      out.push(current);
      current = this.parent(current.id, which);
    }
    return out;
  }

  /**
   * Every topic annotating this ayah, across all three indexes.
   * @param {number} surahId @param {number} ayahId @returns {QulTopic[]}
   */
  topicsFor(surahId, ayahId) {
    this._indexAyahs();
    const ids = this._byAyah?.get(`${surahId}:${ayahId}`) ?? [];
    return ids.map((id) => /** @type QulTopic */ (this._byId.get(id)));
  }

  /**
   * Name and Arabic-name substring search, exact-prefix hits first.
   * @param {string} query @param {number} [limit] @returns {QulTopic[]}
   */
  search(query, limit = 50) {
    const q = String(query ?? "").trim().toLowerCase();
    if (!q) return [];
    const starts = [];
    const contains = [];
    for (const topic of this._topics) {
      const name = topic.name.toLowerCase();
      if (name.startsWith(q)) starts.push(topic);
      else if (name.includes(q) || topic.arabic.includes(query)) contains.push(topic);
      if (starts.length >= limit) break;
    }
    return starts.concat(contains).slice(0, limit);
  }

  count() {
    const byFamily = { thematic: 0, ontology: 0, index: 0 };
    let refs = 0;
    for (const topic of this._topics) {
      for (const family of topic.families) byFamily[family] += 1;
      refs += topic.ayahs.length;
    }
    return { topics: this._topics.length, ...byFamily, references: refs };
  }

  /** @private Children of one tree, built on first use. */
  _childIndex(tree) {
    const cached = this._children.get(tree);
    if (cached) return cached;
    /** @type {Map<number, number[]>} */
    const map = new Map();
    for (const topic of this._topics) {
      const parentId = topic.parents[tree];
      if (!parentId) continue;
      const bucket = map.get(parentId);
      if (bucket) bucket.push(topic.id); else map.set(parentId, [topic.id]);
    }
    for (const bucket of map.values()) bucket.sort((a, b) => a - b);
    this._children.set(tree, map);
    return map;
  }

  /** @private */
  _indexAyahs() {
    if (this._byAyah) return;
    /** @type {Map<string, number[]>} */
    const map = new Map();
    for (const topic of this._topics) {
      for (const key of topic.ayahs) {
        const bucket = map.get(key);
        if (bucket) bucket.push(topic.id); else map.set(key, [topic.id]);
      }
    }
    this._byAyah = map;
  }
}

export class AyahThemes {
  /** @param {Object} [data] data/ayah-themes.json (surah -> passages) */
  constructor(data = {}) {
    this._data = data ?? {};
  }

  get isLoaded() {
    return Object.keys(this._data).length > 0;
  }

  /** A surah's passages, in order. @param {number} surahId @returns {Passage[]} */
  passages(surahId) {
    const rows = this._data[String(surahId)] ?? [];
    return rows.map((row) => ({ surah: surahId, from: row.from, to: row.to, theme: row.theme, topic: row.topic ?? "" }));
  }

  /**
   * The passage an ayah falls in, or null. Passages do not overlap, so this is the one answer.
   * @param {number} surahId @param {number} ayahId @returns {Passage|null}
   */
  passageFor(surahId, ayahId) {
    for (const passage of this.passages(surahId)) {
      if (ayahId >= passage.from && ayahId <= passage.to) return passage;
    }
    return null;
  }

  /** @param {string} query @param {number} [limit] @returns {Passage[]} */
  search(query, limit = 50) {
    const q = String(query ?? "").trim().toLowerCase();
    if (!q) return [];
    const out = [];
    for (const surah of Object.keys(this._data).map(Number).sort((a, b) => a - b)) {
      for (const passage of this.passages(surah)) {
        if (passage.theme.toLowerCase().includes(q) || passage.topic.toLowerCase().includes(q)) {
          out.push(passage);
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  count() {
    let passages = 0;
    for (const rows of Object.values(this._data)) passages += rows.length;
    return { surahs: Object.keys(this._data).length, passages };
  }
}
