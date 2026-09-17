/// The scientific-miracles corpus: 202 short articles, each making one claim
/// about the Quran and anchoring it to the ayahs it rests on, under 15
/// categories.
///
/// An article is a list of BLOCKS in reading order rather than one field of
/// prose, because the layout matters: the claim is a headline, the lead sets it
/// up, a quote carries somebody else's words with the source next to them, an
/// ayah block is a hole the consumer fills from `quran.json`, and the closer
/// asks the rhetorical question the article was built toward.
///
/// An `ayah` block carries NO text, by design: surah, ayah and endAyah only.
/// The verse belongs to this engine's own Hafs text, so duplicating it here
/// would be a second copy to keep in step and would pin the article to one
/// riwayah.
///
/// There are NO `image` blocks and [Miracles.imagesIncluded] is false: the
/// site's illustrations are not republished here for licensing reasons, and the
/// prose is written to stand without them. A consumer that leaves a gap for a
/// picture will be waiting forever.
///
/// Two levels are in play and they are NOT the same number. A CATEGORY has a
/// level (the hardest science it covers) and so does an ARTICLE; 147 of the 202
/// differ, so anything a reader filters or sorts by has to come off the
/// ARTICLE.
///
/// See `../../docs/25-miracles.md`.

/// The four levels, easiest first.
///
/// Hard-coded because this is the app's own ordering and nothing in the file
/// states it: alphabetically "extreme" would sort second, which is precisely
/// backwards.
const List<String> miracleLevels = [
  'simple',
  'intermediate',
  'advanced',
  'extreme'
];

/// The block kinds that carry the article's OWN prose. A quote is somebody
/// else's words and an ayah block has no text at all, so neither belongs in
/// [Miracles.text].
const Set<String> _proseKinds = {'claim', 'lead', 'text', 'closer'};

/// One of the fifteen categories, with the hardest science it covers.
class MiracleCategory {
  final String id;

  /// The CATEGORY's level, which an article under it need not share.
  final String level;

  const MiracleCategory(this.id, this.level);
}

/// A link out of a block: either an outside page or another article in this
/// corpus.
///
/// Exactly one of [url] and [slug] is set. Both forms occur, so a model that
/// kept only [url] would silently drop the twelve internal cross-references.
class MiracleLink {
  final String label;

  /// An outside page.
  final String? url;

  /// Another article's slug: follow it with [Miracles.bySlug].
  final String? slug;

  const MiracleLink({required this.label, this.url, this.slug});

  factory MiracleLink.fromJson(Map<String, dynamic> row) => MiracleLink(
        label: row['label'] as String? ?? '',
        url: row['url'] as String?,
        slug: row['slug'] as String?,
      );
}

/// One block of an article. Which fields are set follows from [kind].
class MiracleBlock {
  /// "claim", "lead", "text", "quote", "ayah" or "closer". Never "image".
  final String kind;

  /// Set on every kind but `ayah`.
  final String text;

  /// `lead` and `text` blocks only.
  final List<MiracleLink> links;

  /// `quote` only: who is being quoted.
  final String? sourceLabel;
  final String? sourceUrl;

  /// `ayah` only.
  final int? surah;

  /// `ayah` only: the first of the range.
  final int? ayah;

  /// `ayah` only: the last of the range, always present and equal to [ayah] for
  /// a single verse.
  final int? endAyah;

  const MiracleBlock({
    required this.kind,
    this.text = '',
    this.links = const [],
    this.sourceLabel,
    this.sourceUrl,
    this.surah,
    this.ayah,
    this.endAyah,
  });

  factory MiracleBlock.fromJson(Map<String, dynamic> row) => MiracleBlock(
        kind: row['kind'] as String? ?? '',
        text: row['text'] as String? ?? '',
        links: ((row['links'] as List<dynamic>?) ?? const [])
            .map((raw) => MiracleLink.fromJson(raw as Map<String, dynamic>))
            .toList(growable: false),
        sourceLabel: row['sourceLabel'] as String?,
        sourceUrl: row['sourceUrl'] as String?,
        surah: row['surah'] as int?,
        ayah: row['ayah'] as int?,
        endAyah: row['endAyah'] as int?,
      );

  /// Whether this is an `ayah` block covering one ayah. A block is a RANGE, so
  /// an article citing 21:30-33 answers to 21:31 as well.
  bool covers(int surahId, int ayahId) {
    if (kind != 'ayah' || surah != surahId || ayah == null) return false;
    return ayahId >= ayah! && ayahId <= (endAyah ?? ayah!);
  }
}

/// One article.
class MiracleArticle {
  final String slug;
  final String title;

  /// A [MiracleCategory] id.
  final String category;

  /// This article's OWN level, not its category's.
  final String level;
  final List<MiracleBlock> blocks;

  const MiracleArticle({
    required this.slug,
    required this.title,
    required this.category,
    required this.level,
    required this.blocks,
  });

