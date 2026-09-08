/// Who among the Ten reads a word differently, what they read, and what the
/// difference means.
///
/// This is the layer the qiraah texts cannot supply. `data/qiraat/` gives each
/// reading its own words, and `QiraatComparison` will align two of them: that
/// answers WHAT each riwayah reads. It cannot say that a form is Hamzah's rather
/// than Nafi's, that it is a passive where Hafs has an active, or that
/// al-Mahdawi held the two to mean the same thing. That is this module, from the
/// Quran.com qiraat matrix.
///
/// Readers against transmitters: a reading lists [VariantReading.readers] when
/// both of an imam's transmitters follow it, and [VariantReading.transmitters]
/// when the two part company. Segment ranges are 0-based inclusive token indices
/// of the raw Hafs text, null where the builder could not place the word, in
/// which case a consumer shows the word untinted rather than guessing.
///
/// Only the eight riwayat whose text this engine publishes appear in
/// [QiraatVariants.places]. The other twelve do appear as attributions, which is
/// right: attributing a reading to Ibn Dhakwan says nothing about the state of
/// his extracted text.
///
/// See `../../docs/21-qiraat-variants.md`.

/// One of the ten imams.
class VariantReader {
  final int id;
  final String name;
  final String abbreviation;
  final String city;
  final int position;

  const VariantReader({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.city,
    required this.position,
  });
}

/// One of the twenty riwayat.
class VariantTransmitter {
  final int id;
  final String name;
  final int reader;

  /// This engine's own slug, so a consumer can join to `data/qiraat` and
  /// `data/mushaf`.
  final String? riwayah;

  /// False for the twelve riwayat whose extracted text is not published.
  final bool textPublished;

  const VariantTransmitter({
    required this.id,
    required this.name,
    required this.reader,
    required this.riwayah,
    required this.textPublished,
  });
}

/// One form of a word, and who reads it.
class VariantReading {
  final String text;
  final String transliteration;
  final String english;
  final String explanation;
  final String grammaticalForm;
  final String rootLetters;

  /// Imams whose two transmitters both read it.
  final List<int> readers;

  /// Individual transmitters, where an imam's two differ.
  final List<int> transmitters;

  const VariantReading({
    required this.text,
    required this.transliteration,
    required this.english,
    required this.explanation,
    required this.grammaticalForm,
    required this.rootLetters,
    required this.readers,
    required this.transmitters,
  });
}

/// Where the word sits. [span] is null where the builder could not place it.
class VariantSegment {
  final String ayah;
  final List<int>? span;

  const VariantSegment(this.ayah, this.span);
}

/// One word of an ayah that the Ten read differently.
class Juncture {
  final int id;
  final String word;
  final String category;
  final List<VariantSegment> segments;
  final List<VariantReading> readings;
  final String note;

  const Juncture({
    required this.id,
    required this.word,
    required this.category,
    required this.segments,
    required this.readings,
    required this.note,
  });
}

/// One ayah where a riwayah differs from Hafs.
///
/// Two kinds, because they are found two ways and a consumer may want only the
/// first: a [word] index is a word dropped, added or spelled differently, which
/// a text diff finds; a [letter] index is a word the printed mushaf marks as
/// read with other vowels over the SAME skeleton, which no text diff can see
/// (مَلِكِ against مَٰلِكِ in al-Fatihah).
class QiraatPlace {
  final int ayah;
  final List<int> word;
  final List<int> letter;

  const QiraatPlace(this.ayah, this.word, this.letter);
}

/// One side of a paired recording. [startMs] and [endMs] are null for a whole
/// per-verse file.
class VariantClip {
  final String url;
  final int? startMs;
  final int? endMs;

  const VariantClip(this.url, this.startMs, this.endMs);
}

/// The same reciter reading a verse both ways.
class VariantAudioPair {
  final String reciter;
  final VariantClip hafs;
  final VariantClip riwayah;

  const VariantAudioPair(this.reciter, this.hafs, this.riwayah);
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');

class QiraatVariants {
  final Map<String, dynamic> _variants;
  final Map<String, dynamic> _places;
  final Map<String, dynamic> _audio;

  const QiraatVariants({
    Map<String, dynamic> variants = const {},
    Map<String, dynamic> places = const {},
    Map<String, dynamic> audio = const {},
  })  : _variants = variants,
        _places = places,
        _audio = audio;

