import 'package:cloud_firestore/cloud_firestore.dart';

class LessonOccurrence {
  const LessonOccurrence({
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.room,
  });

  final int weekday; // 1=Mon..7=Sun
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final String room;

  static LessonOccurrence? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final weekday = raw['weekday'];
    final startHour = raw['startHour'];
    final startMinute = raw['startMinute'];
    final endHour = raw['endHour'];
    final endMinute = raw['endMinute'];
    final room = raw['room'];

    final wd = weekday is int ? weekday : int.tryParse('$weekday');
    final sh = startHour is int ? startHour : int.tryParse('$startHour');
    final sm = startMinute is int ? startMinute : int.tryParse('$startMinute');
    final eh = endHour is int ? endHour : int.tryParse('$endHour');
    final em = endMinute is int ? endMinute : int.tryParse('$endMinute');
    final rm = (room is String) ? room.trim() : '$room'.trim();
    if (wd == null || wd < 1 || wd > 7) return null;
    if (sh == null || sh < 0 || sh > 23) return null;
    if (sm == null || sm < 0 || sm > 59) return null;
    if (eh == null || eh < 0 || eh > 23) return null;
    if (em == null || em < 0 || em > 59) return null;
    if (rm.isEmpty) return null;

    return LessonOccurrence(
      weekday: wd,
      startHour: sh,
      startMinute: sm,
      endHour: eh,
      endMinute: em,
      room: rm,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'room': room.trim(),
    };
  }
}

class WeeklyLesson {
  const WeeklyLesson({
    required this.id,
    required this.courseName,
    required this.sectionName,
    required this.room,
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.groupIds,
    required this.studentIds,
  });

  final String id;
  final String courseName;
  final String sectionName;
  final String room;
  final int weekday; // 1=Mon..7=Sun
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<String> groupIds;
  final List<String> studentIds;

  /// New storage format is one doc per lesson with an `occurrences` array.
  /// This helper expands a lesson doc into one [WeeklyLesson] per occurrence.
  static List<WeeklyLesson> expandFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final courseName = (data['courseName'] as String?)?.trim() ?? '';
    final sectionName = (data['sectionName'] as String?)?.trim() ?? '';
    final groupIds = _readIds(data['groupIds']);
    final studentIds = _readStudentIds(data['studentIds']);

    final occurrences = <LessonOccurrence>[];
    final rawOcc = data['occurrences'];
    if (rawOcc is List) {
      for (final o in rawOcc) {
        final occ = LessonOccurrence.tryFromJson(o);
        if (occ != null) occurrences.add(occ);
      }
    }

    if (occurrences.isEmpty) {
      // Backward compatible: legacy single-slot fields.
      final legacy = WeeklyLesson.fromDoc(doc);
      if (legacy.courseName.trim().isEmpty) return const [];
      return [legacy];
    }

