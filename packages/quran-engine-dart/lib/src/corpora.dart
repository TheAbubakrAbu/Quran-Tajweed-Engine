// Three curated corpora that answer questions the text alone cannot: where
// else the Quran says this, what it says about a topic, and how to learn to
// recite it.
//
// See `../../docs/13-similar-and-themes.md`.
// One similar-ayah match, in display order.

class SimilarMatch {
  final int surah;
  final int ayah;

  /// True for the classical corpus, false for a generated phrase-overlap match.
  final bool verified;

  /// Why a generated row matched; empty for verified rows.
  final List<String> labels;

  /// The shared wording: 0-based inclusive token ranges of the shared words in
  /// the MATCHED ayah's raw text. QUL's own placement where it lists the pair,
  /// else the wording the corpus recorded, located in the ayah when the data
  /// was built. The data carries no text of its own, so cut the words out of
  /// the quran.json ayah by these ranges rather than keeping a second copy of
  /// them. Empty when no source records shared wording.
  final List<List<int>> spans;

  /// QUL's 0-100 similarity, where it listed the pair. Null for rows from the
  /// other two sources: they rank, but they do not score.
  final int? score;

  const SimilarMatch({
    required this.surah,
    required this.ayah,
    required this.verified,
    required this.labels,
    this.spans = const [],
    this.score,
  });
}

/// Similar ayahs (mutashabihat): the other places the Quran says something
/// close to this.
///
/// Verified rows come from the classical corpus and are listed first; generated
/// rows are phrase-overlap matches carrying the labels that explain why they
/// matched. They are a reading aid, not a scholarly claim, so [SimilarMatch.verified]
/// is the flag to gate on if you show only one kind.
///
/// The Quranic Universal Library's table is the third source, and it adds
/// [SimilarMatch.score], its own 0-100 similarity; null for rows from the other
/// two, which rank but do not score.
///
/// The shared wording is [SimilarMatch.spans], token ranges into the matched
/// ayah. The data carries no text of its own (version 2): read the words out
/// of the engine's quran by those spans, so what you show is the Quran text
/// you already have and not a second copy of it.

class SimilarAyahs {
  final Map<String, dynamic> _data;

  /// [data] is the whole `similar-ayahs.json` file, `{v, ayahs}`. A version 1
  /// file (rows keyed at the top level, the phrase as text) is not read: it
  /// would put the shared wording where a span is expected. Anything that is
  /// not version 2 is treated as no data rather than half a corpus.
  SimilarAyahs([Map<String, dynamic>? data]) : _data = _unwrap(data);

  static Map<String, dynamic> _unwrap(Map<String, dynamic>? data) {
    if (data == null || data['v'] != 2) return const {};
    return (data['ayahs'] as Map<String, dynamic>?) ?? const {};
  }

  /// Matches for an ayah, in display order. Empty for most short ayahs.
  List<SimilarMatch> matches(int surahId, int ayahId) {
    final rows = _data['$surahId:$ayahId'] as List<dynamic>?;
    if (rows == null) return const [];
    final out = <SimilarMatch>[];
    for (final raw in rows) {
      // [surah, ayah, verifiedFlag, spans, labels, score]: six fields, always.
      // score is null for the rows the QUL table did not list.
      final row = raw as List<dynamic>;
      if (row.length < 2) continue;
      out.add(SimilarMatch(
        surah: row[0] as int,
        ayah: row[1] as int,
        verified: row.length > 2 && row[2] == 1,
        labels: row.length > 4 && row[4] is List
            ? (row[4] as List<dynamic>).cast<String>()
            : const [],
        spans: row.length > 3 && row[3] is List
            ? (row[3] as List<dynamic>)
                .map((span) => (span as List<dynamic>).cast<int>())
                .toList(growable: false)
            : const [],
        score: row.length > 5 && row[5] is int ? row[5] as int : null,
      ));
    }
    return out;
  }

  /// Whether the ayah has any: a map hit, cheap enough to gate a button on.
  bool has(int surahId, int ayahId) {
    final rows = _data['$surahId:$ayahId'] as List<dynamic>?;
    return rows != null && rows.isNotEmpty;
  }

  /// How many ayahs have at least one match.
  int count() => _data.length;
}

/// One curated topic and the ayahs that speak to it.

class Topic {
  final String id;
  final String name;
  final String description;
  final String category;
  final String domain;

  /// `"2:255"` references, in mushaf order.
  final List<String> ayahs;

  const Topic({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.domain,
    required this.ayahs,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
        ayahs: ((json['ayahs'] as List<dynamic>?) ?? const []).cast<String>(),
      );
}

/// Browse the Quran by theme: curated topics grouped under a category and a
/// domain, each listing the ayahs that speak to it. The lists are curated, not
/// derived, so a topic is a real reading path rather than a keyword hit list;
/// [topicsFor] inverts them.

class Themes {
  final List<Topic> _topics;
  final Map<String, Topic> _byId;
  Map<String, List<Topic>>? _byAyah;

