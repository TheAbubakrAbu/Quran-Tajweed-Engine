package quranengine

// Three curated corpora that answer questions the text alone cannot: where else the Quran says
// this, what it says about a topic, and how to learn to recite it.
//
// See ../../docs/13-similar-and-themes.md.

import (
	"encoding/json"
	"fmt"
	"strings"
)

// SimilarMatch is one similar-ayah match, in display order.
type SimilarMatch struct {
	Surah int
	Ayah  int
	// Phrase is the shared wording, "" when none is recorded.
	Phrase string
	// Verified is true for the classical corpus, false for a generated phrase-overlap match.
	Verified bool
	// Labels say why a generated row matched; empty for verified rows.
	Labels []string
}

// Topic is one curated topic and the ayahs that speak to it.
type Topic struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Category    string `json:"category"`
	Domain      string `json:"domain"`
	// Ayahs are "2:255" references, in mushaf order.
	Ayahs []string `json:"ayahs"`
}

type themesFile struct {
	Topics []Topic `json:"topics"`
}

// TajweedDrill is one practice fragment: a short Arabic snippet with a caption saying what to
// listen for.
type TajweedDrill struct {
	Caption string `json:"caption"`
	Text    string `json:"text"`
}

// TajweedExample is an ayah to hear the rule in, with the phrase to focus on.
type TajweedExample struct {
	SurahID    int    `json:"surahId"`
	AyahNumber int    `json:"ayahNumber"`
	Focus      string `json:"focus"`
}

// TajweedMushafCard shows the rule as it appears in the mushaf.
type TajweedMushafCard struct {
	Fragments []TajweedDrill `json:"fragments"`
	CountEn   string         `json:"countEn"`
	CountAr   string         `json:"countAr"`
}

// TajweedLesson is one lesson of the course.
type TajweedLesson struct {
	ID      string   `json:"id"`
	TitleEn string   `json:"titleEn"`
	TitleAr string   `json:"titleAr"`
	Summary string   `json:"summary"`
	Body    []string `json:"body"`
	// Drills is absent on the lessons that teach through examples alone.
	Drills     []TajweedDrill     `json:"drills"`
	Examples   []TajweedExample   `json:"examples"`
	MushafCard *TajweedMushafCard `json:"mushafCard"`
	// Color is the tajweed colour this rule is painted in, where it has one.
	Color string `json:"color"`
}

// TajweedChapter groups the lessons.
type TajweedChapter struct {
	ID       string          `json:"id"`
	Title    string          `json:"title"`
	Subtitle string          `json:"subtitle"`
	Lessons  []TajweedLesson `json:"lessons"`
}

type tajweedLessonsFile struct {
	Chapters []TajweedChapter `json:"chapters"`
}

// ---- Similar ayahs -------------------------------------------------------------

// SimilarAyahs returns the matches for an ayah, in display order. Empty for most short ayahs.
func (e *Engine) SimilarAyahs(surahID, ayahID int) []SimilarMatch {
	rows, ok := e.similarAyahs[fmt.Sprintf("%d:%d", surahID, ayahID)]
	if !ok {
		return nil
	}
	var out []SimilarMatch
	for _, row := range rows {
		// [surah, ayah, phrase, verifiedFlag, labels?] — heterogeneous, so read field by field.
		if len(row) < 4 {
			continue
		}
		var match SimilarMatch
		if json.Unmarshal(row[0], &match.Surah) != nil || json.Unmarshal(row[1], &match.Ayah) != nil {
			continue
		}
		_ = json.Unmarshal(row[2], &match.Phrase)
		var verified int
		_ = json.Unmarshal(row[3], &verified)
		match.Verified = verified == 1
		if len(row) > 4 {
			_ = json.Unmarshal(row[4], &match.Labels)
		}
		out = append(out, match)
	}
	return out
}

// HasSimilarAyahs reports whether the ayah has any — a map hit, cheap enough to gate a button on.
func (e *Engine) HasSimilarAyahs(surahID, ayahID int) bool {
	return len(e.similarAyahs[fmt.Sprintf("%d:%d", surahID, ayahID)]) > 0
}

// SimilarAyahCount is how many ayahs have at least one match.
func (e *Engine) SimilarAyahCount() int {
	return len(e.similarAyahs)
}

// ---- Themes --------------------------------------------------------------------

// Topics returns every topic, in the order the corpus lists them.
func (e *Engine) Topics() []Topic { return e.topics }

