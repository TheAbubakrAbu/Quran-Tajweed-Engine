// Ask AI: the retrieval and the prompt behind "ask a question, get an answer
// grounded in the text".
//
// ## What this is, and what it is not
//
// It is NOT a model. It is the two halves of a question-answering feature that
// a model cannot do for you and that every app otherwise rebuilds badly:
//
//  1. **Retrieval**: turn a natural-language question into the handful of
//     passages that actually bear on it, each with the reference it must be
//     cited by.
//  2. **The prompt**: the instructions that keep a model from doing the three
//     things that make a Quran assistant harmful: inventing verse numbers,
//     quoting scripture it has half-remembered, and issuing rulings.
//
// ## Why the lanes are separate, and interleaved
//
// The lanes answer different KINDS of question and one would otherwise drown
// the others: what the question NAMES (marked [Passage.isSubject], so a model
// given eight loosely-related verses does not explain the wrong one),
// IDF-weighted keywords, the curated themes, and, only when a [Semantic] index
// is supplied, meaning. They are interleaved round-robin rather than
// concatenated, so each lane gets a voice inside the passage budget instead of
// the first lane filling it.
//
// See `../../docs/14-ask-ai.md`.

import 'dart:math' as math;

import 'corpora.dart';
import 'mushaf.dart';
import 'quran.dart';
import 'search.dart';
import 'semantic.dart';

/// What a passage is, for a consumer deciding what to link it to.

enum PassageKind { ayah, surah, topic }

/// One passage the assistant may draw on for a turn.

class Passage {
  final PassageKind kind;

  /// Cite it exactly like this: `"2:255"`, `"Surah Al-Kahf"`.
  final String reference;
  final String text;

  /// How much of [text] to show the model.
  final int maxCharacters;

  /// The verse or surah the question itself named.
  final bool isSubject;
  final int? surah;
  final int? ayah;

  const Passage({
    required this.kind,
    required this.reference,
    required this.text,
    this.maxCharacters = passageCharacterLimit,
    this.isSubject = false,
    this.surah,
    this.ayah,
  });
}

/// One completed turn of the conversation.

class Turn {
  final String question;
  final String answer;
  const Turn(this.question, this.answer);
}

/// Words too common to name a topic on their own; the keyword lane never
/// searches for them alone.

const Set<String> questionWords = {
  'what', 'why', 'how', 'when', 'where', 'who', 'whom', 'which', 'does', 'do',
  'did', 'is', 'are', 'was', 'were', 'can', 'could', 'should', 'would', 'will',
  'shall', 'have', 'has', 'had', 'there', 'their', 'these', 'those', 'this',
  'that', 'with', 'from', 'about', 'into', 'tell', 'explain', 'please', 'mean',
  'means', 'meaning', 'say', 'says', 'said', 'some', 'many', 'much', 'islam',
  'islamic', 'muslim', 'muslims', 'quran', 'hadith', 'hadiths', 'allah',
  'prophet', 'verse', 'verses', 'surah', 'ayah', 'ayat',
};

/// How many passages a turn carries, and how much of each. See [chatPrompt].

const int passageLimit = 8;
const int passageCharacterLimit = 500;

/// A subject passage gets more room: when the question names the verse, this
/// text IS the answer.

const int subjectCharacterLimit = 1400;

final RegExp _ayahReference = RegExp(r'(?<![\d:])(\d{1,3})\s*:\s*(\d{1,3})(?![\d:])');
final RegExp _surahMention = RegExp(
  r"\b(?:surah|surat|soorah|sura|chapter)\s+([\p{L}'’-]+)(?:\s+([\p{L}'’-]+))?",
  caseSensitive: false,
  unicode: true,
);
final RegExp _ayahMention =
    RegExp(r'\b(?:ayah|ayat|aya|verse)\s+(\d{1,3})\b', caseSensitive: false);
final RegExp _wordSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The prose in a surah's notes that says what it is ABOUT, rather than when it
/// was revealed.

final RegExp _themeHeading = RegExp(
  r'^\s*#*\s*(?:theme|subject|subject matter|central theme|summary|contents|topics)\b[^\n]*$',
  caseSensitive: false,
  multiLine: true,
);

