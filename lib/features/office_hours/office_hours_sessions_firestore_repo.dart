import 'package:cloud_firestore/cloud_firestore.dart';

class OfficeHoursTodaySession {
  const OfficeHoursTodaySession({
    required this.dateKey,
    required this.endedAtMillis,
  });

  final String dateKey;
  final int? endedAtMillis;

  bool get isEnded => endedAtMillis != null;

  static OfficeHoursTodaySession fromSnap(
    String dateKey,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    final endedAt = data['endedAt'];
    return OfficeHoursTodaySession(
      dateKey: dateKey,
      endedAtMillis: endedAt is int ? endedAt : null,
    );
  }
}

class OfficeHoursSessionsFirestoreRepository {
  OfficeHoursSessionsFirestoreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc({
    required String ownerUid,
    required String dateKey,
  }) {
    return _firestore
        .collection('teachers')
        .doc(ownerUid)
        .collection('office_hours_sessions')
        .doc(dateKey);
  }

  Stream<OfficeHoursTodaySession> watchToday({
    required String ownerUid,
    required String dateKey,
  }) {
    return _doc(ownerUid: ownerUid, dateKey: dateKey).snapshots().map(
      (snap) => OfficeHoursTodaySession.fromSnap(dateKey, snap),
    );
  }

  Future<void> endToday({
    required String ownerUid,
    required String dateKey,
  }) async {
    await _doc(ownerUid: ownerUid, dateKey: dateKey).set({
      'endedAt': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
