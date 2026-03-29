import 'package:cloud_firestore/cloud_firestore.dart';

class FacultiesFirestoreRepository {
  FacultiesFirestoreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('faculties');

  Stream<List<String>> watchFaculties() {
    return _col.snapshots().map((snap) {
      final codes = snap.docs
          .map((d) => d.id.trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList(growable: true);
      codes.sort();
      return codes;
    });
  }

  Future<void> upsertFaculty(String code) {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) throw ArgumentError('faculty code is empty');

    return _col.doc(normalized).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _normalizeCode(String raw) {
    final upper = raw.trim().toUpperCase();
    if (upper.isEmpty) return '';

    // Keep only letters/digits.
    final cleaned = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned;
  }
}
