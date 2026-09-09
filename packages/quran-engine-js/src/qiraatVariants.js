// @ts-check
/**
 * Who among the Ten reads a word differently, what they read, and what the difference means.
 *
 * This is the layer the qiraah texts cannot supply, and the reason it exists is worth stating.
 * `data/qiraat/` gives each reading its own words, and `qiraatComparison` will align two of them
 * for you: that answers **what** each riwayah reads. It cannot tell you that a form is Hamzah's
 * rather than Nafi's, that it is a passive where Hafs has an active, or that al-Mahdawi held the
 * two to mean the same thing. That is this module, from the Quran.com qiraat matrix.
 *
 * Three pieces, because they answer three questions a reader asks in sequence:
 *
 *  * `junctures(surah, ayah)` - at this verse, which word is read differently and by whom
 *  * `places(riwayah, surah)` - where in this surah does that riwayah differ at all, so a reader
 *    can step to the next difference instead of hunting for it
 *  * `audio(riwayah, surah, ayah)` - the same reciter reading the verse both ways
 *
 * **Readers against transmitters.** A reading lists `readers` when both of an imam's two
 * transmitters follow it, and `transmitters` when the two part company. So a form attributed to
 * reader 6 is Hamzah entire; a form attributed to transmitter 11 is Khalaf but not Khallad.
 * `attribution()` renders that distinction as the printed sources do.
 *
 * Segment ranges are 0-based inclusive token indices of the raw Hafs text, and `null` where the
 * builder could not place the word: a consumer shows the word untinted rather than guessing.
 *
 * Only the eight riwayat whose text this engine publishes appear in `places`. The other twelve
 * are read by the same imams and do appear as attributions here, which is correct: attributing a
 * reading to Ibn Dhakwan says nothing about the state of his extracted text.
 */

/**
 * @typedef {Object} VariantReading
 * @property {string} text             the word as this group reads it
 * @property {string} transliteration
 * @property {string} english          a rendering of the phrase under this reading
 * @property {string} explanation      why it matters, when a grammarian is cited
 * @property {string} grammaticalForm
 * @property {string} rootLetters
 * @property {number[]} readers        imams whose two transmitters both read it
 * @property {number[]} transmitters   individual transmitters, where the two differ
 */

/**
 * @typedef {Object} Juncture
 * @property {number} id
 * @property {string} word       the Hafs word at issue
 * @property {string} category
 * @property {Array<{ayah: string, span: [number, number]|null}>} segments
 * @property {VariantReading[]} readings
 * @property {string} note
 */

/** @typedef {Object} VariantClip @property {string} url @property {number|null} startMs @property {number|null} endMs */

export class QiraatVariants {
  /**
   * @param {Object} [data]
   * @param {any} [data.variants]  data/qiraat-variants.json
   * @param {any} [data.places]    data/qiraat-places.json
   * @param {any} [data.audio]     data/qiraat-variant-audio.json
   */
  constructor(data = {}) {
    const variants = data.variants ?? {};
    this._readers = variants.readers ?? {};
    this._transmitters = variants.transmitters ?? {};
    this._ayahs = variants.ayahs ?? {};
    this._places = data.places?.riwayat ?? {};
    this._audioSources = data.audio?.sources ?? [];
    this._audio = data.audio?.riwayat ?? {};
  }

  get isLoaded() {
    return Object.keys(this._ayahs).length > 0;
  }

  /**
   * The words of this ayah that the Ten read differently, in the corpus's order.
   * @param {number} surahId @param {number} ayahId @returns {Juncture[]}
   */
  junctures(surahId, ayahId) {
    const rows = this._ayahs[`${surahId}:${ayahId}`] ?? [];
    return rows.map((row, id) => ({
      id,
      word: row.word ?? "",
      category: row.category ?? "",
      segments: row.segments ?? [],
      readings: row.readings ?? [],
      note: row.note ?? "",
    }));
  }

  /** Whether this ayah carries any variant at all. Only 1,409 of 6,236 do. */
  has(surahId, ayahId) {
    return (this._ayahs[`${surahId}:${ayahId}`]?.length ?? 0) > 0;
  }

  /** @param {number} id one of the ten imams */
  reader(id) {
    return this._readers[String(id)] ?? null;
  }

  /** @param {number} id one of the twenty transmitters */
  transmitter(id) {
    return this._transmitters[String(id)] ?? null;
  }

  /** Every transmitter following a reading: an imam's own pair, plus any listed individually. */
  transmittersFollowing(reading) {
    const out = [];
    const seen = new Set();
    for (const readerId of reading.readers ?? []) {
      for (const t of Object.values(this._transmitters)) {
        if (/** @type any */ (t).reader === readerId && !seen.has(/** @type any */ (t).id)) {
          seen.add(/** @type any */ (t).id);
          out.push(t);
        }
      }
    }
    for (const id of reading.transmitters ?? []) {
      const t = this.transmitter(id);
      if (t && !seen.has(t.id)) { seen.add(t.id); out.push(t); }
    }
    return out;
  }

