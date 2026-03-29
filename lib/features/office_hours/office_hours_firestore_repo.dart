import 'package:cloud_firestore/cloud_firestore.dart';

class OfficeHoursCallState {
  const OfficeHoursCallState({
    required this.meetUrl,
    required this.startedAt,
    required this.endedAt,
  });

  final String? meetUrl;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isLive => startedAt != null && endedAt == null;

  static OfficeHoursCallState fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};

    DateTime? readTime(Object? v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return OfficeHoursCallState(
      meetUrl: (d['meetUrl'] as String?)?.trim(),
      startedAt: readTime(d['startedAt']),
      endedAt: readTime(d['endedAt']),
    );
  }
}

class OfficeHoursMeeting {
  const OfficeHoursMeeting({
    required this.id,
    required this.time,
    required this.title,
    required this.description,
    required this.isSingle,
    required this.dayIndex,
    this.plannedStartAt,
    this.meetUrl,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String time;
  final String title;
  final String description;
  final bool isSingle;

  /// 0..6 = Monday..Sunday, 7 = Single meeting
  final int dayIndex;

  /// Optional planned start time (useful for single meetings).
  final DateTime? plannedStartAt;

  /// Optional Google Meet URL to open/join.
  final String? meetUrl;

  /// Set when the meeting is started in the app.
  final DateTime? startedAt;

  /// Set when the meeting is ended in the app.
  final DateTime? endedAt;

  bool get isLive => startedAt != null && endedAt == null;

  Map<String, Object?> toFirestore() {
    return {
      'time': time,
      'title': title,
      'description': description,
      'isSingle': isSingle,
      'dayIndex': dayIndex,
      if (plannedStartAt != null)
        'plannedStartAt': Timestamp.fromDate(plannedStartAt!),
      if (meetUrl != null) 'meetUrl': meetUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static OfficeHoursMeeting fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};

    DateTime? readTime(Object? v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return OfficeHoursMeeting(
      id: doc.id,
      time: (d['time'] as String?) ?? '',
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      isSingle: (d['isSingle'] as bool?) ?? false,
      dayIndex: (d['dayIndex'] as int?) ?? 0,
      plannedStartAt: readTime(d['plannedStartAt']),
      meetUrl: (d['meetUrl'] as String?)?.trim(),
      startedAt: readTime(d['startedAt']),
      endedAt: readTime(d['endedAt']),
    );
  }
}

class OfficeHoursChatMessage {
  const OfficeHoursChatMessage({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.text,
    required this.timestamp,
    required this.timestampMs,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String text;
  final DateTime timestamp;
  final int timestampMs;

  static OfficeHoursChatMessage fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['timestamp'];
    DateTime time;
    if (ts is Timestamp) {
      time = ts.toDate();
    } else {
      time = DateTime.fromMillisecondsSinceEpoch(0);
    }

    int ms;
    final rawMs = d['timestampMs'];
    if (rawMs is int) {
      ms = rawMs;
    } else {
      ms = time.millisecondsSinceEpoch;
    }

    return OfficeHoursChatMessage(
      id: doc.id,
      authorUid: (d['authorUid'] as String?) ?? '',
      authorName: (d['authorName'] as String?) ?? 'Unknown',
      text: (d['text'] as String?) ?? '',
      timestamp: time,
      timestampMs: ms,
    );
  }
}

class OfficeHoursFirestoreRepository {
  OfficeHoursFirestoreRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _meetingsCol(String ownerUid) {
    return _db.collection('office_hours').doc(ownerUid).collection('meetings');
  }

  CollectionReference<Map<String, dynamic>> _meetingMessagesCol(
    String ownerUid,
    String meetingId,
  ) {
    return _db
        .collection('office_hours')
        .doc(ownerUid)
        .collection('meetings')
        .doc(meetingId)
        .collection('messages');
  }

  DocumentReference<Map<String, dynamic>> _globalStateDoc(String ownerUid) {
    return _db
        .collection('office_hours')
        .doc(ownerUid)
        .collection('global')
        .doc('state');
  }

  CollectionReference<Map<String, dynamic>> _globalMessagesCol(
    String ownerUid,
  ) {
    return _globalStateDoc(ownerUid).collection('messages');
  }

  Stream<List<OfficeHoursMeeting>> watchMeetings(String ownerUid) {
    // Avoid composite-index requirements by sorting client-side.
    return _meetingsCol(ownerUid).snapshots().map((s) {
      final items = s.docs
          .map(OfficeHoursMeeting.fromDoc)
          .toList(growable: true);
      items.sort((a, b) {
        final d = a.dayIndex.compareTo(b.dayIndex);
        if (d != 0) return d;

        // For single meetings, prefer sorting by plannedStartAt.
        if (a.dayIndex == 7 && b.dayIndex == 7) {
          final ap = a.plannedStartAt;
          final bp = b.plannedStartAt;
          if (ap != null && bp != null) {
            final c = ap.compareTo(bp);
            if (c != 0) return c;
          }
        }

        int? toMinutes(String raw) {
          final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
          if (m == null) return null;
          final hh = int.tryParse(m.group(1) ?? '');
          final mm = int.tryParse(m.group(2) ?? '');
          if (hh == null || mm == null) return null;
          if (hh < 0 || hh > 23) return null;
          if (mm < 0 || mm > 59) return null;
          return hh * 60 + mm;
        }

        final am = toMinutes(a.time);
        final bm = toMinutes(b.time);
        if (am != null && bm != null) return am.compareTo(bm);

        return a.time.toLowerCase().compareTo(b.time.toLowerCase());
      });
      return items;
    });
  }

  Stream<OfficeHoursMeeting?> watchMeeting({
    required String ownerUid,
    required String meetingId,
  }) {
    return _meetingsCol(ownerUid).doc(meetingId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return OfficeHoursMeeting.fromDoc(doc);
    });
  }

  Future<void> upsertMeeting(
    String ownerUid,
    OfficeHoursMeeting meeting,
  ) async {
    final map = meeting.toFirestore();

    if (meeting.id.isEmpty) {
      await _meetingsCol(
        ownerUid,
      ).add({...map, 'createdAt': FieldValue.serverTimestamp()});
      return;
    }

    await _meetingsCol(ownerUid).doc(meeting.id).set({
      ...map,
      // Allow clearing fields from the editor.
      'plannedStartAt': meeting.plannedStartAt == null
          ? FieldValue.delete()
          : Timestamp.fromDate(meeting.plannedStartAt!),
      'meetUrl': (meeting.meetUrl == null || meeting.meetUrl!.trim().isEmpty)
          ? FieldValue.delete()
          : meeting.meetUrl!.trim(),
    }, SetOptions(merge: true));
  }

  Future<void> updateMeetUrl({
    required String ownerUid,
    required String meetingId,
    required String? meetUrl,
  }) async {
    final trimmed = meetUrl?.trim();
    await _meetingsCol(ownerUid).doc(meetingId).set({
      'meetUrl': (trimmed == null || trimmed.isEmpty)
          ? FieldValue.delete()
          : trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startMeeting({
    required String ownerUid,
    required String meetingId,
  }) async {
    await _meetingsCol(ownerUid).doc(meetingId).set({
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> endMeeting({
    required String ownerUid,
    required String meetingId,
  }) async {
    await _meetingsCol(ownerUid).doc(meetingId).set({
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMeeting(String ownerUid, String meetingId) async {
    await _meetingsCol(ownerUid).doc(meetingId).delete();
  }

  Stream<List<OfficeHoursChatMessage>> watchMessages({
    required String ownerUid,
    required String meetingId,
  }) {
    return _meetingMessagesCol(ownerUid, meetingId)
        .orderBy('timestampMs')
        .limitToLast(200)
        .snapshots()
        .map((s) => s.docs.map(OfficeHoursChatMessage.fromDoc).toList());
  }

  Stream<List<OfficeHoursChatMessage>> watchGlobalMessages({
    required String ownerUid,
  }) {
    return _globalMessagesCol(ownerUid)
        .orderBy('timestampMs')
        .limitToLast(200)
        .snapshots()
        .map((s) => s.docs.map(OfficeHoursChatMessage.fromDoc).toList());
  }

  Stream<OfficeHoursCallState?> watchGlobalCallState({
    required String ownerUid,
  }) {
    return _globalStateDoc(ownerUid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return OfficeHoursCallState.fromDoc(doc);
    });
  }

  Future<void> sendMessage({
    required String ownerUid,
    required String meetingId,
    required String authorUid,
    required String authorName,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;

    await _meetingMessagesCol(ownerUid, meetingId).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'text': t,
      'timestamp': FieldValue.serverTimestamp(),
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> sendGlobalMessage({
    required String ownerUid,
    required String authorUid,
    required String authorName,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;

    await _globalMessagesCol(ownerUid).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'text': t,
      'timestamp': FieldValue.serverTimestamp(),
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteMessage({
    required String ownerUid,
    required String meetingId,
    required String messageId,
  }) async {
    final mid = messageId.trim();
    if (mid.isEmpty) return;
    await _meetingMessagesCol(ownerUid, meetingId).doc(mid).delete();
  }

  Future<void> deleteGlobalMessage({
    required String ownerUid,
    required String messageId,
  }) async {
    final mid = messageId.trim();
    if (mid.isEmpty) return;
    await _globalMessagesCol(ownerUid).doc(mid).delete();
  }

  Future<void> updateGlobalMeetUrl({
    required String ownerUid,
    required String? meetUrl,
  }) async {
    final trimmed = meetUrl?.trim();
    await _globalStateDoc(ownerUid).set({
      'meetUrl': (trimmed == null || trimmed.isEmpty)
          ? FieldValue.delete()
          : trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startGlobalCall({required String ownerUid}) async {
    await _globalStateDoc(ownerUid).set({
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> endGlobalCall({required String ownerUid}) async {
    await _globalStateDoc(ownerUid).set({
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
