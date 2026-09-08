/// The corpora added upstream in Al-Islam 4.6.4: the repeated phrases, the QUL
/// topic indexes, the hizb/ruku/manzil divisions, the qiraat variant matrix and
/// the word of the day. Morphology has its own file.
///
/// See `../../docs/19-mutashabihat.md`, `20-topics-and-metadata.md`,
/// `21-qiraat-variants.md` and `22-word-of-day.md`.

// ---- shared helpers ---------------------------------------------------------

/// Split a `"surah:ayah"` key; `(0, 0)` for anything malformed, which never
/// passes for a real ayah.
List<int> splitAyahKey(String key) {
  final parts = key.split(':');
  if (parts.length != 2) return const [0, 0];
  return [int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0];
}

int _compareAyahKeys(String a, String b) {
  final pa = splitAyahKey(a);
  final pb = splitAyahKey(b);
  return pa[0] != pb[0] ? pa[0] - pb[0] : pa[1] - pb[1];
}

// ---- mutashabihat -----------------------------------------------------------

/// One repeated phrase and every place it occurs.
///
/// A different thing from a similar ayah: that is a whole-ayah match, this is
/// the exact run of words two ayahs share, which is the memoriser's question.
/// Spans are 0-based inclusive token ranges of the raw Hafs text, mapped at
/// build time, so nothing here matches text.
class MutashabihatPhrase {
  final int id;

  /// The ayah the phrase is defined from.
  final String source;

  /// Inclusive token range inside [source], as `[first, last]`.
  final List<int> span;
  final int count;
  final int ayahCount;
  final int surahCount;

  /// Ayah key -> the spans carrying the phrase in that ayah.
  final Map<String, List<List<int>>> occurrences;

  const MutashabihatPhrase({
    required this.id,
    required this.source,
    required this.span,
    required this.count,
    required this.ayahCount,
    required this.surahCount,
    required this.occurrences,
  });

  /// How long the phrase is, in words.
  int get wordCount => span[1] - span[0] + 1;

  /// The occurrences in mushaf order.
  List<String> get orderedKeys =>
      occurrences.keys.toList(growable: false)..sort(_compareAyahKeys);
}

/// One place a phrase occurs.
class PhraseOccurrence {
  final int surah;
  final int ayah;
  final String key;
  final List<List<int>> spans;

  const PhraseOccurrence(this.surah, this.ayah, this.key, this.spans);
}

class Mutashabihat {
  final Map<String, dynamic> _data;

  const Mutashabihat([this._data = const {}]);

  Map<String, dynamic> get _phrases =>
      _data['phrases'] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _index =>
      _data['index'] as Map<String, dynamic>? ?? const {};

  bool get isLoaded => _phrases.isNotEmpty;

  /// One phrase by id.
  MutashabihatPhrase? phrase(int id) {
    final row = _phrases['$id'] as Map<String, dynamic>?;
    if (row == null) return null;
    final span = (row['span'] as List<dynamic>).cast<int>();
    if (span.length != 2 || span[1] < span[0]) return null;
    final occurrences = <String, List<List<int>>>{};
    (row['occurrences'] as Map<String, dynamic>? ?? const {})
        .forEach((key, spans) {
      occurrences[key] = (spans as List<dynamic>)
          .map((s) => (s as List<dynamic>).cast<int>())
          .toList(growable: false);
    });
    return MutashabihatPhrase(
      id: id,
      source: row['source'] as String,
      span: span,
      count: row['count'] as int,
      ayahCount: row['ayahCount'] as int,
      surahCount: row['surahCount'] as int,
      occurrences: occurrences,
    );
  }

  /// The phrases this ayah carries, longest first so the most distinctive
  /// shared wording leads.
  List<MutashabihatPhrase> phrasesFor(int surahId, int ayahId) {
    final ids = (_index['$surahId:$ayahId'] as List<dynamic>? ?? const [])
        .cast<int>();
    final out = <MutashabihatPhrase>[];
    for (final id in ids) {
      final found = phrase(id);
      if (found != null) out.add(found);
    }
    out.sort((a, b) =>
        a.wordCount != b.wordCount ? b.wordCount - a.wordCount : a.id - b.id);
    return out;
  }

  /// Whether the ayah carries any: a map hit, cheap enough to gate a button on.
  bool has(int surahId, int ayahId) {
    final ids = _index['$surahId:$ayahId'] as List<dynamic>?;
    return ids != null && ids.isNotEmpty;
  }

