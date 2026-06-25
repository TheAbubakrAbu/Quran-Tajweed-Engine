package quranengine

import (
	"fmt"
	"sort"
	"strings"
)

// pad3 zero-pads to three digits: 1 -> "001", 57 -> "057", 114 -> "114".
func pad3(n int) string { return fmt.Sprintf("%03d", n) }

// Reciters returns all reciters sorted by name (matching the JS port's display order).
func (e *Engine) Reciters() []Reciter {
	out := make([]Reciter, len(e.reciters))
	copy(out, e.reciters)
	sort.SliceStable(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// ReciterByID returns the reciter with the given id, or nil if not found.
func (e *Engine) ReciterByID(id string) *Reciter {
	for i := range e.reciters {
		if e.reciters[i].ID == id {
			return &e.reciters[i]
		}
	}
	return nil
}

// SurahAudioURL builds the full-surah recitation URL:
//
//	reciter.SurahLink + pad3(surah) + ".mp3"
func SurahAudioURL(r *Reciter, surahNumber int) (string, error) {
	if surahNumber < 1 || surahNumber > 114 {
		return "", fmt.Errorf("surah out of range: %d", surahNumber)
	}
	if r.SurahLink == "" {
		return "", fmt.Errorf("reciter %q has no full-surah feed", r.Name)
	}
	return r.SurahLink + pad3(surahNumber) + ".mp3", nil
}

// AyahAudioURL builds the per-ayah recitation URL. globalAyahNumber is the
// 1..6236 value from Engine.GlobalAyahNumber.
//
//	https://cdn.islamic.network/quran/audio/{bitrate}/{identifier}/{globalAyah}.mp3
func AyahAudioURL(r *Reciter, globalAyahNumber int) string {
	return fmt.Sprintf("https://cdn.islamic.network/quran/audio/%s/%s/%d.mp3",
		r.AyahBitrate, r.AyahIdentifier, globalAyahNumber)
}

const minshawiFallbackName = "Muhammad Al-Minshawi (Murattal)"

// DefaultsToMinshawi reports whether a reciter falls back to Minshawi for ayah audio.
func DefaultsToMinshawi(r *Reciter) bool {
	return strings.Contains(r.AyahIdentifier, "minshawi") && !strings.Contains(r.Name, "Minshawi")
}

// AyahNowPlayingName returns the display name to show while ayah audio plays.
func AyahNowPlayingName(r *Reciter) string {
	if DefaultsToMinshawi(r) {
		return minshawiFallbackName
	}
	if r.Qiraah != "" {
		return fmt.Sprintf("%s (%s)", r.Name, r.Qiraah)
	}
	return r.Name
}
