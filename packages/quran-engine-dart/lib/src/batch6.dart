/// The corpora added upstream in Al-Islam 4.6.5: the 99 Names in depth, and the
/// chains of transmission of the Ten Readings.
///
/// See `../../docs/23-names-depth.md` and `24-isnad.md`.

// ---- the Names in depth ----------------------------------------------------

/// One of the nine themes the Names are grouped under.
class NameTheme {
  final String id;
  final String label;

  const NameTheme(this.id, this.label);
}

/// One ayah a Name appears in.
class NameOccurrence {
  final int surah;
  final int ayah;

  /// 0-based whitespace-token index into the ayah's raw text, or null where the
  /// corpus could not place the Name in the ayah (ten occurrences across four
  /// Names). The ayah is still right: show the verse whole and highlight nothing.
  final int? token;

  /// How many tokens the Name spans (0 for an unplaced occurrence).
  final int tokens;

  const NameOccurrence(this.surah, this.ayah, this.token, this.tokens);
}

/// The layer under `names-of-allah.json`: what the Name is built on and what it
/// asks of a reader.
///
/// The written material is Tilawa's (Jamil Hammoudeh), used with permission; the
/// occurrences point into this engine's own Hafs text.
class NameDepth {
  final int number;

  /// Printed SPACED, the way a grammar book sets a root ("ر ح م"). [rootKey]
  /// closes it up to the form `morphology.json` stores.
  final String root;
  final String theme;
  final String explanation;
  final String living;
  final List<NameOccurrence> occurrences;

  const NameDepth({
    required this.number,
    required this.root,
    required this.theme,
    required this.explanation,
    required this.living,
    required this.occurrences,
  });

  factory NameDepth.fromJson(Map<String, dynamic> row) => NameDepth(
        number: row['number'] as int,
        root: row['root'] as String? ?? '',
        theme: row['theme'] as String? ?? '',
        explanation: row['explanation'] as String? ?? '',
        living: row['living'] as String? ?? '',
        occurrences:
            (row['occurrences'] as List<dynamic>? ?? const []).map((raw) {
          final o = raw as Map<String, dynamic>;
          return NameOccurrence(o['surah'] as int, o['ayah'] as int,
              o['token'] as int?, o['tokens'] as int? ?? 0);
        }).toList(growable: false),
      );
}

/// A spaced root as morphology stores it: `"ر ح م"` -> `"رحم"`.
///
/// Every port strips whitespace explicitly rather than trimming, because a root
/// is spaced in the middle and not only at the ends.
String rootKey(String root) => root.split(RegExp(r'\s+')).join();

/// A Name and the occurrence that put it in an ayah.
class NameInAyah {
  final NameDepth name;
  final NameOccurrence occurrence;

  const NameInAyah(this.name, this.occurrence);
}

class NamesDepth {
  final List<NameDepth> _names;
  final List<NameTheme> _themes;
  final Map<int, NameDepth> _byNumber;

