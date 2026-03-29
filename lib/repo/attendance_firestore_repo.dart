import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance.dart';

class AttendanceFirestoreRepository {
  AttendanceFirestoreRepository({
    required this.ownerUid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String ownerUid;

  DocumentReference<Map<String, dynamic>> _doc({
    required String lessonId,
    required String dateKey,
  }) {
    return _firestore
        .collection('teachers')
        .doc(ownerUid)
        .collection('attendance')
        .doc(lessonId)
        .collection('dates')
        .doc(dateKey);
  }

  Stream<Map<String, AttendanceStatus>> watchMarks({
    required String lessonId,
    required String dateKey,
  }) {
    return _doc(lessonId: lessonId, dateKey: dateKey).snapshots().map((snap) {
      final data = snap.data();
      final raw = data?['marks'];
      if (raw is! Map) return const <String, AttendanceStatus>{};

      final out = <String, AttendanceStatus>{};
      raw.forEach((key, value) {
        if (key is! String) return;
        final v = value is String ? value : '';
        final status = switch (v) {
          'present' => AttendanceStatus.present,
          'late' => AttendanceStatus.late,
          _ => null,
        };
        if (status == null) return;
        out[key] = status;
      });

      return out;
    });
  }

  Future<void> setMark({
    required String lessonId,
    required String dateKey,
    required String studentId,
    required AttendanceStatus status,
  }) async {
    final sid = studentId.trim();
    if (sid.isEmpty) throw ArgumentError('studentId is empty');

    final doc = _doc(lessonId: lessonId, dateKey: dateKey);

    final fieldPath = 'marks.$sid';
    if (status == AttendanceStatus.unmarked) {
      // Ensure doc exists, but do not clear the whole marks map.
      await doc.set({
        'lessonId': lessonId,
        'dateKey': dateKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await doc.update({
        fieldPath: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final value = switch (status) {
      AttendanceStatus.present => 'present',
      AttendanceStatus.late => 'late',
      AttendanceStatus.unmarked => null,
    };

    if (value == null) return;

    // IMPORTANT: writing {'marks': {sid: value}} with merge:true still REPLACES
    // the whole 'marks' map. Use a dot-path update so only one student changes.
    await doc.set({
      'lessonId': lessonId,
      'dateKey': dateKey,
      'updatedAt': FieldValue.serverTimestamp(),
      fieldPath: value,
    }, SetOptions(merge: true));
  }
}