  /**
   * The reading a given riwayah follows at a juncture, by engine slug ("warsh", "hafs").
   *
   * A reading names an imam when BOTH his transmitters follow it, and names a transmitter when the two part company, so a transmitter named on one reading overrides his imam's listing on a sibling. Look for him across the whole juncture before falling back to the imams: at 12:109 ʿĀṣim is named on نوحي while Shuʿbah is named on يوحى, and Shuʿbah recites يوحى.
   * @param {Juncture} juncture @param {string} riwayah
   * @returns {VariantReading|null}
   */
  readingFor(juncture, riwayah) {
    const readings = juncture.readings ?? [];
    for (const reading of readings) {
      for (const id of reading.transmitters ?? []) {
        if (/** @type any */ (this.transmitter(id))?.riwayah === riwayah) return reading;
      }
    }
    for (const reading of readings) {
      for (const readerId of reading.readers ?? []) {
        for (const t of Object.values(this._transmitters)) {
          const tr = /** @type any */ (t);
          if (tr.reader === readerId && tr.riwayah === riwayah) return reading;
        }
      }
    }
    return null;
  }

  /**
   * Who reads a form, rendered the way the printed sources do: the imams first in their
   * canonical order, then any lone transmitters with their imam named in parentheses.
   * @param {VariantReading} reading
   */
  attribution(reading) {
    const readers = (reading.readers ?? [])
      .map((id) => this.reader(id))
      .filter(Boolean)
      .sort((a, b) => a.position - b.position)
      .map((r) => r.abbreviation);
    const transmitters = (reading.transmitters ?? [])
      .map((id) => this.transmitter(id))
      .filter(Boolean)
      .sort((a, b) => {
        const pa = this.reader(a.reader)?.position ?? 99;
        const pb = this.reader(b.reader)?.position ?? 99;
        return pa !== pb ? pa - pb : a.id - b.id;
      })
      .map((t) => {
        const imam = this.reader(t.reader)?.abbreviation ?? "";
        return imam ? `${t.name} (${imam})` : t.name;
      });
    const parts = [];
    if (readers.length) parts.push(readers.join(", "));
    if (transmitters.length) parts.push(transmitters.join(", "));
    return parts.join(" · ");
  }

  /**
   * Where a riwayah differs from Hafs in a surah. Two kinds, because they are found two ways:
   * `word` indices are words dropped, added or spelled differently, which a text diff finds;
   * `letter` indices are words the printed mushaf marks as read with other vowels over the same
   * skeleton, which no text diff can see (مَلِكِ against مَٰلِكِ in al-Fatihah).
   * @param {string} riwayah engine slug @param {number} surahId
   * @returns {Array<{ayah: number, word: number[], letter: number[]}>}
   */
  places(riwayah, surahId) {
    const table = this._places[riwayah]?.[String(surahId)] ?? {};
    return Object.keys(table)
      .map(Number)
      .sort((a, b) => a - b)
      .map((ayah) => ({ ayah, word: table[String(ayah)].word ?? [], letter: table[String(ayah)].letter ?? [] }));
  }

  /** The riwayat `places` can answer for: the eight whose text is published. */
  riwayatWithPlaces() {
    return Object.keys(this._places).sort();
  }

  /**
   * One reciter reading the verse both ways, for the four riwayat where such a recording exists.
   * al-Bazzi, Qunbul, as-Susi and the rest carry none: no reciter published both sides with
   * timings. That is a fact about the world, and the honest rendering of it is "no recording",
   * never a button that does nothing.
   * @param {string} riwayah engine slug @param {number} surahId @param {number} ayahId
   * @returns {{reciter: string, hafs: VariantClip, riwayah: VariantClip}|null}
   */
  audio(riwayah, surahId, ayahId) {
    const rows = this._audio[riwayah]?.[String(surahId)] ?? [];
    const row = rows.find((r) => r[0] === ayahId);
    if (!row) return null;
    const source = this._audioSources[row[1]];
    if (!source) return null;
    const isSpan = source.kind === "span";
    const pad = (n, width) => String(n).padStart(width, "0");
    const name = isSpan ? `${pad(surahId, 3)}.mp3` : `${pad(surahId, 3)}${pad(ayahId, 3)}.mp3`;
    return {
      reciter: source.reciter,
      hafs: { url: `${source.hafsBase}/${name}`, startMs: isSpan ? row[2] : null, endMs: isSpan ? row[3] : null },
      riwayah: { url: `${source.riwayahBase}/${name}`, startMs: isSpan ? row[4] : null, endMs: isSpan ? row[5] : null },
    };
  }

  /** The riwayat that have any paired recordings at all. */
  riwayatWithAudio() {
    return Object.keys(this._audio).sort();
  }

  count() {
    let junctures = 0;
    let readings = 0;
    for (const rows of Object.values(this._ayahs)) {
      junctures += /** @type any[] */ (rows).length;
      for (const row of /** @type any[] */ (rows)) readings += row.readings?.length ?? 0;
    }
    return { ayahs: Object.keys(this._ayahs).length, junctures, readings };
  }
}
