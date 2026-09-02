// @ts-check
/**
 * Ask AI: the retrieval and the prompt behind "ask a question, get an answer grounded in the text".
 *
 * WHAT THIS IS, AND WHAT IT IS NOT
 * --------------------------------
 * It is NOT a model. It is the two halves of a question-answering feature that a model cannot do
 * for you and that every app otherwise rebuilds badly:
 *
 *  1. **Retrieval** - turn a natural-language question into the handful of passages that actually
 *     bear on it, each with the reference it must be cited by.
 *  2. **The prompt** - the instructions that keep a model from doing the three things that make a
 *     Quran assistant harmful: inventing verse numbers, quoting scripture it has half-remembered,
 *     and issuing rulings.
 *
 * Hand the result to whatever model you use - on-device (Apple Foundation Models, Gemini Nano),
 * hosted, or none at all: the passages are worth showing on their own.
 *
 * WHY THE LANES ARE SEPARATE, AND INTERLEAVED
 * -------------------------------------------
 * The lanes answer different KINDS of question and one would otherwise drown the others:
 *
 *  * Lane 0, **what the question names**. "Explain 2:255", "what is Surah al-Kahf about",
 *    "ayat al-kursi". These passages are marked `isSubject`: without that marking a model given
 *    eight loosely-related verses will happily explain the wrong one. This lane runs first and
 *    always wins its slot.
 *  * Lane 1, **keywords**, weighted by inverse document frequency. Plain term counting ranks a
 *    question by whichever verse says "the" most; weighting each term by log(N / (1 + df)) fixes
 *    that with no stopword list to maintain against the corpus.
 *  * Lane 2, **themes**: the curated topic lists, which reach ayahs sharing no wording with the
 *    question at all.
 *  * Lane 3, **meaning**, only when you pass a `semantic` index (see semantic.js). Optional on
 *    purpose - the other three need no model and no vectors, so the feature works everywhere.
 *
 * Then they are interleaved round-robin rather than concatenated, so each lane gets a voice inside
 * the passage budget instead of the first lane filling it.
 */

import { Semantic } from "./semantic.js";

/** Words too common to name a topic on their own; the keyword lane never searches for them alone. */
export const QUESTION_WORDS = new Set([
  "what", "why", "how", "when", "where", "who", "whom", "which", "does", "do", "did", "is", "are",
  "was", "were", "can", "could", "should", "would", "will", "shall", "have", "has", "had", "there",
  "their", "these", "those", "this", "that", "with", "from", "about", "into", "tell", "explain",
  "please", "mean", "means", "meaning", "say", "says", "said", "some", "many", "much", "islam",
  "islamic", "muslim", "muslims", "quran", "hadith", "hadiths", "allah", "prophet", "verse", "verses",
  "surah", "ayah", "ayat",
]);

/** How many passages a turn carries, and how much of each. See `chatPrompt`. */
export const PASSAGE_LIMIT = 8;
export const PASSAGE_CHARACTER_LIMIT = 500;
/** A subject passage gets more room: when the question names the verse, this text IS the answer. */
export const SUBJECT_CHARACTER_LIMIT = 1400;

const AYAH_REFERENCE = /(?<![\d:])(\d{1,3})\s*:\s*(\d{1,3})(?![\d:])/g;
const SURAH_MENTION = /\b(?:surah|surat|soorah|sura|chapter)\s+([\p{L}'’-]+)(?:\s+([\p{L}'’-]+))?/giu;
const AYAH_MENTION = /\b(?:ayah|ayat|aya|verse)\s+(\d{1,3})\b/gi;
const WORD_SPLIT = /[^\p{L}\p{N}]+/u;

/** Household names for specific verses that no pattern catches. */
const NAMED_AYAHS = [
  {
    names: ["ayat al-kursi", "ayatul kursi", "ayat ul kursi", "ayat al kursi", "ayatul-kursi",
            "throne verse", "verse of the throne"],
    surah: 2, ayah: 255,
  },
];

