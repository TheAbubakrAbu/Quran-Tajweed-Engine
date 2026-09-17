// @ts-check
/**
 * The chains of transmission (isnād) of the Ten Readings.
 *
 * From the Prophet ﷺ down through the Companions who learned from him, the Successors who
 * taught each imam, the imam himself, the links between him and each of his two narrators,
 * and the students who carried each narration on.
 *
 * The links are the standard ones of the classical record: Ibn al-Jazarī's *al-Nashr* and
 * *Ghāyat al-Nihāyah*, al-Dānī's *al-Taysīr*, and the ṭuruq of al-Shāṭibiyyah and al-Durrah.
 * Where a narrator's students are not listed with confidence, the layer is simply absent.
 *
 * A chain is returned as LAYERS, one per generation, top (the Prophet ﷺ) to bottom, which is
 * how a consumer draws it: a row per layer, connected downward.
 *
 * Riwayah keys are the canonical tags this engine uses elsewhere ("Warsh an Nafi"), and imam
 * keys are the imam's short name ("Nafi"). `chain()` takes either and works out which it has.
 *
 * @typedef {Object} IsnadNode
 * @property {string} name
 * @property {string} arabic
 * @property {string} detail  the death year, e.g. "d. 117 AH"
 * @property {"prophet"|"companion"|"successor"|"imam"|"link"|"narrator"|"student"} role
 *
 * @typedef {Object} IsnadLayer
 * @property {string} title  e.g. "THE COMPANIONS"
 * @property {IsnadNode[]} nodes
 *
 * @typedef {Object} ImamChain
 * @property {IsnadNode[]} teachers
 * @property {IsnadNode[]} companions
 *
 * @typedef {Object} NarratorChain
 * @property {string} imam          the imam this narration comes from
 * @property {IsnadNode[]} links     empty where the narrator read on the imam himself
 * @property {IsnadNode[]} students
 */

export class Isnad {
  /**
   * @param {Object} [data] parsed data/isnad.json
   * @param {IsnadNode} [data.prophet]
   * @param {IsnadNode[]} [data.companions]
   * @param {Record<string, ImamChain>} [data.imams]
   * @param {Record<string, NarratorChain>} [data.narrators]
   */
  constructor(data = {}) {
    this._prophet = data.prophet ?? null;
    this._companions = data.companions ?? [];
    this._imams = data.imams ?? {};
    this._narrators = data.narrators ?? {};
  }

  get isLoaded() {
    return Object.keys(this._imams).length > 0;
  }

  /** The Prophet ﷺ, the head of every chain. @returns {IsnadNode|null} */
  prophet() {
    return this._prophet;
  }

  /** The thirteen Companions the readings are transmitted from. @returns {IsnadNode[]} */
  companions() {
    return this._companions;
  }

  /** The ten imams' keys, e.g. "Nafi". @returns {string[]} */
  imamKeys() {
    return Object.keys(this._imams);
  }

  /** The twenty riwayah tags, e.g. "Warsh an Nafi". @returns {string[]} */
  narratorKeys() {
    return Object.keys(this._narrators);
  }

  /** @param {string} imam @returns {ImamChain|null} */
  imam(imam) {
    return this._imams[imam] ?? null;
  }

  /** @param {string} riwayah @returns {NarratorChain|null} */
  narrator(riwayah) {
    return this._narrators[riwayah] ?? null;
  }

  /**
   * Whether a narrator read on his imam himself, with nobody between them.
   * @param {string} riwayah @returns {boolean}
   */
  readsDirectly(riwayah) {
    const chain = this._narrators[riwayah];
    return !!chain && chain.links.length === 0;
  }

  /**
   * The imam a riwayah comes from. Read from the corpus, NOT parsed off the tag: four tags name
   * the imam in the Arabic genitive ("ad-Duri an Abi Amr") while his key is the nominative ("Abu
   * Amr"), so splitting on " an " would resolve those four to nothing.
   * @param {string} riwayah @returns {string|null}
   */
  imamOf(riwayah) {
    const imam = this._narrators[riwayah]?.imam;
    return imam && this._imams[imam] ? imam : null;
  }

