//! Ask AI: the retrieval and the prompt behind "ask a question, get an answer grounded in the text".
//!
//! It is NOT a model. It is the two halves a model cannot do for you and that every app otherwise
//! rebuilds badly: turning a natural-language question into the handful of passages that bear on it
//! (each with the reference it must be cited by), and the instructions that keep a model from doing
//! the three things that make a Quran assistant harmful, inventing verse numbers, quoting
//! scripture it has half-remembered, and issuing rulings.
//!
//! Four lanes, interleaved round-robin so each gets a voice inside the passage budget rather than
//! the first one filling it: what the question NAMES (marked as the subject), IDF-weighted
//! keywords, the curated themes, and: only when a [`crate::semantic::Semantic`] index is supplied
//!, meaning.
//!
//! See `../../docs/14-ask-ai.md`.

/// What a passage is, for a consumer deciding what to link it to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PassageKind {
    Ayah,
    Surah,
    Topic,
}

/// One passage the assistant may draw on for a turn.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Passage {
    pub kind: PassageKind,
    /// Cite it exactly like this: `"2:255"`, `"Surah Al-Kahf"`.
    pub reference: String,
    pub text: String,
    /// How much of `text` to show the model.
    pub max_characters: usize,
    /// The verse or surah the question itself named.
    pub is_subject: bool,
    pub surah: Option<u32>,
    pub ayah: Option<u32>,
}

/// Words too common to name a topic on their own; the keyword lane never searches for them alone.
pub const QUESTION_WORDS: &[&str] = &[
    "what", "why", "how", "when", "where", "who", "whom", "which", "does", "do", "did", "is", "are",
    "was", "were", "can", "could", "should", "would", "will", "shall", "have", "has", "had",
    "there", "their", "these", "those", "this", "that", "with", "from", "about", "into", "tell",
    "explain", "please", "mean", "means", "meaning", "say", "says", "said", "some", "many", "much",
    "islam", "islamic", "muslim", "muslims", "quran", "hadith", "hadiths", "allah", "prophet",
    "verse", "verses", "surah", "ayah", "ayat",
];

/// How many passages a turn carries, and how much of each. See [`chat_prompt`].
pub const PASSAGE_LIMIT: usize = 8;
pub const PASSAGE_CHARACTER_LIMIT: usize = 500;
/// A subject passage gets more room: when the question names the verse, this text IS the answer.
pub const SUBJECT_CHARACTER_LIMIT: usize = 1400;

/// The system instructions. Rules 2, 3 and 5 are the ones that matter: a model left to itself will
/// cite verse numbers it half-remembers, "quote" scripture it has paraphrased, and answer
/// "is X halal" with a verdict. Everything else is tone.
pub const CHAT_INSTRUCTIONS: &str = "You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words (\"the Quran teaches\", \"it is reported that\") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For \"is X halal/haram/allowed\" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble (\"Sure!\", \"Great question\"), no labels such as \"Q:\" or \"A:\", and never repeat the question back. Do not add a \"References\" list at the end.";

/// One completed turn of the conversation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Turn {
    pub question: String,
    pub answer: String,
}

/// The instructions and the user-side prompt for one turn: the passages, the recent conversation,
/// the question.
///
/// Eight passages of 500 characters is roughly a thousand tokens, sized for a ~4k on-device window
/// with room for the instructions, the conversation, and a full answer. Raise both for a larger
/// model; the shape does not change.
pub fn chat_prompt(question: &str, passages: &[Passage], transcript: &[Turn]) -> (String, String) {
    let rendered: Vec<String> = passages
        .iter()
        .take(PASSAGE_LIMIT)
        .map(|p| {
            format!(
                "{}[{}] {}",
                if p.is_subject { "SUBJECT OF THE QUESTION " } else { "" },
                p.reference,
                clip(&p.text, p.max_characters)
            )
        })
        .collect();
    let recent: Vec<String> = transcript
        .iter()
        .rev()
        .take(3)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .map(|t| {
            format!(
                "Earlier question: {}\nEarlier answer: {}",
                clip(&t.question, 300),
                clip(&t.answer, 500)
            )
        })
        .collect();

    let mut prompt = String::new();
    if !rendered.is_empty() {
        prompt.push_str("PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n");
        prompt.push_str(&rendered.join("\n"));
        prompt.push_str("\n\n");
    }
    if !recent.is_empty() {
        prompt.push_str("CONVERSATION SO FAR:\n");
        prompt.push_str(&recent.join("\n"));
        prompt.push_str("\n\n");
    }
    prompt.push_str("QUESTION: ");
    prompt.push_str(question);

    (CHAT_INSTRUCTIONS.to_string(), prompt)
}