/** The prose in a surah's notes that says what it is ABOUT, rather than when it was revealed. */
const THEME_HEADING = /^\s*#*\s*(?:theme|subject|subject matter|central theme|summary|contents|topics)\b[^\n]*$/im;

/**
 * @typedef {Object} Passage
 * @property {"ayah"|"surah"|"topic"} kind
 * @property {string} reference       cite it exactly like this: "2:255", "Surah Al-Kahf"
 * @property {string} text
 * @property {number} maxCharacters   how much of `text` to show the model
 * @property {boolean} isSubject      the verse or surah the question itself named
 * @property {number} [surah]
 * @property {number} [ayah]
 */

export class AskAI {
  /**
   * @param {Object} parts
   * @param {import('./quran.js').Quran} parts.quran
   * @param {import('./search.js').Search} parts.search
   * @param {import('./themes.js').Themes} [parts.themes]
   * @param {Semantic} [parts.semantic] an index over the ayah translations; optional
   * @param {"textEnglishSaheeh"|"textEnglishMustafa"} [parts.translation="textEnglishSaheeh"]
   */
  constructor({ quran, search, themes, semantic, translation = "textEnglishSaheeh" }) {
    this.quran = quran;
    this.search = search;
    this.themes = themes ?? null;
    this.semantic = semantic ?? null;
    this.translation = translation;
    /** @type {Map<string, number>|null} lazily built document frequencies for the IDF weighting */
    this._documentFrequency = null;
    this._documentCount = 0;
  }

  /**
   * Build a semantic index over the ayah translations with your own embedder, and use it as lane 3.
   * @param {(word: string) => (number[]|Float32Array|null|undefined)} embed
   */
  buildSemanticIndex(embed) {
    const documents = [];
    for (const surah of this.quran.all()) {
      for (const ayah of surah.ayahs) {
        documents.push({
          id: `${surah.id}:${ayah.id}`,
          text: ayah[this.translation] ?? "",
          meta: { surah: surah.id, ayah: ayah.id },
        });
      }
    }
    this.semantic = new Semantic({ embed }).index(documents);
    return this.semantic;
  }

  /**
   * The passages for a question, best first.
   * @param {string} question
   * @param {Object} [opts]
   * @param {string} [opts.previousQuestion] folded into the search when this is a bare follow-up
   * @param {Passage[]} [opts.carried] passages the previous answer cited - "why?" is about those
   * @param {number} [opts.limit=PASSAGE_LIMIT]
   * @returns {Passage[]}
   */
  retrieve(question, { previousQuestion, carried = [], limit = PASSAGE_LIMIT } = {}) {
    const trimmed = question.trim();
    if (trimmed.length < 3) return [];

    const seen = new Set();
    /** @param {Passage} p */
    const claim = (p) => (seen.has(p.reference) ? false : (seen.add(p.reference), true));

    // Lane 0: what the question NAMES.
    const named = this.referencePassages(trimmed).filter(claim);

    // A bare follow-up ("why?", "what about zakat?") searches as the previous question plus this
    // one, and keeps the passages the previous answer cited in the pool.
    const bare = this.isBareFollowUp(trimmed);
    const searchText = bare && previousQuestion?.trim() ? `${previousQuestion.trim()} ${trimmed}` : trimmed;
    if (bare) named.push(...carried.slice(0, 3).filter(claim));

    const keyword = this.keywordPassages(searchText).filter(claim);
    const thematic = this.themePassages(searchText).filter(claim);
    const meaning = this.semanticPassages(searchText).filter(claim);

    return [...named, ...interleave([keyword, meaning, thematic])].slice(0, limit);
  }

  // ---- Lane 0: references ---------------------------------------------------------

