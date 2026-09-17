package quranengine

// Meaning-based ("AI") search: find the ayahs about a topic whether or not they use its words.
//
// WHY WORD VECTORS AND MaxSim, NOT A SENTENCE EMBEDDING
//
// Measured, not assumed. Scoring an ayah by the cosine between a SENTENCE embedding of the query
// and one of the ayah ranks this corpus close to randomly: translated scripture is dense, and one
// vector for a whole verse washes out the single idea the query is asking about. Scoring word by
// word fixes it, embed every word, and score a text as the MEAN over the query's words of the
// BEST matching word in the text. On real verses that separates related (0.42–0.70) from unrelated
// (0.27–0.41) cleanly, and it degrades gracefully: a query word the model has never seen
// contributes nothing instead of poisoning the vector.
//
// THE EMBEDDER IS YOURS
//
// This engine ships no model, word vectors are tens of megabytes and every platform already has
// one worth using. Hand NewSemantic a function from a lowercased word to its vector, or nil when
// it has none. Vectors are cached per word, so a repeated word costs one lookup for the corpus.
//
// See ../../docs/14-ask-ai.md.

import (
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// SemanticHit is one scored document.
type SemanticHit struct {
	ID string
	// Score is the mean best-match cosine over the query's words, 0..1.
	Score float64
}

// SemanticDocument is one corpus entry to index.
type SemanticDocument struct {
	ID   string
	Text string
}

// Semantic is a word-vector MaxSim index over any corpus. It is not safe for concurrent use: both
// indexing and searching populate the vector cache.
type Semantic struct {
	embed func(word string) []float64
	// MinWordLength: words shorter than this are skipped on both sides. Default 3.
	minWordLength int
	vectors       map[string][]float64
	documents     []semanticDocument
}

type semanticDocument struct {
	id      string
	vectors [][]float64
}

// NewSemantic returns an empty index. embed maps a lowercased word to its vector, or nil when it
// has none.
func NewSemantic(embed func(word string) []float64) *Semantic {
	return &Semantic{
		embed:         embed,
		minWordLength: 3,
		vectors:       map[string][]float64{},
	}
}

// WithMinWordLength sets the floor on word length, on both sides of the comparison.
func (s *Semantic) WithMinWordLength(length int) *Semantic {
	s.minWordLength = length
	return s
}

// Len is how many documents are indexed.
func (s *Semantic) Len() int { return len(s.documents) }

// Index builds (or rebuilds) the index. Call once per corpus.
func (s *Semantic) Index(corpus []SemanticDocument) *Semantic {
	s.documents = s.documents[:0]
	for _, document := range corpus {
		vectors := s.vectorize(document.Text)
		if len(vectors) > 0 {
			s.documents = append(s.documents, semanticDocument{id: document.ID, vectors: vectors})
		}
	}
	return s
}

// Search returns the documents closest in meaning to query, best first. minScore is a floor on
// "actually related": 0.42 is a sensible start on English translations, but calibrate it against
// YOUR embedder.
func (s *Semantic) Search(query string, limit int, minScore float64) []SemanticHit {
	queryVectors := s.vectorize(query)
	if len(queryVectors) == 0 {
		return nil
	}

	var hits []SemanticHit
	for _, document := range s.documents {
		total := 0.0
		for _, q := range queryVectors {
			best := -1.0
			for _, w := range document.vectors {
				if score := Cosine(q, w); score > best {
					best = score
				}
			}
			total += best
		}
		score := total / float64(len(queryVectors))
		if score >= minScore {
			hits = append(hits, SemanticHit{ID: document.id, Score: score})
		}
	}
	sort.SliceStable(hits, func(i, j int) bool {
		if hits[i].Score != hits[j].Score {
			return hits[i].Score > hits[j].Score
		}
		return hits[i].ID < hits[j].ID
	})
	if limit > 0 && len(hits) > limit {
		hits = hits[:limit]
	}
	return hits
}

// Clear drops the index and the vector cache.
func (s *Semantic) Clear() {
	s.documents = nil
	s.vectors = map[string][]float64{}
}

func (s *Semantic) vectorize(text string) [][]float64 {
	var out [][]float64
	seen := map[string]bool{}
	for _, raw := range strings.FieldsFunc(strings.ToLower(text), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	}) {
		if len([]rune(raw)) < s.minWordLength || seen[raw] {
			continue
		}
		seen[raw] = true
		if vector := s.vector(raw); vector != nil {
			out = append(out, vector)
		}
	}
	return out
}

func (s *Semantic) vector(word string) []float64 {
	if cached, ok := s.vectors[word]; ok {
		return cached
	}
	raw := s.embed(word)
	// Normalized once here, so scoring is a dot product rather than three passes per pair.
	var normalized []float64
	if len(raw) > 0 {
		normalized = normalize(raw)
	}
	s.vectors[word] = normalized
	return normalized
}

// Cosine is the similarity of two ALREADY NORMALIZED vectors, i.e. their dot product.
func Cosine(a, b []float64) float64 {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	sum := 0.0
	for i := 0; i < n; i++ {
		sum += a[i] * b[i]
	}
	return sum
}

func normalize(raw []float64) []float64 {
	magnitude := 0.0
	for _, value := range raw {
		magnitude += value * value
	}
	magnitude = math.Sqrt(magnitude)
	out := make([]float64, len(raw))
	if magnitude == 0 {
		return out
	}
	for i, value := range raw {
		out[i] = value / magnitude
	}
	return out
}

// SemanticCorpus is the (id, translation) pairs to hand Semantic.Index for the Ask AI meaning lane.
func (e *Engine) SemanticCorpus() []SemanticDocument {
	out := make([]SemanticDocument, 0, e.totalAyahs)
	for i := range e.surahs {
		surah := &e.surahs[i]
		for _, ayah := range surah.Ayahs {
			out = append(out, SemanticDocument{
				ID:   strconv.Itoa(surah.ID) + ":" + strconv.Itoa(ayah.ID),
				Text: ayah.TextEnglishSaheeh,
			})
		}
	}
	return out
}
