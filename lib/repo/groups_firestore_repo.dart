import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import '_local_json_cache.dart';

class GroupsFirestoreRepository {
  GroupsFirestoreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('groups');

  static final LocalJsonCache _cache = LocalJsonCache('groups_cache_v1.json');

  static List<StudentGroup> _normalizeGroups(Iterable<StudentGroup> input) {
    final out = input
        .where((g) => g.id.trim().isNotEmpty)
        .toList(growable: true);
    out.sort(_compareGroups);
    return out;
  }

  static Future<void> _writeCache(List<StudentGroup> groups) {
    return _cache.writeList(
      groups
          .map(
            (g) => <String, Object?>{
              'id': g.id,
              'name': g.name,
              'studentIds': g.studentIds,
            },
          )
          .toList(growable: false),
    );
  }

  static StudentGroup _groupFromCacheJson(Object? json) {
    if (json is! Map) {
      return const StudentGroup(id: '', name: null, studentIds: <String>[]);
    }
    final id = (json['id'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim();
    final studentIdsRaw = json['studentIds'];
    final studentIds = <String>[];
    if (studentIdsRaw is List) {
      for (final v in studentIdsRaw) {
        final s = (v is String) ? v.trim() : '';
        if (s.isNotEmpty) studentIds.add(s);
      }
    }
    studentIds.sort();
    return StudentGroup(
      id: id,
      name: name?.isEmpty ?? true ? null : name,
      studentIds: studentIds,
    );
  }

  Stream<List<StudentGroup>> watchGroups() async* {
    final cached = await _cache.readList<StudentGroup>(_groupFromCacheJson);
    final cachedClean = _normalizeGroups(cached);
    if (cachedClean.isNotEmpty) {
      yield cachedClean;
    }

    try {
      await for (final snap in _col.snapshots()) {
        final groups = _normalizeGroups(
          snap.docs.map((d) {
            final data = d.data();
            return StudentGroup(
              id: d.id,
              name: (data['name'] as String?)?.trim(),
              studentIds: _readStudentIds(data['studentIds']),
            );
          }),
        );

        await _writeCache(groups);
        yield groups;
      }
    } catch (_) {
      // Ignore; cache already yielded and will be used next time.
    }
  }

  Future<void> upsertGroup({
    required String number,
    required List<String> studentIds,
    String? name,
  }) async {
    final groupId = _normalizeGroupId(number);
    if (groupId.isEmpty) throw ArgumentError('group id is empty');

    final parts = _tryParseGroupId(groupId);
    if (parts != null && parts.number == '00') {
      throw ArgumentError('group number cannot be 00');
    }

    final doc = _col.doc(groupId);

    final unique =
        studentIds
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    // Optimistic cache update.
    final cached = await _cache.readList<StudentGroup>(_groupFromCacheJson);
    final map = <String, StudentGroup>{
      for (final g in cached)
        if (g.id.trim().isNotEmpty) g.id: g,
    };
    map[groupId] = StudentGroup(
      id: groupId,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
      studentIds: unique,
    );
    await _writeCache(_normalizeGroups(map.values));

    await doc.set({
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (parts != null) ...{
        'faculty': parts.faculty,
        'year': parts.year,
        'number': parts.number,
      },
      'studentIds': unique,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> upsertGroupName({
    required String id,
    required String name,
  }) async {
    final groupId = _normalizeGroupId(id);
    if (groupId.isEmpty) throw ArgumentError('group id is empty');

    final cached = await _cache.readList<StudentGroup>(_groupFromCacheJson);
    final map = <String, StudentGroup>{
      for (final g in cached)
        if (g.id.trim().isNotEmpty) g.id: g,
    };
    final existing = map[groupId];
    map[groupId] = StudentGroup(
      id: groupId,
      name: name.trim(),
      studentIds: existing?.studentIds ?? const <String>[],
    );
    await _writeCache(_normalizeGroups(map.values));

    await _col.doc(groupId).set({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteGroup(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) throw ArgumentError('groupId is empty');

    final cached = await _cache.readList<StudentGroup>(_groupFromCacheJson);
    final map = <String, StudentGroup>{
      for (final g in cached)
        if (g.id.trim().isNotEmpty) g.id: g,
    };
    map.remove(id);
    await _writeCache(_normalizeGroups(map.values));

    await _col.doc(id).delete();
  }

  static List<String> _readStudentIds(Object? raw) {
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final v in raw) {
      final s = (v is String) ? v.trim() : '';
      if (s.isEmpty) continue;
      ids.add(s);
    }
    final unique = ids.toSet().toList()..sort();
    return unique;
  }

  static String _normalizeGroupId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    // New format: FACULTY-YY-NN (example: CIE-25-17)
    final t = trimmed.toUpperCase();
    final m = RegExp(r'^([A-Z0-9]{2,10})-(\d{2})-(\d{2})$').firstMatch(t);
    if (m != null) {
      final faculty = m.group(1)!;
      final year = m.group(2)!;
      final number = m.group(3)!;
      return '$faculty-$year-$number';
    }

    // Backward compatibility: numeric ids like "001".
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      final n = int.tryParse(trimmed);
      if (n == null) return trimmed;
      if (n < 0) return trimmed;
      return n.toString().padLeft(3, '0');
    }

    return trimmed;
  }

  static ({String faculty, String year, String number})? _tryParseGroupId(
    String groupId,
  ) {
    final m = RegExp(
      r'^([A-Z0-9]{2,10})-(\d{2})-(\d{2})$',
    ).firstMatch(groupId.trim().toUpperCase());
    if (m == null) return null;
    return (faculty: m.group(1)!, year: m.group(2)!, number: m.group(3)!);
  }

  static int _compareGroups(StudentGroup a, StudentGroup b) {
    final pa = _tryParseGroupId(a.id);
    final pb = _tryParseGroupId(b.id);
    if (pa != null && pb != null) {
      // Desc by year, so 26 is above 14.
      final ya = int.tryParse(pa.year) ?? 0;
      final yb = int.tryParse(pb.year) ?? 0;
      final yc = yb.compareTo(ya);
      if (yc != 0) return yc;

      final fc = pa.faculty.compareTo(pb.faculty);
      if (fc != 0) return fc;

      final na = int.tryParse(pa.number) ?? 0;
      final nb = int.tryParse(pb.number) ?? 0;
      return na.compareTo(nb);
    }

    final na = int.tryParse(a.id);
    final nb = int.tryParse(b.id);
    if (na != null && nb != null) return na.compareTo(nb);

    return a.id.toLowerCase().compareTo(b.id.toLowerCase());
  }
}
