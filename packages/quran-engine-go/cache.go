package quranengine

import "strings"

// SanitizeReciterDir turns a reciter id into a filesystem-safe directory name:
// every char not in [A-Za-z0-9-_] becomes "_", capped at 180 chars, with the
// fallback "reciter" for an empty result.
func SanitizeReciterDir(reciterID string) string {
	var b strings.Builder
	for _, r := range reciterID {
		switch {
		case r >= 'A' && r <= 'Z', r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	safe := b.String()
	if len(safe) > 180 {
		safe = safe[:180]
	}
	if safe == "" {
		return "reciter"
	}
	return safe
}

// LocalSurahPath is the relative path (under a downloads root) for a downloaded
// full-surah file: sanitize(reciter.id)/pad3(surah).mp3.
func LocalSurahPath(r *Reciter, surahNumber int) string {
	return SanitizeReciterDir(r.ID) + "/" + pad3(surahNumber) + ".mp3"
}

// SharedAudioPath is the content-addressed shared file path for a content hash.
func SharedAudioPath(sha256Hex, ext string) string {
	if ext == "" {
		ext = "mp3"
	}
	return "SharedAudio/" + sha256Hex + "." + ext
}
