import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

import 'features/attendance/attendance_screen.dart';
import 'features/home/home_screen.dart';
import 'features/office_hours/office_hours_screen.dart';
import 'features/manage/manage_screen.dart';
import 'app_clock.dart';
import 'models/models.dart';
import 'repo/lessons_firestore_repo.dart';
import 'repo/students_firestore_repo.dart';
import 'repo/attendance_firestore_repo.dart';
import 'repo/groups_firestore_repo.dart';
import 'ui/app_theme.dart';

class EClassApp extends StatelessWidget {
  const EClassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eClass IUT',
      theme: AppTheme.buildTheme(),
      home: const EClassShell(),
    );
  }
}

class EClassShell extends StatefulWidget {
  const EClassShell({super.key});

  @override
  State<EClassShell> createState() => _EClassShellState();
}

class _EClassShellState extends State<EClassShell> {
  int _index = 0;
  Timer? _timer;
  DateTime _now = appNow();

  late final StudentsFirestoreRepository _studentsRepo;
  LessonsFirestoreRepository? _lessonsRepo;
  AttendanceFirestoreRepository? _attendanceRepo;
  GroupsFirestoreRepository? _groupsRepo;

  @override
  void initState() {
    super.initState();
    _studentsRepo = StudentsFirestoreRepository();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _lessonsRepo = LessonsFirestoreRepository(ownerUid: uid);
      _attendanceRepo = AttendanceFirestoreRepository(ownerUid: uid);
      _groupsRepo = GroupsFirestoreRepository();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = appNow());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lessonsRepo = _lessonsRepo;
    final attendanceRepo = _attendanceRepo;
    final groupsRepo = _groupsRepo;
    if (lessonsRepo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (attendanceRepo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (groupsRepo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<List<WeeklyLesson>>(
      stream: lessonsRepo.watchWeeklyLessons(),
      builder: (context, snapshot) {
        final weekly = snapshot.data ?? const <WeeklyLesson>[];
        final sessions = _materializeUpcomingSessions(
          weeklyLessons: weekly,
          now: _now,
          daysAhead: 7,
        );
        final attendanceTarget = _pickAttendanceSession(
          sessions: sessions,
          now: _now,
        );

        final tabs = <Widget>[
          HomeScreen(
            now: _now,
            sessions: sessions,
            onOpenAttendance: _openAttendance,
          ),
          AttendanceScreen(
            key: ValueKey(
              '${attendanceTarget?.id ?? 'no-session'}|${attendanceTarget?.start.millisecondsSinceEpoch ?? 0}',
            ),
            session: attendanceTarget,
            studentsRepo: _studentsRepo,
            lessonsRepo: lessonsRepo,
            groupsRepo: groupsRepo,
            attendanceRepo: attendanceRepo,
          ),
          const OfficeHoursScreen(),
          const ManageScreen(),
        ];

        return PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            setState(() => _index = 0);
          },
          child: Scaffold(
            extendBody: true,
            body: IndexedStack(index: _index, children: tabs),
            bottomNavigationBar: SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _BottomPillNav(
                  selectedIndex: _index,
                  onSelected: (value) => setState(() {
                    _now = appNow();
                    _index = value;
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openAttendance(ClassSession session, int semester, int weekNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttendanceScreen(
          session: session,
          selectedSemester: semester,
          selectedWeekNumber: weekNumber,
          studentsRepo: _studentsRepo,
          lessonsRepo: _lessonsRepo!,
          groupsRepo: _groupsRepo!,
          attendanceRepo: _attendanceRepo!,
        ),
      ),
    );
  }

  static List<ClassSession> _materializeUpcomingSessions({
    required List<WeeklyLesson> weeklyLessons,
    required DateTime now,
    required int daysAhead,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final endDay = today.add(Duration(days: daysAhead));

    final sessions = <ClassSession>[];
    for (final lesson in weeklyLessons) {
      DateTime? nextDay;
      for (var offset = 0; offset <= daysAhead; offset++) {
        final d = today.add(Duration(days: offset));
        if (d.isAfter(endDay)) break;
        if (d.weekday == lesson.weekday) {
          final end = DateTime(
            d.year,
            d.month,
            d.day,
            lesson.endHour,
            lesson.endMinute,
          );

          // If this lesson already ended (e.g. it's the same weekday but
          // we're late in the day), materialize the next occurrence instead.
          if (!end.isAfter(now)) {
            continue;
          }

          nextDay = d;
          break;
        }
      }
      if (nextDay == null) continue;

      final start = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        lesson.startHour,
        lesson.startMinute,
      );
      final end = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        lesson.endHour,
        lesson.endMinute,
      );

      sessions.add(
        ClassSession(
          id: lesson.id,
          courseName: lesson.courseName,
          sectionName: lesson.sectionName,
          room: lesson.room,
          start: start,
          end: end,
        ),
      );
    }

    sessions.sort((a, b) => a.start.compareTo(b.start));
    return sessions;
  }

  static ClassSession? _pickAttendanceSession({
    required List<ClassSession> sessions,
    required DateTime now,
  }) {
    for (final session in sessions) {
      final isCurrent =
          !now.isBefore(session.start) && now.isBefore(session.end);
      if (isCurrent) return session;
    }

    for (final session in sessions) {
      if (session.start.isAfter(now)) return session;
    }

    return null;
  }
}

class _BottomPillNav extends StatelessWidget {
  const _BottomPillNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.brandDeep, Color(0xFF234D72)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brandDeep.withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _PillNavItem(
                selected: selectedIndex == 0,
                label: 'Home',
                selectedIcon: Icons.home_rounded,
                unselectedIcon: Icons.home_outlined,
                onTap: () => onSelected(0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PillNavItem(
                selected: selectedIndex == 1,
                label: 'Attendance',
                selectedIcon: Icons.fact_check_rounded,
                unselectedIcon: Icons.how_to_reg_outlined,
                onTap: () => onSelected(1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PillNavItem(
                selected: selectedIndex == 2,
                label: 'Office hours',
                selectedIcon: Icons.forum_rounded,
                unselectedIcon: Icons.forum_outlined,
                onTap: () => onSelected(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PillNavItem(
                selected: selectedIndex == 3,
                label: 'Manage',
                selectedIcon: Icons.grid_view_rounded,
                unselectedIcon: Icons.grid_view_outlined,
                onTap: () => onSelected(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.selected,
    required this.label,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    selected ? selectedIcon : unselectedIcon,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.78),
                    size: 21,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.78),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
