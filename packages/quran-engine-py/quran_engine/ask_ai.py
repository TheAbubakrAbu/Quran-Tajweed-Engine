"""Ask AI: the retrieval and the prompt behind a grounded question-answering feature.

Mirrors src/askAI.js; see docs/11-ask-ai.md for the reasoning. In short, this is NOT a model - it
is the two halves a model cannot do for you: turning a question into the passages that bear on it
(with the references they must be cited by), and the instructions that stop a model inventing
verse numbers, "quoting" scripture it half-remembers, and issuing rulings.

Four lanes, interleaved so each gets a voice inside the passage budget: what the question NAMES
(marked as the subject), IDF-weighted keywords, the curated themes, and - only when you supply a
`Semantic` index - meaning.
"""
from __future__ import annotations
import math
import re
from typing import Callable, Optional, Sequence

from .semantic import Semantic

#: Words too common to name a topic on their own.
QUESTION_WORDS = {
    "what", "why", "how", "when", "where", "who", "whom", "which", "does", "do", "did", "is", "are",
    "was", "were", "can", "could", "should", "would", "will", "shall", "have", "has", "had", "there",
    "their", "these", "those", "this", "that", "with", "from", "about", "into", "tell", "explain",
    "please", "mean", "means", "meaning", "say", "says", "said", "some", "many", "much", "islam",
    "islamic", "muslim", "muslims", "quran", "hadith", "hadiths", "allah", "prophet", "verse", "verses",
    "surah", "ayah", "ayat",
}

PASSAGE_LIMIT = 8
PASSAGE_CHARACTER_LIMIT = 500
#: A subject passage gets more room: when the question names the verse, this text IS the answer.
SUBJECT_CHARACTER_LIMIT = 1400

_AYAH_REFERENCE = re.compile(r"(?<![\d:])(\d{1,3})\s*:\s*(\d{1,3})(?![\d:])")
# A surah name is letters plus the punctuation that binds one: "al-kahf", "an-nas", "ta'ha".
# Without the hyphen in the class, "surah al-kahf" captures just "al" and resolves to al-Fatihah.
_NAME_WORD = r"(?:[^\W\d_]|['\u2019-])+"
_SURAH_MENTION = re.compile(
    r"\b(?:surah|surat|soorah|sura|chapter)\s+(" + _NAME_WORD + r")(?:\s+(" + _NAME_WORD + r"))?",
    re.IGNORECASE | re.UNICODE)
_AYAH_MENTION = re.compile(r"\b(?:ayah|ayat|aya|verse)\s+(\d{1,3})\b", re.IGNORECASE)
_WORD_SPLIT = re.compile(r"[^\w]+", re.UNICODE)
_THEME_HEADING = re.compile(
    r"^\s*#*\s*(?:theme|subject|subject matter|central theme|summary|contents|topics)\b[^\n]*$",
    re.IGNORECASE | re.MULTILINE)

_NAMED_AYAHS = [
    (["ayat al-kursi", "ayatul kursi", "ayat ul kursi", "ayat al kursi", "ayatul-kursi",
      "throne verse", "verse of the throne"], 2, 255),
]


class Passage(dict):
    """kind, reference, text, max_characters, is_subject, surah?, ayah?."""


