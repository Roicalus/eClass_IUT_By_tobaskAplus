// ignore_for_file: unused_element, unused_local_variable

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repo/groups_firestore_repo.dart';
import '../../repo/lessons_firestore_repo.dart';
import '../../repo/students_firestore_repo.dart';
import '../../repo/weeks_settings_firestore_repo.dart';

class LessonsManageScreen extends StatefulWidget {
  const LessonsManageScreen({super.key});

  @override
  State<LessonsManageScreen> createState() => _LessonsManageScreenState();
}

class _LessonsManageScreenState extends State<LessonsManageScreen> {
  late final LessonsFirestoreRepository _repo;
  late final GroupsFirestoreRepository _groupsRepo;
  late final StudentsFirestoreRepository _studentsRepo;
  late final WeeksSettingsFirestoreRepository _weeksRepo;
  StreamSubscription? _sub;
  StreamSubscription? _weeksSub;

  var _loading = true;
  Object? _error;
  var _lessons = const <LessonDoc>[];

  int _semester = 1;
  DateTime? _week1Anchor;
  int _midtermWeek = 8;
  int _finalWeek = 16;

  bool _weeksExpanded = false;

  WeeksSettings? _weeksSettings;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _loading = false;
      _error = StateError('Not signed in');
      return;
    }

    _repo = LessonsFirestoreRepository(ownerUid: uid);
    _groupsRepo = GroupsFirestoreRepository();
    _studentsRepo = StudentsFirestoreRepository();
    _weeksRepo = WeeksSettingsFirestoreRepository(ownerUid: uid);
    _sub = _repo.watchLessonDocs().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
          _lessons = items;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e;
        });
      },
    );

    _weeksSub = _weeksRepo.watch().listen(
      (s) {
        if (!mounted) return;
        setState(() {
          _weeksSettings = s;
          _semester = s.semester.clamp(1, 2);

          final sem = _semester == 1 ? s.s1 : s.s2;
          _week1Anchor = sem.week1AnchorMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(sem.week1AnchorMillis!);
          _midtermWeek = sem.midtermWeek;
          _finalWeek = sem.finalWeek;
        });
      },
      onError: (_) {
        // ignore
      },
    );
  }

  bool get _canCreateLessons => _week1Anchor != null;

  Future<void> _persistWeekSettings() async {
    final current = _weeksSettings;
    if (current == null) return;

    final sem = SemesterWeeksSettings(
      week1AnchorMillis: _week1Anchor?.millisecondsSinceEpoch,
      midtermWeek: _midtermWeek,
      finalWeek: _finalWeek,
    );

    final next = WeeksSettings(
      semester: _semester,
      s1: _semester == 1 ? sem : current.s1,
      s2: _semester == 2 ? sem : current.s2,
    );

    await _weeksRepo.upsert(next);
  }

  Future<void> _switchSemester(int semester) async {
    await _persistWeekSettings();
    setState(() => _semester = semester);

    final current = _weeksSettings;
    if (current == null) return;
    final sem = semester == 1 ? current.s1 : current.s2;
    setState(() {
      _week1Anchor = sem.week1AnchorMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(sem.week1AnchorMillis!);
      _midtermWeek = sem.midtermWeek;
      _finalWeek = sem.finalWeek;
    });

    await _weeksRepo.upsert(
      WeeksSettings(semester: semester, s1: current.s1, s2: current.s2),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  Widget _buildManageWeeksHeader(BuildContext context) {
    final headerTextStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _weeksExpanded = !_weeksExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Manage weeks', style: headerTextStyle),
                    ),
                    Icon(
                      _weeksExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (!_weeksExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Semester $_semester • Week 1: ${_week1Anchor == null ? 'Not set' : _fmtDate(_week1Anchor!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_weeksExpanded) ...[
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Semester 1')),
                  ButtonSegment(value: 2, label: Text('Semester 2')),
                ],
                selected: {_semester},
                onSelectionChanged: (s) async {
                  final v = s.first;
                  await _switchSemester(v);
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final initial =
                      _week1Anchor ??
                      DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                        DateTime.now().day,
                      );
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(DateTime.now().year - 1, 1, 1),
                    lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                  );
                  if (picked == null) return;
                  setState(() => _week1Anchor = picked);
                  _persistWeekSettings();
                },
                icon: const Icon(Icons.flag_outlined),
                label: Text(
                  _week1Anchor == null
                      ? 'Set Week 1 start'
                      : 'Week 1 start: ${_fmtDate(_week1Anchor!)}',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _midtermWeek,
                      decoration: const InputDecoration(
                        labelText: 'Midterm week',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: List.generate(
                        16,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('Week ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _midtermWeek = v);
                        _persistWeekSettings();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _finalWeek,
                      decoration: const InputDecoration(
                        labelText: 'Final week',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: List.generate(
                        16,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('Week ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _finalWeek = v);
                        _persistWeekSettings();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _weeksSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lessons / Schedule')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: _canCreateLessons
            ? () => _openLessonEditor()
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Set Week 1 start to create lessons.'),
                  ),
                );
              },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(error: _error)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: (_lessons.isEmpty ? 2 : _lessons.length + 1),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildManageWeeksHeader(context);
                }
                if (_lessons.isEmpty) {
                  return index == 1
                      ? _EmptyView(
                          canAdd: _canCreateLessons,
                          onAdd: () => _openLessonEditor(),
                        )
                      : const SizedBox.shrink();
                }
                final l = _lessons[index - 1];
                return _LessonDocTile(
                  lesson: l,
                  onEdit: () => _openLessonEditorById(l.id),
                  onDelete: () => _confirmDelete(l.id),
                );
              },
            ),
    );
  }

  Future<void> _openLessonEditorById(String lessonId) async {
    final id = lessonId.trim();
    if (id.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(_repo.ownerUid)
          .collection('lessons')
          .doc(id)
          .get();
      if (!snap.exists) return;

      final doc = LessonDoc.fromSnap(snap);
      final initialSlots = doc.occurrences
          .map(
            (o) => (
              weekday: o.weekday,
              start: TimeOfDay(hour: o.startHour, minute: o.startMinute),
              end: TimeOfDay(hour: o.endHour, minute: o.endMinute),
              room: o.room,
            ),
          )
          .toList(growable: false);

      await _openLessonEditor(
        initial: WeeklyLesson(
          id: doc.id,
          courseName: doc.courseName,
          sectionName: doc.sectionName,
          room: initialSlots.isEmpty ? '' : initialSlots.first.room,
          weekday: initialSlots.isEmpty
              ? DateTime.monday
              : initialSlots.first.weekday,
          startHour: initialSlots.isEmpty ? 9 : initialSlots.first.start.hour,
          startMinute: initialSlots.isEmpty
              ? 0
              : initialSlots.first.start.minute,
          endHour: initialSlots.isEmpty ? 10 : initialSlots.first.end.hour,
          endMinute: initialSlots.isEmpty ? 30 : initialSlots.first.end.minute,
          groupIds: doc.groupIds,
          studentIds: doc.studentIds,
        ),
        initialSlots: initialSlots,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open editor: $e')));
    }
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete lesson'),
        content: const Text('Do you want to delete this lesson?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _repo.deleteWeeklyLesson(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _openLessonEditor({
    WeeklyLesson? initial,
    List<({int weekday, TimeOfDay start, TimeOfDay end, String room})>?
    initialSlots,
  }) async {
    final courseController = TextEditingController(text: initial?.courseName);
    final sectionNumberController = TextEditingController(
      text: _normalize3DigitsIfNumeric(initial?.sectionName ?? ''),
    );

    final courseOptions =
        _lessons
            .map((l) => l.courseName.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final sectionOptions =
        _lessons
            .map((l) => l.sectionName.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();

    final selectedGroupNumbers = <String>{...?(initial?.groupIds)};
    final selectedStudentIds = <String>{...?(initial?.studentIds)};
    var groupQuery = '';
    var studentQuery = '';
    var openSection = _EditorSection.none;

    int weekday = initial?.weekday ?? DateTime.monday;
    var start = TimeOfDay(
      hour: initial?.startHour ?? 9,
      minute: initial?.startMinute ?? 0,
    );
    var end = TimeOfDay(
      hour: initial?.endHour ?? 10,
      minute: initial?.endMinute ?? 30,
    );

    final defaultRoom = (initial?.room ?? '').trim();

    final slots =
        <({int weekday, TimeOfDay start, TimeOfDay end, String room})>[];
    if (initialSlots != null && initialSlots.isNotEmpty) {
      slots.addAll(initialSlots);
    } else {
      slots.add((weekday: weekday, start: start, end: end, room: defaultRoom));
    }
    var timesPerWeek = slots.length;
    // Editor UI is built inside the bottom sheet builder below.

    final result = await showModalBottomSheet<_LessonDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      initial == null ? 'Add lesson' : 'Edit lesson',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 9),
                    Autocomplete<String>(
                      initialValue: TextEditingValue(
                        text: courseController.text,
                      ),
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return courseOptions;
                        return courseOptions.where(
                          (o) => o.toLowerCase().contains(q),
                        );
                      },
                      onSelected: (v) =>
                          setState(() => courseController.text = v),
                      fieldViewBuilder:
                          (ctx, textController, focusNode, onFieldSubmitted) {
                            textController.text = courseController.text;
                            textController
                                .selection = TextSelection.fromPosition(
                              TextPosition(offset: textController.text.length),
                            );
                            return TextField(
                              controller: textController,
                              focusNode: focusNode,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Course',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) =>
                                  setState(() => courseController.text = v),
                            );
                          },
                    ),
                    const SizedBox(height: 9),
                    Builder(
                      builder: (ctx) {
                        final sectionItems = List.generate(
                          10,
                          (i) => (i + 1).toString().padLeft(3, '0'),
                          growable: false,
                        );
                        final current = _normalize3DigitsIfNumeric(
                          sectionNumberController.text,
                        );
                        final value = sectionItems.contains(current)
                            ? current
                            : sectionItems.first;

                        return DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                            border: OutlineInputBorder(),
                          ),
                          items: sectionItems
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => sectionNumberController.text = v);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    DropdownButtonFormField<int>(
                      initialValue: timesPerWeek,
                      decoration: const InputDecoration(
                        labelText: 'Times per week',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1')),
                        DropdownMenuItem(value: 2, child: Text('2')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 4, child: Text('4')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 6, child: Text('6')),
                        DropdownMenuItem(value: 7, child: Text('7')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          timesPerWeek = v;
                          while (slots.length < timesPerWeek) {
                            slots.add((
                              weekday: DateTime.monday,
                              start: const TimeOfDay(hour: 9, minute: 0),
                              end: const TimeOfDay(hour: 10, minute: 30),
                              room: defaultRoom,
                            ));
                          }
                          if (slots.length > timesPerWeek) {
                            slots.removeRange(timesPerWeek, slots.length);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 9),
                    for (var i = 0; i < slots.length; i++) ...[
                      _SlotEditor(
                        index: i,
                        weekday: slots[i].weekday,
                        start: slots[i].start,
                        end: slots[i].end,
                        room: slots[i].room,
                        onWeekdayChanged: (wd) => setState(() {
                          slots[i] = (
                            weekday: wd,
                            start: slots[i].start,
                            end: slots[i].end,
                            room: slots[i].room,
                          );
                        }),
                        onStartChanged: (t) => setState(() {
                          slots[i] = (
                            weekday: slots[i].weekday,
                            start: t,
                            end: slots[i].end,
                            room: slots[i].room,
                          );
                        }),
                        onEndChanged: (t) => setState(() {
                          slots[i] = (
                            weekday: slots[i].weekday,
                            start: slots[i].start,
                            end: t,
                            room: slots[i].room,
                          );
                        }),
                        onRoomChanged: (v) => setState(() {
                          slots[i] = (
                            weekday: slots[i].weekday,
                            start: slots[i].start,
                            end: slots[i].end,
                            room: v,
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 9),
                    _EditorAccordionHeader(
                      title: 'Groups',
                      buttonLabel: 'Add groups',
                      isOpen: openSection == _EditorSection.groups,
                      selectedCount: selectedGroupNumbers.length,
                      onToggle: () => setState(() {
                        openSection = openSection == _EditorSection.groups
                            ? _EditorSection.none
                            : _EditorSection.groups;
                      }),
                    ),
                    if (openSection == _EditorSection.groups)
                      StreamBuilder(
                        stream: _groupsRepo.watchGroups(),
                        builder: (ctx, snapshot) {
                          final groups =
                              snapshot.data ?? const <StudentGroup>[];
                          final q = groupQuery.trim().toLowerCase();
                          final visible = q.isEmpty
                              ? groups
                              : groups
                                    .where((g) {
                                      final title = (g.name ?? '').trim();
                                      final hay = '${g.id} $title'
                                          .toLowerCase();
                                      return hay.contains(q);
                                    })
                                    .toList(growable: false);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              if (groups.isEmpty)
                                Text(
                                  'No groups yet. Create groups in Manage → Groups.',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                )
                              else ...[
                                TextField(
                                  onChanged: (v) =>
                                      setState(() => groupQuery = v),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: 'Search groups',
                                    prefixIcon: const Icon(Icons.search),
                                    filled: true,
                                    fillColor: Theme.of(ctx)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Material(
                                  color: Theme.of(ctx).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(8),
                                    itemCount: visible.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (ctx, index) {
                                      final g = visible[index];
                                      final num = g.id;
                                      final selected = selectedGroupNumbers
                                          .contains(num);
                                      final groupTitle =
                                          (g.name == null ||
                                              g.name!.trim().isEmpty)
                                          ? 'Group $num'
                                          : 'Group $num • ${g.name!.trim()}';
                                      return ListTile(
                                        dense: true,
                                        title: Text(groupTitle),
                                        subtitle: Text(
                                          'Students: ${g.studentIds.length}',
                                        ),
                                        trailing: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                        ),
                                        onTap: () => setState(() {
                                          if (!selectedGroupNumbers.add(num)) {
                                            selectedGroupNumbers.remove(num);
                                          }
                                        }),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    const SizedBox(height: 9),
                    _EditorAccordionHeader(
                      title: 'Retakers',
                      buttonLabel: 'Add retakers',
                      isOpen: openSection == _EditorSection.students,
                      selectedCount: selectedStudentIds.length,
                      onToggle: () => setState(() {
                        openSection = openSection == _EditorSection.students
                            ? _EditorSection.none
                            : _EditorSection.students;
                      }),
                    ),
                    if (openSection == _EditorSection.students)
                      StreamBuilder(
                        stream: _studentsRepo.watchAllStudents(),
                        builder: (ctx, snapshot) {
                          final students = snapshot.data ?? const <Student>[];
                          final q = studentQuery.trim().toLowerCase();
                          final visible = q.isEmpty
                              ? students
                              : students
                                    .where((s) {
                                      final hay = '${s.id} ${s.fullName}'
                                          .toLowerCase();
                                      return hay.contains(q);
                                    })
                                    .toList(growable: false);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              if (students.isEmpty)
                                Text(
                                  'No students yet. Create students in Manage → Students.',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                )
                              else ...[
                                TextField(
                                  onChanged: (v) =>
                                      setState(() => studentQuery = v),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: 'Search retakers',
                                    prefixIcon: const Icon(Icons.search),
                                    filled: true,
                                    fillColor: Theme.of(ctx)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Material(
                                  color: Theme.of(ctx).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(8),
                                    itemCount: visible.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (ctx, index) {
                                      final s = visible[index];
                                      final selected = selectedStudentIds
                                          .contains(s.id);
                                      return ListTile(
                                        dense: true,
                                        title: Text(s.fullName),
                                        subtitle: Text(s.id),
                                        trailing: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                        ),
                                        onTap: () => setState(() {
                                          if (!selectedStudentIds.add(s.id)) {
                                            selectedStudentIds.remove(s.id);
                                          }
                                        }),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (selectedGroupNumbers.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select at least one group.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.of(ctx).pop(
                            _LessonDraft(
                              courseName: courseController.text,
                              sectionNumber: sectionNumberController.text,
                              slots: slots.toList(growable: false),
                              groupNumbers: selectedGroupNumbers.toList(
                                growable: false,
                              ),
                              studentIds: selectedStudentIds.toList(
                                growable: false,
                              ),
                            ),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    try {
      final occurrences = result.slots
          .map(
            (slot) => LessonOccurrence(
              weekday: slot.weekday,
              startHour: slot.start.hour,
              startMinute: slot.start.minute,
              endHour: slot.end.hour,
              endMinute: slot.end.minute,
              room: slot.room.trim(),
            ),
          )
          .toList(growable: false);

      await _repo.upsertWeeklyLesson(
        lessonId: initial?.id,
        courseName: result.courseName,
        sectionName: _normalize3DigitsIfNumeric(result.sectionNumber),
        occurrences: occurrences,
        groupIds: result.groupNumbers,
        studentIds: result.studentIds,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  static String _fmt(TimeOfDay t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  static String _normalize3DigitsIfNumeric(String raw) {
    final t = raw.trim();
    if (!RegExp(r'^\d+$').hasMatch(t)) return t;
    final n = int.tryParse(t);
    if (n == null) return t;
    if (n < 0) return t;
    return n.toString().padLeft(3, '0');
  }
}

class _LessonDraft {
  const _LessonDraft({
    required this.courseName,
    required this.sectionNumber,
    required this.slots,
    required this.groupNumbers,
    required this.studentIds,
  });

  final String courseName;
  final String sectionNumber;
  final List<({int weekday, TimeOfDay start, TimeOfDay end, String room})>
  slots;
  final List<String> groupNumbers;
  final List<String> studentIds;
}

enum _EditorSection { none, groups, students }

class _EditorAccordionHeader extends StatelessWidget {
  const _EditorAccordionHeader({
    required this.title,
    required this.buttonLabel,
    required this.isOpen,
    required this.selectedCount,
    required this.onToggle,
  });

  final String title;
  final String buttonLabel;
  final bool isOpen;
  final int selectedCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          selectedCount == 0 ? '' : 'Selected: $selectedCount',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: onToggle,
          icon: Icon(isOpen ? Icons.expand_less : Icons.expand_more),
          label: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.index,
    required this.weekday,
    required this.start,
    required this.end,
    required this.room,
    required this.onWeekdayChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onRoomChanged,
  });

  final int index;
  final int weekday;
  final TimeOfDay start;
  final TimeOfDay end;
  final String room;
  final ValueChanged<int> onWeekdayChanged;
  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;
  final ValueChanged<String> onRoomChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lesson ${index + 1}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: room,
              onChanged: onRoomChanged,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Room',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: weekday,
              decoration: const InputDecoration(
                labelText: 'Weekday',
                border: OutlineInputBorder(),
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
                onWeekdayChanged(v);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: start,
                      );
                      if (t == null) return;
                      onStartChanged(t);
                    },
                    child: Text(
                      'Start: ${_LessonsManageScreenState._fmt(start)}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: end,
                      );
                      if (t == null) return;
                      onEndChanged(t);
                    },
                    child: Text('End: ${_LessonsManageScreenState._fmt(end)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonDocTile extends StatelessWidget {
  const _LessonDocTile({
    required this.lesson,
    required this.onEdit,
    required this.onDelete,
  });

  final LessonDoc lesson;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    String weekdayLabel(int weekday) {
      return switch (weekday) {
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        7 => 'Sun',
        _ => 'Day',
      };
    }

    final occ = [...lesson.occurrences];
    occ.sort((a, b) {
      final wd = a.weekday.compareTo(b.weekday);
      if (wd != 0) return wd;
      final sh = a.startHour.compareTo(b.startHour);
      if (sh != 0) return sh;
      return a.startMinute.compareTo(b.startMinute);
    });

    String two(int v) => v.toString().padLeft(2, '0');
    String fmtTime(int h, int m) => '${two(h)}:${two(m)}';

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.calendar_month_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lesson.courseName} • ${lesson.sectionName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final o in occ) ...[
                      Text(
                        '${weekdayLabel(o.weekday)} ${fmtTime(o.startHour, o.startMinute)}–${fmtTime(o.endHour, o.endMinute)} • ${o.room}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.onEdit,
    required this.onDelete,
  });

  final WeeklyLesson lesson;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lesson.courseName} • ${lesson.sectionName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_weekdayLabel(lesson.weekday)} ${_timeRange(lesson)} • ${lesson.room}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      1 => 'Mon',
      2 => 'Tue',
      3 => 'Wed',
      4 => 'Thu',
      5 => 'Fri',
      6 => 'Sat',
      7 => 'Sun',
      _ => 'Day',
    };
  }

  static String _timeRange(WeeklyLesson l) {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = '${two(l.startHour)}:${two(l.startMinute)}';
    final e = '${two(l.endHour)}:${two(l.endMinute)}';
    return '$s–$e';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.canAdd, required this.onAdd});

  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note,
              size: 48,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 9),
            Text(
              'No lessons yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              canAdd
                  ? 'Use the + button to create your first lesson.'
                  : 'Set Week 1 start above to begin creating lessons.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(
              'Failed to load lessons',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
