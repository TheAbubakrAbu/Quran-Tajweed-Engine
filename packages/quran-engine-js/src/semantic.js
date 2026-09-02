// @ts-check
/**
 * Meaning-based ("AI") search: find the ayahs about a topic whether or not they use its words.
 * "Patience in hardship" should reach the verses about sabr even when neither word appears.
 *
 * WHY WORD VECTORS AND MaxSim, NOT A SENTENCE EMBEDDING
 * -----------------------------------------------------
 * Measured, not assumed. Scoring an ayah by the cosine between a SENTENCE embedding of the query
 * and one of the ayah ranks this corpus close to randomly - translated scripture is dense, and one
 * vector for a whole verse washes out the one idea the query is asking about. Scoring word by word
 * fixes it: embed every word, and score a text as the MEAN over the query's words of the BEST
 * matching word in the text. On real verses that separates related (0.42-0.70) from unrelated
 * (0.27-0.41) cleanly, and it degrades gracefully - a query word the model has never seen simply
 * contributes nothing instead of poisoning the vector.
 *
 * THE EMBEDDER IS YOURS
 * ---------------------
 * This engine ships no model: word vectors are tens of megabytes and every platform already has
 * one worth using (Apple's `NLEmbedding.wordEmbedding`, Android's ML Kit, `wink-embeddings` or a
 * GloVe file in Node, whatever your stack offers). Hand `embed` a function from a lowercased word
 * to its vector, or null when it has none, and this module does the rest. Vectors are cached per
 * word, so a repeated word costs one lookup for the whole corpus.
 *
 * Build the index once (it is O(words in corpus) embedder calls) and keep it: over the 6,236
 * English translations that is a few seconds and ~10-25 MB, which is why every serious consumer
 * persists it rather than rebuilding per launch.
 */

const WORD = /[^\p{L}\p{N}]+/u;

/**
 * @typedef {Object} SemanticHit
 * @property {string} id
 * @property {number} score  mean best-match cosine over the query's words, 0...1
 * @property {any} [meta]
 */

export class Semantic {
  /**
   * @param {Object} opts
   * @param {(word: string) => (number[]|Float32Array|null|undefined)} opts.embed
   * @param {number} [opts.minWordLength=3] words shorter than this are skipped on both sides
   */
  constructor({ embed, minWordLength = 3 }) {
    if (typeof embed !== "function") throw new TypeError("Semantic needs an embed(word) function");
    this._embed = embed;
    this._minWordLength = minWordLength;
    /** @type {Map<string, Float32Array|null>} */
    this._vectors = new Map();
    /** @type {{id:string, meta:any, vectors:Float32Array[]}[]} */
    this._documents = [];
  }

  /** How many documents are indexed. */
  get size() {
    return this._documents.length;
  }

  /**
   * Build (or rebuild) the index. Call once per corpus.
   * @param {Iterable<{id:string, text:string, meta?:any}>} documents
   */
  index(documents) {
    this._documents = [];
    for (const doc of documents) {
      const vectors = this._vectorize(doc.text);
      if (vectors.length) this._documents.push({ id: doc.id, meta: doc.meta ?? null, vectors });
    }
    return this;
  }

  /**
   * The documents closest in meaning to `query`, best first.
   * @param {string} query
   * @param {Object} [opts]
   * @param {number} [opts.limit=10]
   * @param {number} [opts.minScore=0] drop hits below this - 0.42 is a sensible "actually related"
   *        floor on English translations, but calibrate it against YOUR embedder
   * @returns {SemanticHit[]}
   */
  search(query, { limit = 10, minScore = 0 } = {}) {
    const queryVectors = this._vectorize(query);
    if (!queryVectors.length) return [];

    /** @type {SemanticHit[]} */
    const hits = [];
    for (const doc of this._documents) {
      let total = 0;
      for (const q of queryVectors) {
        let best = -1;
        for (const w of doc.vectors) {
          const score = cosine(q, w);
          if (score > best) best = score;
        }
        total += best;
      }
      const score = total / queryVectors.length;
      if (score >= minScore) hits.push({ id: doc.id, score, meta: doc.meta });
    }
    hits.sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : 1));
    return hits.slice(0, limit);
  }

  /** Drop the index and the vector cache. */
  clear() {
    this._documents = [];
    this._vectors.clear();
    return this;
  }

  /** @param {string} text @returns {Float32Array[]} */
  _vectorize(text) {
    /** @type {Float32Array[]} */
    const out = [];
    const seen = new Set();
    for (const raw of text.toLowerCase().split(WORD)) {
      if (raw.length < this._minWordLength || seen.has(raw)) continue;
      seen.add(raw);
      const vector = this._vector(raw);
      if (vector) out.push(vector);
    }
    return out;
  }

  /** @param {string} word */
  _vector(word) {
    if (this._vectors.has(word)) return this._vectors.get(word) ?? null;
    const raw = this._embed(word);
    // Normalized once here, so scoring is a dot product rather than three passes per pair.
    const vector = raw && raw.length ? normalize(raw) : null;
    this._vectors.set(word, vector);
    return vector;
  }
}

/**
 * Cosine similarity of two ALREADY NORMALIZED vectors, i.e. their dot product.
 * @param {Float32Array} a @param {Float32Array} b
 */
export function cosine(a, b) {
  const n = Math.min(a.length, b.length);
  let sum = 0;
  for (let i = 0; i < n; i++) sum += a[i] * b[i];
  return sum;
}

/** @param {number[]|Float32Array} raw */
function normalize(raw) {
  let magnitude = 0;
  for (let i = 0; i < raw.length; i++) magnitude += raw[i] * raw[i];
  magnitude = Math.sqrt(magnitude);
  const out = new Float32Array(raw.length);
  if (magnitude === 0) return out;
  for (let i = 0; i < raw.length; i++) out[i] = raw[i] / magnitude;
  return out;
}
