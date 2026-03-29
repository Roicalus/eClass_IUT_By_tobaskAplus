class StudentGroup {
  const StudentGroup({required this.id, required this.studentIds, this.name});

  /// Group number, stored as the Firestore document id.
  final String id;

  /// Optional human-readable group name.
  final String? name;

  final List<String> studentIds;
}
