import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import '_local_json_cache.dart';

class StudentsFirestoreRepository {
  StudentsFirestoreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('students');

  static final LocalJsonCache _cache = LocalJsonCache('students_cache_v1.json');

  static List<Student> _normalizeStudents(Iterable<Student> input) {
    final out = input
        .where((s) => s.id.trim().isNotEmpty)
        .toList(growable: true);
    out.sort((a, b) => _compareIds(a.id, b.id));
    return out;
  }

  static Future<void> _writeCache(List<Student> students) {
    return _cache.writeList(
      students
          .map((s) => <String, Object?>{'id': s.id, 'fullName': s.fullName})
          .toList(growable: false),
    );
  }

  Stream<List<Student>> watchAllStudents() async* {
    final cached = await _cache.readList<Student>((json) {
      if (json is! Map) return const Student(id: '', fullName: '');
      final id = (json['id'] as String?)?.trim() ?? '';
      final fullName = (json['fullName'] as String?)?.trim() ?? '';
      return Student(id: id, fullName: fullName);
    });

    final cachedClean = _normalizeStudents(cached);
    if (cachedClean.isNotEmpty) {
      yield cachedClean;
    }

    // Keep streaming server updates, but don't let transient offline errors
    // kill the stream (cache should still work).
    try {
      await for (final snap in _col.snapshots()) {
        final students = _normalizeStudents(
          snap.docs.map(
            (d) => Student(
              id: d.id,
              fullName: (d.data()['fullName'] as String?)?.trim() ?? '',
            ),
          ),
        );

        await _writeCache(students);
        yield students;
      }
    } catch (_) {
      // Ignore; cache already yielded and will be used next time.
    }
  }

  static int _compareIds(String a, String b) {
    final aTrim = a.trim();
    final bTrim = b.trim();

    final re = RegExp(r'^(\D*)(\d+)$');
    final ma = re.firstMatch(aTrim);
    final mb = re.firstMatch(bTrim);
    if (ma != null && mb != null) {
      final pa = (ma.group(1) ?? '').toLowerCase();
      final pb = (mb.group(1) ?? '').toLowerCase();
      final p = pa.compareTo(pb);
      if (p != 0) return p;

      final na = int.tryParse(ma.group(2) ?? '');
      final nb = int.tryParse(mb.group(2) ?? '');
      if (na != null && nb != null) {
        final n = na.compareTo(nb);
        if (n != 0) return n;
      }
    }

    return aTrim.toLowerCase().compareTo(bTrim.toLowerCase());
  }

  Future<void> upsertStudent({
    required String id,
    required String fullName,
  }) async {
    final studentId = id.trim();
    final name = fullName.trim();
    if (studentId.isEmpty) {
      throw ArgumentError('Student id is empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('Student fullName is empty');
    }

    // Optimistic local cache update (offline-friendly).
    final cached = await _cache.readList<Student>((json) {
      if (json is! Map) return const Student(id: '', fullName: '');
      final id = (json['id'] as String?)?.trim() ?? '';
      final fullName = (json['fullName'] as String?)?.trim() ?? '';
      return Student(id: id, fullName: fullName);
    });
    final map = <String, Student>{
      for (final s in cached)
        if (s.id.trim().isNotEmpty) s.id: s,
    };
    map[studentId] = Student(id: studentId, fullName: name);
    await _writeCache(_normalizeStudents(map.values));

    await _col.doc(studentId).set({
      'fullName': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteStudent(String id) async {
    final studentId = id.trim();
    if (studentId.isEmpty) {
      throw ArgumentError('Student id is empty');
    }

    final cached = await _cache.readList<Student>((json) {
      if (json is! Map) return const Student(id: '', fullName: '');
      final id = (json['id'] as String?)?.trim() ?? '';
      final fullName = (json['fullName'] as String?)?.trim() ?? '';
      return Student(id: id, fullName: fullName);
    });
    final map = <String, Student>{
      for (final s in cached)
        if (s.id.trim().isNotEmpty) s.id: s,
    };
    map.remove(studentId);
    await _writeCache(_normalizeStudents(map.values));

    await _col.doc(studentId).delete();
  }
}
