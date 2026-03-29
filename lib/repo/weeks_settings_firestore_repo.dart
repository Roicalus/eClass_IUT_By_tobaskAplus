import 'package:cloud_firestore/cloud_firestore.dart';

class WeeksSettings {
  const WeeksSettings({
    required this.semester,
    required this.s1,
    required this.s2,
  });

  final int semester;
  final SemesterWeeksSettings s1;
  final SemesterWeeksSettings s2;

  static WeeksSettings fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};

    int readInt(String key, int fallback) {
      final v = data[key];
      return v is int ? v : fallback;
    }

    final semester = readInt('semester', 1).clamp(1, 2);

    SemesterWeeksSettings readSemester(String key) {
      final raw = data[key];
      if (raw is! Map) return const SemesterWeeksSettings();
      return SemesterWeeksSettings.fromJson(raw);
    }

    return WeeksSettings(
      semester: semester,
      s1: readSemester('s1'),
      s2: readSemester('s2'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'semester': semester,
      's1': s1.toJson(),
      's2': s2.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class SemesterWeeksSettings {
  const SemesterWeeksSettings({
    this.week1AnchorMillis,
    this.midtermWeek = 8,
    this.finalWeek = 16,
  });

  final int? week1AnchorMillis;
  final int midtermWeek;
  final int finalWeek;

  bool get configured => week1AnchorMillis != null;

  static SemesterWeeksSettings fromJson(Map raw) {
    int? readIntNullable(String key) {
      final v = raw[key];
      return v is int ? v : null;
    }

    int readInt(String key, int fallback) {
      final v = raw[key];
      return v is int ? v : fallback;
    }

    return SemesterWeeksSettings(
      week1AnchorMillis: readIntNullable('week1Anchor'),
      midtermWeek: readInt('midtermWeek', 8),
      finalWeek: readInt('finalWeek', 16),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'week1Anchor': week1AnchorMillis,
      'midtermWeek': midtermWeek,
      'finalWeek': finalWeek,
    };
  }

  SemesterWeeksSettings copyWith({
    int? week1AnchorMillis,
    bool clearWeek1Anchor = false,
    int? midtermWeek,
    int? finalWeek,
  }) {
    return SemesterWeeksSettings(
      week1AnchorMillis: clearWeek1Anchor
          ? null
          : (week1AnchorMillis ?? this.week1AnchorMillis),
      midtermWeek: midtermWeek ?? this.midtermWeek,
      finalWeek: finalWeek ?? this.finalWeek,
    );
  }
}

class WeeksSettingsFirestoreRepository {
  WeeksSettingsFirestoreRepository({
    required this.ownerUid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String ownerUid;

  DocumentReference<Map<String, dynamic>> _doc() {
    return _firestore
        .collection('teachers')
        .doc(ownerUid)
        .collection('settings')
        .doc('weeks');
  }

  Stream<WeeksSettings> watch() {
    return _doc().snapshots().map((snap) {
      if (!snap.exists) {
        return const WeeksSettings(
          semester: 1,
          s1: SemesterWeeksSettings(),
          s2: SemesterWeeksSettings(),
        );
      }
      return WeeksSettings.fromSnap(snap);
    });
  }

  Future<void> upsert(WeeksSettings settings) async {
    await _doc().set(settings.toJson(), SetOptions(merge: true));
  }
}
