// The printed mushaf: twenty riwayat as page-exact facsimiles, and the page
// table each one is actually paginated by.
//
// A riwayah's pagination is NOT Hafs' pagination. Readings merge and split
// ayahs and spell words differently, so the same ayah sits on a different page
// in Warsh's print than in Hafs'. The page numbers on `quran.json`'s ayahs are
// the Madani (Hafs) ones; [Mushaf.page] is that riwayah's own. Every facsimile
// is exactly 604 pages on the Madani division, so PDF page N is mushaf page N
// with no offset table.
//
// Twelve of the twenty ship their printed mushaf and page table but no text:
// their text is machine-extracted and not yet proofread, so it is not
// published, and the line and tajweed data that index into it stay out with it.
// [RiwayahEntry.textIncluded] says which is which.
//
// See `../../docs/10-mushaf.md`.
// A surah+ayah pair by number: what the page tables index and return.

class VerseRef {
  final int surah;
  final int ayah;
  const VerseRef(this.surah, this.ayah);

  @override
  bool operator ==(Object other) =>
      other is VerseRef && other.surah == surah && other.ayah == ayah;

  @override
  int get hashCode => Object.hash(surah, ayah);

  @override
  String toString() => '$surah:$ayah';
}

/// One row of `data/mushaf/index.json`.

class RiwayahEntry {
  /// Slug, e.g. `"warsh"`.
  final String riwayah;

  /// The tag the Al-Islam app stores for this riwayah (`""` for Hafs).
  final String tag;
  final String name;
  final String nameArabic;

  /// The qiraah's imam, e.g. `"Nafi"`.
  final String imam;
  final String imamArabic;
  final int narratorDiedAH;

  /// Path to the facsimile, relative to `data/mushaf/`. One solid xz stream
  /// over the PDF: decompress it before handing the bytes to a renderer.
  final String pdf;
  final int pdfBytes;
  final String pages;

 /// Null when the riwayah's text (and so its line table), is not published.
  final String? lines;

  /// Null when the riwayah has no tajweed pack.
  final String? tajweed;
  final bool textIncluded;

  const RiwayahEntry({
    required this.riwayah,
    required this.tag,
    required this.name,
    required this.nameArabic,
    required this.imam,
    required this.imamArabic,
    required this.narratorDiedAH,
    required this.pdf,
    required this.pdfBytes,
    required this.pages,
    required this.lines,
    required this.tajweed,
    required this.textIncluded,
  });

  factory RiwayahEntry.fromJson(Map<String, dynamic> json) => RiwayahEntry(
        riwayah: json['riwayah'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameArabic: json['nameArabic'] as String? ?? '',
        imam: json['imam'] as String? ?? '',
        imamArabic: json['imamArabic'] as String? ?? '',
        // The JSON spells this with a trailing capital AH, unlike every other key.
        narratorDiedAH: json['narratorDiedAH'] as int? ?? 0,
        pdf: json['pdf'] as String? ?? '',
        pdfBytes: json['pdfBytes'] as int? ?? 0,
        pages: json['pages'] as String? ?? '',
        lines: json['lines'] as String?,
        tajweed: json['tajweed'] as String?,
        textIncluded: json['textIncluded'] as bool? ?? false,
      );
}

class Mushaf {
  final List<RiwayahEntry> _riwayat;
  final int _totalPages;
  final Map<String, RiwayahEntry> _byRiwayah;

  /// slug -> surah id -> ayah id -> page.
  final Map<String, Map<String, Map<String, int>>> _pages;

  /// slug -> surah id -> ayah id -> the offsets a printed line starts at.
  final Map<String, Map<String, Map<String, List<int>>>> _lines;

  /// Inverted page -> ayahs, built the first time a riwayah is asked.
  final Map<String, Map<int, List<VerseRef>>> _onPage = {};

