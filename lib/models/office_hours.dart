class OfficeHoursSlot {
  const OfficeHoursSlot({
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  /// 1 = Monday ... 7 = Sunday
  final int weekday;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  bool contains(DateTime time) {
    if (time.weekday != weekday) return false;
    final start = DateTime(
      time.year,
      time.month,
      time.day,
      startHour,
      startMinute,
    );
    final end = DateTime(time.year, time.month, time.day, endHour, endMinute);
    return time.isAfter(start) && time.isBefore(end);
  }

  DateTime nextStartAfter(DateTime now) {
    // Find next occurrence of weekday.
    final daysAhead = (weekday - now.weekday) % 7;
    final base = now.add(Duration(days: daysAhead));
    final candidate = DateTime(
      base.year,
      base.month,
      base.day,
      startHour,
      startMinute,
    );

    if (candidate.isAfter(now)) return candidate;
    return candidate.add(const Duration(days: 7));
  }
}