class AskAI:
    def __init__(self, quran, search, themes=None, semantic: Optional[Semantic] = None,
                 translation: str = "text_english_saheeh"):
        self.quran = quran
        self.search = search
        self.themes = themes
        self.semantic = semantic
        self.translation = translation
        self._document_frequency: Optional[dict[str, int]] = None
        self._document_count = 0

    def build_semantic_index(self, embed: Callable[[str], Optional[Sequence[float]]]) -> Semantic:
        """Index the ayah translations with your own embedder, and use it as lane 3."""
        documents = [
            {"id": f"{surah.id}:{ayah.id}", "text": getattr(ayah, self.translation, ""),
             "meta": (surah.id, ayah.id)}
            for surah in self.quran.all() for ayah in surah.ayahs
        ]
        self.semantic = Semantic(embed).index(documents)
        return self.semantic

    def retrieve(self, question: str, previous_question: Optional[str] = None,
                 carried: Optional[list[Passage]] = None,
                 limit: int = PASSAGE_LIMIT) -> list[Passage]:
        trimmed = question.strip()
        if len(trimmed) < 3:
            return []
        carried = carried or []
        seen: set[str] = set()

        def claim(passages: list[Passage]) -> list[Passage]:
            kept = []
            for passage in passages:
                if passage["reference"] not in seen:
                    seen.add(passage["reference"])
                    kept.append(passage)
            return kept

        named = claim(self.reference_passages(trimmed))

        bare = self.is_bare_follow_up(trimmed)
        search_text = f"{previous_question.strip()} {trimmed}" if bare and previous_question and previous_question.strip() else trimmed
        if bare:
            named += claim(carried[:3])

        keyword = claim(self.keyword_passages(search_text))
        thematic = claim(self.theme_passages(search_text))
        meaning = claim(self.semantic_passages(search_text))

        return (named + _interleave([keyword, meaning, thematic]))[:limit]

    # ---- Lane 0: references ------------------------------------------------------

    def reference_passages(self, question: str) -> list[Passage]:
        lowered = question.lower()
        ayahs: list[tuple[int, int]] = []
        surahs: list[int] = []

        for match in _AYAH_REFERENCE.finditer(question):
            surah, ayah = int(match.group(1)), int(match.group(2))
            if self.quran.ayah(surah, ayah):
                ayahs.append((surah, ayah))
        for names, surah, ayah in _NAMED_AYAHS:
            if any(name in lowered for name in names):
                ayahs.append((surah, ayah))
        for match in _SURAH_MENTION.finditer(question):
            candidates = [c for c in (
                f"{match.group(1)} {match.group(2)}" if match.group(1) and match.group(2) else None,
                match.group(1)) if c]
            for candidate in candidates:
                hit = self._resolve_surah(candidate)
                if hit:
                    surahs.append(hit)
                    break
        loose = [int(m.group(1)) for m in _AYAH_MENTION.finditer(question)]
        if loose and surahs and not ayahs:
            ayahs += [(surahs[0], a) for a in loose if self.quran.ayah(surahs[0], a)]

        out: list[Passage] = []
        for surah, ayah in ayahs:
            passage = self.ayah_passage(surah, ayah, is_subject=True,
                                        max_characters=SUBJECT_CHARACTER_LIMIT)
            if passage:
                out.append(passage)
        if not ayahs:
            for surah in surahs:
                passage = self.surah_passage(surah)
                if passage:
                    out.append(passage)
        return out

    def _resolve_surah(self, candidate: str) -> Optional[int]:
        """`search_surahs` is a substring match, so an exact name match wins when there is one -
        the difference between answering about the cave and answering about the opening."""
        hits = self.search.search_surahs(candidate)
        if not hits:
            return None
        fold = lambda text: re.sub(r"[^a-z]", "", text.lower())  # noqa: E731
        wanted = fold(candidate)
        for surah in hits:
            if fold(surah.name_transliteration) == wanted or fold(surah.name_english) == wanted:
                return surah.id
        if len(wanted) >= 3:
            for surah in hits:
                if fold(surah.name_transliteration).endswith(wanted):
                    return surah.id
        return hits[0].id

    # ---- Lane 1: keywords, IDF-weighted -------------------------------------------

    def keyword_passages(self, question: str, limit: int = 4) -> list[Passage]:
        terms = self.content_words(question)
        if not terms:
            return []
        weights = self.term_weights(terms)

        scores: dict[str, float] = {}
        for term, weight in zip(terms, weights):
            if weight <= 0:
                continue
            for hit in self.search.search_verses(term, limit=400):
                key = f"{hit['surah']}:{hit['ayah']}"
                scores[key] = scores.get(key, 0.0) + weight

        out: list[Passage] = []
        for key, _ in sorted(scores.items(), key=lambda kv: (-kv[1], kv[0])):
            surah, ayah = (int(x) for x in key.split(":"))
            passage = self.ayah_passage(surah, ayah)
            if passage:
                out.append(passage)
            if len(out) >= limit:
                break
        return out

    # ---- Lane 2: themes -------------------------------------------------------------

    def theme_passages(self, question: str, limit: int = 2) -> list[Passage]:
        if self.themes is None:
            return []
        words = self.content_words(question)
        if not words:
            return []
        best, best_score = None, 0
        for topic in self.themes.all():
            haystack = f"{topic['name']} {topic['description']} {topic['category']}".lower()
            score = sum(len(w) for w in words if w.lower() in haystack)
            if score > best_score:
                best, best_score = topic, score
        if best is None:
            return []
        out: list[Passage] = []
        for ref in best["ayahs"]:
            surah, ayah = (int(x) for x in ref.split(":"))
            passage = self.ayah_passage(surah, ayah)
            if passage:
                out.append(passage)
            if len(out) >= limit:
                break
        return out

    # ---- Lane 3: meaning ------------------------------------------------------------

    def semantic_passages(self, question: str, limit: int = 3, min_score: float = 0.42) -> list[Passage]:
        if self.semantic is None:
            return []
        words = self.content_words(question)
        query = " ".join(words) if words else question
        out: list[Passage] = []
        for hit in self.semantic.search(query, limit=limit * 2, min_score=min_score):
            surah, ayah = (int(x) for x in hit["id"].split(":"))
            passage = self.ayah_passage(surah, ayah)
            if passage:
                out.append(passage)
            if len(out) >= limit:
                break
        return out

    # ---- Passage construction --------------------------------------------------------

    def ayah_passage(self, surah_id: int, ayah_id: int, is_subject: bool = False,
                     max_characters: int = PASSAGE_CHARACTER_LIMIT) -> Optional[Passage]:
        ayah = self.quran.ayah(surah_id, ayah_id)
        if ayah is None:
            return None
        text = getattr(ayah, self.translation, "") or ayah.text_english_saheeh or ayah.text_english_mustafa
        if not text:
            return None
        return Passage({"kind": "ayah", "reference": f"{surah_id}:{ayah_id}", "text": text,
                        "max_characters": max_characters, "is_subject": is_subject,
                        "surah": surah_id, "ayah": ayah_id})

    def surah_passage(self, surah_id: int) -> Optional[Passage]:
        """A surah's background. The notes open with the period of revelation, which answers
        "what is this surah about" with history - so the theme section, when there is one, wins."""
        surah = self.quran.surah(surah_id)
        sources = self.quran.info(surah_id) or []
        if surah is None or not sources:
            return None
        text = ""
        for source in sources:
            match = _THEME_HEADING.search(source["contents"])
            if not match:
                continue
            from_theme = _plain_prose(source["contents"][match.start():])
            if len(from_theme) >= 200:
                text = from_theme
                break
        if not text:
            text = _plain_prose(sources[0]["contents"])
        if not text:
            return None
        return Passage({"kind": "surah", "reference": f"Surah {surah.name_transliteration}",
                        "text": text, "max_characters": SUBJECT_CHARACTER_LIMIT,
                        "is_subject": True, "surah": surah_id})

    # ---- Question analysis -------------------------------------------------------------

    def content_words(self, question: str) -> list[str]:
        return [w for w in _WORD_SPLIT.split(question)
                if len(w) >= 3 and w.lower() not in QUESTION_WORDS]

    def is_bare_follow_up(self, question: str) -> bool:
        """Fewer than two content words ("why?", "and zakat?") - only meaningful with the last one."""
        return len([w for w in _WORD_SPLIT.split(question)
                    if len(w) >= 4 and w.lower() not in QUESTION_WORDS]) < 2

    def term_weights(self, terms: list[str]) -> list[float]:
        """log(N / (1 + df)), floored at 0. A word in half the Quran weighs almost nothing."""
        if self._document_frequency is None:
            frequency: dict[str, int] = {}
            documents = 0
            for surah in self.quran.all():
                for ayah in surah.ayahs:
                    documents += 1
                    text = (getattr(ayah, self.translation, "") or "").lower()
                    for word in {w for w in _WORD_SPLIT.split(text) if len(w) >= 3}:
                        frequency[word] = frequency.get(word, 0) + 1
            self._document_frequency = frequency
            self._document_count = documents
        return [max(0.0, math.log(self._document_count / (1 + self._document_frequency.get(t.lower(), 0))))
                for t in terms]