  Map<String, dynamic> get _ayahs =>
      _variants['ayahs'] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _readers =>
      _variants['readers'] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _transmitters =>
      _variants['transmitters'] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _placeRiwayat =>
      _places['riwayat'] as Map<String, dynamic>? ?? const {};

  List<dynamic> get _audioSources =>
      _audio['sources'] as List<dynamic>? ?? const [];

  Map<String, dynamic> get _audioRiwayat =>
      _audio['riwayat'] as Map<String, dynamic>? ?? const {};

  bool get isLoaded => _ayahs.isNotEmpty;

  /// The words of this ayah that the Ten read differently, in corpus order.
  List<Juncture> junctures(int surahId, int ayahId) {
    final rows = _ayahs['$surahId:$ayahId'] as List<dynamic>? ?? const [];
    return List.generate(rows.length, (i) {
      final row = rows[i] as Map<String, dynamic>;
      return Juncture(
        id: i,
        word: row['word'] as String? ?? '',
        category: row['category'] as String? ?? '',
        segments: (row['segments'] as List<dynamic>? ?? const []).map((raw) {
          final segment = raw as Map<String, dynamic>;
          final span = segment['span'] as List<dynamic>?;
          return VariantSegment(
              segment['ayah'] as String, span?.cast<int>());
        }).toList(growable: false),
        readings: (row['readings'] as List<dynamic>? ?? const []).map((raw) {
          final reading = raw as Map<String, dynamic>;
          return VariantReading(
            text: reading['text'] as String? ?? '',
            transliteration: reading['transliteration'] as String? ?? '',
            english: reading['english'] as String? ?? '',
            explanation: reading['explanation'] as String? ?? '',
            grammaticalForm: reading['grammaticalForm'] as String? ?? '',
            rootLetters: reading['rootLetters'] as String? ?? '',
            readers: (reading['readers'] as List<dynamic>? ?? const []).cast<int>(),
            transmitters:
                (reading['transmitters'] as List<dynamic>? ?? const []).cast<int>(),
          );
        }).toList(growable: false),
        note: row['note'] as String? ?? '',
      );
    });
  }

  /// Whether the ayah carries any. Only 1,409 of the 6,236 do.
  bool has(int surahId, int ayahId) {
    final rows = _ayahs['$surahId:$ayahId'] as List<dynamic>?;
    return rows != null && rows.isNotEmpty;
  }

  VariantReader? reader(int id) {
    final row = _readers['$id'] as Map<String, dynamic>?;
    if (row == null) return null;
    return VariantReader(
      id: row['id'] as int,
      name: row['name'] as String,
      abbreviation: row['abbreviation'] as String? ?? row['name'] as String,
      city: row['city'] as String? ?? '',
      position: row['position'] as int? ?? 99,
    );
  }

  VariantTransmitter? transmitter(int id) {
    final row = _transmitters['$id'] as Map<String, dynamic>?;
    if (row == null) return null;
    return VariantTransmitter(
      id: row['id'] as int,
      name: row['name'] as String,
      reader: row['reader'] as int,
      riwayah: row['riwayah'] as String?,
      textPublished: row['textPublished'] as bool? ?? false,
    );
  }

  /// Every transmitter reading a form: an imam's own pair, plus any listed
  /// individually.
  List<VariantTransmitter> transmittersFollowing(VariantReading reading) {
    final out = <VariantTransmitter>[];
    final seen = <int>{};
    for (final readerId in reading.readers) {
      final ids = <int>[];
      _transmitters.forEach((_, raw) {
        final row = raw as Map<String, dynamic>;
        if (row['reader'] == readerId) ids.add(row['id'] as int);
      });
      ids.sort();
      for (final id in ids) {
        if (seen.add(id)) {
          final found = transmitter(id);
          if (found != null) out.add(found);
        }
      }
    }
    for (final id in reading.transmitters) {
      if (seen.contains(id)) continue;
      final found = transmitter(id);
      if (found != null) {
        seen.add(id);
        out.add(found);
      }
    }
    return out;
  }

  /// The reading a riwayah follows at a juncture, by engine slug.
  VariantReading? readingFor(Juncture juncture, String riwayah) {
    for (final reading in juncture.readings) {
      if (transmittersFollowing(reading).any((t) => t.riwayah == riwayah)) {
        return reading;
      }
    }
    return null;
  }