    return occurrences
        .map(
          (o) => WeeklyLesson(
            id: doc.id,
            courseName: courseName,
            sectionName: sectionName,
            room: o.room,
            weekday: o.weekday,
            startHour: o.startHour,
            startMinute: o.startMinute,
            endHour: o.endHour,
            endMinute: o.endMinute,
            groupIds: groupIds,
            studentIds: studentIds,
          ),
        )
        .where((l) => l.courseName.trim().isNotEmpty)
        .toList(growable: false);
  }

  factory WeeklyLesson.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return WeeklyLesson(
      id: doc.id,
      courseName: (data['courseName'] as String?)?.trim() ?? '',
      sectionName: (data['sectionName'] as String?)?.trim() ?? '',
      room: (data['room'] as String?)?.trim() ?? '',
      weekday: (data['weekday'] as int?) ?? 1,
      startHour: (data['startHour'] as int?) ?? 9,
      startMinute: (data['startMinute'] as int?) ?? 0,
      endHour: (data['endHour'] as int?) ?? 10,
      endMinute: (data['endMinute'] as int?) ?? 0,
      groupIds: _readIds(data['groupIds']),
      studentIds: _readStudentIds(data['studentIds']),
    );
  }

  factory WeeklyLesson.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    return WeeklyLesson(
      id: snap.id,
      courseName: (data?['courseName'] as String?)?.trim() ?? '',
      sectionName: (data?['sectionName'] as String?)?.trim() ?? '',
      room: (data?['room'] as String?)?.trim() ?? '',
      weekday: (data?['weekday'] as int?) ?? 1,
      startHour: (data?['startHour'] as int?) ?? 9,
      startMinute: (data?['startMinute'] as int?) ?? 0,
      endHour: (data?['endHour'] as int?) ?? 10,
      endMinute: (data?['endMinute'] as int?) ?? 0,
      groupIds: _readIds(data?['groupIds']),
      studentIds: _readStudentIds(data?['studentIds']),
    );
  }

  static List<String> _readIds(Object? raw) {
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final v in raw) {
      final s = (v is String) ? v.trim() : '';
      if (s.isEmpty) continue;
      ids.add(_normalize3DigitsIfNumeric(s));
    }
    final unique = ids.toSet().toList()..sort();
    return unique;
  }

  static String _normalize3DigitsIfNumeric(String raw) {
    final t = raw.trim();
    if (!RegExp(r'^\d+$').hasMatch(t)) return t;
    final n = int.tryParse(t);
    if (n == null) return t;
    if (n < 0) return t;
    return n.toString().padLeft(3, '0');
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

  Map<String, dynamic> toFirestore() {
    return {
      'courseName': courseName.trim(),
      'sectionName': sectionName.trim(),
      'room': room.trim(),
      'weekday': weekday,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'groupIds': groupIds,
      'studentIds': studentIds,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class LessonDoc {
  const LessonDoc({
    required this.id,
    required this.courseName,
    required this.sectionName,
    required this.groupIds,
    required this.studentIds,
    required this.occurrences,
  });

  final String id;
  final String courseName;
  final String sectionName;
  final List<String> groupIds;
  final List<String> studentIds;
  final List<LessonOccurrence> occurrences;

  factory LessonDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    final occ = <LessonOccurrence>[];
    final rawOcc = data?['occurrences'];
    if (rawOcc is List) {
      for (final o in rawOcc) {
        final parsed = LessonOccurrence.tryFromJson(o);
        if (parsed != null) occ.add(parsed);
      }
    }

    // Backward compatible: legacy single-slot fields.
    if (occ.isEmpty && data != null) {
      final legacy = WeeklyLesson.fromSnap(snap);
      if (legacy.courseName.trim().isNotEmpty) {
        occ.add(
          LessonOccurrence(
            weekday: legacy.weekday,
            startHour: legacy.startHour,
            startMinute: legacy.startMinute,
            endHour: legacy.endHour,
            endMinute: legacy.endMinute,
            room: legacy.room,
          ),
        );
      }
    }

    return LessonDoc(
      id: snap.id,
      courseName: (data?['courseName'] as String?)?.trim() ?? '',
      sectionName: (data?['sectionName'] as String?)?.trim() ?? '',
      groupIds: WeeklyLesson._readIds(data?['groupIds']),
      studentIds: WeeklyLesson._readStudentIds(data?['studentIds']),
      occurrences: occ,
    );
  }
}

class LessonsFirestoreRepository {
  LessonsFirestoreRepository({
    required this.ownerUid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String ownerUid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('teachers').doc(ownerUid).collection('lessons');

  Stream<List<WeeklyLesson>> watchWeeklyLessons() {
    return _col.snapshots().map((snap) {
      final lessons = <WeeklyLesson>[];
      for (final doc in snap.docs) {
        lessons.addAll(WeeklyLesson.expandFromDoc(doc));
      }

      lessons.sort((a, b) {
        final wd = a.weekday.compareTo(b.weekday);
        if (wd != 0) return wd;
        final sh = a.startHour.compareTo(b.startHour);
        if (sh != 0) return sh;
        return a.startMinute.compareTo(b.startMinute);
      });

      return lessons;
    });
  }

  Stream<List<LessonDoc>> watchLessonDocs() {
    return _col.snapshots().map((snap) {
      final docs = snap.docs
          .map((d) => LessonDoc.fromSnap(d))
          .where((d) => d.courseName.trim().isNotEmpty)
          .toList(growable: true);

      docs.sort((a, b) {
        final c = a.courseName.compareTo(b.courseName);
        if (c != 0) return c;
        return a.sectionName.compareTo(b.sectionName);
      });
      return docs;
    });
  }

  Stream<LessonDoc?> watchLesson(String lessonId) {
    final id = lessonId.trim();
    if (id.isEmpty) {
      return Stream<LessonDoc?>.value(null);
    }

    return _col.doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      return LessonDoc.fromSnap(snap);
    });
  }

  Future<void> upsertWeeklyLesson({
    String? lessonId,
    required String courseName,
    required String sectionName,
    required List<LessonOccurrence> occurrences,
    List<String> groupIds = const [],
    List<String> studentIds = const [],
  }) {
    final cn = courseName.trim();
    final snRaw = sectionName.trim();
    final sn = WeeklyLesson._normalize3DigitsIfNumeric(snRaw);
    if (cn.isEmpty) throw ArgumentError('courseName is empty');
    if (snRaw.isEmpty) throw ArgumentError('sectionName is empty');
    if (!RegExp(r'^\d{3}$').hasMatch(sn)) {
      throw ArgumentError('sectionName must be a 3-digit number');
    }
    if (occurrences.isEmpty) throw ArgumentError('occurrences is empty');
    for (final o in occurrences) {
      if (o.room.trim().isEmpty) {
        throw ArgumentError('occurrence room is empty');
      }
      if (o.weekday < 1 || o.weekday > 7) {
        throw ArgumentError('weekday out of range');
      }
    }

    final doc = (lessonId == null || lessonId.trim().isEmpty)
        ? _col.doc()
        : _col.doc(lessonId.trim());

    final normalizedGroupIds =
        groupIds
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(WeeklyLesson._normalize3DigitsIfNumeric)
            .toSet()
            .toList()
          ..sort();

    final occJson = occurrences.map((o) => o.toJson()).toList(growable: false);

    return doc.set({
      'courseName': cn,
      'sectionName': sn,
      'occurrences': occJson,
      'groupIds': normalizedGroupIds,
      'studentIds': studentIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWeeklyLesson(String lessonId) {
    final id = lessonId.trim();
    if (id.isEmpty) throw ArgumentError('lessonId is empty');
    return _col.doc(id).delete();
  }
}