/// Truncate on a character boundary, the way every other port's `prefix`/`slice` does.
fn clip(text: &str, max: usize) -> String {
    text.chars().take(max).collect()
}

/// Round-robin the lanes so each gets a voice inside the budget.
pub(crate) fn interleave(lanes: Vec<Vec<Passage>>) -> Vec<Passage> {
    let depth = lanes.iter().map(Vec::len).max().unwrap_or(0);
    let mut out = Vec::new();
    for i in 0..depth {
        for lane in &lanes {
            if let Some(passage) = lane.get(i) {
                out.push(passage.clone());
            }
        }
    }
    out
}

/// Strip the light markdown the surah notes carry, so a passage reads as prose.
pub(crate) fn plain_prose(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.replace('\r', "").lines() {
        let trimmed = line.trim_start();
        let without_heading = trimmed.trim_start_matches('#').trim_start();
        let cleaned: String = without_heading
            .chars()
            .filter(|c| *c != '*' && *c != '_' && *c != '`')
            .collect();
        // Collapse runs of blank lines: the notes separate paragraphs with two, and a passage that
        // the model reads is better as one paragraph per line.
        if cleaned.trim().is_empty() {
            if out.ends_with('\n') || out.is_empty() {
                continue;
            }
        }
        out.push_str(cleaned.trim_end());
        out.push('\n');
    }
    out.trim().to_string()
}

use crate::{Engine, SearchOpts, Topic};
use std::collections::{HashMap, HashSet};

/// Household names for specific verses that no pattern catches.
const NAMED_AYAHS: &[(&[&str], u32, u32)] = &[(
    &[
        "ayat al-kursi",
        "ayatul kursi",
        "ayat ul kursi",
        "ayat al kursi",
        "ayatul-kursi",
        "throne verse",
        "verse of the throne",
    ],
    2,
    255,
)];

const SURAH_WORDS: &[&str] = &["surah", "surat", "soorah", "sura", "chapter"];
const AYAH_WORDS: &[&str] = &["ayah", "ayat", "aya", "verse"];

/// The prose in a surah's notes that says what it is ABOUT, rather than when it was revealed.
const THEME_HEADINGS: &[&str] = &[
    "theme",
    "subject",
    "subject matter",
    "central theme",
    "summary",
    "contents",
    "topics",
];

impl Engine {
    /// The passages for a question, best first.
    ///
    /// `previous_question` and `carried` turn a bare follow-up ("why?") into a search over both
    /// questions, with the last answer's passages kept in the pool.
    pub fn ask_ai_retrieve(
        &self,
        question: &str,
        previous_question: Option<&str>,
        carried: &[Passage],
        limit: usize,
    ) -> Vec<Passage> {
        let trimmed = question.trim();
        if trimmed.chars().count() < 3 {
            return Vec::new();
        }

        let mut seen: HashSet<String> = HashSet::new();
        let mut claim = |passages: Vec<Passage>| -> Vec<Passage> {
            passages
                .into_iter()
                .filter(|p| seen.insert(p.reference.clone()))
                .collect()
        };

        let mut named = claim(self.reference_passages(trimmed));

        let bare = self.is_bare_follow_up(trimmed);
        let previous = previous_question.map(str::trim).unwrap_or("");
        let combined;
        let search_text = if bare && !previous.is_empty() {
            combined = format!("{previous} {trimmed}");
            combined.as_str()
        } else {
            trimmed
        };
        if bare {
            named.extend(claim(carried.iter().take(3).cloned().collect()));
        }

        let keyword = claim(self.keyword_passages(search_text, 4));
        let thematic = claim(self.theme_passages(search_text, 2));

        let mut out = named;
        out.extend(interleave(vec![keyword, thematic]));
        out.truncate(limit);
        out
    }