  /**
   * The verses and surahs the question names, as subject passages.
   * @param {string} question
   * @returns {Passage[]}
   */
  referencePassages(question) {
    const lowered = question.toLowerCase();
    /** @type {{surah:number, ayah:number}[]} */
    const ayahs = [];
    /** @type {number[]} */
    const surahs = [];

    for (const match of question.matchAll(AYAH_REFERENCE)) {
      const surah = Number(match[1]);
      const ayah = Number(match[2]);
      if (this.quran.ayah(surah, ayah)) ayahs.push({ surah, ayah });
    }
    for (const named of NAMED_AYAHS) {
      if (named.names.some((n) => lowered.includes(n))) ayahs.push({ surah: named.surah, ayah: named.ayah });
    }
    for (const match of question.matchAll(SURAH_MENTION)) {
      // Two words then one: "surah al kahf" resolves on the pair, "surah yusuf" on the single.
      const candidates = [match[1] && match[2] ? `${match[1]} ${match[2]}` : null, match[1]].filter(Boolean);
      for (const candidate of candidates) {
        const hit = this._resolveSurah(/** @type string */ (candidate));
        if (hit) { surahs.push(hit); break; }
      }
    }
    // "surah al-kahf verse 10" - an ayah number on its own belongs to the surah just named.
    const loose = [...question.matchAll(AYAH_MENTION)].map((m) => Number(m[1]));
    if (loose.length && surahs.length && !ayahs.length) {
      for (const ayah of loose) {
        if (this.quran.ayah(surahs[0], ayah)) ayahs.push({ surah: surahs[0], ayah });
      }
    }

    /** @type {Passage[]} */
    const out = [];
    for (const { surah, ayah } of ayahs) {
      const passage = this.ayahPassage(surah, ayah, { isSubject: true, maxCharacters: SUBJECT_CHARACTER_LIMIT });
      if (passage) out.push(passage);
    }
    // A surah named on its own (with no verse) is answered by its background prose.
    if (!ayahs.length) {
      for (const id of surahs) {
        const passage = this.surahPassage(id);
        if (passage) out.push(passage);
      }
    }
    return out;
  }

  /**
   * A surah named in words. `searchSurahs` is a substring match, so "al kahf" also reaches
   * al-Fatihah (whose similar names include "Al..."); an exact name match wins when there is one,
   * which is the difference between answering about the cave and answering about the opening.
   * @param {string} candidate
   * @returns {number|null}
   */
  _resolveSurah(candidate) {
    const hits = this.search.searchSurahs(candidate);
    if (!hits.length) return null;
    const fold = (/** @type string */ text) => text.toLowerCase().replace(/[^a-z]/g, "");
    const wanted = fold(candidate);
    const exact = hits.find((s) => fold(s.nameTransliteration) === wanted || fold(s.nameEnglish) === wanted);
    const suffix = hits.find((s) => fold(s.nameTransliteration).endsWith(wanted) && wanted.length >= 3);
    return (exact ?? suffix ?? hits[0]).id;
  }

  // ---- Lane 1: keywords, IDF-weighted --------------------------------------------

  /**
   * Ayahs whose translation carries the question's content words, ranked by how INFORMATIVE those
   * words are rather than by how often they occur.
   * @param {string} question
   * @param {Object} [opts]
   * @param {number} [opts.limit=4]
   * @returns {Passage[]}
   */
  keywordPassages(question, { limit = 4 } = {}) {
    const terms = this.contentWords(question);
    if (!terms.length) return [];
    const weights = this.termWeights(terms);

    /** @type {Map<string, number>} */
    const scores = new Map();
    for (let i = 0; i < terms.length; i++) {
      if (weights[i] <= 0) continue;
      for (const hit of this.search.searchVerses(terms[i], { limit: 400 })) {
        scores.set(hit.id, (scores.get(hit.id) ?? 0) + weights[i]);
      }
    }
    // A verse matching two informative words beats one matching a single word twice.
    const ranked = [...scores.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));

