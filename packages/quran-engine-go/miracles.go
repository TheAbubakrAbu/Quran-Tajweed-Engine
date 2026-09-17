package quranengine

// The scientific-miracles corpus: 202 short articles, each making one claim about the Quran and
// anchoring it to the ayahs it rests on, under 15 categories.
//
// An article is a list of BLOCKS in reading order rather than one field of prose, because the
// layout matters: the claim is a headline, the lead sets it up, a quote carries somebody else's
// words with the source next to them, an ayah block is a hole the consumer fills from quran.json,
// and the closer asks the rhetorical question the article was built toward.
//
// An ayah block carries NO text, by design: surah, ayah and end ayah only. The verse belongs to
// this engine's own Hafs text, so duplicating it here would be a second copy to keep in step and
// would pin the article to one riwayah.
//
// There are NO image blocks and ImagesIncluded is false: the site's illustrations are not
// republished here for licensing reasons, and the prose is written to stand without them. A
// consumer that leaves a gap for a picture will be waiting forever.
//
// Two levels are in play and they are NOT the same number. A CATEGORY has a level (the hardest
// science it covers) and so does an ARTICLE; 147 of the 202 differ, so anything a reader filters
// or sorts by has to come off the ARTICLE.
//
// See ../../docs/25-miracles.md.

import (
	"sort"
	"strings"
)

// MiracleLevels are the four levels, easiest first.
//
// Hard-coded because this is the app's own ordering and nothing in the file states it:
// alphabetically "extreme" would sort second, which is precisely backwards.
var MiracleLevels = []string{"simple", "intermediate", "advanced", "extreme"}

// miracleProseKinds are the block kinds that carry the article's OWN prose. A quote is somebody
// else's words and an ayah block has no text at all, so neither belongs in MiracleText.
var miracleProseKinds = map[string]bool{"claim": true, "lead": true, "text": true, "closer": true}

// MiracleCategory is one of the fifteen categories, with the hardest science it covers.
type MiracleCategory struct {
	ID string `json:"id"`
	// Level is the CATEGORY's, which an article under it need not share.
	Level string `json:"level"`
}

// MiracleLink is a link out of a block: either an outside page or another article in this corpus.
//
// Exactly one of URL and Slug is set. Both forms occur, so a model that kept only URL would
// silently drop the twelve internal cross-references.
type MiracleLink struct {
	Label string `json:"label"`
	// URL is an outside page.
	URL string `json:"url"`
	// Slug is another article's, to follow with Miracle.
	Slug string `json:"slug"`
}

// MiracleBlock is one block of an article. Which fields are set follows from Kind.
type MiracleBlock struct {
	// Kind is "claim", "lead", "text", "quote", "ayah" or "closer". Never "image".
	Kind string `json:"kind"`
	// Text is set on every kind but ayah.
	Text string `json:"text"`
	// Links appear on lead and text blocks only.
	Links []MiracleLink `json:"links"`
	// SourceLabel and SourceURL are on quote blocks only: who is being quoted.
	SourceLabel string `json:"sourceLabel"`
	SourceURL   string `json:"sourceUrl"`
	// Surah, Ayah and EndAyah are on ayah blocks only. EndAyah is always present, and equal to
	// Ayah for a single verse.
	Surah   int `json:"surah"`
	Ayah    int `json:"ayah"`
	EndAyah int `json:"endAyah"`
}

// MiracleArticle is one article.
type MiracleArticle struct {
	Slug  string `json:"slug"`
	Title string `json:"title"`
	// Category is a MiracleCategory ID.
	Category string `json:"category"`
	// Level is this article's OWN level, not its category's.
	Level  string         `json:"level"`
	Blocks []MiracleBlock `json:"blocks"`
}

// MiracleAyahRef is one ayah range an article cites.
type MiracleAyahRef struct {
	Surah   int
	Ayah    int
	EndAyah int
}

type miraclesFile struct {
	Source string `json:"source"`
	// ImagesIncluded is false, always: the illustrations are not republished.
	ImagesIncluded bool              `json:"imagesIncluded"`
	Categories     []MiracleCategory `json:"categories"`
	Articles       []MiracleArticle  `json:"articles"`
}

// miracleLevelRank is where a level sorts, or past the end for one the corpus invents later.
func miracleLevelRank(level string) int {
	for i, l := range MiracleLevels {
		if l == level {
			return i
		}
	}
	return len(MiracleLevels)
}

// covers reports whether an ayah block covers one ayah. A block is a RANGE, so an article citing
// 21:30-33 answers to 21:31 as well.
func (b MiracleBlock) covers(surahID, ayahID int) bool {
	if b.Kind != "ayah" || b.Surah != surahID {
		return false
	}
	end := b.EndAyah
	if end < b.Ayah {
		end = b.Ayah
	}
	return ayahID >= b.Ayah && ayahID <= end
}

// Miracles returns all 202 articles, in corpus order.
func (e *Engine) Miracles() []MiracleArticle { return e.miracles.Articles }

// Miracle returns one article, by its slug.
func (e *Engine) Miracle(slug string) (MiracleArticle, bool) {
	for _, article := range e.miracles.Articles {
		if article.Slug == slug {
			return article, true
		}
	}
	return MiracleArticle{}, false
}