  NamesDepth([Map<String, dynamic>? json])
      : _names = ((json?['names'] as List<dynamic>?) ?? const [])
            .map((row) => NameDepth.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
        _themes = ((json?['themes'] as List<dynamic>?) ?? const []).map((raw) {
          final t = raw as Map<String, dynamic>;
          return NameTheme(t['id'] as String, t['label'] as String? ?? '');
        }).toList(growable: false),
        _byNumber = {} {
    for (final name in _names) {
      _byNumber[name.number] = name;
    }
  }

  bool get isLoaded => _names.isNotEmpty;

  /// All 99, ordered by number.
  List<NameDepth> all() => _names;

  NameDepth? byNumber(int number) => _byNumber[number];

  /// The nine themes, in the corpus's own order.
  List<NameTheme> themes() => _themes;

  NameTheme? theme(String id) {
    for (final t in _themes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Every Name under one theme, by number.
  List<NameDepth> byTheme(String id) =>
      _names.where((n) => n.theme == id).toList(growable: false);

  /// Every Name built on one root. Accepts either spelling, spaced or closed up.
  List<NameDepth> byRoot(String root) {
    final key = rootKey(root);
    if (key.isEmpty) return const [];
    return _names
        .where((n) => rootKey(n.root) == key)
        .toList(growable: false);
  }

  /// Every Name appearing in an ayah, in token order. An unplaced occurrence (a
  /// null token) sorts last, so a highlighted list stays in reading order.
  List<NameInAyah> inAyah(int surahId, int ayahId) {
    final hits = <NameInAyah>[];
    for (final name in _names) {
      for (final occurrence in name.occurrences) {
        if (occurrence.surah == surahId && occurrence.ayah == ayahId) {
          hits.add(NameInAyah(name, occurrence));
        }
      }
    }
    int at(NameOccurrence o) => o.token ?? 1 << 40;
    hits.sort((a, b) => at(a.occurrence).compareTo(at(b.occurrence)));
    return List<NameInAyah>.unmodifiable(hits);
  }

  /// Matches the root (spaces closed on both sides), the explanation and the
  /// living line.
  List<NameDepth> search(String query, {int limit = 25}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    final key = rootKey(q);
    return _names
        .where((n) =>
            (key.isNotEmpty && rootKey(n.root).contains(key)) ||
            n.explanation.toLowerCase().contains(lower) ||
            n.living.toLowerCase().contains(lower))
        .take(limit)
        .toList(growable: false);
  }

  Map<String, int> count() => {
        'names': _names.length,
        'themes': _themes.length,
        'occurrences':
            _names.fold(0, (total, n) => total + n.occurrences.length),
      };
}

// ---- the chains of transmission --------------------------------------------

/// One person in a chain.
class IsnadNode {
  final String name;
  final String arabic;

  /// The death year, e.g. "d. 117 AH".
  final String detail;
  final String role;

  const IsnadNode(this.name, this.arabic, this.detail, this.role);

  factory IsnadNode.fromJson(Map<String, dynamic> row) => IsnadNode(
        row['name'] as String,
        row['arabic'] as String? ?? '',
        row['detail'] as String? ?? '',
        row['role'] as String? ?? '',
      );
}

/// One generation of a chain, as a consumer draws it: a row, connected downward.
class IsnadLayer {
  final String title;
  final List<IsnadNode> nodes;

  const IsnadLayer(this.title, this.nodes);
}

/// An imam's side: the Successors he read on, and the Companions they read on.
class ImamChain {
  final List<IsnadNode> teachers;
  final List<IsnadNode> companions;

  const ImamChain(this.teachers, this.companions);
}

/// A narrator's side: the links between him and the imam (empty where he read on
/// the imam himself), and the students who carried his narration on.
class NarratorChain {
  /// The imam this narration comes from.
  final String imam;
  final List<IsnadNode> links;
  final List<IsnadNode> students;

  const NarratorChain(this.imam, this.links, this.students);
}

List<IsnadNode> _nodes(dynamic raw) =>
    ((raw as List<dynamic>?) ?? const [])
        .map((n) => IsnadNode.fromJson(n as Map<String, dynamic>))
        .toList(growable: false);

class Isnad {
  final IsnadNode? _prophet;
  final List<IsnadNode> _companions;
  final Map<String, ImamChain> _imams;
  final Map<String, NarratorChain> _narrators;

  Isnad([Map<String, dynamic>? json])
      : _prophet = json?['prophet'] == null
            ? null
            : IsnadNode.fromJson(json!['prophet'] as Map<String, dynamic>),
        _companions = _nodes(json?['companions']),
        _imams = {},
        _narrators = {} {
    final imams = (json?['imams'] as Map<String, dynamic>?) ?? const {};
    imams.forEach((key, raw) {
      final row = raw as Map<String, dynamic>;
      _imams[key] = ImamChain(_nodes(row['teachers']), _nodes(row['companions']));
    });
    final narrators = (json?['narrators'] as Map<String, dynamic>?) ?? const {};
    narrators.forEach((key, raw) {
      final row = raw as Map<String, dynamic>;
      _narrators[key] = NarratorChain(row['imam'] as String? ?? '',
          _nodes(row['links']), _nodes(row['students']));
    });
  }

  bool get isLoaded => _imams.isNotEmpty;

  /// The head of every chain.
  IsnadNode? prophet() => _prophet;

  /// The thirteen Companions the readings are transmitted from.
  List<IsnadNode> companions() => _companions;

  /// The ten imams' keys, sorted.
  List<String> imamKeys() => _imams.keys.toList(growable: false)..sort();

  /// The twenty riwayah tags, sorted.
  List<String> narratorKeys() => _narrators.keys.toList(growable: false)..sort();

  ImamChain? imam(String imam) => _imams[imam];

  NarratorChain? narrator(String riwayah) => _narrators[riwayah];

  /// Whether a narrator read on his imam himself, with nobody between them.
  bool readsDirectly(String riwayah) {
    final chain = _narrators[riwayah];
    return chain != null && chain.links.isEmpty;
  }

  /// The imam a riwayah comes from.
  ///
  /// Read from the corpus, NOT parsed off the tag: four tags name the imam in the
  /// Arabic genitive ("ad-Duri an Abi Amr") while his key is the nominative
  /// ("Abu Amr"), so splitting on " an " would resolve those four to nothing.
  String? imamOf(String riwayah) {
    final imam = _narrators[riwayah]?.imam;
    return imam != null && _imams.containsKey(imam) ? imam : null;
  }

  String _narratorName(String riwayah) {
    final i = riwayah.indexOf(' an ');
    return i < 0 ? riwayah : riwayah.substring(0, i);
  }

  IsnadNode _plain(String name, String role) => IsnadNode(name, '', '', role);

  /// The layers above any imam: the Prophet, the Companions his teachers read on,
  /// and those teachers. Shared by both chain forms.
  List<IsnadLayer> topLayers(String imam) {
    final chain = _imams[imam];
    if (chain == null) return const [];
    final layers = <IsnadLayer>[];
    final p = _prophet;
    if (p != null) layers.add(IsnadLayer('THE PROPHET', [p]));
    if (chain.companions.isNotEmpty) {
      layers.add(IsnadLayer('THE COMPANIONS', chain.companions));
    }
    if (chain.teachers.isNotEmpty) {
      layers.add(IsnadLayer(
          chain.teachers.length == 1 ? 'HIS TEACHER' : 'HIS TEACHERS',
          chain.teachers));
    }
    return layers;
  }

  /// A whole chain as layers: a riwayah tag for one narration's chain, or an imam
  /// key for the reading's, which ends at his two narrators.
  List<IsnadLayer> chain(String key) {
    final k = key.trim();
    if (_imams.containsKey(k)) {
      final layers = topLayers(k);
      if (layers.isEmpty) return layers;
      layers.add(IsnadLayer('THE IMAM', [_plain(k, 'imam')]));
      final nodes = <IsnadNode>[];
      for (final tag in narratorKeys()) {
        if (imamOf(tag) == k) nodes.add(_plain(_narratorName(tag), 'narrator'));
      }
      if (nodes.isNotEmpty) layers.add(IsnadLayer('HIS TWO NARRATORS', nodes));
      return layers;
    }

    final narrator = _narrators[k];
    if (narrator == null) return const [];
    final imam = imamOf(k);
    if (imam == null) return const [];
    final layers = topLayers(imam);
    if (layers.isEmpty) return layers;
    layers.add(IsnadLayer('THE IMAM', [_plain(imam, 'imam')]));
    if (narrator.links.isNotEmpty) {
      layers.add(IsnadLayer(
          narrator.links.length == 1 ? 'THE LINK BETWEEN' : 'THE LINKS BETWEEN',
          narrator.links));
    }
    layers.add(
        IsnadLayer('THE NARRATOR', [_plain(_narratorName(k), 'narrator')]));
    if (narrator.students.isNotEmpty) {
      layers.add(IsnadLayer('HIS STUDENTS', narrator.students));
    }
    return layers;
  }

  /// One sentence on how a narrator reaches his imam: directly, or through the
  /// links between.
  String sentence(String riwayah) {
    final chain = _narrators[riwayah];
    final imam = imamOf(riwayah);
    if (chain == null || imam == null) return '';
    final narrator = _narratorName(riwayah);
    if (chain.links.isEmpty) {
      return "$narrator read on $imam himself, and $imam's chain runs through "
          'his teachers to the Companions and to the Prophet ﷺ.';
    }
    final names = chain.links.map((n) => n.name).toList(growable: false);
    final path = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and then ${names.last}';
    return '$narrator did not meet $imam: the reading reached him through $path, '
        'and from $imam it runs through his teachers to the Companions and to '
        'the Prophet ﷺ.';
  }

  Map<String, int> count() => {
        'imams': _imams.length,
        'narrators': _narrators.length,
        'companions': _companions.length,
      };
}