  /// A phrase's occurrences in mushaf order, not key order.
  List<PhraseOccurrence> occurrences(int id) {
    final found = phrase(id);
    if (found == null) return const [];
    return found.orderedKeys.map((key) {
      final parts = splitAyahKey(key);
      return PhraseOccurrence(
          parts[0], parts[1], key, found.occurrences[key] ?? const []);
    }).toList(growable: false);
  }

  /// The phrase's own words, sliced out of the ayah text you hand it. The engine
  /// does not carry the text in here: the caller already has the ayah it is
  /// displaying.
  String textOf(int id, String sourceAyahText) {
    final found = phrase(id);
    if (found == null) return '';
    final tokens =
        sourceAyahText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (found.span[1] >= tokens.length) return '';
    return tokens.sublist(found.span[0], found.span[1] + 1).join(' ');
  }

  /// How many phrases there are, and how many ayahs carry one.
  Map<String, int> count() =>
      {'phrases': _phrases.length, 'ayahs': _index.length};
}

// ---- QUL topics -------------------------------------------------------------

/// One of the three QUL indexes.
///
/// They are three trees over ONE pool of topics, not three partitions of it: a
/// topic can be a node in more than one (17 are), and a tree's parent need not
/// itself be listed in that tree.
/// The third value is `generalIndex`, not `index`, only because every Dart enum
/// already has an `index` getter and the two cannot share a name. The wire name
/// stays `"index"`, and [topicTreeWireName] is the mapping; the other six ports
/// call it `index`.
enum TopicTree { thematic, ontology, generalIndex }

/// The name this tree carries in `data/quran-topics.json`.
String topicTreeWireName(TopicTree tree) =>
    tree == TopicTree.generalIndex ? 'index' : tree.name;

/// One topic of the Quranic Universal Library's indexes.
class QulTopic {
  final int id;
  final String name;
  final String arabic;

  /// The indexes listing this topic; 17 topics are listed in two.
  final List<TopicTree> families;

  /// One parent per tree, independently. Null where the topic is not in that
  /// tree, or is one of its roots.
  final Map<TopicTree, int?> parents;
  final String description;
  final String wiki;

  /// `"2:255"` references, in the corpus's order.
  final List<String> ayahs;
  final List<int> related;

  const QulTopic({
    required this.id,
    required this.name,
    required this.arabic,
    required this.families,
    required this.parents,
    required this.description,
    required this.wiki,
    required this.ayahs,
    required this.related,
  });

  /// The parent in one tree, if any.
  int? parentIn(TopicTree tree) => parents[tree];

  /// Whether this index lists the topic.
  bool isListedIn(TopicTree tree) => families.contains(tree);

  /// The tree to use when a caller does not name one.
  TopicTree? get defaultTree => families.isEmpty ? null : families.first;

  factory QulTopic.fromJson(Map<String, dynamic> row) {
    TopicTree? parse(String name) {
      for (final tree in TopicTree.values) {
        if (topicTreeWireName(tree) == name) return tree;
      }
      return null;
    }

    final families = (row['families'] as List<dynamic>? ?? const [])
        .map((f) => parse(f as String))
        .whereType<TopicTree>()
        .toList(growable: false);
    final rawParents = row['parents'] as Map<String, dynamic>? ?? const {};
    final parents = <TopicTree, int?>{};
    for (final tree in TopicTree.values) {
      parents[tree] = rawParents[topicTreeWireName(tree)] as int?;
    }
    return QulTopic(
      id: row['id'] as int,
      name: row['name'] as String,
      arabic: row['arabic'] as String? ?? '',
      families: families,
      parents: parents,
      description: row['description'] as String? ?? '',
      wiki: row['wiki'] as String? ?? '',
      ayahs: (row['ayahs'] as List<dynamic>? ?? const []).cast<String>(),
      related: (row['related'] as List<dynamic>? ?? const []).cast<int>(),
    );
  }
}

class QuranTopics {
  final List<QulTopic> _all;
  final Map<int, QulTopic> _byId;
  final Map<TopicTree, Map<int, List<int>>> _children = {};
  Map<String, List<int>>? _byAyah;