    /// Lane 0: the verses and surahs the question names, as subject passages.
    pub fn reference_passages(&self, question: &str) -> Vec<Passage> {
        let lowered = question.to_lowercase();
        let mut ayahs: Vec<(u32, u32)> = Vec::new();
        let mut surahs: Vec<u32> = Vec::new();

        for (surah, ayah) in scan_references(question) {
            if self.ayah(surah, ayah).is_some() {
                ayahs.push((surah, ayah));
            }
        }
        for (names, surah, ayah) in NAMED_AYAHS {
            if names.iter().any(|name| lowered.contains(name)) {
                ayahs.push((*surah, *ayah));
            }
        }

        // "surah al kahf" resolves on the pair, "surah yusuf" on the single word after the keyword.
        let words: Vec<&str> = lowered
            .split(|c: char| !c.is_alphanumeric() && c != '\'' && c != '-')
            .filter(|w| !w.is_empty())
            .collect();
        let mut loose_ayahs: Vec<u32> = Vec::new();
        for (index, word) in words.iter().enumerate() {
            if SURAH_WORDS.contains(word) {
                let pair = match (words.get(index + 1), words.get(index + 2)) {
                    (Some(a), Some(b)) => Some(format!("{a} {b}")),
                    _ => None,
                };
                let single = words.get(index + 1).map(|w| w.to_string());
                for candidate in [pair, single].into_iter().flatten() {
                    if let Some(id) = self.resolve_surah(&candidate) {
                        surahs.push(id);
                        break;
                    }
                }
            } else if AYAH_WORDS.contains(word) {
                if let Some(number) = words.get(index + 1).and_then(|w| w.parse::<u32>().ok()) {
                    loose_ayahs.push(number);
                }
            }
        }
        // A bare ayah number belongs to the surah just named.
        if ayahs.is_empty() {
            if let Some(surah) = surahs.first().copied() {
                for ayah in loose_ayahs {
                    if self.ayah(surah, ayah).is_some() {
                        ayahs.push((surah, ayah));
                    }
                }
            }
        }

        let mut out = Vec::new();
        for (surah, ayah) in &ayahs {
            if let Some(passage) =
                self.ayah_passage(*surah, *ayah, true, SUBJECT_CHARACTER_LIMIT)
            {
                out.push(passage);
            }
        }
        // A surah named on its own (with no verse) is answered by its background prose.
        if ayahs.is_empty() {
            for surah in surahs {
                if let Some(passage) = self.surah_passage(surah) {
                    out.push(passage);
                }
            }
        }
        out
    }

    /// `search_surahs` is a substring match, so "al kahf" also reaches al-Fatihah; an exact name
    /// match wins when there is one, which is the difference between answering about the cave and
    /// answering about the opening.
    fn resolve_surah(&self, candidate: &str) -> Option<u32> {
        let hits = self.search_surahs(candidate);
        if hits.is_empty() {
            return None;
        }
        let wanted = fold_ascii(candidate);
        for id in &hits {
            if let Some(surah) = self.surah(*id) {
                if fold_ascii(&surah.name_transliteration) == wanted
                    || fold_ascii(&surah.name_english) == wanted
                {
                    return Some(*id);
                }
            }
        }
        if wanted.len() >= 3 {
            for id in &hits {
                if let Some(surah) = self.surah(*id) {
                    if fold_ascii(&surah.name_transliteration).ends_with(&wanted) {
                        return Some(*id);
                    }
                }
            }
        }
        hits.first().copied()
    }

    /// Lane 1: ayahs whose translation carries the question's content words, ranked by how
    /// INFORMATIVE those words are rather than by how often they occur.
    pub fn keyword_passages(&self, question: &str, limit: usize) -> Vec<Passage> {
        let terms = self.content_words(question);
        if terms.is_empty() {
            return Vec::new();
        }
        let weights = self.term_weights(&terms);

        let mut scores: HashMap<(u32, u32), f64> = HashMap::new();
        for (term, weight) in terms.iter().zip(weights.iter()) {
            if *weight <= 0.0 {
                continue;
            }
            let opts = SearchOpts { offset: None, limit: Some(400), ignore_silent_letters: false };
            for hit in self.search_verses(term, &opts) {
                *scores.entry((hit.surah, hit.ayah)).or_insert(0.0) += weight;
            }
        }
        let mut ranked: Vec<((u32, u32), f64)> = scores.into_iter().collect();
        ranked.sort_by(|a, b| {
            b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.0.cmp(&b.0))
        });

