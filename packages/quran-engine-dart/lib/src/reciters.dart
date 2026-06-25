/// Reciter directory built from parsed `data/reciters.json`.
import 'models.dart';

/// A sorted, indexed directory of reciters.
class Reciters {
  /// All reciters, sorted by name.
  final List<Reciter> list;
  final Map<String, Reciter> _byId;

  Reciters(List<Reciter> reciters)
      : list = ([...reciters]..sort((a, b) => a.name.compareTo(b.name))),
        _byId = {for (final r in reciters) r.id: r};

  /// Build from already-decoded `data/reciters.json`.
  factory Reciters.fromJson(List<dynamic> json) => Reciters(
      json.map((e) => Reciter.fromJson(e as Map<String, dynamic>)).toList());

  /// All reciters in name order.
  List<Reciter> all() => list;

  /// Lookup by id.
  Reciter? byId(String id) => _byId[id];

  /// Reciters that have a usable full-surah feed.
  List<Reciter> withSurahFeed() => list
      .where((r) => r.surahLink.isNotEmpty && !r.surahLink.endsWith('.mp3'))
      .toList();

  /// Reciters for a given riwayah label (null/"hafs" => default Hafs feeds).
  List<Reciter> byQiraah(String? qiraah) {
    if (qiraah == null || qiraah.toLowerCase() == 'hafs') {
      return list.where((r) => r.qiraah == null).toList();
    }
    return list.where((r) => r.qiraah == qiraah).toList();
  }

  /// Distinct riwayah labels available (excluding default Hafs).
  List<String> qiraat() {
    final seen = <String>{};
    final out = <String>[];
    for (final r in list) {
      final q = r.qiraah;
      if (q != null && seen.add(q)) out.add(q);
    }
    return out;
  }
}
