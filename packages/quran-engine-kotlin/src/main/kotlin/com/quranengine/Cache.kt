package com.quranengine

/**
 * Caching / offline-download path helpers. Ported from `packages/quran-engine-js/src/cache.js`.
 *
 * The engine stays storage-agnostic: it gives you the canonical cache paths/keys; you plug in any
 * storage backend (filesystem, Android files dir, etc.). Layout (full-surah audio only):
 *   <root>/<sanitize(reciter.id)>/<zeroPad3(surah)>.mp3
 */

private val SANITIZE_DISALLOWED = Regex("[^A-Za-z0-9\\-_]")

/**
 * Sanitize a reciter id into a filesystem-safe directory name: keep [A-Za-z0-9-_], replace everything
 * else with "_", cap at 180 chars, fall back to "reciter" if empty.
 */
fun sanitizeReciterDir(reciterId: String): String {
    val safe = SANITIZE_DISALLOWED.replace(reciterId, "_").take(180)
    return safe.ifEmpty { "reciter" }
}

/** Relative path (under the downloads root) for a downloaded full-surah file. */
fun localSurahPath(reciter: Reciter, surahNumber: Int): String =
    "${sanitizeReciterDir(reciter.id)}/${zeroPad3(surahNumber)}.mp3"

/** Relative path of the content-addressed shared file for a given content hash. */
fun sharedAudioPath(sha256Hex: String, ext: String = "mp3"): String =
    "SharedAudio/$sha256Hex.$ext"