// MiracleCategories returns the fifteen categories, in the corpus's own order.
func (e *Engine) MiracleCategories() []MiracleCategory { return e.miracles.Categories }

// MiracleCategoryByID returns one category, by its id.
func (e *Engine) MiracleCategoryByID(id string) (MiracleCategory, bool) {
	for _, category := range e.miracles.Categories {
		if category.ID == id {
			return category, true
		}
	}
	return MiracleCategory{}, false
}

// MiraclesByCategory returns every article filed under one category.
func (e *Engine) MiraclesByCategory(id string) []MiracleArticle {
	out := []MiracleArticle{}
	for _, article := range e.miracles.Articles {
		if article.Category == id {
			out = append(out, article)
		}
	}
	return out
}

// MiraclesByLevel returns every article at one level.
//
// The ARTICLE's level, not its category's: they disagree far more often than they agree, and a
// reader who picked "simple" means the article.
func (e *Engine) MiraclesByLevel(level string) []MiracleArticle {
	out := []MiracleArticle{}
	for _, article := range e.miracles.Articles {
		if article.Level == level {
			out = append(out, article)
		}
	}
	return out
}

// MiracleLevelsPresent returns the article levels actually present, easiest first.
func (e *Engine) MiracleLevelsPresent() []string {
	seen := map[string]bool{}
	out := []string{}
	for _, article := range e.miracles.Articles {
		if !seen[article.Level] {
			seen[article.Level] = true
			out = append(out, article.Level)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		ri, rj := miracleLevelRank(out[i]), miracleLevelRank(out[j])
		if ri != rj {
			return ri < rj
		}
		return out[i] < out[j]
	})
	return out
}

// MiraclesCiting returns every article that cites an ayah: the way into this corpus from elsewhere
// in the engine.
//
// An ayah block is a RANGE, so an article citing 21:30-33 answers to 21:31 as well. An article
// that cites the same ayah in two blocks is still listed once.
func (e *Engine) MiraclesCiting(surahID, ayahID int) []MiracleArticle {
	out := []MiracleArticle{}
	for _, article := range e.miracles.Articles {
		for _, block := range article.Blocks {
			if block.covers(surahID, ayahID) {
				out = append(out, article)
				break
			}
		}
	}
	return out
}

// MiracleAyahRefs returns the ayah ranges one article cites, in the order it cites them.
func (e *Engine) MiracleAyahRefs(slug string) []MiracleAyahRef {
	article, ok := e.Miracle(slug)
	if !ok {
		return nil
	}
	out := []MiracleAyahRef{}
	for _, block := range article.Blocks {
		if block.Kind != "ayah" {
			continue
		}
		end := block.EndAyah
		if end < block.Ayah {
			end = block.Ayah
		}
		out = append(out, MiracleAyahRef{Surah: block.Surah, Ayah: block.Ayah, EndAyah: end})
	}
	return out
}

// SearchMiracles returns articles whose title or prose matches a query, case-insensitively.
//
// Quotes are searched as well: a reader looking for a word remembers reading it, not who wrote it.
func (e *Engine) SearchMiracles(query string, limit int) []MiracleArticle {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil
	}
	out := []MiracleArticle{}
	for _, article := range e.miracles.Articles {
		hit := strings.Contains(strings.ToLower(article.Title), q)
		if !hit {
			for _, block := range article.Blocks {
				if strings.Contains(strings.ToLower(block.Text), q) {
					hit = true
					break
				}
			}
		}
		if hit {
			out = append(out, article)
			if limit > 0 && len(out) >= limit {
				break
			}
		}
	}
	return out
}

// MiracleText returns one article's own prose, blocks joined with a blank line in reading order.
//
// Quote blocks are SKIPPED: they are third-party excerpts sitting next to a source label, so
// folding them in would put somebody else's words into the article's voice and would break a
// citation off from what it cites. Ayah blocks are skipped because they carry no text at all, only
// a reference for the consumer to resolve.
func (e *Engine) MiracleText(slug string) string {
	article, ok := e.Miracle(slug)
	if !ok {
		return ""
	}
	parts := []string{}
	for _, block := range article.Blocks {
		if miracleProseKinds[block.Kind] && block.Text != "" {
			parts = append(parts, block.Text)
		}
	}
	return strings.Join(parts, "\n\n")
}

// MiraclesSource reports where the corpus came from and when it was captured.
func (e *Engine) MiraclesSource() string { return e.miracles.Source }

// MiraclesImagesIncluded is false, always: the illustrations are not republished.
func (e *Engine) MiraclesImagesIncluded() bool { return e.miracles.ImagesIncluded }

// MiraclesCount reports how many articles, categories and ayah refs the corpus carries.
func (e *Engine) MiraclesCount() (articles, categories, ayahRefs int) {
	for _, article := range e.miracles.Articles {
		for _, block := range article.Blocks {
			if block.Kind == "ayah" {
				ayahRefs++
			}
		}
	}
	return len(e.miracles.Articles), len(e.miracles.Categories), ayahRefs
}
