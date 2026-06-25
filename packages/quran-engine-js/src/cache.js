// @ts-check
/**
 * Caching / offline-download helpers.
 *
 * Mirrors ReciterDownloadManager in QuranPlayer.swift. The engine itself stays storage-agnostic:
 * it gives you the canonical cache *paths/keys*, and you plug in any storage backend (filesystem,
 * IndexedDB, React-Native FS, Cache API, …) via the `CacheStore` interface.
 *
 * Layout (full-surah audio only; ayah audio is streamed, not cached, in the reference app):
 *   <root>/<sanitize(reciter.id)>/<zeroPad3(surah)>.mp3        per-reciter file
 *   <root>/SharedAudio/<sha256hex(content)>.<ext>             content-addressed dedup store
 */

/** @param {number} n */
function pad3(n) {
  return String(n).padStart(3, "0");
}

/**
 * Sanitize a reciter id into a filesystem-safe directory name. Mirrors safeDirectoryName:
 * keep [A-Za-z0-9-_], replace everything else with "_", cap at 180 chars.
 * @param {string} reciterId  "{name}|{qiraah??'Hafs'}|{surahLink}"
 */
export function sanitizeReciterDir(reciterId) {
  const safe = reciterId.replace(/[^A-Za-z0-9\-_]/g, "_").slice(0, 180);
  return safe || "reciter";
}

/**
 * Relative path (under the downloads root) for a downloaded full-surah file.
 * @param {{id:string}} reciter
 * @param {number} surahNumber
 */
export function localSurahPath(reciter, surahNumber) {
  return `${sanitizeReciterDir(reciter.id)}/${pad3(surahNumber)}.mp3`;
}

/** Relative path of the content-addressed shared file for a given content hash. */
export function sharedAudioPath(sha256Hex, ext = "mp3") {
  return `SharedAudio/${sha256Hex}.${ext}`;
}

/**
 * @typedef {Object} CacheStore
 * @property {(key:string)=>Promise<boolean>} has
 * @property {(key:string)=>Promise<ArrayBuffer|Uint8Array|null>} get
 * @property {(key:string, data:ArrayBuffer|Uint8Array)=>Promise<void>} put
 * @property {(key:string)=>Promise<void>} delete
 */

/**
 * A thin caching audio resolver. Given a URL builder and a CacheStore, returns the cached bytes
 * when present, otherwise fetches, stores, and returns them. Works in any environment that has
 * `fetch` (browser, Node 18+, Deno, Bun) and any storage you provide.
 */
export class AudioCache {
  /**
   * @param {CacheStore} store
   * @param {{ fetch?: typeof fetch }} [opts]
   */
  constructor(store, opts = {}) {
    this.store = store;
    this._fetch = opts.fetch ?? (typeof fetch !== "undefined" ? fetch : undefined);
  }

  /**
   * Resolve a full-surah file: cache key is the per-reciter path. Returns the bytes.
   * @param {{id:string}} reciter
   * @param {number} surahNumber
   * @param {string} url   from audio.surahAudioUrl(reciter, surahNumber)
   * @returns {Promise<Uint8Array>}
   */
  async surah(reciter, surahNumber, url) {
    const key = localSurahPath(reciter, surahNumber);
    if (await this.store.has(key)) {
      const cached = await this.store.get(key);
      if (cached) return toBytes(cached);
    }
    if (!this._fetch) throw new Error("No fetch available; pass { fetch } to AudioCache");
    const res = await this._fetch(url);
    if (!res.ok) throw new Error(`Download failed (${res.status}) for ${url}`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    await this.store.put(key, bytes);
    return bytes;
  }

  /** Whether a full-surah file is already downloaded. */
  async hasSurah(reciter, surahNumber) {
    return this.store.has(localSurahPath(reciter, surahNumber));
  }

  /** Remove a downloaded full-surah file. */
  async removeSurah(reciter, surahNumber) {
    return this.store.delete(localSurahPath(reciter, surahNumber));
  }
}

/** A simple in-memory CacheStore — handy for tests and ephemeral use. @returns {CacheStore} */
export function memoryStore() {
  /** @type {Map<string,Uint8Array>} */
  const m = new Map();
  return {
    async has(k) { return m.has(k); },
    async get(k) { return m.get(k) ?? null; },
    async put(k, d) { m.set(k, toBytes(d)); },
    async delete(k) { m.delete(k); },
  };
}

function toBytes(d) {
  return d instanceof Uint8Array ? d : new Uint8Array(d);
}