  factory MiracleArticle.fromJson(Map<String, dynamic> row) => MiracleArticle(
        slug: row['slug'] as String? ?? '',
        title: row['title'] as String? ?? '',
        category: row['category'] as String? ?? '',
        level: row['level'] as String? ?? '',
        blocks: ((row['blocks'] as List<dynamic>?) ?? const [])
            .map((raw) => MiracleBlock.fromJson(raw as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One ayah range an article cites.
class MiracleAyahRef {
  final int surah;
  final int ayah;
  final int endAyah;

  const MiracleAyahRef(this.surah, this.ayah, this.endAyah);

  @override
  bool operator ==(Object other) =>
      other is MiracleAyahRef &&
      other.surah == surah &&
      other.ayah == ayah &&
      other.endAyah == endAyah;

  @override
  int get hashCode => Object.hash(surah, ayah, endAyah);

  @override
  String toString() => '$surah:$ayah-$endAyah';
}

/// How many articles, categories and ayah refs the corpus carries.
class MiraclesCount {
  final int articles;
  final int categories;
  final int ayahRefs;

  const MiraclesCount(this.articles, this.categories, this.ayahRefs);
}

/// Where a level sorts, or past the end for one the corpus invents later.
int miracleLevelRank(String level) {
  final i = miracleLevels.indexOf(level);
  return i == -1 ? miracleLevels.length : i;
}

class Miracles {
  final List<MiracleArticle> _articles;
  final List<MiracleCategory> _categories;
  final Map<String, MiracleArticle> _bySlug;
  final String _source;

  /// False, always: the illustrations are not republished.
  final bool imagesIncluded;

  Miracles([Map<String, dynamic>? json])
      : _articles = ((json?['articles'] as List<dynamic>?) ?? const [])
            .map((row) => MiracleArticle.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
        _categories = ((json?['categories'] as List<dynamic>?) ?? const [])
            .map((raw) {
          final c = raw as Map<String, dynamic>;
          return MiracleCategory(
              c['id'] as String? ?? '', c['level'] as String? ?? '');
        }).toList(growable: false),
        _source = json?['source'] as String? ?? '',
        imagesIncluded = json?['imagesIncluded'] as bool? ?? false,
        _bySlug = {} {
    for (final article in _articles) {
      _bySlug[article.slug] = article;
    }
  }

  bool get isLoaded => _articles.isNotEmpty;

  /// Where the corpus came from and when it was captured.
  String source() => _source;

  /// All 202, in corpus order.
  List<MiracleArticle> all() => _articles;

  MiracleArticle? bySlug(String slug) => _bySlug[slug];

  /// The fifteen categories, in the corpus's own order.
  List<MiracleCategory> categories() => _categories;

  MiracleCategory? category(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Every article filed under one category.
  List<MiracleArticle> byCategory(String id) =>
      _articles.where((a) => a.category == id).toList(growable: false);

  /// Every article at one level.
  ///
  /// The ARTICLE's level, not its category's: they disagree far more often than
  /// they agree, and a reader who picked "simple" means the article.
  List<MiracleArticle> byLevel(String level) =>
      _articles.where((a) => a.level == level).toList(growable: false);

  /// The article levels actually present, easiest first.
  List<String> levels() {
    final present = _articles.map((a) => a.level).toSet().toList();
    present.sort((a, b) {
      final rank = miracleLevelRank(a).compareTo(miracleLevelRank(b));
      return rank != 0 ? rank : a.compareTo(b);
    });
    return present;
  }

  /// Every article that cites an ayah: the way into this corpus from elsewhere
  /// in the engine.
  ///
  /// An `ayah` block is a RANGE, so an article citing 21:30-33 answers to 21:31
  /// as well. An article that cites the same ayah in two blocks is still listed
  /// once.
  List<MiracleArticle> citing(int surahId, int ayahId) => _articles
      .where((a) => a.blocks.any((b) => b.covers(surahId, ayahId)))
      .toList(growable: false);

  /// The ayah ranges one article cites, in the order it cites them.
  List<MiracleAyahRef> ayahRefs(String slug) {
    final article = _bySlug[slug];
    if (article == null) return const [];
    return article.blocks
        .where((b) => b.kind == 'ayah' && b.surah != null && b.ayah != null)
        .map((b) => MiracleAyahRef(b.surah!, b.ayah!, b.endAyah ?? b.ayah!))
        .toList(growable: false);
  }

  /// Articles whose title or prose matches a query, case-insensitively.
  ///
  /// Quotes are searched as well: a reader looking for a word remembers reading
  /// it, not who wrote it.
  List<MiracleArticle> search(String query, [int limit = 25]) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _articles
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            a.blocks.any((b) => b.text.toLowerCase().contains(q)))
        .take(limit)
        .toList(growable: false);
  }

  /// One article's own prose, blocks joined with a blank line in reading order.
  ///
  /// Quote blocks are SKIPPED: they are third-party excerpts sitting next to a
  /// source label, so folding them in would put somebody else's words into the
  /// article's voice and would break a citation off from what it cites. Ayah
  /// blocks are skipped because they carry no text at all, only a reference for
  /// the consumer to resolve.
  String text(String slug) {
    final article = _bySlug[slug];
    if (article == null) return '';
    return article.blocks
        .where((b) => _proseKinds.contains(b.kind) && b.text.isNotEmpty)
        .map((b) => b.text)
        .join('\n\n');
  }

  MiraclesCount count() {
    var refs = 0;
    for (final article in _articles) {
      for (final block in article.blocks) {
        if (block.kind == 'ayah') refs++;
      }
    }
    return MiraclesCount(_articles.length, _categories.length, refs);
  }
}