/// A household name for a specific verse that no pattern catches.
class _NamedAyah {
  final List<String> names;
  final int surah;
  final int ayah;
  const _NamedAyah(this.names, this.surah, this.ayah);
}

const List<_NamedAyah> _namedAyahs = [
  _NamedAyah(
    [
      'ayat al-kursi', 'ayatul kursi', 'ayat ul kursi', 'ayat al kursi',
      'ayatul-kursi', 'throne verse', 'verse of the throne',
    ],
    2,
    255,
  ),
];

/// The system instructions. Rules 2, 3 and 5 are the ones that matter: a model
/// left to itself will cite verse numbers it half-remembers, "quote" scripture
/// it has paraphrased, and answer "is X halal" with a verdict. Everything else
/// is tone.

const String chatInstructions =
    '''You are a knowledgeable, warm assistant inside a Quran reading app. People ask you about the Quran, Islamic history and practice, and you answer the way a well-read friend would: directly, completely, and in plain language.

You may be given PASSAGES the app retrieved for the question (ayahs, a surah's background, a topic's verses, each with its reference) and the CONVERSATION so far. Rules, in order:
1. Answer the question fully, from your general knowledge of Islam AND the passages. When the question names a verse or a surah and a passage carries that exact reference, that passage IS the subject: explain it, and do not describe some other verse instead. Other passages are support, not a fence: build on the relevant ones and ignore the rest silently.
2. Cite a passage you use inline in parentheses exactly as its reference is written, for example (2:153). Cite ONLY references that appear in PASSAGES. Never add a reference or a verse number from memory: if you draw on general knowledge, say so in words ("the Quran teaches", "it is reported that") with no number.
3. Never write out the wording of a verse, and never put anything in quotation marks as if it were scripture. Describe and paraphrase in your own words. The app shows every passage you cite right beneath your answer.
4. Be honest about uncertainty and scholarly disagreement: say when something is debated, and when you are not sure.
5. Never issue a religious ruling, verdict, or fatwa. For "is X halal/haram/allowed" questions, explain the considerations and the views that exist, then note that a qualified scholar should be consulted for a personal ruling.
6. Keep the conversation's thread: a follow-up refers to what was discussed before.
7. Write in English even when the question is in another language, keeping key Arabic terms. PLAIN TEXT ONLY: no asterisks, underscores, pound signs, or other markdown; short paragraphs; a numbered list only when it genuinely helps.
8. Begin directly with the answer: no preamble ("Sure!", "Great question"), no labels such as "Q:" or "A:", and never repeat the question back. Do not add a "References" list at the end.''';

class AskAI {
  final Quran quran;
  final Search search;
  final Themes? themes;

  /// An index over the ayah translations; optional, because the other three
  /// lanes need no model.
  Semantic? semantic;

  /// Lazily built document frequencies for the IDF weighting.
  Map<String, int>? _documentFrequency;
  int _documentCount = 0;

  AskAI({
    required this.quran,
    required this.search,
    this.themes,
    this.semantic,
  });

  /// Build a semantic index over the ayah translations with your own embedder,
  /// and use it as the meaning lane.
  Semantic buildSemanticIndex(List<double>? Function(String word) embed) {
    final documents = <SemanticDocument>[
      for (final surah in quran.all())
        for (final ayah in surah.ayahs)
          SemanticDocument('${surah.id}:${ayah.id}', ayah.textEnglishSaheeh),
    ];
    return semantic = Semantic(embed).index(documents);
  }

  /// The passages for a question, best first.
  ///
  /// [previousQuestion] and [carried] turn a bare follow-up ("why?") into a
  /// search over both questions, with the last answer's passages kept in the
  /// pool.
  List<Passage> retrieve(
    String question, {
    String? previousQuestion,
    List<Passage> carried = const [],
    int limit = passageLimit,
  }) {
    final trimmed = question.trim();
    if (trimmed.length < 3) return const [];

    final seen = <String>{};
    List<Passage> claim(List<Passage> passages) =>
        passages.where((p) => seen.add(p.reference)).toList();

    // Lane 0: what the question NAMES.
    final named = claim(referencePassages(trimmed));

    final bare = isBareFollowUp(trimmed);
    final previous = previousQuestion?.trim() ?? '';
    final searchText =
        bare && previous.isNotEmpty ? '$previous $trimmed' : trimmed;
    if (bare) named.addAll(claim(carried.take(3).toList()));

    final keyword = claim(keywordPassages(searchText));
    final thematic = claim(themePassages(searchText));
    final meaning = claim(semanticPassages(searchText));

    return [...named, ..._interleave([keyword, meaning, thematic])]
        .take(limit)
        .toList(growable: false);
  }

