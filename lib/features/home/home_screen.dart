import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ignore_for_file: unused_element

import '../../app_clock.dart';
import '../../models/models.dart';
import '../../repo/weeks_settings_firestore_repo.dart';
import '../../ui/app_top_bar.dart';
import '../../ui/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.now,
    required this.sessions,
    required this.onOpenAttendance,
  });

  final DateTime now;
  final List<ClassSession> sessions;
  final void Function(
    ClassSession session,
    int selectedSemester,
    int selectedWeekNumber,
  )
  onOpenAttendance;

  @override
  Widget build(BuildContext context) {
    final now = this.now;
    final todayLessons = sessions
        .where((s) => _isSameDay(s.start, now) && now.isBefore(s.end))
        .toList();
    ClassSession? liveLesson;
    for (final lesson in todayLessons) {
      if (lesson.isNow(now)) {
        liveLesson = lesson;
        break;
      }
    }
    final nextLesson =
        liveLesson ?? (todayLessons.isEmpty ? null : todayLessons.first);

    final allLessonsUnique = <String, ClassSession>{};
    for (final s in sessions) {
      final key = '${s.courseName}__${s.sectionName}';
      allLessonsUnique.putIfAbsent(key, () => s);
    }
    final allLessons = allLessonsUnique.values.toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const AppTopBar(
        title: 'Teaching Dashboard',
        subtitle: 'eClass IUT',
        icon: Icons.dashboard_customize_rounded,
        badgeLabel: 'Home',
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.pageGradient),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 122),
          children: [
            _DashboardHero(
              now: now,
              liveLesson: liveLesson,
              nextLesson: nextLesson,
              todayCount: todayLessons.length,
              allCount: allLessons.length,
            ),
            const SizedBox(height: 18),
            _SectionBlock(
              title: 'Today',
              subtitle: todayLessons.isEmpty
                  ? 'No active lessons for the rest of today.'
                  : '${todayLessons.length} lesson${todayLessons.length == 1 ? '' : 's'} left today',
              child: Column(
                children: [
                  if (todayLessons.isEmpty)
                    const _EmptySectionState(
                      icon: Icons.event_available_outlined,
                      title: 'Free right now',
                      subtitle:
                          'Your next teaching block will appear here automatically.',
                    )
                  else
                    for (final session in todayLessons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ClassCard(
                          session: session,
                          now: now,
                          showDetails: true,
                          showNowBadge: true,
                          onTap: () => _pickWeekDayAndOpen(context, session),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionBlock(
              title: 'Courses',
              subtitle: allLessons.isEmpty
                  ? 'Add lessons in Manage to build your weekly schedule.'
                  : '${allLessons.length} course card${allLessons.length == 1 ? '' : 's'} ready for attendance',
              child: Column(
                children: [
                  if (allLessons.isEmpty)
                    const _EmptySectionState(
                      icon: Icons.school_outlined,
                      title: 'No schedule yet',
                      subtitle:
                          'Create lessons once and open attendance from here in one tap.',
                    )
                  else
                    for (final session in allLessons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ClassCard(
                          session: session,
                          now: now,
                          showDetails: false,
                          showNowBadge: false,
                          onTap: () => _pickWeekDayAndOpen(context, session),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickWeekDayAndOpen(
    BuildContext context,
    ClassSession session,
  ) async {
    final now = appNow();
    final defaultDay = DateTime(
      session.start.year,
      session.start.month,
      session.start.day,
    );

    // Only allow days that exist for this class (as configured in Manage).
    // We derive them from the sessions list using course+section as the key.
    final allowedWeekdays =
        sessions
            .where(
              (s) =>
                  s.courseName == session.courseName &&
                  s.sectionName == session.sectionName,
            )
            .map((s) => s.start.weekday)
            .toSet()
            .toList(growable: false)
          ..sort();

    int defaultSemesterForMonth(int month) {
      // Sep–Dec => Semester 1, Jan–Aug => Semester 2
      return month >= 9 ? 1 : 2;
    }

    int currentWeekFromAnchor({
      required DateTime now,
      required int week1AnchorMillis,
    }) {
      final anchor = DateTime.fromMillisecondsSinceEpoch(week1AnchorMillis);
      final anchorMonday = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
      ).subtract(Duration(days: anchor.weekday - 1));
      final nowMonday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final diffDays = nowMonday.difference(anchorMonday).inDays;
      return (diffDays ~/ 7) + 1;
    }

    DateTime semesterStartFor(DateTime now, int semester) {
      if (semester == 1) {
        final year = now.month >= 9 ? now.year : (now.year - 1);
        return DateTime(year, 9, 1);
      }
      return DateTime(now.year, 1, 1);
    }

    int currentWeekInSemester(DateTime now, int semester) {
      final start = semesterStartFor(now, semester);
      final startMonday = DateTime(
        start.year,
        start.month,
        start.day,
      ).subtract(Duration(days: start.weekday - 1));
      final nowMonday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final diffDays = nowMonday.difference(startMonday).inDays;
      return (diffDays ~/ 7) + 1;
    }

    int semester = defaultSemesterForMonth(now.month);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    WeeksSettings? weeksSettings;
    if (uid != null) {
      try {
        weeksSettings = await WeeksSettingsFirestoreRepository(
          ownerUid: uid,
        ).watch().first;
      } catch (_) {
        weeksSettings = null;
      }
    }

    if (!context.mounted) return;

    int currentWeekForSemester(int semester) {
      final ws = weeksSettings;
      final sem = semester == 1 ? ws?.s1 : ws?.s2;
      final anchor = sem?.week1AnchorMillis;
      if (anchor != null) {
        return currentWeekFromAnchor(now: now, week1AnchorMillis: anchor);
      }
      return currentWeekInSemester(now, semester);
    }

    final defaultWeekNumber = currentWeekForSemester(semester).clamp(1, 16);

    int weekOffset = defaultWeekNumber - 1;
    int weekday = allowedWeekdays.contains(defaultDay.weekday)
        ? defaultDay.weekday
        : (allowedWeekdays.isNotEmpty
              ? allowedWeekdays.first
              : defaultDay.weekday);

    final result = await showModalBottomSheet<_WeekDayPickResult>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottomSystemInset = math.max(
          mq.padding.bottom,
          mq.viewPadding.bottom,
        );

        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomSystemInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance date',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.courseName} - Section ${session.sectionName}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: semester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Semester 1')),
                      DropdownMenuItem(value: 2, child: Text('Semester 2')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        semester = v;
                        final weekNumber = currentWeekForSemester(
                          semester,
                        ).clamp(1, 16);
                        weekOffset = weekNumber - 1;

                        // Day must stay within allowed weekdays for this class.
                        if (allowedWeekdays.isNotEmpty &&
                            !allowedWeekdays.contains(weekday)) {
                          weekday = allowedWeekdays.first;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: weekOffset,
                          decoration: const InputDecoration(
                            labelText: 'Week',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: List.generate(
                            16,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text('Week ${i + 1}'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => weekOffset = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: weekday,
                          decoration: const InputDecoration(
                            labelText: 'Day',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items:
                              (allowedWeekdays.isNotEmpty
                                      ? allowedWeekdays
                                      : const <int>[1, 2, 3, 4, 5, 6, 7])
                                  .map(
                                    (wd) => DropdownMenuItem(
                                      value: wd,
                                      child: Text(_weekdayShort(wd)),
                                    ),
                                  )
                                  .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => weekday = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop(
                          _WeekDayPickResult(
                            semester: semester,
                            weekOffset: weekOffset,
                            weekday: weekday,
                          ),
                        );
                      },
                      child: const Text('Open Attendance'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    final start = semesterStartFor(now, result.semester);
    final startMonday = DateTime(
      start.year,
      start.month,
      start.day,
    ).subtract(Duration(days: start.weekday - 1));
    final mondayTarget = startMonday.add(Duration(days: result.weekOffset * 7));
    final selectedDay = mondayTarget.add(Duration(days: result.weekday - 1));

    onOpenAttendance(
      session.withDay(selectedDay),
      result.semester,
      result.weekOffset + 1,
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static int _weekOffsetForDate(DateTime now, DateTime date) {
    final mondayNow = _mondayOfWeek(now);
    final mondayDate = _mondayOfWeek(date);
    final days = mondayDate.difference(mondayNow).inDays;
    return days ~/ 7;
  }

  static int _clampWeekOffset(int value) {
    if (value < 0) return 0;
    if (value > 15) return 15;
    return value;
  }

  static String _weekdayShort(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return 'Day';
    }
  }

  static DateTime _mondayOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.now,
    required this.liveLesson,
    required this.nextLesson,
    required this.todayCount,
    required this.allCount,
  });

  final DateTime now;
  final ClassSession? liveLesson;
  final ClassSession? nextLesson;
  final int todayCount;
  final int allCount;

  @override
  Widget build(BuildContext context) {
    final headline = liveLesson != null
        ? 'Class in progress'
        : nextLesson != null
        ? 'Ready for the next lesson'
        : 'Clear schedule right now';
    final subtitle = liveLesson != null
        ? '${liveLesson!.courseName} - Section ${liveLesson!.sectionName}'
        : nextLesson != null
        ? '${_fmtDate(now)} / Next at ${_fmtTime(nextLesson!.start)}'
        : 'Use Manage to build out the rest of your week.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandDeep.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -26,
            right: -16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 120, height: 120),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _LogoMark(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'eClass IUT',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtDate(now),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _fmtTime(now),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                headline,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.3,
                ),
              ),
              if (nextLesson != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_fmtTime(nextLesson!.start)} - ${_fmtTime(nextLesson!.end)} / ${nextLesson!.room}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Today',
                      value: '$todayCount',
                      icon: Icons.today_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Courses',
                      value: '$allCount',
                      icon: Icons.menu_book_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Status',
                      value: liveLesson != null ? 'Live' : 'Ready',
                      icon: liveLesson != null
                          ? Icons.radio_button_checked_rounded
                          : Icons.check_circle_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dt.month - 1];
    return '${dt.day} $month ${dt.year}';
  }

  static String _fmtTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.88)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.92),
            AppTheme.bgTop.withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandDeep.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.brandDeep,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.brand, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _WeekDayPickResult {
  const _WeekDayPickResult({
    required this.semester,
    required this.weekOffset,
    required this.weekday,
  });

  final int semester;
  final int weekOffset;
  final int weekday;
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.session,
    required this.now,
    required this.showDetails,
    required this.showNowBadge,
    required this.onTap,
  });

  final ClassSession session;
  final DateTime now;
  final bool showDetails;
  final bool showNowBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNow = showNowBadge && session.isNow(now);
    final primary = Theme.of(context).colorScheme.primary;
    final timeRange = '${_fmtTime(session.start)} - ${_fmtTime(session.end)}';

    return Material(
      color: const Color(0xFFF9FCFF),
      borderRadius: BorderRadius.circular(28),
      shadowColor: AppTheme.brandDeep.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 74,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isNow
                      ? primary.withValues(alpha: 0.12)
                      : AppTheme.bgTop.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtTime(session.start),
                      style: TextStyle(
                        color: isNow ? primary : AppTheme.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'to',
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtTime(session.end),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            showDetails
                                ? session.sectionName
                                : session.courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                          ),
                        ),
                        if (isNow) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Now',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      showDetails
                          ? session.courseName
                          : 'Section ${session.sectionName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoTag(
                          icon: Icons.schedule_rounded,
                          label: timeRange,
                        ),
                        if (showDetails)
                          _InfoTag(
                            icon: Icons.location_on_outlined,
                            label: session.room,
                          )
                        else
                          _InfoTag(
                            icon: Icons.calendar_view_week_rounded,
                            label: HomeScreen._weekdayShort(
                              session.start.weekday,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (showDetails)
                _LessonProgressPie(
                  session: session,
                  now: now,
                  showWhenNow: isNow,
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.north_east_rounded,
                    color: AppTheme.brand,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgTop.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.brand),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonProgressPie extends StatelessWidget {
  const _LessonProgressPie({
    required this.session,
    required this.now,
    required this.showWhenNow,
  });

  final ClassSession session;
  final DateTime now;
  final bool showWhenNow;

  @override
  Widget build(BuildContext context) {
    if (!showWhenNow) {
      return const SizedBox(width: 44, height: 44);
    }

    final total = session.end.difference(session.start);
    if (total.inSeconds <= 0) {
      return const SizedBox(width: 44, height: 44);
    }

    // Before start: hide.
    if (now.isBefore(session.start)) {
      return const SizedBox(width: 44, height: 44);
    }

    // After end: hide.
    if (!now.isBefore(session.end)) {
      return const SizedBox(width: 44, height: 44);
    }

    final elapsed = now.difference(session.start);
    final progress = elapsed.inMilliseconds / total.inMilliseconds;
    final remaining = (1.0 - progress).clamp(0.0, 1.0);
    final color = _pieColor(progress: progress);

    return _PieDot(remaining: remaining, color: color);
  }

  static Color _pieColor({required double progress}) {
    final p = progress.clamp(0.0, 1.0);

    const green = Colors.green;
    const yellow = Colors.amber;
    const red = Colors.red;

    // 0%..50%: green
    if (p <= 0.50) return green;

    // 51%..60%: smooth green -> yellow
    if (p <= 0.60) {
      final t = ((p - 0.50) / (0.60 - 0.50)).clamp(0.0, 1.0);
      return Color.lerp(green, yellow, t) ?? yellow;
    }

    // 61%..80%: yellow
    if (p <= 0.80) return yellow;

    // 81%..90%: smooth yellow -> red
    if (p <= 0.90) {
      final t = ((p - 0.80) / (0.90 - 0.80)).clamp(0.0, 1.0);
      return Color.lerp(yellow, red, t) ?? red;
    }

    // 91%..100%: red
    return red;
  }
}

class _PieDot extends StatelessWidget {
  const _PieDot({required this.remaining, required this.color});

  final double remaining;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _PieDotPainter(remaining: remaining, color: color),
      ),
    );
  }
}

class _PieDotPainter extends CustomPainter {
  _PieDotPainter({required this.remaining, required this.color});

  final double remaining;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    const strokeWidth = 7.0;
    final r = radius - strokeWidth / 2;

    final trackPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.12);

    // Background track.
    canvas.drawCircle(center, r, trackPaint);

    if (color == null) return;

    final sweep = 2 * math.pi * remaining;
    if (sweep <= 0.01) {
      return;
    }

    final arcPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color!;

    final rect = Rect.fromCircle(center: center, radius: r);
    // Start from top (-90deg).
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _PieDotPainter oldDelegate) {
    return oldDelegate.remaining != remaining || oldDelegate.color != color;
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.school_outlined, color: Colors.white),
      ),
    );
  }
}
