# 14 · Ask AI: retrieval, meaning search, and the prompt

Ask a question in plain language, get an answer grounded in the text, with the passages it drew on, cited.

> **This ships no model.** It ships the two halves a model cannot do for you: turning a question into the passages that actually bear on it, and the instructions that stop a model doing the three things that make a Quran assistant *harmful*.

## What it is

```js
const passages = engine.askAI.retrieve("what does the Quran say about patience in hardship");
// [{ kind: "ayah", reference: "2:153", text: "O you who have believed, seek help through patience …",
//    maxCharacters: 500, isSubject: false, surah: 2, ayah: 153 }, …]

const { instructions, prompt } = chatPrompt(question, passages);
// hand these to whatever model you use, on-device, hosted, or none
```

The passages are worth showing on their own. Plenty of apps ship exactly this with no model behind it: a question box that finds the relevant verses.

## The four lanes

They answer different **kinds** of question, and one would otherwise drown the others, so they run separately and are interleaved round-robin, not concatenated.

### Lane 0, what the question names

"Explain 2:255", "what is Surah al-Kahf about", "ayat al-kursi", "surah al-kahf verse 10".

These passages are marked **`isSubject: true`** and always win their slot. Without that marking, a model handed eight loosely-related verses will cheerfully explain the wrong one; this was the single biggest quality problem in the feature this is ported from.

Resolution covers: `N:M` references, surah names in words (`surah|surat|soorah|sura|chapter` + one or two words), a bare `ayah|ayat|aya|verse N` bound to the surah just named, and household names for specific verses (the Throne Verse). A named **surah with no verse** is answered by its background prose rather than by its first ayah, and by the *theme* section of that prose where there is one, because the notes open with the period of revelation, which answers "what is this surah about" with history.

Surah-name resolution prefers an **exact** name match over a substring one. `searchSurahs("al kahf")` also reaches al-Fātiḥah; the difference between answering about the cave and answering about the opening is one line of tie-breaking.

### Lane 1, keywords, weighted by IDF

Plain term counting ranks a question by whichever verse says "the" most. Weighting each term by `log(N / (1 + df))` (its inverse document frequency over the translations), fixes it with **no stopword list to maintain** against the corpus. A word in half the Quran weighs almost nothing; a word in ten ayahs weighs a lot, and a verse matching two informative words beats one matching a single word twice.

A small hard-coded set (`QUESTION_WORDS`) drops the words that are grammar rather than topic: "what", "how", "does", and also "quran", "allah", "verse", which are in nearly every question asked of this app and name nothing.

### Lane 2, themes

The curated topic whose name or description the question matches, contributing its first ayahs. This is the lane that reaches verses sharing **no wording** with the question. See [13 · Themes](13-similar-and-themes.md#themes).

### Lane 3, meaning (optional)

Only runs when you supply a semantic index. The other three need no model and no vectors, which is why this one is optional: the feature works everywhere, and gets better where an embedder exists.

## Meaning search

`Semantic` is a small, embedder-agnostic module you can also use on its own.

### Why word vectors and MaxSim, not a sentence embedding

Measured, not assumed. Scoring an ayah by the cosine between a **sentence** embedding of the query and one of the ayah ranks this corpus close to randomly, translated scripture is dense, and one vector for a whole verse washes out the single idea the query is about. (In the app this is ported from, the lashing verse outscored the patience verse for "patience in hardship".)

Scoring **word by word** fixes it: embed every word, and score a text as the **mean over the query's words of the best-matching word in the text**. On real verses that separates related (0.42–0.70) from unrelated (0.27–0.41) cleanly, and it degrades gracefully: a query word the model has never seen contributes nothing instead of poisoning the vector.

### The embedder is yours

This engine ships no word vectors: they are tens of megabytes, and every platform already has something worth using, Apple's `NLEmbedding.wordEmbedding(for:.english)`, ML Kit on Android, a GloVe file or `wink-embeddings` in Node. Hand `Semantic` a function from a lowercased word to its vector (or null):

```js
const semantic = new Semantic({ embed: (word) => myModel.vector(word) });
semantic.index([{ id: "2:153", text: "O you who have believed, seek help through patience and prayer…" }]);
semantic.search("patience in hardship", { limit: 5, minScore: 0.42 });

// or wire it straight into retrieval as lane 3:
engine.askAI.buildSemanticIndex((word) => myModel.vector(word));
```

Vectors are cached per word, so a repeated word costs one lookup for the whole corpus. Building over the 6,236 translations is a few seconds and ~10–25 MB, which is why any serious consumer **persists** the index rather than rebuilding it per launch. `minScore` is a floor on "actually related": 0.42 is a sensible starting point on English translations, but calibrate it against *your* embedder.

## The prompt

`CHAT_INSTRUCTIONS` is the system prompt. Rules 2, 3 and 5 are the ones that matter; the rest is tone.

| Rule | Why |
|---|---|
| **2. Cite only references that appear in PASSAGES** | A model asked about the Quran will produce plausible verse numbers from memory, and they are frequently wrong. Citing only what was retrieved makes every reference in the answer checkable, and the app shows each cited passage beneath the answer, so a wrong one is visible immediately. |
| **3. Never write out the wording of a verse** | A paraphrase presented in quotation marks reads as scripture and is not. Describing in the model's own words, with the real text shown separately, keeps the two apart. |
| **5. Never issue a ruling** | "Is X halal" has a right answer only from a qualified scholar who knows the asker's situation. The instruction is to explain the considerations and the views that exist, and say so. |

`chatPrompt` assembles the turn: passages first (subject ones labelled), then the last three turns of conversation, then the question. Eight passages of 500 characters is roughly a thousand tokens, sized for a ~4k on-device window with room for the instructions, the conversation, and a full answer. Raise both for a larger model; the shape does not change.

## Follow-ups

A question with fewer than two content words ("why?", "and zakat?", "what about that one") retrieves noise on its own. Pass the previous question and the passages the previous answer cited, and the follow-up searches as *both* questions while keeping those passages in the pool:

```js
const first = engine.askAI.retrieve("tell me about 2:153");
const then  = engine.askAI.retrieve("why?", { previousQuestion: "tell me about 2:153", carried: first });
```

The model is still shown the question as typed. Only the retrieval sees the pair.

## API

| Method | Returns |
|---|---|
| `retrieve(question, { previousQuestion, carried, limit })` | the passages, subject first |
| `referencePassages(question)` | lane 0 alone |
| `keywordPassages(question, { limit })` | lane 1 alone |
| `themePassages(question, { limit })` | lane 2 alone |
| `semanticPassages(question, { limit, minScore })` | lane 3 alone, `[]` with no index |
| `buildSemanticIndex(embed)` | index the translations and enable lane 3 |
| `ayahPassage(surah, ayah, opts)` / `surahPassage(surah)` | build one passage directly |
| `contentWords(question)` / `isBareFollowUp(question)` / `termWeights(terms)` | the question analysis, exposed |
| `chatPrompt(question, passages, { transcript })` | `{ instructions, prompt }` |

Retrieval needs nothing beyond the default load. Lane 2 needs `themes` (loaded by default); lane 0's surah backgrounds need `surah-info.json` (also default).