  /**
   * The layers above any imam: the Prophet ﷺ, the Companions his teachers read on, and those
   * teachers. Shared by both `chain` forms, since every chain runs through them.
   * @param {string} imam @returns {IsnadLayer[]}
   */
  topLayers(imam) {
    const chain = this._imams[imam];
    if (!chain) return [];
    /** @type {IsnadLayer[]} */
    const layers = [];
    if (this._prophet) layers.push({ title: "THE PROPHET", nodes: [this._prophet] });
    if (chain.companions.length) layers.push({ title: "THE COMPANIONS", nodes: chain.companions });
    if (chain.teachers.length) {
      layers.push({ title: chain.teachers.length === 1 ? "HIS TEACHER" : "HIS TEACHERS", nodes: chain.teachers });
    }
    return layers;
  }

  /**
   * A whole chain as layers. Give it a riwayah tag ("Warsh an Nafi") for one narration's chain,
   * or an imam key ("Nafi") for the reading's, which ends at his narrators.
   * @param {string} key @returns {IsnadLayer[]}
   */
  chain(key) {
    const k = String(key ?? "").trim();
    if (this._imams[k]) return this._chainOfImam(k);
    if (this._narrators[k]) return this._chainOfNarrator(k);
    return [];
  }

  /** @param {string} imam @returns {IsnadLayer[]} */
  _chainOfImam(imam) {
    const layers = this.topLayers(imam);
    if (!layers.length) return [];
    layers.push({ title: "THE IMAM", nodes: [{ name: imam, arabic: "", detail: "", role: "imam" }] });
    const narrators = this.narratorKeys()
      .filter((tag) => this.imamOf(tag) === imam)
      .map((tag) => ({ name: tag.slice(0, tag.indexOf(" an ")), arabic: "", detail: "", role: /** @type {const} */ ("narrator") }));
    if (narrators.length) layers.push({ title: "HIS TWO NARRATORS", nodes: narrators });
    return layers;
  }

  /** @param {string} riwayah @returns {IsnadLayer[]} */
  _chainOfNarrator(riwayah) {
    const imam = this.imamOf(riwayah);
    if (!imam) return [];
    const layers = this.topLayers(imam);
    if (!layers.length) return [];
    layers.push({ title: "THE IMAM", nodes: [{ name: imam, arabic: "", detail: "", role: "imam" }] });
    const chain = this._narrators[riwayah];
    if (chain.links.length) {
      layers.push({ title: chain.links.length === 1 ? "THE LINK BETWEEN" : "THE LINKS BETWEEN", nodes: chain.links });
    }
    layers.push({
      title: "THE NARRATOR",
      nodes: [{ name: riwayah.slice(0, riwayah.indexOf(" an ")), arabic: "", detail: "", role: "narrator" }],
    });
    if (chain.students.length) layers.push({ title: "HIS STUDENTS", nodes: chain.students });
    return layers;
  }

  /**
   * One sentence on how a narrator reaches his imam: directly, or through the links between.
   * @param {string} riwayah @returns {string}
   */
  sentence(riwayah) {
    const imam = this.imamOf(riwayah);
    const chain = this._narrators[riwayah];
    if (!imam || !chain) return "";
    const narrator = riwayah.slice(0, riwayah.indexOf(" an "));
    if (!chain.links.length) {
      return `${narrator} read on ${imam} himself, and ${imam}'s chain runs through his teachers to the Companions and to the Prophet ﷺ.`;
    }
    const names = chain.links.map((n) => n.name);
    const path = names.length === 1 ? names[0] : `${names.slice(0, -1).join(", ")} and then ${names[names.length - 1]}`;
    return `${narrator} did not meet ${imam}: the reading reached him through ${path}, and from ${imam} it runs through his teachers to the Companions and to the Prophet ﷺ.`;
  }

  count() {
    return {
      imams: Object.keys(this._imams).length,
      narrators: Object.keys(this._narrators).length,
      companions: this._companions.length,
    };
  }
}
