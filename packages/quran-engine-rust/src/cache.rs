//! Caching path helpers. Mirrors the path-builder portion of `src/cache.js`.
//!
//! The engine stays storage-agnostic — it only produces the canonical cache paths/keys.
//! Layout: `<root>/<sanitize(reciter.id)>/<zeroPad3(surah)>.mp3`.

use crate::util::zero_pad3;

/// Sanitize a reciter id into a filesystem-safe directory name: keep `[A-Za-z0-9-_]`,
/// replace everything else with `_`, cap at 180 chars (fallback `"reciter"`).
pub fn sanitize_reciter_dir(reciter_id: &str) -> String {
    let mut safe: String = reciter_id
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .take(180)
        .collect();
    if safe.is_empty() {
        safe = "reciter".to_string();
    }
    safe
}

/// Relative path (under the downloads root) for a downloaded full-surah file:
/// `sanitize(reciter.id)/zeroPad3(surah).mp3`.
pub fn local_surah_path(reciter_id: &str, surah: u32) -> String {
    format!("{}/{}.mp3", sanitize_reciter_dir(reciter_id), zero_pad3(surah))
}

/// Relative path of the content-addressed shared file for a given content hash.
pub fn shared_audio_path(sha256_hex: &str, ext: &str) -> String {
    format!("SharedAudio/{}.{}", sha256_hex, ext)
}