        let mut out = Vec::new();
        for ((surah, ayah), _) in ranked {
            if let Some(passage) = self.ayah_passage(surah, ayah, false, PASSAGE_CHARACTER_LIMIT) {
                out.push(passage);
            }
            if out.len() >= limit {
                break;
            }
        }
        out
    }

    /// Lane 2: ayahs from the curated topic the question matches, the lane that reaches verses
    /// sharing no wording with the question at all.
    pub fn theme_passages(&self, question: &str, limit: usize) -> Vec<Passage> {
        let words = self.content_words(question);
        if words.is_empty() {
            return Vec::new();
        }
        let mut best: Option<&Topic> = None;
        let mut best_score = 0usize;
        for topic in self.topics() {
            let haystack =
                format!("{} {} {}", topic.name, topic.description, topic.category).to_lowercase();
            let score: usize = words
                .iter()
                .filter(|w| haystack.contains(&w.to_lowercase()))
                .map(|w| w.chars().count())
                .sum();
            if score > best_score {
                best_score = score;
                best = Some(topic);
            }
        }
        let Some(topic) = best else {
            return Vec::new();
        };

        let mut out = Vec::new();
        for reference in &topic.ayahs {
            let Some((surah, ayah)) = parse_reference(reference) else {
                continue;
            };
            if let Some(passage) = self.ayah_passage(surah, ayah, false, PASSAGE_CHARACTER_LIMIT) {
                out.push(passage);
            }
            if out.len() >= limit {
                break;
            }
        }
        out
    }

    /// Lane 3: ayahs closest in MEANING to the question, using a semantic index you built and own.
    /// The other lanes need no model, which is why this one takes the index as an argument instead
    /// of the engine holding it.
    pub fn semantic_passages(
        &self,
        semantic: &mut crate::Semantic,
        question: &str,
        limit: usize,
        min_score: f32,
    ) -> Vec<Passage> {
        // The score is a MEAN over query words, so "what does the Quran say about" dilutes the topic.
        let words = self.content_words(question);
        let query = if words.is_empty() { question.to_string() } else { words.join(" ") };

        let mut out = Vec::new();
        for hit in semantic.search(&query, limit * 2, min_score) {
            let Some((surah, ayah)) = parse_reference(&hit.id) else {
                continue;
            };
            if let Some(passage) = self.ayah_passage(surah, ayah, false, PASSAGE_CHARACTER_LIMIT) {
                out.push(passage);
            }
            if out.len() >= limit {
                break;
            }
        }
        out
    }

    /// The `(id, translation)` pairs to hand [`crate::Semantic::index`] for lane 3.
    pub fn semantic_corpus(&self) -> Vec<(String, String)> {
        self.surahs()
            .iter()
            .flat_map(|surah| {
                surah.ayahs.iter().map(move |ayah| {
                    (format!("{}:{}", surah.id, ayah.id), ayah.text_english_saheeh.clone())
                })
            })
            .collect()
    }

    pub fn ayah_passage(
        &self,
        surah: u32,
        ayah: u32,
        is_subject: bool,
        max_characters: usize,
    ) -> Option<Passage> {
        let entry = self.ayah(surah, ayah)?;
        if entry.text_english_saheeh.is_empty() {
            return None;
        }
        Some(Passage {
            kind: PassageKind::Ayah,
            reference: format!("{surah}:{ayah}"),
            text: entry.text_english_saheeh.clone(),
            max_characters,
            is_subject,
            surah: Some(surah),
            ayah: Some(ayah),
        })
    }

    /// A surah's background prose. The bundled notes open with the period of revelation, which
    /// answers "what is this surah about" with history, so the theme section, when a source has
    /// one, is what the question actually meant.
    pub fn surah_passage(&self, surah_id: u32) -> Option<Passage> {
        let surah = self.surah(surah_id)?;
        let sources = self.surah_info(surah_id);
        if sources.is_empty() {
            return None;
        }

        let mut text = String::new();
        for source in sources {
            if let Some(offset) = theme_heading_offset(&source.contents) {
                let from_theme = plain_prose(&source.contents[offset..]);
                if from_theme.chars().count() >= 200 {
                    text = from_theme;
                    break;
                }
            }
        }
        if text.is_empty() {
            text = plain_prose(&sources[0].contents);
        }
        if text.is_empty() {
            return None;
        }

        Some(Passage {
            kind: PassageKind::Surah,
            reference: format!("Surah {}", surah.name_transliteration),
            text,
            max_characters: SUBJECT_CHARACTER_LIMIT,
            is_subject: true,
            surah: Some(surah_id),
            ayah: None,
        })
    }

    /// The words in a question that actually name its topic.
    pub fn content_words(&self, question: &str) -> Vec<String> {
        question
            .split(|c: char| !c.is_alphanumeric())
            .filter(|w| w.chars().count() >= 3 && !QUESTION_WORDS.contains(&w.to_lowercase().as_str()))
            .map(str::to_string)
            .collect()
    }

    /// A question with fewer than two content words ("why?", "and zakat?") only makes sense with
    /// the previous question beside it.
    pub fn is_bare_follow_up(&self, question: &str) -> bool {
        question
            .split(|c: char| !c.is_alphanumeric())
            .filter(|w| w.chars().count() >= 4 && !QUESTION_WORDS.contains(&w.to_lowercase().as_str()))
            .count()
            < 2
    }

    /// Inverse document frequency per term: `log(N / (1 + df))`, floored at 0. A word in half the
    /// Quran weighs almost nothing; a word in ten ayahs weighs a lot.
    pub fn term_weights(&self, terms: &[String]) -> Vec<f64> {
        let mut frequency: HashMap<String, u32> = HashMap::new();
        let mut documents = 0u32;
        for surah in self.surahs() {
            for ayah in &surah.ayahs {
                documents += 1;
                let lowered = ayah.text_english_saheeh.to_lowercase();
                let words: HashSet<&str> = lowered
                    .split(|c: char| !c.is_alphanumeric())
                    .filter(|w| w.chars().count() >= 3)
                    .collect();
                for word in words {
                    *frequency.entry(word.to_string()).or_insert(0) += 1;
                }
            }
        }
        terms
            .iter()
            .map(|term| {
                let df = frequency.get(&term.to_lowercase()).copied().unwrap_or(0);
                (documents as f64 / (1 + df) as f64).ln().max(0.0)
            })
            .collect()
    }
}

