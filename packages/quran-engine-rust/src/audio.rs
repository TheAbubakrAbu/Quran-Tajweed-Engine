//! Recitation audio URL builders. Mirrors `src/audio.js`.
//!
//! Two independent feeds:
//! - Full-surah:   `surahLink + zeroPad3(surah) + ".mp3"` (mp3quran.net CDNs)
//! - Ayah-by-ayah: `https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3`

use crate::model::Reciter;
use crate::util::zero_pad3;

const MINSHAWI_FALLBACK_NAME: &str = "Muhammad Al-Minshawi (Murattal)";

/// Full-surah recitation URL: `reciter.surahLink + zeroPad3(surah) + ".mp3"`.
///
/// Returns `Err` if `surah` is out of range (1..=114) or the reciter has no full-surah feed.
pub fn surah_audio_url(reciter: &Reciter, surah: u32) -> Result<String, String> {
    if !(1..=114).contains(&surah) {
        return Err(format!("surah out of range: {surah}"));
    }
    if reciter.surah_link.is_empty() {
        return Err(format!("Reciter \"{}\" has no full-surah feed", reciter.name));
    }
    Ok(format!("{}{}.mp3", reciter.surah_link, zero_pad3(surah)))
}

/// Ayah-by-ayah recitation URL. `global_ayah` is the global ayah number (1..=6236);
/// use [`crate::Engine::global_ayah_number`] to compute it.
pub fn ayah_audio_url(reciter: &Reciter, global_ayah: u32) -> String {
    format!(
        "https://cdn.islamic.network/quran/audio/{}/{}/{}.mp3",
        reciter.ayah_bitrate, reciter.ayah_identifier, global_ayah
    )
}

/// True if this reciter falls back to Minshawi for individual-ayah audio.
pub fn defaults_to_minshawi(reciter: &Reciter) -> bool {
    reciter.ayah_identifier.contains("minshawi") && !reciter.name.contains("Minshawi")
}

/// Display name to show while ayah audio plays (honest about the fallback).
pub fn ayah_now_playing_name(reciter: &Reciter) -> String {
    if defaults_to_minshawi(reciter) {
        return MINSHAWI_FALLBACK_NAME.to_string();
    }
    match &reciter.qiraah {
        Some(q) if !q.is_empty() => format!("{} ({})", reciter.name, q),
        _ => reciter.name.clone(),
    }
}