  // ---- Lane 0: references -------------------------------------------------

  /// The verses and surahs the question names, as subject passages.
  List<Passage> referencePassages(String question) {
    final lowered = question.toLowerCase();
    final ayahs = <VerseRef>[];
    final surahs = <int>[];

    for (final match in _ayahReference.allMatches(question)) {
      final surah = int.parse(match.group(1)!);
      final ayah = int.parse(match.group(2)!);
      if (quran.ayah(surah, ayah) != null) ayahs.add(VerseRef(surah, ayah));
    }
    for (final named in _namedAyahs) {
      if (named.names.any(lowered.contains)) {
        ayahs.add(VerseRef(named.surah, named.ayah));
      }
    }
    for (final match in _surahMention.allMatches(question)) {
      // Two words then one: "surah al kahf" resolves on the pair, "surah yusuf"
      // on the single.
      final first = match.group(1);
      final second = match.group(2);
      final candidates = <String>[
        if (first != null && second != null) '$first $second',
        if (first != null) first,
      ];
      for (final candidate in candidates) {
        final hit = _resolveSurah(candidate);
        if (hit != null) {
          surahs.add(hit);
          break;
        }
      }
    }
    // "surah al-kahf verse 10", an ayah number on its own belongs to the surah
    // just named.
    final loose = _ayahMention
        .allMatches(question)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    if (loose.isNotEmpty && surahs.isNotEmpty && ayahs.isEmpty) {
      for (final ayah in loose) {
        if (quran.ayah(surahs.first, ayah) != null) {
          ayahs.add(VerseRef(surahs.first, ayah));
        }
      }
    }

    final out = <Passage>[];
    for (final reference in ayahs) {
      final passage = ayahPassage(reference.surah, reference.ayah,
          isSubject: true, maxCharacters: subjectCharacterLimit);
      if (passage != null) out.add(passage);
    }
    // A surah named on its own (with no verse) is answered by its background.
    if (ayahs.isEmpty) {
      for (final id in surahs) {
        final passage = surahPassage(id);
        if (passage != null) out.add(passage);
      }
    }
    return out;
  }

  /// A surah named in words. [Search.searchSurahs] is a substring match, so
  /// "al kahf" also reaches al-Fatihah (whose similar names include "Al...");
  /// an exact name match wins when there is one, which is the difference between
  /// answering about the cave and answering about the opening.
  int? _resolveSurah(String candidate) {
    final hits = search.searchSurahs(candidate);
    if (hits.isEmpty) return null;
    final wanted = _fold(candidate);
    for (final surah in hits) {
      if (_fold(surah.nameTransliteration) == wanted ||
          _fold(surah.nameEnglish) == wanted) {
        return surah.id;
      }
    }
    if (wanted.length >= 3) {
      for (final surah in hits) {
        if (_fold(surah.nameTransliteration).endsWith(wanted)) return surah.id;
      }
    }
    return hits.first.id;
  }

  // ---- Lane 1: keywords, IDF-weighted -------------------------------------

