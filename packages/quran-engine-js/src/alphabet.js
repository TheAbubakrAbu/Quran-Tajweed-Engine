// @ts-check
/**
 * The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name and
 * transliteration, and - the part that matters for tajweed - its WEIGHT.
 *
 * Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
 * pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the
 * divine name), and alif has no weight of its own at all: it inherits the letter before it. That
 * single fact is behind a large share of beginner mistakes, and it is a property of the letter, not
 * of any particular verse, so it lives here beside the letter and not in the annotation corpus.
 *
 * Also carried: the letters outside the 28 (hamza, ta marbuta, lam-alif), the six Persian/Urdu
 * letters that appear in some printed mushafs, the Eastern-Arabic numerals the ayah markers use,
 * the tashkeel marks, and the waqf (stopping) signs - the ones a reader must obey rather than sound
 * out.
 */

/**
 * @typedef {Object} ArabicLetter
 * @property {number} id
 * @property {string} letter          the isolated form
 * @property {string[]} forms         final, medial, initial as the source records them
 * @property {string} name            the letter's Arabic name
 * @property {string} transliteration
 * @property {boolean} showTashkeel   whether the reference renders it with a vowel
 * @property {string} sound
 * @property {string} [weight]        "light" | "heavy" | "conditional" | "followsPrevious"
 * @property {string} [weightRule]    why, in one sentence
 */

/**
 * @typedef {Object} Tashkeel
 * @property {string} english
 * @property {string} arabic
 * @property {string} mark
 * @property {string} transliteration
 */

/**
 * @typedef {Object} StoppingSign
 * @property {string} symbol
 * @property {string} title
 */

/**
 * @typedef {Object} ArabicNumeral
 * @property {string} number         the Eastern-Arabic digit
 * @property {string} name
 * @property {string} transliteration
 * @property {string} englishNumber
 */

export class ArabicAlphabet {
  /** @param {Object} [data] data/arabic-alphabet.json */
  constructor(data = /** @type any */ ({})) {
    this._data = data ?? {};
  }

  /** The 28 letters of the alphabet, in order. */
  letters() {
    return /** @type {ArabicLetter[]} */ (this._data.standardLetters ?? []);
  }

  /** Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28. */
  otherLetters() {
    return /** @type {ArabicLetter[]} */ (this._data.otherLetters ?? []);
  }

  /** The Persian/Urdu letters some printed mushafs use for non-Arabic sounds. */
  nonArabicScriptLetters() {
    return /** @type {ArabicLetter[]} */ (this._data.nonArabicScriptLetters ?? []);
  }

  /** Every letter this reference knows, the 28 first. */
  allLetters() {
    return [...this.letters(), ...this.otherLetters(), ...this.nonArabicScriptLetters()];
  }

  /**
   * One letter by its isolated form. Accepts any of its joining forms too, so a letter lifted out
   * of a word still resolves.
   * @param {string} letter
   * @returns {ArabicLetter|null}
   */
  letter(letter) {
    const wanted = letter.trim();
    if (!wanted) return null;
    return this.allLetters().find(
      (entry) => entry.letter === wanted || (entry.forms ?? []).includes(wanted)
    ) ?? null;
  }

  /** @param {number} id */
  letterById(id) {
    return this.allLetters().find((entry) => entry.id === id) ?? null;
  }

  /**
   * The tajweed weight of a letter: "light", "heavy", "conditional", or "followsPrevious". Null for
   * a letter the reference records no weight for.
   * @param {string} letter
   */
  weight(letter) {
    return this.letter(letter)?.weight ?? null;
  }

  /** What a weight name means, in one line. */
  weightDescriptions() {
    return /** @type {Record<string,string>} */ (this._data.weights ?? {});
  }

  /** The letters pronounced full - the isti'la letters plus the contextual ones when they are. */
  heavyLetters() {
    return this.letters().filter((entry) => entry.weight === "heavy");
  }

  /** The tashkeel marks, with the sound each one writes. */
  tashkeel() {
    return /** @type {Tashkeel[]} */ (this._data.tashkeel ?? []);
  }

  /** The waqf signs, with what each one tells the reciter to do. */
  stoppingSigns() {
    return /** @type {StoppingSign[]} */ (this._data.stoppingSigns ?? []);
  }

  /**
   * One waqf sign by its symbol - what to do when it appears mid-ayah.
   * @param {string} symbol
   */
  stoppingSign(symbol) {
    return this.stoppingSigns().find((sign) => sign.symbol === symbol) ?? null;
  }

  /** The Eastern-Arabic numerals, 0 through 10. */
  numbers() {
    return /** @type {ArabicNumeral[]} */ (this._data.numbers ?? []);
  }

  /** Where the waqf sign meanings come from. */
  stoppingSignsSource() {
    return /** @type {string} */ (this._data.stoppingSignsSource ?? "");
  }
}
