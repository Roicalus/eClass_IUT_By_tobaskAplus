import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny JSON file cache for small lists.
///
/// Designed for "cache-first" UX: read cached value immediately, then refresh
/// from network and overwrite cache.
class LocalJsonCache {
  LocalJsonCache(this.fileName);

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<List<T>> readList<T>(T Function(Object? json) fromJson) async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(fromJson).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeList(List<Object?> jsonList) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {
      // Best-effort cache.
    }
  }
}