CHAT_INSTRUCTIONS = """You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end."""


def chat_prompt(question: str, passages: list[Passage],
                transcript: Optional[list[dict]] = None,
                passage_limit: int = PASSAGE_LIMIT) -> dict:
    """The instructions and the user-side prompt for one turn.

    Eight passages of 500 characters is roughly a thousand tokens - sized for a ~4k on-device
    window with room for the instructions, the conversation, and a full answer.
    """
    transcript = transcript or []
    rendered = "\n".join(
        f"{'SUBJECT OF THE QUESTION ' if p['is_subject'] else ''}[{p['reference']}] {p['text'][:p['max_characters']]}"
        for p in passages[:passage_limit])
    recent = "\n".join(
        f"Earlier question: {turn['question'][:300]}\nEarlier answer: {turn['answer'][:500]}"
        for turn in transcript[-3:])

    prompt = ""
    if rendered:
        prompt += ("PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE "
                   "QUESTION is the verse or surah the question is about: base the answer on it; "
                   "cite the passages you use, ignore the rest):\n" + rendered + "\n\n")
    if recent:
        prompt += f"CONVERSATION SO FAR:\n{recent}\n\n"
    prompt += f"QUESTION: {question}"
    return {"instructions": CHAT_INSTRUCTIONS, "prompt": prompt}


def _interleave(lanes: list[list[Passage]]) -> list[Passage]:
    """Round-robin, so each lane gets a voice inside the budget instead of the first filling it."""
    out: list[Passage] = []
    for i in range(max((len(lane) for lane in lanes), default=0)):
        for lane in lanes:
            if i < len(lane):
                out.append(lane[i])
    return out


def _plain_prose(text: str) -> str:
    text = re.sub(r"^\s*#+\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"[*_`]+", "", text).replace("\r", "")
    return re.sub(r"\n{2,}", "\n", text).strip()