  Themes([Map<String, dynamic>? data])
      : _topics = ((data?['topics'] as List<dynamic>?) ?? const [])
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        _byId = {} {
    for (final topic in _topics) {
      _byId[topic.id] = topic;
    }
  }

  /// Every topic, in the order the corpus lists them.
  List<Topic> all() => _topics;

  Topic? topic(String id) => _byId[id];

  /// The distinct domains, in first-seen order.
  List<String> domains() =>
      _topics.map((t) => t.domain).toSet().toList(growable: false);

  /// The distinct categories, optionally within one domain.
  List<String> categories([String? domain]) => _topics
      .where((t) => domain == null || t.domain == domain)
      .map((t) => t.category)
      .toSet()
      .toList(growable: false);

  List<Topic> inDomain(String domain) =>
      _topics.where((t) => t.domain == domain).toList(growable: false);

  List<Topic> inCategory(String category) =>
      _topics.where((t) => t.category == category).toList(growable: false);

  /// The topics an ayah appears under.
  List<Topic> topicsFor(int surahId, int ayahId) {
    final index = _byAyah ??= () {
      final built = <String, List<Topic>>{};
      for (final topic in _topics) {
        for (final reference in topic.ayahs) {
          built.putIfAbsent(reference, () => []).add(topic);
        }
      }
      return built;
    }();
    return index['$surahId:$ayahId'] ?? const [];
  }

  /// Topics whose name, description, category or domain carries [query].
  List<Topic> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return _topics
        .where((t) => [t.name, t.description, t.category, t.domain]
            .any((field) => field.toLowerCase().contains(needle)))
        .toList(growable: false);
  }
}

/// One practice fragment: a short Arabic snippet with a caption saying what to
/// listen for.

/// One practice fragment: a short Arabic snippet with a caption saying what to
/// listen for.
///
/// The Arabic is in exactly one of two places. Teaching Arabic a tutor wrote
/// (invented drill syllables, single letters, the isti'adhah) is [text]. Arabic
/// that IS Quran is [ayah], a reference into this engine's own text, and then
/// [text] is empty: version 4 stopped copying verses into the lesson pack for
/// the same reason nothing else here copies them.
class TajweedDrill {
  final String caption;

  /// The fragment as written, or empty when [ayah] locates it instead.
  final String text;

  /// Where the words are in the Quran when this drill is a real verse. Cut them
  /// out of the engine's quran by it; the data carries no copy of them. Null
  /// when [text] already holds the Arabic.
  final TajweedAyahWords? ayah;

  const TajweedDrill(this.caption, this.text, [this.ayah]);

  factory TajweedDrill.fromJson(Map<String, dynamic> json) => TajweedDrill(
        json['caption'] as String? ?? '',
        json['text'] as String? ?? '',
        TajweedAyahWords.fromJson(json['ayah'] as List<dynamic>?),
      );
}

/// A run of Quran words a lesson points at: `[surah, ayah, first, last]` in the
/// JSON, the span 0-based and inclusive over the ayah's whitespace tokens.
class TajweedAyahWords {
  final int surahId;
  final int ayahNumber;
  final int first;
  final int last;

  const TajweedAyahWords(this.surahId, this.ayahNumber, this.first, this.last);

  /// Null for a drill that carries its Arabic as text, or for a malformed row:
  /// a lesson that cannot place its words still loads and shows its prose.
  static TajweedAyahWords? fromJson(List<dynamic>? row) {
    if (row == null || row.length != 4) return null;
    final span = row.cast<int>();
    if (span[2] < 0 || span[3] < span[2]) return null;
    return TajweedAyahWords(span[0], span[1], span[2], span[3]);
  }
}

/// An ayah to hear the rule in, with the words to focus on.

class TajweedExample {
  final int surahId;
  final int ayahNumber;
  final String focus;

  /// The 0-based inclusive token range `[start, end]` of the words to listen
  /// at, into the ayah's raw text. Read them out of the engine's quran: the
  /// data carries no copy of the words (version 3). Null when the lesson
  /// names the whole ayah.
  final List<int>? wordSpan;

  const TajweedExample(this.surahId, this.ayahNumber, this.focus,
      [this.wordSpan]);

  factory TajweedExample.fromJson(Map<String, dynamic> json) => TajweedExample(
        json['surahId'] as int? ?? 0,
        json['ayahNumber'] as int? ?? 0,
        json['focus'] as String? ?? '',
        (json['wordSpan'] as List<dynamic>?)?.cast<int>(),
      );
}

/// The memory-hook word a rule card hangs on, with what it means. Teaching
/// Arabic chosen for the rule it demonstrates, so it is written out rather than
/// referenced.
class TajweedMnemonic {
  final String arabic;
  final String gloss;
  const TajweedMnemonic(this.arabic, this.gloss);