  Mushaf({
    Map<String, dynamic>? index,
    Map<String, Map<String, dynamic>> pages = const {},
    Map<String, Map<String, dynamic>> lines = const {},
  })  : _riwayat = ((index?['riwayat'] as List<dynamic>?) ?? const [])
            .map((e) => RiwayahEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        _totalPages = index?['totalPages'] as int? ?? 604,
        _byRiwayah = {},
        _pages = {
          for (final entry in pages.entries)
            entry.key: _intTable(entry.value['pages'] as Map<String, dynamic>?),
        },
        _lines = {
          for (final entry in lines.entries)
            entry.key:
                _listTable(entry.value['lineBreaks'] as Map<String, dynamic>?),
        } {
    for (final entry in _riwayat) {
      _byRiwayah[entry.riwayah] = entry;
    }
  }

  static Map<String, Map<String, int>> _intTable(Map<String, dynamic>? raw) => {
        for (final surah in (raw ?? const {}).entries)
          surah.key: {
            for (final ayah in (surah.value as Map<String, dynamic>).entries)
              ayah.key: ayah.value as int,
          },
      };

  static Map<String, Map<String, List<int>>> _listTable(
          Map<String, dynamic>? raw) =>
      {
        for (final surah in (raw ?? const {}).entries)
          surah.key: {
            for (final ayah in (surah.value as Map<String, dynamic>).entries)
              ayah.key: (ayah.value as List<dynamic>).cast<int>(),
          },
      };

  /// Every riwayah, in the classical order of the Ten Qiraat.
  List<RiwayahEntry> riwayat() => _riwayat;

  /// Only the riwayat whose text this engine publishes (the eight verified ones).
  List<RiwayahEntry> riwayatWithText() =>
      _riwayat.where((r) => r.textIncluded).toList(growable: false);

  RiwayahEntry? riwayah(String slug) => _byRiwayah[slug];

  /// 604 for every facsimile in the set.
  int totalPages() => _totalPages;

  /// The facsimile's path, relative to `data/mushaf/`.
  String? pdfPath(String slug) => _byRiwayah[slug]?.pdf;

  /// The page an ayah is printed on in this riwayah's own mushaf.
  int? page(int surahId, int ayahId, [String riwayah = 'hafs']) =>
      _pages[riwayah]?['$surahId']?['$ayahId'];

  /// Every ayah printed on a page of this riwayah's mushaf, in mushaf order.
  List<VerseRef> ayahsOnPage(int page, [String riwayah = 'hafs']) =>
      _pageIndex(riwayah)[page] ?? const [];

  /// What a "go to page 213" jump lands on.
  VerseRef? firstAyahOfPage(int page, [String riwayah = 'hafs']) {
    final hits = ayahsOnPage(page, riwayah);
    return hits.isEmpty ? null : hits.first;
  }

  /// The character offsets into the ayah's own text at which this riwayah's
  /// print starts a new line. Null when the text is not published.
  List<int>? lineBreaks(int surahId, int ayahId, [String riwayah = 'hafs']) =>
      _lines[riwayah]?['$surahId']?['$ayahId'];

  /// Whether `tajweed-qiraat/<slug>.json` exists for this riwayah.
  bool hasTajweedPack(String riwayah) => _byRiwayah[riwayah]?.tajweed != null;

  Map<int, List<VerseRef>> _pageIndex(String riwayah) {
    final cached = _onPage[riwayah];
    if (cached != null) return cached;
    final index = <int, List<VerseRef>>{};
    final table = _pages[riwayah] ?? const {};
    final surahs = table.keys.map(int.parse).toList()..sort();
    for (final surah in surahs) {
      final ayahs = table['$surah']!;
      final numbers = ayahs.keys.map(int.parse).toList()..sort();
      for (final ayah in numbers) {
        index.putIfAbsent(ayahs['$ayah']!, () => []).add(VerseRef(surah, ayah));
      }
    }
    _onPage[riwayah] = index;
    return index;
  }
}