/// Every `N:M` in the text, ignoring anything glued to more digits or another colon.
fn scan_references(text: &str) -> Vec<(u32, u32)> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if !chars[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        // A digit or a colon immediately before makes this the tail of something else.
        if i > 0 && (chars[i - 1].is_ascii_digit() || chars[i - 1] == ':') {
            while i < chars.len() && chars[i].is_ascii_digit() {
                i += 1;
            }
            continue;
        }
        let start = i;
        while i < chars.len() && chars[i].is_ascii_digit() {
            i += 1;
        }
        let surah: String = chars[start..i].iter().collect();
        let mut j = i;
        while j < chars.len() && chars[j] == ' ' {
            j += 1;
        }
        if j >= chars.len() || chars[j] != ':' {
            continue;
        }
        j += 1;
        while j < chars.len() && chars[j] == ' ' {
            j += 1;
        }
        let ayah_start = j;
        while j < chars.len() && chars[j].is_ascii_digit() {
            j += 1;
        }
        if ayah_start == j {
            continue;
        }
        // A trailing digit-or-colon means this was part of a longer token.
        if j < chars.len() && chars[j] == ':' {
            continue;
        }
        let ayah: String = chars[ayah_start..j].iter().collect();
        if surah.len() <= 3 && ayah.len() <= 3 {
            if let (Ok(s), Ok(a)) = (surah.parse(), ayah.parse()) {
                out.push((s, a));
            }
        }
        i = j;
    }
    out
}

fn parse_reference(text: &str) -> Option<(u32, u32)> {
    let (surah, ayah) = text.split_once(':')?;
    Some((surah.parse().ok()?, ayah.parse().ok()?))
}

fn fold_ascii(text: &str) -> String {
    text.to_lowercase().chars().filter(|c| c.is_ascii_alphabetic()).collect()
}

/// The byte offset of the first line that opens with a theme-ish heading, if any.
fn theme_heading_offset(text: &str) -> Option<usize> {
    let mut offset = 0;
    for line in text.split_inclusive('\n') {
        let stripped = line.trim_start().trim_start_matches('#').trim_start().to_lowercase();
        if THEME_HEADINGS.iter().any(|heading| {
            stripped.starts_with(heading)
                && stripped[heading.len()..]
                    .chars()
                    .next()
                    .map(|c| !c.is_alphanumeric())
                    .unwrap_or(true)
        }) {
            return Some(offset);
        }
        offset += line.len();
    }
    None
}