  factory TajweedMnemonic.fromJson(Map<String, dynamic> json) => TajweedMnemonic(
        json['arabic'] as String? ?? '',
        json['gloss'] as String? ?? '',
      );
}

/// The card that states the rule: when it triggers, what to do, how long to
/// hold it, the mnemonic it hangs on, and fragments to see it in.
class TajweedRuleCard {
  final List<TajweedDrill> fragments;
  final String? trigger;
  final String? action;
  final String? hold;
  final TajweedMnemonic? mnemonic;
  final String? countEn;
  final String? countAr;
  const TajweedRuleCard(this.fragments, this.trigger, this.action, this.hold,
      this.mnemonic, this.countEn, this.countAr);

  factory TajweedRuleCard.fromJson(Map<String, dynamic> json) => TajweedRuleCard(
        ((json['fragments'] as List<dynamic>?) ?? const [])
            .map((e) => TajweedDrill.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        json['trigger'] as String?,
        json['action'] as String?,
        json['hold'] as String?,
        json['mnemonic'] == null
            ? null
            : TajweedMnemonic.fromJson(json['mnemonic'] as Map<String, dynamic>),
        json['countEn'] as String?,
        json['countAr'] as String?,
      );
}

class TajweedLesson {
  final String id;
  final String titleEn;
  final String titleAr;
  final String summary;
  final List<String> body;

  /// Absent on the lessons that teach through examples alone.
  final List<TajweedDrill> drills;
  final List<TajweedExample> examples;
  final TajweedRuleCard? ruleCard;

  /// The tajweed colour this rule is painted in, where it has one.
  final String? color;

  const TajweedLesson({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.summary,
    required this.body,
    required this.drills,
    required this.examples,
    required this.ruleCard,
    required this.color,
  });

  factory TajweedLesson.fromJson(Map<String, dynamic> json) => TajweedLesson(
        id: json['id'] as String? ?? '',
        titleEn: json['titleEn'] as String? ?? '',
        titleAr: json['titleAr'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        body: ((json['body'] as List<dynamic>?) ?? const []).cast<String>(),
        drills: ((json['drills'] as List<dynamic>?) ?? const [])
            .map((e) => TajweedDrill.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        examples: ((json['examples'] as List<dynamic>?) ?? const [])
            .map((e) => TajweedExample.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        ruleCard: json['ruleCard'] == null
            ? null
            : TajweedRuleCard.fromJson(json['ruleCard'] as Map<String, dynamic>),
        color: json['color'] as String?,
      );
}

class TajweedChapter {
  final String id;
  final String title;
  final String subtitle;
  final List<TajweedLesson> lessons;

  const TajweedChapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lessons,
  });

  factory TajweedChapter.fromJson(Map<String, dynamic> json) => TajweedChapter(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        lessons: ((json['lessons'] as List<dynamic>?) ?? const [])
            .map((e) => TajweedLesson.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// The tajweed course: chapters from the Arabic alphabet to the rules of
/// stopping, each lesson carrying its prose, its drills, and Quranic examples to
/// hear the rule in.
///
/// Content, not algorithm — but it belongs in the engine for the same reason the
/// rule catalogue does: every app that teaches tajweed otherwise rewrites the
/// same curriculum, and a lesson that cites `2:255` should cite the same ayah
/// everywhere.

class TajweedLessons {
  final List<TajweedChapter> _chapters;
  final Map<String, TajweedChapter> _chapterOf = {};
  final Map<String, TajweedLesson> _byLesson = {};

  TajweedLessons([Map<String, dynamic>? data])
      : _chapters = ((data?['chapters'] as List<dynamic>?) ?? const [])
            .map((e) => TajweedChapter.fromJson(e as Map<String, dynamic>))
            .toList(growable: false) {
    for (final chapter in _chapters) {
      for (final lesson in chapter.lessons) {
        _byLesson[lesson.id] = lesson;
        _chapterOf[lesson.id] = chapter;
      }
    }
  }

  /// Every chapter, in course order.
  List<TajweedChapter> chapters() => _chapters;

  TajweedChapter? chapter(String id) {
    for (final chapter in _chapters) {
      if (chapter.id == id) return chapter;
    }
    return null;
  }

  /// Every lesson across every chapter, in course order.
  List<TajweedLesson> allLessons() =>
      [for (final chapter in _chapters) ...chapter.lessons];

  TajweedLesson? lesson(String id) => _byLesson[id];

  /// Which chapter a lesson belongs to.
  TajweedChapter? chapterOf(String id) => _chapterOf[id];

  /// The lesson after this one, walking across chapter boundaries.
  TajweedLesson? next(String id) {
    final all = allLessons();
    final at = all.indexWhere((l) => l.id == id);
    return at >= 0 && at + 1 < all.length ? all[at + 1] : null;
  }

  TajweedLesson? previous(String id) {
    final all = allLessons();
    final at = all.indexWhere((l) => l.id == id);
    return at > 0 ? all[at - 1] : null;
  }
}