  QuranTopics([Map<String, dynamic>? json])
      : _all = ((json?['topics'] as List<dynamic>?) ?? const [])
            .map((row) => QulTopic.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
        _byId = {} {
    for (final topic in _all) {
      _byId[topic.id] = topic;
    }
  }

  bool get isLoaded => _all.isNotEmpty;

  /// Every topic, in corpus order.
  List<QulTopic> topics() => _all;

  QulTopic? topic(int id) => _byId[id];

  /// The topics an index lists.
  List<QulTopic> inFamily(TopicTree tree) =>
      _all.where((t) => t.isListedIn(tree)).toList(growable: false);

  /// Topics an index lists that have no parent in that same tree.
  List<QulTopic> roots(TopicTree tree) => _all
      .where((t) => t.isListedIn(tree) && t.parentIn(tree) == null)
      .toList(growable: false);

  /// The parent in one tree. Pass null for the topic's first listed index.
  QulTopic? parent(int id, [TopicTree? tree]) {
    final topic = _byId[id];
    if (topic == null) return null;
    final which = tree ?? topic.defaultTree;
    if (which == null) return null;
    final parentId = topic.parentIn(which);
    return parentId == null ? null : _byId[parentId];
  }

  /// Direct children in one tree, in id order.
  List<QulTopic> children(int id, [TopicTree? tree]) {
    final topic = _byId[id];
    if (topic == null) return const [];
    final which = tree ?? topic.defaultTree;
    if (which == null) return const [];
    final ids = _childIndex(which)[id] ?? const <int>[];
    return ids.map((c) => _byId[c]).whereType<QulTopic>().toList(growable: false);
  }

  /// The chain up to the root of one tree, nearest first. Cycle-safe: the corpus
  /// is trusted for its content, not for its shape.
  List<QulTopic> ancestors(int id, [TopicTree? tree]) {
    final topic = _byId[id];
    if (topic == null) return const [];
    final which = tree ?? topic.defaultTree;
    if (which == null) return const [];
    final out = <QulTopic>[];
    final seen = <int>{id};
    var current = parent(id, which);
    while (current != null && seen.add(current.id)) {
      out.add(current);
      current = parent(current.id, which);
    }
    return out;
  }

  /// Every topic annotating this ayah, across all three indexes.
  List<QulTopic> topicsFor(int surahId, int ayahId) {
    _buildAyahIndex();
    final ids = _byAyah?['$surahId:$ayahId'] ?? const <int>[];
    return ids.map((id) => _byId[id]).whereType<QulTopic>().toList(growable: false);
  }

  /// Name and Arabic-name substring search, exact-prefix hits first.
  List<QulTopic> search(String query, {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <QulTopic>[];
    final contains = <QulTopic>[];
    for (final topic in _all) {
      final name = topic.name.toLowerCase();
      if (name.startsWith(q)) {
        starts.add(topic);
      } else if (name.contains(q) || topic.arabic.contains(query)) {
        contains.add(topic);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList(growable: false);
  }

  /// Corpus size. The per-index counts deliberately sum to MORE than the topic
  /// count: the 17 topics listed in two indexes are counted in both.
  Map<String, int> count() {
    var thematic = 0, ontology = 0, index = 0, references = 0;
    for (final topic in _all) {
      for (final family in topic.families) {
        switch (family) {
          case TopicTree.thematic:
            thematic++;
            break;
          case TopicTree.ontology:
            ontology++;
            break;
          case TopicTree.generalIndex:
            index++;
            break;
        }
      }
      references += topic.ayahs.length;
    }
    return {
      'topics': _all.length,
      'thematic': thematic,
      'ontology': ontology,
      'index': index,
      'references': references,
    };
  }

  Map<int, List<int>> _childIndex(TopicTree tree) {
    final cached = _children[tree];
    if (cached != null) return cached;
    final table = <int, List<int>>{};
    for (final topic in _all) {
      final parentId = topic.parentIn(tree);
      if (parentId != null) table.putIfAbsent(parentId, () => []).add(topic.id);
    }
    for (final bucket in table.values) {
      bucket.sort();
    }
    _children[tree] = table;
    return table;
  }

  void _buildAyahIndex() {
    if (_byAyah != null) return;
    final table = <String, List<int>>{};
    for (final topic in _all) {
      for (final key in topic.ayahs) {
        table.putIfAbsent(key, () => []).add(topic.id);
      }
    }
    _byAyah = table;
  }
}

// ---- passage themes ---------------------------------------------------------

/// One short sentence describing a run of ayahs.
///
/// Passages run in order through a surah and do not nest. They do not tile it
/// either: an ayah between two passages has none.
class ThemePassage {
  final int surah;
  final int from;
  final int to;
  final String theme;
  final String topic;

  const ThemePassage({
    required this.surah,
    required this.from,
    required this.to,
    required this.theme,
    required this.topic,
  });
}

class AyahThemes {
  final Map<String, dynamic> _data;

  const AyahThemes([this._data = const {}]);

  bool get isLoaded => _data.isNotEmpty;

  /// A surah's passages, in order.
  List<ThemePassage> passages(int surahId) {
    final rows = _data['$surahId'] as List<dynamic>? ?? const [];
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      return ThemePassage(
        surah: surahId,
        from: row['from'] as int,
        to: row['to'] as int,
        theme: row['theme'] as String,
        topic: row['topic'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  /// The passage an ayah falls in. Passages do not overlap, so this is the one
  /// answer; null for an ayah between two of them.
  ThemePassage? passageFor(int surahId, int ayahId) {
    for (final passage in passages(surahId)) {
      if (ayahId >= passage.from && ayahId <= passage.to) return passage;
    }
    return null;
  }

  /// Matches the theme sentence and the topic it sits under.
  List<ThemePassage> search(String query, {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <ThemePassage>[];
    final surahs = _data.keys.map(int.parse).toList()..sort();
    for (final surah in surahs) {
      for (final passage in passages(surah)) {
        if (passage.theme.toLowerCase().contains(q) ||
            passage.topic.toLowerCase().contains(q)) {
          out.add(passage);
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  Map<String, int> count() {
    var passages = 0;
    for (final rows in _data.values) {
      passages += (rows as List<dynamic>).length;
    }
    return {'surahs': _data.length, 'passages': passages};
  }
}

// ---- hizb / ruku / manzil ---------------------------------------------------

/// One hizb, ruku or manzil, identified by where it starts.
class Division {
  final int number;
  final int surah;
  final int ayah;
  final String key;

  const Division(this.number, this.surah, this.ayah, this.key);
}

/// One of the three schedule divisions, stored as its start keys in order so a
/// lookup is a binary search rather than a table with one row per ayah.
class DivisionTable {
  final List<String> _starts;
  final List<int> _ranks;

  DivisionTable(List<String> starts)
      : _starts = starts,
        _ranks = starts.map((key) {
          final parts = splitAyahKey(key);
          return parts[0] * 1000 + parts[1];
        }).toList(growable: false);

  int get length => _starts.length;

  /// The 1-based number containing an ayah, or 0 when there is no table.
  int numberFor(int surahId, int ayahId) {
    final target = surahId * 1000 + ayahId;
    var low = 0, high = _ranks.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_ranks[mid] <= target) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found + 1;
  }

  /// Where a division begins.
  Division? start(int number) {
    if (number < 1 || number > _starts.length) return null;
    final key = _starts[number - 1];
    final parts = splitAyahKey(key);
    return Division(number, parts[0], parts[1], key);
  }

  /// Every start, in order.
  List<Division> all() => List.generate(_starts.length, (i) => start(i + 1)!);

  /// A division's start and the start of the next one, which is where it ends.
  /// The second is null for the last, which runs to the end of the Quran: no
  /// start key says so, and pretending otherwise would invent a boundary.
  MapEntry<Division, Division?>? range(int number) {
    final from = start(number);
    if (from == null) return null;
    return MapEntry(from, start(number + 1));
  }
}

/// 60 hizb (the juz halved, the unit a memorisation plan is written in), 558
/// ruku (thematic sections printed in the margin of South Asian mushafs), 7
/// manzil (the seven-day division).
class QuranMetadata {
  final DivisionTable hizb;
  final DivisionTable ruku;
  final DivisionTable manzil;

  QuranMetadata([Map<String, dynamic>? json])
      : hizb = DivisionTable(
            ((json?['hizb'] as List<dynamic>?) ?? const []).cast<String>()),
        ruku = DivisionTable(
            ((json?['ruku'] as List<dynamic>?) ?? const []).cast<String>()),
        manzil = DivisionTable(
            ((json?['manzil'] as List<dynamic>?) ?? const []).cast<String>());

  bool get isLoaded => hizb.length > 0;

  /// All three at once, which is what a "where am I" line under an ayah wants.
  Map<String, int> divisionsFor(int surahId, int ayahId) => {
        'hizb': hizb.numberFor(surahId, ayahId),
        'ruku': ruku.numberFor(surahId, ayahId),
        'manzil': manzil.numberFor(surahId, ayahId),
      };

  Map<String, int> count() =>
      {'hizb': hizb.length, 'ruku': ruku.length, 'manzil': manzil.length};
}
