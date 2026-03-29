import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_clock.dart';
import '../../models/models.dart';
import '../../repo/attendance_firestore_repo.dart';
import '../../repo/groups_firestore_repo.dart';
import '../../repo/lessons_firestore_repo.dart';
import '../../repo/students_firestore_repo.dart';
import '../../repo/weeks_settings_firestore_repo.dart';
import '../../ui/app_theme.dart';
import 'attendance_google_sheets_export.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.session,
    this.selectedWeekNumber,
    this.selectedSemester,
    required this.studentsRepo,
    required this.lessonsRepo,
    required this.groupsRepo,
    required this.attendanceRepo,
  });

  final ClassSession? session;
  final int? selectedWeekNumber;
  final int? selectedSemester;
  final StudentsFirestoreRepository studentsRepo;
  final LessonsFirestoreRepository lessonsRepo;
  final GroupsFirestoreRepository groupsRepo;
  final AttendanceFirestoreRepository attendanceRepo;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late List<Student> _students;
  late Map<String, AttendanceStatus> _statusByStudentId;

  bool _exporting = false;
  bool _markingAllPresent = false;

  Map<String, AttendanceStatus> _remoteMarks = const {};
  Map<String, AttendanceStatus> _pendingMarks = const {};
  List<String> _assignedStudentIds = const [];
  List<String> _assignedGroupIds = const [];
  Map<String, List<String>> _groupMembersById = const {};
  Set<String>? _boundStudentIds;
  StreamSubscription? _lessonSub;
  StreamSubscription? _marksSub;
  StreamSubscription? _groupsSub;
  StreamSubscription<WeeksSettings>? _weeksSub;
  WeeksSettings? _weeksSettings;
  String? _activeKey;

  String _query = '';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static int _weekNumberForDate({
    required DateTime date,
    DateTime? week1Anchor,
  }) {
    if (week1Anchor == null) return 0;
    final anchorMonday = DateTime(
      week1Anchor.year,
      week1Anchor.month,
      week1Anchor.day,
    ).subtract(Duration(days: week1Anchor.weekday - 1));
    final dateMonday = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    final diffDays = dateMonday.difference(anchorMonday).inDays;
    return (diffDays ~/ 7) + 1;
  }

  Timer? _timer;
  DateTime _now = appNow();

  int _pickWeekOffset = 0;
  int _pickWeekday = DateTime.monday;
  String? _pickLessonId;
  LessonOccurrence? _pickOccurrence;

  int _semester = 1;
  DateTime? _week1Anchor;

  bool _didAutoPickForPicker = false;
  bool _userChangedPicker = false;

  static int _defaultSemesterForMonth(int month) {
    // Sep–Dec => Semester 1, Jan–Aug => Semester 2
    return month >= 9 ? 1 : 2;
  }

  static DateTime _semesterStartFor(DateTime now, int semester) {
    // Semester 1: starts Sep 1 of the current academic year.
    // Semester 2: starts Jan 1 of the current calendar year.
    if (semester == 1) {
      final year = now.month >= 9 ? now.year : (now.year - 1);
      return DateTime(year, 9, 1);
    }
    return DateTime(now.year, 1, 1);
  }

  static int _currentWeekInSemester(DateTime now, int semester) {
    final start = _semesterStartFor(now, semester);
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

  static DateTime _dateForSemesterWeekAndWeekday({
    required DateTime now,
    required int semester,
    required int weekNumber,
    required int weekday,
  }) {
    final start = _semesterStartFor(now, semester);
    final startMonday = DateTime(
      start.year,
      start.month,
      start.day,
    ).subtract(Duration(days: start.weekday - 1));
    final mondayTarget = startMonday.add(Duration(days: (weekNumber - 1) * 7));
    return mondayTarget.add(Duration(days: weekday - 1));
  }

  void _autoPickCurrentWeekAndSemester() {
    // Do NOT auto-change day; user will pick it.
    final configuredSemester = _weeksSettings?.semester;
    _semester =
        widget.selectedSemester ??
        configuredSemester ??
        _defaultSemesterForMonth(_now.month);

    int weekNo;
    final semSettings = _semester == 1
        ? _weeksSettings?.s1
        : _weeksSettings?.s2;
    final anchorMillis = semSettings?.week1AnchorMillis;
    if (anchorMillis != null) {
      final anchor = DateTime.fromMillisecondsSinceEpoch(anchorMillis);
      weekNo = _weekNumberForDate(date: _now, week1Anchor: anchor);
    } else {
      weekNo = _currentWeekInSemester(_now, _semester);
    }

    // If the screen was opened with an explicit week, prefer it.
    weekNo = widget.selectedWeekNumber ?? weekNo;
    final offset = (weekNo - 1).clamp(0, 15);
    _pickWeekOffset = offset;
  }

  void _autoPickFallbackIfNeeded() {
    if (widget.session != null) return;
    if (_didAutoPickForPicker) return;

    _autoPickCurrentWeekAndSemester();
    _didAutoPickForPicker = true;
  }

  StreamSubscription<List<Student>>? _studentsSub;

  @override
  void initState() {
    super.initState();
    _students = const [];
    _statusByStudentId = {};
    _studentsSub = widget.studentsRepo.watchAllStudents().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _students = items;
          _recomputeStatuses();
        });
      },
      onError: (_) {
        // Errors are handled by showing empty state; details are shown elsewhere.
      },
    );

    _groupsSub = widget.groupsRepo.watchGroups().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _groupMembersById = {for (final g in items) g.id: g.studentIds};
          _recomputeBoundStudents();
        });
      },
      onError: (_) {
        // ignore; fall back to explicit student IDs only
      },
    );

    _attachSession();

    // If we're in the Attendance date picker (session == null), set defaults
    // immediately so the sheet shows current values without waiting for async.
    if (widget.session == null) {
      _autoPickCurrentWeekAndSemester();
      _didAutoPickForPicker = true;
    }

    _attachWeeksSettings();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = appNow());
    });
  }

  String? get _ownerUidOrNull => FirebaseAuth.instance.currentUser?.uid;

  void _attachWeeksSettings() {
    _weeksSub?.cancel();
    final uid = _ownerUidOrNull;
    if (uid == null) {
      setState(() {
        _autoPickFallbackIfNeeded();
      });
      return;
    }

    final repo = WeeksSettingsFirestoreRepository(ownerUid: uid);
    _weeksSub = repo.watch().listen(
      (settings) {
        if (!mounted) return;
        setState(() {
          _weeksSettings = settings;
          _semester = settings.semester;
          final active = _semester == 1 ? settings.s1 : settings.s2;
          _week1Anchor = active.week1AnchorMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(active.week1AnchorMillis!);

          // After weeks settings load, re-apply defaults from weeks manager
          // unless the user already changed the picker.
          if (widget.session == null && !_userChangedPicker) {
            _autoPickCurrentWeekAndSemester();
            _didAutoPickForPicker = true;
          }
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _autoPickFallbackIfNeeded();
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = _sessionKey(oldWidget.session);
    final newKey = _sessionKey(widget.session);
    if (oldKey != newKey) {
      _attachSession();
    }
  }

  String? _sessionKey(ClassSession? session) {
    if (session == null) return null;
    return '${session.id}|${_dateKey(session.start)}';
  }

  void _attachSession() {
    _lessonSub?.cancel();
    _marksSub?.cancel();

    final session = widget.session;
    if (session == null) {
      setState(() {
        _activeKey = null;
        _remoteMarks = const {};
        _assignedStudentIds = const [];
        _assignedGroupIds = const [];
        _boundStudentIds = null;
        _recomputeStatuses();
      });
      return;
    }

    final key = _sessionKey(session);
    _activeKey = key;

    _lessonSub = widget.lessonsRepo
        .watchLesson(session.id)
        .listen(
          (lesson) {
            if (!mounted) return;
            if (_activeKey != key) return;
            setState(() {
              _assignedStudentIds = lesson?.studentIds ?? const [];
              _assignedGroupIds = lesson?.groupIds ?? const [];
              _recomputeBoundStudents();
            });
          },
          onError: (_) {
            // ignore; fall back to showing all students
          },
        );

    final dateKey = _dateKey(session.start);
    _marksSub = widget.attendanceRepo
        .watchMarks(lessonId: session.id, dateKey: dateKey)
        .listen(
          (marks) {
            if (!mounted) return;
            if (_activeKey != key) return;
            setState(() {
              _remoteMarks = marks;
              _pendingMarks = {
                for (final e in _pendingMarks.entries)
                  if (!_remoteMatchesPending(
                    remote: marks,
                    studentId: e.key,
                    pending: e.value,
                  ))
                    e.key: e.value,
              };
              _recomputeStatuses();
            });
          },
          onError: (_) {
            // ignore; show unmarked
          },
        );

    setState(() {
      _remoteMarks = const {};
      _pendingMarks = const {};
      _assignedStudentIds = const [];
      _assignedGroupIds = const [];
      _boundStudentIds = null;
      _recomputeStatuses();
    });
  }

  void _recomputeBoundStudents() {
    final explicit = _assignedStudentIds;
    final groups = _assignedGroupIds;
    if (explicit.isEmpty && groups.isEmpty) {
      _boundStudentIds = null;
      return;
    }

    final ids = <String>{...explicit};
    for (final gid in groups) {
      final members = _groupMembersById[gid];
      if (members == null) continue;
      ids.addAll(members);
    }

    _boundStudentIds = ids;
  }

  void _recomputeStatuses() {
    _statusByStudentId = {
      for (final s in _students)
        s.id:
            _pendingMarks[s.id] ??
            _remoteMarks[s.id] ??
            AttendanceStatus.unmarked,
    };
  }

  bool _remoteMatchesPending({
    required Map<String, AttendanceStatus> remote,
    required String studentId,
    required AttendanceStatus pending,
  }) {
    final remoteValue = remote[studentId];
    if (pending == AttendanceStatus.unmarked) {
      return remoteValue == null;
    }
    return remoteValue == pending;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _studentsSub?.cancel();
    _groupsSub?.cancel();
    _lessonSub?.cancel();
    _marksSub?.cancel();
    _weeksSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      final headerSemester = _semester;
      final weekNumber = _pickWeekOffset + 1;
      return Scaffold(
        appBar: AppBar(title: const Text('Attendance')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<List<LessonDoc>>(
            stream: widget.lessonsRepo.watchLessonDocs(),
            builder: (ctx, snap) {
              final lessons = snap.data ?? const <LessonDoc>[];
              if (lessons.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_outlined, size: 48),
                        const SizedBox(height: 10),
                        Text(
                          'No lessons yet',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Create lessons in the Manage tab to start taking attendance.',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final candidates = <({LessonDoc lesson, LessonOccurrence occ})>[];
              for (final l in lessons) {
                for (final o in l.occurrences) {
                  if (o.weekday != _pickWeekday) continue;
                  candidates.add((lesson: l, occ: o));
                }
              }
              candidates.sort((a, b) {
                final c = a.lesson.courseName.compareTo(b.lesson.courseName);
                if (c != 0) return c;
                final s = a.lesson.sectionName.compareTo(b.lesson.sectionName);
                if (s != 0) return s;
                final sh = a.occ.startHour.compareTo(b.occ.startHour);
                if (sh != 0) return sh;
                return a.occ.startMinute.compareTo(b.occ.startMinute);
              });

              final selected =
                  (_pickLessonId == null || _pickOccurrence == null)
                  ? null
                  : candidates
                        .where((c) {
                          if (c.lesson.id != _pickLessonId) return false;
                          final o = _pickOccurrence!;
                          return c.occ.weekday == o.weekday &&
                              c.occ.startHour == o.startHour &&
                              c.occ.startMinute == o.startMinute &&
                              c.occ.endHour == o.endHour &&
                              c.occ.endMinute == o.endMinute &&
                              c.occ.room == o.room;
                        })
                        .cast<({LessonDoc lesson, LessonOccurrence occ})?>()
                        .firstOrNull;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select attendance',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Semester $headerSemester - Week ${weekNumber > 0 ? weekNumber : '?'}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Semester 1')),
                      ButtonSegment(value: 2, label: Text('Semester 2')),
                    ],
                    selected: {_semester},
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setState(() {
                        _userChangedPicker = true;
                        _semester = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _pickWeekOffset,
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
                            setState(() {
                              _userChangedPicker = true;
                              _pickWeekOffset = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _pickWeekday,
                          decoration: const InputDecoration(
                            labelText: 'Day',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Mon')),
                            DropdownMenuItem(value: 2, child: Text('Tue')),
                            DropdownMenuItem(value: 3, child: Text('Wed')),
                            DropdownMenuItem(value: 4, child: Text('Thu')),
                            DropdownMenuItem(value: 5, child: Text('Fri')),
                            DropdownMenuItem(value: 6, child: Text('Sat')),
                            DropdownMenuItem(value: 7, child: Text('Sun')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _userChangedPicker = true;
                              _pickWeekday = v;
                              _pickLessonId = null;
                              _pickOccurrence = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selected == null
                        ? null
                        : candidates.indexOf(selected as dynamic),
                    decoration: const InputDecoration(
                      labelText: 'Lesson',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (var i = 0; i < candidates.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${candidates[i].lesson.courseName} - Section ${candidates[i].lesson.sectionName} - ${_two(candidates[i].occ.startHour)}:${_two(candidates[i].occ.startMinute)}-${_two(candidates[i].occ.endHour)}:${_two(candidates[i].occ.endMinute)} - ${candidates[i].occ.room}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (i) {
                      if (i == null) return;
                      final c = candidates[i];
                      setState(() {
                        _pickLessonId = c.lesson.id;
                        _pickOccurrence = c.occ;
                      });
                    },
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        (_pickLessonId == null || _pickOccurrence == null)
                        ? null
                        : () {
                            final c = candidates.firstWhere(
                              (x) =>
                                  x.lesson.id == _pickLessonId &&
                                  x.occ == _pickOccurrence,
                              orElse: () => candidates.first,
                            );
                            final weekNumber = _pickWeekOffset + 1;
                            final date = _dateForSemesterWeekAndWeekday(
                              now: _now,
                              semester: _semester,
                              weekNumber: weekNumber,
                              weekday: _pickWeekday,
                            );
                            final start = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              c.occ.startHour,
                              c.occ.startMinute,
                            );
                            final end = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              c.occ.endHour,
                              c.occ.endMinute,
                            );

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AttendanceScreen(
                                  session: ClassSession(
                                    id: c.lesson.id,
                                    courseName: c.lesson.courseName,
                                    sectionName: c.lesson.sectionName,
                                    room: c.occ.room,
                                    start: start,
                                    end: end,
                                  ),
                                  selectedWeekNumber: weekNumber,
                                  selectedSemester: _semester,
                                  studentsRepo: widget.studentsRepo,
                                  lessonsRepo: widget.lessonsRepo,
                                  groupsRepo: widget.groupsRepo,
                                  attendanceRepo: widget.attendanceRepo,
                                ),
                              ),
                            );
                          },
                    child: const Text('Open'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    final showTimeLeft = session.isNow(_now);
    final timeLeft = showTimeLeft ? session.timeLeft(_now) : null;

    final weekNumber =
        widget.selectedWeekNumber ??
        _weekNumberForDate(date: session.start, week1Anchor: _week1Anchor);

    final assignedSet = _boundStudentIds;

    final q = _query.trim().toLowerCase();
    final boundStudents = assignedSet == null
        ? _students
        : _students.where((s) => assignedSet.contains(s.id)).toList();

    final visibleStudents = q.isEmpty
        ? boundStudents
        : boundStudents
              .where(
                (s) =>
                    s.fullName.toLowerCase().contains(q) ||
                    s.id.toLowerCase().contains(q),
              )
              .toList();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final presentCount = boundStudents
        .where((s) => _statusByStudentId[s.id] == AttendanceStatus.present)
        .length;
    final lateCount = boundStudents
        .where((s) => _statusByStudentId[s.id] == AttendanceStatus.late)
        .length;
    final absentCount = boundStudents.length - presentCount - lateCount;
    final allPresent =
        boundStudents.isNotEmpty &&
        boundStudents.every(
          (s) => _statusByStudentId[s.id] == AttendanceStatus.present,
        );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.brandDeep,
        foregroundColor: Colors.white,
        toolbarHeight: showTimeLeft ? 112 : 84,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.sectionName.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  height: 1.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Semester $_semester • ${session.courseName} • ${weekNumber > 0 ? 'Week $weekNumber' : 'Week ?'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (timeLeft != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Time left: ${_formatDuration(timeLeft)}',
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        children: [
          _AttendanceSummaryCard(
            session: session,
            semester: _semester,
            weekNumber: weekNumber,
            timeLeft: timeLeft,
            studentCount: boundStudents.length,
            presentCount: presentCount,
            lateCount: lateCount,
            absentCount: absentCount,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _markingAllPresent || boundStudents.isEmpty || allPresent
                  ? null
                  : () => _markAllPresent(session, students: boundStudents),
              icon: _markingAllPresent
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded),
              label: Text(
                allPresent ? 'All already marked Present' : 'Mark All Present',
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name or ID',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < visibleStudents.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _StudentRow(
              student: visibleStudents[i],
              status:
                  _statusByStudentId[visibleStudents[i].id] ??
                  AttendanceStatus.unmarked,
              onTogglePresent: () =>
                  _togglePresent(session, visibleStudents[i].id),
              onToggleLate: () => _toggleLate(session, visibleStudents[i].id),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _exporting
                  ? null
                  : () => _saveAndSend(session, students: boundStudents),
              child: _exporting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save & Send'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndSend(
    ClassSession session, {
    required List<Student> students,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final exporter = AttendanceGoogleSheetsExporter();
      final uri = await exporter.export(
        session: session,
        date: session.start,
        students: students,
        statusByStudentId: _statusByStudentId,
      );

      if (!mounted) return;

      var opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      opened =
          opened || await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Sheet')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _togglePresent(ClassSession session, String studentId) async {
    final current = _statusByStudentId[studentId] ?? AttendanceStatus.unmarked;
    final next = current == AttendanceStatus.present
        ? AttendanceStatus.unmarked
        : AttendanceStatus.present;
    await _setStatus(session, studentId, next);
  }

  Future<void> _toggleLate(ClassSession session, String studentId) async {
    final current = _statusByStudentId[studentId] ?? AttendanceStatus.unmarked;
    final next = current == AttendanceStatus.late
        ? AttendanceStatus.unmarked
        : AttendanceStatus.late;
    await _setStatus(session, studentId, next);
  }

  Future<void> _markAllPresent(
    ClassSession session, {
    required List<Student> students,
  }) async {
    if (_markingAllPresent) return;
    if (students.isEmpty) return;

    setState(() => _markingAllPresent = true);

    final previousById = <String, AttendanceStatus>{};
    for (final s in students) {
      previousById[s.id] =
          _statusByStudentId[s.id] ?? AttendanceStatus.unmarked;
    }

    setState(() {
      final nextPending = {..._pendingMarks};
      final nextStatus = {..._statusByStudentId};
      for (final s in students) {
        nextPending[s.id] = AttendanceStatus.present;
        nextStatus[s.id] = AttendanceStatus.present;
      }
      _pendingMarks = nextPending;
      _statusByStudentId = nextStatus;
    });

    var failed = 0;
    for (final s in students) {
      try {
        await widget.attendanceRepo.setMark(
          lessonId: session.id,
          dateKey: _dateKey(session.start),
          studentId: s.id,
          status: AttendanceStatus.present,
        );
      } catch (_) {
        failed++;
        final prev = previousById[s.id] ?? AttendanceStatus.unmarked;
        if (!mounted) continue;
        setState(() {
          final nextPending = {..._pendingMarks};
          nextPending.remove(s.id);
          _pendingMarks = nextPending;
          _statusByStudentId = {..._statusByStudentId, s.id: prev};
        });
      }
    }

    if (!mounted) return;
    setState(() => _markingAllPresent = false);

    final saved = students.length - failed;
    if (failed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked $saved student(s) as Present')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Marked $saved student(s). Failed to save $failed student(s).',
        ),
      ),
    );
  }

  Future<void> _setStatus(
    ClassSession session,
    String studentId,
    AttendanceStatus status,
  ) async {
    final prev = _statusByStudentId[studentId] ?? AttendanceStatus.unmarked;
    setState(() {
      _pendingMarks = {..._pendingMarks, studentId: status};
      _statusByStudentId = {..._statusByStudentId, studentId: status};
    });

    try {
      await widget.attendanceRepo.setMark(
        lessonId: session.id,
        dateKey: _dateKey(session.start),
        studentId: studentId,
        status: status,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final nextPending = {..._pendingMarks};
        nextPending.remove(studentId);
        _pendingMarks = nextPending;
        _statusByStudentId = {..._statusByStudentId, studentId: prev};
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  static String _dateKey(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  static String _formatDuration(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.status,
    required this.onTogglePresent,
    required this.onToggleLate,
  });

  final Student student;
  final AttendanceStatus status;
  final VoidCallback onTogglePresent;
  final VoidCallback onToggleLate;

  void _showStudentDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottomSystemInset = mq.viewPadding.bottom > mq.padding.bottom
            ? mq.viewPadding.bottom
            : mq.padding.bottom;
        final scheme = Theme.of(ctx).colorScheme;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomSystemInset),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              student.id,
                              style: Theme.of(ctx).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.70,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentSelected = status == AttendanceStatus.present;
    final selected = presentSelected;
    final cancelOnTap = presentSelected;
    final baseBlue = Theme.of(context).colorScheme.primary;
    final gradient = selected
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              baseBlue.withValues(alpha: 0.0),
              baseBlue.withValues(alpha: 1.0),
              baseBlue.withValues(alpha: 1.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          )
        : null;

    final clockSelected = status == AttendanceStatus.late;
    final leftShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return SizedBox(
      height: 82,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              shape: leftShape,
              child: Ink(
                decoration: BoxDecoration(
                  color: selected
                      ? null
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  splashFactory: cancelOnTap ? NoSplash.splashFactory : null,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return cancelOnTap
                          ? Colors.transparent
                          : baseBlue.withValues(alpha: 0.16);
                    }
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)) {
                      return cancelOnTap
                          ? Colors.transparent
                          : baseBlue.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                  onTap: onTogglePresent,
                  onLongPress: () => _showStudentDetails(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Text(
                                  student.fullName,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      student.id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.copyWith(
                                            fontSize: 15.6,
                                            fontWeight: FontWeight.w700,
                                          ) ??
                                          const TextStyle(
                                            fontSize: 15.6,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _StatusChip(
                                    status: status,
                                    onSelectedCard: selected,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: _ClockButton(selected: clockSelected, onTap: onToggleLate),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  const _AttendanceSummaryCard({
    required this.session,
    required this.semester,
    required this.weekNumber,
    required this.timeLeft,
    required this.studentCount,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
  });

  final ClassSession session;
  final int semester;
  final int weekNumber;
  final Duration? timeLeft;
  final int studentCount;
  final int presentCount;
  final int lateCount;
  final int absentCount;

  String _two(int value) => value.toString().padLeft(2, '0');

  String _timeRange() {
    return '${_two(session.start.hour)}:${_two(session.start.minute)} - '
        '${_two(session.end.hour)}:${_two(session.end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.brandDeep, AppTheme.brand],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandDeep.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.courseName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.sectionName.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (timeLeft != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    _AttendanceScreenState._formatDuration(timeLeft!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(icon: Icons.schedule_rounded, label: _timeRange()),
              _InfoPill(icon: Icons.meeting_room_rounded, label: session.room),
              _InfoPill(
                icon: Icons.calendar_view_week_rounded,
                label: weekNumber > 0 ? 'Week $weekNumber' : 'Week ?',
              ),
              _InfoPill(
                icon: Icons.school_rounded,
                label: 'Semester $semester',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AttendanceMetric(
                  label: 'Students',
                  value: '$studentCount',
                  tint: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttendanceMetric(
                  label: 'Present',
                  value: '$presentCount',
                  tint: AppTheme.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttendanceMetric(
                  label: 'Late',
                  value: '$lateCount',
                  tint: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttendanceMetric(
                  label: 'Absent',
                  value: '$absentCount',
                  tint: scheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceMetric extends StatelessWidget {
  const _AttendanceMetric({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: tint,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.onSelectedCard = false});

  final AttendanceStatus status;
  final bool onSelectedCard;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, border) = switch (status) {
      AttendanceStatus.present => (
        'Present',
        onSelectedCard ? Colors.white : AppTheme.brand.withValues(alpha: 0.18),
        onSelectedCard ? AppTheme.brandDeep : AppTheme.brand,
        onSelectedCard
            ? Colors.white.withValues(alpha: 0.92)
            : AppTheme.brand.withValues(alpha: 0.30),
      ),
      AttendanceStatus.late => (
        'Late',
        AppTheme.warning.withValues(alpha: 0.20),
        const Color(0xFF8A5A00),
        AppTheme.warning.withValues(alpha: 0.40),
      ),
      AttendanceStatus.unmarked => (
        'Absent',
        AppTheme.surfaceSoft,
        AppTheme.danger,
        AppTheme.line,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _ClockButton extends StatefulWidget {
  const _ClockButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ClockButton> createState() => _ClockButtonState();
}

class _ClockButtonState extends State<_ClockButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = widget.selected
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

    final pressedFg = widget.selected
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.primary;
    final effectiveFg = _pressed ? pressedFg : fg;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashFactory: widget.selected ? NoSplash.splashFactory : null,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onHighlightChanged: (v) {
          if (_pressed == v) return;
          setState(() => _pressed = v);
        },
        onTap: widget.onTap,
        child: SizedBox.expand(
          child: Icon(Icons.access_time, size: 30, color: effectiveFg),
        ),
      ),
    );
  }
}