// Topic looks one up by id.
func (e *Engine) Topic(id string) *Topic {
	for i := range e.topics {
		if e.topics[i].ID == id {
			return &e.topics[i]
		}
	}
	return nil
}

// TopicDomains lists the distinct domains, in first-seen order.
func (e *Engine) TopicDomains() []string {
	return orderedUnique(e.topics, func(t Topic) string { return t.Domain })
}

// TopicCategories lists the distinct categories, optionally within one domain ("" for all).
func (e *Engine) TopicCategories(domain string) []string {
	var scope []Topic
	for _, topic := range e.topics {
		if domain == "" || topic.Domain == domain {
			scope = append(scope, topic)
		}
	}
	return orderedUnique(scope, func(t Topic) string { return t.Category })
}

// TopicsInDomain filters by domain.
func (e *Engine) TopicsInDomain(domain string) []Topic {
	return filterTopics(e.topics, func(t Topic) bool { return t.Domain == domain })
}

// TopicsInCategory filters by category.
func (e *Engine) TopicsInCategory(category string) []Topic {
	return filterTopics(e.topics, func(t Topic) bool { return t.Category == category })
}

// TopicsFor lists the topics an ayah appears under.
func (e *Engine) TopicsFor(surahID, ayahID int) []Topic {
	reference := fmt.Sprintf("%d:%d", surahID, ayahID)
	return filterTopics(e.topics, func(t Topic) bool {
		for _, ayah := range t.Ayahs {
			if ayah == reference {
				return true
			}
		}
		return false
	})
}

// SearchTopics finds topics whose name, description, category or domain carries query.
func (e *Engine) SearchTopics(query string) []Topic {
	needle := strings.ToLower(strings.TrimSpace(query))
	if needle == "" {
		return nil
	}
	return filterTopics(e.topics, func(t Topic) bool {
		for _, field := range []string{t.Name, t.Description, t.Category, t.Domain} {
			if strings.Contains(strings.ToLower(field), needle) {
				return true
			}
		}
		return false
	})
}

// ---- The tajweed course ---------------------------------------------------------

// TajweedChapters returns every chapter, in course order.
func (e *Engine) TajweedChapters() []TajweedChapter { return e.tajweedChapters }

// TajweedChapter looks one up by id.
func (e *Engine) TajweedChapter(id string) *TajweedChapter {
	for i := range e.tajweedChapters {
		if e.tajweedChapters[i].ID == id {
			return &e.tajweedChapters[i]
		}
	}
	return nil
}

// TajweedLessons returns every lesson across every chapter, in course order.
func (e *Engine) TajweedLessons() []TajweedLesson {
	var out []TajweedLesson
	for _, chapter := range e.tajweedChapters {
		out = append(out, chapter.Lessons...)
	}
	return out
}

// TajweedLesson looks one up by id.
func (e *Engine) TajweedLesson(id string) *TajweedLesson {
	lessons := e.TajweedLessons()
	for i := range lessons {
		if lessons[i].ID == id {
			return &lessons[i]
		}
	}
	return nil
}

// TajweedChapterOf is which chapter a lesson belongs to.
func (e *Engine) TajweedChapterOf(id string) *TajweedChapter {
	for i := range e.tajweedChapters {
		for _, lesson := range e.tajweedChapters[i].Lessons {
			if lesson.ID == id {
				return &e.tajweedChapters[i]
			}
		}
	}
	return nil
}

// NextTajweedLesson is the lesson after this one, walking across chapter boundaries.
func (e *Engine) NextTajweedLesson(id string) *TajweedLesson {
	lessons := e.TajweedLessons()
	for i := range lessons {
		if lessons[i].ID == id && i+1 < len(lessons) {
			return &lessons[i+1]
		}
	}
	return nil
}

// PreviousTajweedLesson is its twin.
func (e *Engine) PreviousTajweedLesson(id string) *TajweedLesson {
	lessons := e.TajweedLessons()
	for i := range lessons {
		if lessons[i].ID == id && i > 0 {
			return &lessons[i-1]
		}
	}
	return nil
}

func filterTopics(topics []Topic, keep func(Topic) bool) []Topic {
	var out []Topic
	for _, topic := range topics {
		if keep(topic) {
			out = append(out, topic)
		}
	}
	return out
}

func orderedUnique(topics []Topic, field func(Topic) string) []string {
	seen := make(map[string]bool, len(topics))
	var out []string
	for _, topic := range topics {
		value := field(topic)
		if seen[value] {
			continue
		}
		seen[value] = true
		out = append(out, value)
	}
	return out
}
