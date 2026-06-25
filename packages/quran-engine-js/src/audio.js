// @ts-check
/**
 * Recitation audio URL builders + reciter directory.
 *
 * Mirrors QuranPlayer.swift. Two independent feeds:
 *   • Full-surah  : `surahLink + zeroPad3(surah) + ".mp3"`   (mp3quran.net CDNs)
 *   • Ayah-by-ayah: `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3`
 */

/**
 * @typedef {Object} Reciter
 * @property {string} id              "{name}|{qiraah??'Hafs'}|{surahLink}"
 * @property {string} name
 * @property {string} ayahIdentifier  e.g. "ar.alafasy"
 * @property {string} ayahBitrate     e.g. "128" (string, used verbatim)
 * @property {string} surahLink       full-surah CDN base, trailing slash
 * @property {string|null} qiraah     null => Hafs; else riwayah label
 * @property {string} [group]
 */

/** @param {number} n */
function pad3(n) {
  return String(n).padStart(3, "0");
}

/**
 * Full-surah recitation URL.
 * @param {Reciter} reciter
 * @param {number} surahNumber 1..114
 */
export function surahAudioUrl(reciter, surahNumber) {
  if (!(surahNumber >= 1 && surahNumber <= 114)) throw new RangeError(`surah out of range: ${surahNumber}`);
  if (!reciter.surahLink) throw new Error(`Reciter "${reciter.name}" has no full-surah feed`);
  return `${reciter.surahLink}${pad3(surahNumber)}.mp3`;
}

/**
 * Ayah-by-ayah recitation URL. Requires the global ayah number (1..6236); use
 * `Quran.globalAyahNumber(surah, ayah)` to compute it.
 * @param {Reciter} reciter
 * @param {number} globalAyahNumber
 */
export function ayahAudioUrl(reciter, globalAyahNumber) {
  return `https://cdn.islamic.network/quran/audio/${reciter.ayahBitrate}/${reciter.ayahIdentifier}/${globalAyahNumber}.mp3`;
}

const MINSHAWI_FALLBACK_NAME = "Muhammad Al-Minshawi (Murattal)";

/** True if this reciter falls back to Minshawi for individual-ayah audio. Mirrors defaultToMinshawi. */
export function defaultsToMinshawi(reciter) {
  return reciter.ayahIdentifier.includes("minshawi") && !reciter.name.includes("Minshawi");
}

/** Display name to show while ayah audio plays (honest about the fallback). */
export function ayahNowPlayingName(reciter) {
  if (defaultsToMinshawi(reciter)) return MINSHAWI_FALLBACK_NAME;
  if (reciter.qiraah) return `${reciter.name} (${reciter.qiraah})`;
  return reciter.name;
}

export class Reciters {
  /** @param {Reciter[]} list parsed data/reciters.json */
  constructor(list) {
    /** @type {Reciter[]} */
    this.list = [...list].sort((a, b) => a.name.localeCompare(b.name));
    /** @type {Map<string,Reciter>} */
    this._byId = new Map(this.list.map((r) => [r.id, r]));
  }

  all() { return this.list; }

  /** @param {string} id */
  byId(id) { return this._byId.get(id); }

  /** Reciters that have a full-surah feed. */
  withSurahFeed() { return this.list.filter((r) => r.surahLink && !r.surahLink.endsWith(".mp3")); }

  /** Reciters for a given riwayah label (null/"hafs" => the default Hafs feeds). @param {string|null} qiraah */
  byQiraah(qiraah) {
    if (!qiraah || qiraah.toLowerCase() === "hafs") return this.list.filter((r) => !r.qiraah);
    return this.list.filter((r) => r.qiraah === qiraah);
  }

  /** Distinct riwayah labels available (excluding default Hafs). */
  qiraat() {
    return [...new Set(this.list.map((r) => r.qiraah).filter(Boolean))];
  }
}