  /// Ayahs whose translation carries the question's content words, ranked by how
  /// INFORMATIVE those words are rather than by how often they occur.
  List<Passage> keywordPassages(String question, {int limit = 4}) {
    final terms = contentWords(question);
    if (terms.isEmpty) return const [];
    final weights = termWeights(terms);

    final scores = <String, double>{};
    for (var i = 0; i < terms.length; i++) {
      if (weights[i] <= 0) continue;
      for (final hit in search.searchVerses(terms[i], limit: 400)) {
        scores[hit.id] = (scores[hit.id] ?? 0) + weights[i];
      }
    }
    // A verse matching two informative words beats one matching a single word
    // twice.
    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });

    final out = <Passage>[];
    for (final entry in ranked) {
      final reference = _parseReference(entry.key);
      if (reference == null) continue;
      final passage = ayahPassage(reference.surah, reference.ayah);
      if (passage != null) out.add(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Lane 2: themes -----------------------------------------------------

  /// Ayahs from the curated topic whose name or description the question
  /// matches, the lane that reaches verses sharing no wording with the question
  /// at all.
  List<Passage> themePassages(String question, {int limit = 2}) {
    final topics = themes?.all();
    if (topics == null || topics.isEmpty) return const [];
    final words = contentWords(question);
    if (words.isEmpty) return const [];

    Topic? best;
    var bestScore = 0;
    for (final topic in topics) {
      final haystack =
          '${topic.name} ${topic.description} ${topic.category}'.toLowerCase();
      var score = 0;
      for (final word in words) {
        if (haystack.contains(word.toLowerCase())) score += word.length;
      }
      if (score > bestScore) {
        bestScore = score;
        best = topic;
      }
    }
    if (best == null) return const [];

    final out = <Passage>[];
    for (final reference in best.ayahs) {
      final parsed = _parseReference(reference);
      if (parsed == null) continue;
      final passage = ayahPassage(parsed.surah, parsed.ayah);
      if (passage != null) out.add(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Lane 3: meaning ----------------------------------------------------

  /// Ayahs closest in MEANING to the question. Empty unless a semantic index was
  /// supplied: the other lanes still answer, which is why this one is optional.
  List<Passage> semanticPassages(String question,
      {int limit = 3, double minScore = 0.42}) {
    final index = semantic;
    if (index == null) return const [];
    // The score is a MEAN over query words, so "what does the Quran say about"
    // dilutes the topic: the meaning query is the content words alone.
    final words = contentWords(question);
    final query = words.isEmpty ? question : words.join(' ');

    final out = <Passage>[];
    for (final hit in index.search(query, limit: limit * 2, minScore: minScore)) {
      final parsed = _parseReference(hit.id);
      if (parsed == null) continue;
      final passage = ayahPassage(parsed.surah, parsed.ayah);
      if (passage != null) out.add(passage);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- Passage construction ------------------------------------------------

  Passage? ayahPassage(int surahId, int ayahId,
      {bool isSubject = false, int maxCharacters = passageCharacterLimit}) {
    final ayah = quran.ayah(surahId, ayahId);
    if (ayah == null) return null;
    final text = ayah.textEnglishSaheeh.isNotEmpty
        ? ayah.textEnglishSaheeh
        : ayah.textEnglishMustafa;
    if (text.isEmpty) return null;
    return Passage(
      kind: PassageKind.ayah,
      reference: '$surahId:$ayahId',
      text: text,
      maxCharacters: maxCharacters,
      isSubject: isSubject,
      surah: surahId,
      ayah: ayahId,
    );
  }

  /// A surah's background prose. The bundled notes open with the period of
  /// revelation, which answers "what is this surah about" with history, so the
  /// theme section, when a source has one, is what the question actually meant.
  Passage? surahPassage(int surahId) {
    final surah = quran.surah(surahId);
    final sources = quran.info(surahId);
    if (surah == null || sources.isEmpty) return null;

    var text = '';
    for (final source in sources) {
      final match = _themeHeading.firstMatch(source.contents);
      if (match == null) continue;
      final fromTheme = _plainProse(source.contents.substring(match.start));
      if (fromTheme.length >= 200) {
        text = fromTheme;
        break;
      }
    }
    if (text.isEmpty) text = _plainProse(sources.first.contents);
    if (text.isEmpty) return null;

    return Passage(
      kind: PassageKind.surah,
      reference: 'Surah ${surah.nameTransliteration}',
      text: text,
      maxCharacters: subjectCharacterLimit,
      isSubject: true,
      surah: surahId,
    );
  }

  // ---- Question analysis ---------------------------------------------------

  /// The words in a question that actually name its topic.
  List<String> contentWords(String question) => question
      .split(_wordSplit)
      .where((w) => w.length >= 3 && !questionWords.contains(w.toLowerCase()))
      .toList(growable: false);

  /// A question with fewer than two content words ("why?", "and zakat?") only
  /// makes sense with the previous question beside it.
  bool isBareFollowUp(String question) =>
      question
          .split(_wordSplit)
          .where((w) => w.length >= 4 && !questionWords.contains(w.toLowerCase()))
          .length <
      2;

  /// Inverse document frequency per term: `log(N / (1 + df))`, floored at 0. A
  /// word in half the Quran weighs almost nothing; a word in ten ayahs weighs a
  /// lot. Built once, over the translations.
  List<double> termWeights(List<String> terms) {
    var frequency = _documentFrequency;
    if (frequency == null) {
      frequency = <String, int>{};
      var documents = 0;
      for (final surah in quran.all()) {
        for (final ayah in surah.ayahs) {
          documents++;
          final words = ayah.textEnglishSaheeh
              .toLowerCase()
              .split(_wordSplit)
              .where((w) => w.length >= 3)
              .toSet();
          for (final word in words) {
            frequency[word] = (frequency[word] ?? 0) + 1;
          }
        }
      }
      _documentFrequency = frequency;
      _documentCount = documents;
    }
    return [
      for (final term in terms)
        math.max(0.0,
            math.log(_documentCount / (1 + (frequency[term.toLowerCase()] ?? 0)))),
    ];
  }
}

/// The system instructions and the user-side prompt for one turn.
class ChatPrompt {
  final String instructions;
  final String prompt;
  const ChatPrompt(this.instructions, this.prompt);
}

/// The instructions and the user-side prompt for one turn: the passages, the
/// recent conversation, the question.
///
/// Eight passages of 500 characters is roughly a thousand tokens, sized for a
/// ~4k on-device window with room for the instructions, the conversation, and a
/// full answer. Raise both for a larger model; the shape does not change.

ChatPrompt chatPrompt(
  String question,
  List<Passage> passages, {
  List<Turn> transcript = const [],
  int limit = passageLimit,
}) {
  final rendered = passages.take(limit).map((p) {
    final marker = p.isSubject ? 'SUBJECT OF THE QUESTION ' : '';
    return '$marker[${p.reference}] ${_clip(p.text, p.maxCharacters)}';
  }).join('\n');
  final recent = transcript
      .skip(transcript.length > 3 ? transcript.length - 3 : 0)
      .map((t) => 'Earlier question: ${_clip(t.question, 300)}\n'
          'Earlier answer: ${_clip(t.answer, 500)}')
      .join('\n');

  final prompt = StringBuffer();
  if (rendered.isNotEmpty) {
    prompt.write(
        'PASSAGES the app retrieved for this question (a passage marked SUBJECT OF THE QUESTION is the verse or surah the question is about: base the answer on it; cite the passages you use, ignore the rest):\n');
    prompt.write(rendered);
    prompt.write('\n\n');
  }
  if (recent.isNotEmpty) {
    prompt.write('CONVERSATION SO FAR:\n$recent\n\n');
  }
  prompt.write('QUESTION: $question');

  return ChatPrompt(chatInstructions, prompt.toString());
}

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

/// Round-robin the lanes so each gets a voice inside the budget.

List<Passage> _interleave(List<List<Passage>> lanes) {
  final depth =
      lanes.fold<int>(0, (best, lane) => lane.length > best ? lane.length : best);
  final out = <Passage>[];
  for (var i = 0; i < depth; i++) {
    for (final lane in lanes) {
      if (i < lane.length) out.add(lane[i]);
    }
  }
  return out;
}

/// Strip the light markdown the surah notes carry, so a passage reads as prose.

String _plainProse(String text) => text
    .replaceAll(RegExp(r'^\s*#+\s*', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`]+'), '')
    .replaceAll('\r', '')
    .replaceAll(RegExp(r'\n{2,}'), '\n')
    .trim();

String _fold(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

VerseRef? _parseReference(String text) {
  final parts = text.split(':');
  if (parts.length != 2) return null;
  final surah = int.tryParse(parts[0]);
  final ayah = int.tryParse(parts[1]);
  if (surah == null || ayah == null) return null;
  return VerseRef(surah, ayah);
}
