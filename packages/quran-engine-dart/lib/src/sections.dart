// Where a surah changes subject: an outline of each surah as titled ayah ranges,
// plus one sentence saying what the surah as a whole is about.
//
// This answers "I am at 18:60 - what is this passage doing here", which neither
// the translation nor the tafsir answers quickly, because both are written per
// ayah. 111 of the 114 surahs carry an outline; al-Fatihah, Fussilat and
// ad-Dukhan do not.
//
// THE OUTLINE IS A TREE, FLATTENED. Ranges are inclusive, in mushaf order, and
// MAY NEST: a broad section is followed by the sections inside it, parent before
// children (Hud opens with 1-24 "Doctrine facts", then 1-4, 5-6, 7-11, 12-17,
// 18-24 within it). They also do not tile the surah - an ayah can belong to no
// section at all. So an ayah has a CHAIN of sections, outermost first, which is
// what [SurahSections.sectionsFor] returns; [SurahSections.outline] rebuilds it
// as a tree.
//
// See `../../docs/15-surah-sections.md`.

/// One titled range of ayahs. [from] and [to] are inclusive.
class SurahSection {
  final int from;
  final int to;
  final String english;
  final String arabic;

  const SurahSection(this.from, this.to, this.english, this.arabic);

  bool contains(int ayahId) => ayahId >= from && ayahId <= to;
}

/// A section with the sections inside it.
class OutlineNode {
  final SurahSection section;
  final List<OutlineNode> children;

  OutlineNode(this.section, [List<OutlineNode>? children])
      : children = children ?? <OutlineNode>[];
}

/// A section paired with the surah it belongs to.
class SectionHit {
  final int surah;
  final SurahSection section;
  const SectionHit(this.surah, this.section);
}

class SurahSections {
  final Map<String, dynamic> _data;

  const SurahSections([this._data = const {}]);

  /// One sentence on what the whole surah is about, `''` when none is recorded.
  String overview(int surahId) =>
      (_data['$surahId'] as Map<String, dynamic>?)?['overview'] as String? ?? '';

  /// The surah's sections, flat and in the order the source records them (a
  /// parent immediately before the sections inside it).
  List<SurahSection> sections(int surahId) {
    final rows = (_data['$surahId'] as Map<String, dynamic>?)?['sections'] as List<dynamic>?;
    if (rows == null) return const [];
    final out = <SurahSection>[];
    for (final raw in rows) {
      // [from, to, english, arabic] - heterogeneous, so read positionally.
      final row = raw as List<dynamic>;
      if (row.length < 4) continue;
      out.add(SurahSection(
          row[0] as int, row[1] as int, row[2] as String, row[3] as String));
    }
    return out;
  }

  /// The same sections as a tree: top-level passages, each with what is inside it.
  List<OutlineNode> outline(int surahId) {
    final roots = <OutlineNode>[];
    final open = <OutlineNode>[];
    for (final section in sections(surahId)) {
      // A section belongs to the nearest still-open range that fully contains it.
      while (open.isNotEmpty &&
          !(open.last.section.from <= section.from &&
              section.to <= open.last.section.to)) {
        open.removeLast();
      }
      final node = OutlineNode(section);
      (open.isEmpty ? roots : open.last.children).add(node);
      open.add(node);
    }
    return roots;
  }

  /// Every section covering an ayah, outermost first - the breadcrumb for "you
  /// are here". Empty when the surah has no outline, or when this ayah falls
  /// between sections.
  List<SurahSection> sectionsFor(int surahId, int ayahId) =>
      sections(surahId).where((s) => s.contains(ayahId)).toList(growable: false);

  /// The most specific section covering an ayah - the heading a reader wants
  /// beside the verse.
  SurahSection? sectionFor(int surahId, int ayahId) {
    final chain = sectionsFor(surahId, ayahId);
    return chain.isEmpty ? null : chain.last;
  }

  /// Whether this surah has an outline at all.
  bool hasSections(int surahId) {
    final rows = (_data['$surahId'] as Map<String, dynamic>?)?['sections'] as List<dynamic>?;
    return rows != null && rows.isNotEmpty;
  }

  /// How many surahs carry an outline.
  int count() => _data.keys
      .where((k) => hasSections(int.tryParse(k) ?? -1))
      .length;

  /// Sections whose title carries [query], across every surah.
  List<SectionHit> search(String query) {
    final trimmed = query.trim();
    final needle = trimmed.toLowerCase();
    if (needle.isEmpty) return const [];
    final out = <SectionHit>[];
    final ids = _data.keys.map(int.parse).toList()..sort();
    for (final id in ids) {
      for (final section in sections(id)) {
        if (section.english.toLowerCase().contains(needle) ||
            section.arabic.contains(trimmed)) {
          out.add(SectionHit(id, section));
        }
      }
    }
    return out;
  }
}