  /// Who reads a form, rendered the way the printed sources do: the imams first
  /// in their canonical order, then any lone transmitters with their imam named
  /// in parentheses.
  String attribution(VariantReading reading) {
    final readers = reading.readers
        .map(reader)
        .whereType<VariantReader>()
        .toList()
      ..sort((a, b) => a.position - b.position);
    final transmitters = reading.transmitters
        .map(transmitter)
        .whereType<VariantTransmitter>()
        .toList()
      ..sort((a, b) {
        final pa = reader(a.reader)?.position ?? 99;
        final pb = reader(b.reader)?.position ?? 99;
        return pa != pb ? pa - pb : a.id - b.id;
      });
    final parts = <String>[];
    if (readers.isNotEmpty) {
      parts.add(readers.map((r) => r.abbreviation).join(', '));
    }
    if (transmitters.isNotEmpty) {
      parts.add(transmitters.map((t) {
        final imam = reader(t.reader)?.abbreviation ?? '';
        return imam.isEmpty ? t.name : '${t.name} ($imam)';
      }).join(', '));
    }
    return parts.join(' · ');
  }

  /// Where a riwayah differs from Hafs in a surah, in ayah order.
  List<QiraatPlace> places(String riwayah, int surahId) {
    final surahs = _placeRiwayat[riwayah] as Map<String, dynamic>?;
    final table = surahs?['$surahId'] as Map<String, dynamic>?;
    if (table == null) return const [];
    final ayahs = table.keys.map(int.parse).toList()..sort();
    return ayahs.map((ayah) {
      final row = table['$ayah'] as Map<String, dynamic>;
      return QiraatPlace(
        ayah,
        (row['word'] as List<dynamic>? ?? const []).cast<int>(),
        (row['letter'] as List<dynamic>? ?? const []).cast<int>(),
      );
    }).toList(growable: false);
  }

  /// The riwayat [places] can answer for: the published ones.
  List<String> riwayatWithPlaces() => _placeRiwayat.keys.toList()..sort();

  /// One reciter reading the verse both ways, for the four riwayat where such a
  /// recording exists.
  ///
  /// The rest carry none: no reciter published both sides with timings. A pair
  /// drawn from two shaykhs would differ in voice, pace and maqam as well, and
  /// teach nothing about the variant. The honest rendering is "no recording",
  /// never a button that does nothing.
  VariantAudioPair? audio(String riwayah, int surahId, int ayahId) {
    final surahs = _audioRiwayat[riwayah] as Map<String, dynamic>?;
    final rows = surahs?['$surahId'] as List<dynamic>?;
    if (rows == null) return null;
    for (final raw in rows) {
      final row = (raw as List<dynamic>).cast<int>();
      if (row.isEmpty || row[0] != ayahId || row.length < 6) continue;
      if (row[1] < 0 || row[1] >= _audioSources.length) return null;
      final source = _audioSources[row[1]] as Map<String, dynamic>;
      final isSpan = source['kind'] == 'span';
      final name = isSpan
          ? '${_pad(surahId, 3)}.mp3'
          : '${_pad(surahId, 3)}${_pad(ayahId, 3)}.mp3';
      VariantClip clip(String base, int start, int end) => VariantClip(
            '$base/$name',
            isSpan ? start : null,
            isSpan ? end : null,
          );
      return VariantAudioPair(
        source['reciter'] as String,
        clip(source['hafsBase'] as String, row[2], row[3]),
        clip(source['riwayahBase'] as String, row[4], row[5]),
      );
    }
    return null;
  }

  /// The riwayat that have any paired recordings at all.
  List<String> riwayatWithAudio() => _audioRiwayat.keys.toList()..sort();

  /// Corpus size: ayahs carrying a variant, junctures, and readings.
  Map<String, int> count() {
    var junctures = 0, readings = 0;
    for (final rows in _ayahs.values) {
      final list = rows as List<dynamic>;
      junctures += list.length;
      for (final row in list) {
        readings +=
            ((row as Map<String, dynamic>)['readings'] as List<dynamic>? ?? const [])
                .length;
      }
    }
    return {'ayahs': _ayahs.length, 'junctures': junctures, 'readings': readings};
  }
}
