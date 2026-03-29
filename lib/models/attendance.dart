enum AttendanceStatus { unmarked, present, late }

class AttendanceMark {
  const AttendanceMark({required this.studentId, required this.status});

  final String studentId;
  final AttendanceStatus status;

  AttendanceMark copyWith({AttendanceStatus? status}) {
    return AttendanceMark(studentId: studentId, status: status ?? this.status);
  }
}