    /** @type {Passage[]} */
    const out = [];
    for (const [id] of ranked) {
      const [surah, ayah] = id.split(":").map(Number);
      const passage = this.ayahPassage(surah, ayah);
      if (passage) out.push(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Lane 2: themes -------------------------------------------------------------

  /**
   * Ayahs from the curated topic whose name or description the question matches - the lane that
   * reaches verses sharing no wording with the question at all.
   * @param {string} question
   * @param {Object} [opts]
   * @param {number} [opts.limit=2]
   * @returns {Passage[]}
   */
  themePassages(question, { limit = 2 } = {}) {
    if (!this.themes) return [];
    const words = this.contentWords(question);
    if (!words.length) return [];

    let best = null;
    let bestScore = 0;
    for (const topic of this.themes.all()) {
      const haystack = `${topic.name} ${topic.description} ${topic.category}`.toLowerCase();
      const score = words.reduce((sum, w) => sum + (haystack.includes(w.toLowerCase()) ? w.length : 0), 0);
      if (score > bestScore) { bestScore = score; best = topic; }
    }
    if (!best) return [];

    /** @type {Passage[]} */
    const out = [];
    for (const ref of best.ayahs) {
      const [surah, ayah] = ref.split(":").map(Number);
      const passage = this.ayahPassage(surah, ayah);
      if (passage) out.push(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Lane 3: meaning ------------------------------------------------------------

  /**
   * Ayahs closest in MEANING to the question. Empty unless a semantic index was supplied - the
   * other lanes still answer, which is why this one is optional.
   * @param {string} question
   * @param {Object} [opts]
   * @param {number} [opts.limit=3]
   * @param {number} [opts.minScore=0.42]
   * @returns {Passage[]}
   */
  semanticPassages(question, { limit = 3, minScore = 0.42 } = {}) {
    if (!this.semantic) return [];
    // The score is a MEAN over query words, so "what does the Quran say about" dilutes the topic:
    // the meaning query is the content words alone.
    const words = this.contentWords(question);
    const query = words.length ? words.join(" ") : question;

    /** @type {Passage[]} */
    const out = [];
    for (const hit of this.semantic.search(query, { limit: limit * 2, minScore })) {
      const [surah, ayah] = hit.id.split(":").map(Number);
      const passage = this.ayahPassage(surah, ayah);
      if (passage) out.push(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Passage construction --------------------------------------------------------

  /**
   * @param {number} surahId @param {number} ayahId
   * @param {{isSubject?:boolean, maxCharacters?:number}} [opts]
   * @returns {Passage|null}
   */
  ayahPassage(surahId, ayahId, { isSubject = false, maxCharacters = PASSAGE_CHARACTER_LIMIT } = {}) {
    const ayah = this.quran.ayah(surahId, ayahId);
    if (!ayah) return null;
    const text = ayah[this.translation] || ayah.textEnglishSaheeh || ayah.textEnglishMustafa || "";
    if (!text) return null;
    return { kind: "ayah", reference: `${surahId}:${ayahId}`, text, maxCharacters, isSubject, surah: surahId, ayah: ayahId };
  }

  /**
   * A surah's background prose. The bundled notes open with the period of revelation, which
   * answers "what is this surah about" with history - so the theme section, when there is one,
   * is what the question actually meant.
   * @param {number} surahId
   * @returns {Passage|null}
   */
  surahPassage(surahId) {
    const surah = this.quran.surah(surahId);
    // `info` hands back the list of write-ups directly (Maududi, Ibn Ashur), not a wrapper.
    const sources = this.quran.info(surahId) ?? [];
    if (!surah || !sources.length) return null;

    let text = "";
    for (const source of sources) {
      const match = THEME_HEADING.exec(source.contents);
      if (!match) continue;
      const fromTheme = plainProse(source.contents.slice(match.index));
      if (fromTheme.length >= 200) { text = fromTheme; break; }
    }
    if (!text) text = plainProse(sources[0].contents);
    if (!text) return null;

    return {
      kind: "surah",
      reference: `Surah ${surah.nameTransliteration}`,
      text,
      maxCharacters: SUBJECT_CHARACTER_LIMIT,
      isSubject: true,
      surah: surahId,
    };
  }

  // ---- Question analysis -------------------------------------------------------------

  /**
   * The words in a question that actually name its topic.
   * @param {string} question
   */
  contentWords(question) {
    return question
      .split(WORD_SPLIT)
      .filter((w) => w.length >= 3 && !QUESTION_WORDS.has(w.toLowerCase()));
  }

  /**
   * A question with fewer than two content words ("why?", "and zakat?") only makes sense with the
   * previous question beside it.
   * @param {string} question
   */
  isBareFollowUp(question) {
    return question.split(WORD_SPLIT).filter((w) => w.length >= 4 && !QUESTION_WORDS.has(w.toLowerCase())).length < 2;
  }

  /**
   * Inverse document frequency per term: log(N / (1 + df)), floored at 0. A word in half the Quran
   * weighs almost nothing; a word in ten ayahs weighs a lot. Built once, over the translations.
   * @param {string[]} terms
   * @returns {number[]}
   */
  termWeights(terms) {
    if (!this._documentFrequency) {
      /** @type {Map<string, number>} */
      const frequency = new Map();
      let documents = 0;
      for (const surah of this.quran.all()) {
        for (const ayah of surah.ayahs) {
          documents++;
          const text = (ayah[this.translation] ?? "").toLowerCase();
          for (const word of new Set(text.split(WORD_SPLIT).filter((w) => w.length >= 3))) {
            frequency.set(word, (frequency.get(word) ?? 0) + 1);
          }
        }
      }
      this._documentFrequency = frequency;
      this._documentCount = documents;
    }
    return terms.map((term) => {
      const df = this._documentFrequency?.get(term.toLowerCase()) ?? 0;
      return Math.max(0, Math.log(this._documentCount / (1 + df)));
    });
  }
}

// ---- The prompt --------------------------------------------------------------------

/**
 * The system instructions. Rules 2, 3 and 5 are the ones that matter: a model left to itself will
 * cite verse numbers it half-remembers, "quote" scripture it has paraphrased, and answer
 * "is X halal" with a verdict. Everything else is tone.
 */
export const CHAT_INSTRUCTIONS = `You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end.`;

/**
 * The user-side prompt for one turn: the passages, the recent conversation, the question.
 *
 * Eight passages of 500 characters is roughly a thousand tokens - sized for a ~4k on-device window
 * with room left for the instructions, the conversation, and a full answer. Raise both for a
 * larger model; the shape does not change.
 *
 * @param {string} question
 * @param {Passage[]} passages
 * @param {Object} [opts]
 * @param {{question:string, answer:string}[]} [opts.transcript] the completed turns so far
 * @param {number} [opts.passageLimit=PASSAGE_LIMIT]
 * @returns {{instructions: string, prompt: string}}
 */
export function chatPrompt(question, passages, { transcript = [], passageLimit = PASSAGE_LIMIT } = {}) {
  const rendered = passages.slice(0, passageLimit).map((p) =>
    `${p.isSubject ? "SUBJECT OF THE QUESTION " : ""}[${p.reference}] ${p.text.slice(0, p.maxCharacters)}`
  ).join("\n");
  const recent = transcript.slice(-3).map((turn) =>
    `Earlier question: ${turn.question.slice(0, 300)}\nEarlier answer: ${turn.answer.slice(0, 500)}`
  ).join("\n");

  let prompt = "";
  if (rendered) {
    prompt += "PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n"
      + rendered + "\n\n";
  }
  if (recent) prompt += `CONVERSATION SO FAR:\n${recent}\n\n`;
  prompt += `QUESTION: ${question}`;

  return { instructions: CHAT_INSTRUCTIONS, prompt };
}

/**
 * Round-robin the lanes so each gets a voice inside the budget, instead of the first lane filling it.
 * @template T @param {T[][]} lanes @returns {T[]}
 */
function interleave(lanes) {
  /** @type {T[]} */
  const out = [];
  const depth = Math.max(0, ...lanes.map((l) => l.length));
  for (let i = 0; i < depth; i++) {
    for (const lane of lanes) if (i < lane.length) out.push(lane[i]);
  }
  return out;
}

/** Strip the light markdown the surah notes carry, so a passage reads as prose. */
function plainProse(text) {
  return text
    .replace(/^\s*#+\s*/gm, "")
    .replace(/[*_`]+/g, "")
    .replace(/\r/g, "")
    .replace(/\n{2,}/g, "\n")
    .trim();
}
