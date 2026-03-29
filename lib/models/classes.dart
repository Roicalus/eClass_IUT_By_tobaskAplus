class ClassSession {
  const ClassSession({
    required this.id,
    required this.courseName,
    required this.sectionName,
    required this.room,
    required this.start,
    required this.end,
  });

  final String id;
  final String courseName;
  final String sectionName;
  final String room;
  final DateTime start;
  final DateTime end;

  ClassSession withDay(DateTime day) {
    final shiftedStart = DateTime(
      day.year,
      day.month,
      day.day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
    final shiftedEnd = DateTime(
      day.year,
      day.month,
      day.day,
      end.hour,
      end.minute,
      end.second,
      end.millisecond,
      end.microsecond,
    );

    return ClassSession(
      id: id,
      courseName: courseName,
      sectionName: sectionName,
      room: room,
      start: shiftedStart,
      end: shiftedEnd,
    );
  }

  bool isNow(DateTime now) => now.isAfter(start) && now.isBefore(end);

  Duration timeLeft(DateTime now) {
    final diff = end.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }
}
