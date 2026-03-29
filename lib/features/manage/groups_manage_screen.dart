import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repo/faculties_firestore_repo.dart';
import '../../repo/groups_firestore_repo.dart';
import '../../repo/students_firestore_repo.dart';

class GroupsManageScreen extends StatefulWidget {
  const GroupsManageScreen({super.key});

  @override
  State<GroupsManageScreen> createState() => _GroupsManageScreenState();
}

class _GroupsManageScreenState extends State<GroupsManageScreen> {
  GroupsFirestoreRepository? _repo;
  StreamSubscription? _sub;

  final _studentsRepo = StudentsFirestoreRepository();
  final _facultiesRepo = FacultiesFirestoreRepository();
  StreamSubscription<List<Student>>? _studentsSub;

  var _loading = true;
  Object? _error;
  var _groups =
      const <({String number, String? name, List<String> studentIds})>[];
  var _students = const <Student>[];

  @override
  void initState() {
    super.initState();
    _repo = GroupsFirestoreRepository();
    _sub = _repo!.watchGroups().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
          _groups = [
            for (final g in items)
              (number: g.id, name: g.name, studentIds: g.studentIds),
          ];
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

    _studentsSub = _studentsRepo.watchAllStudents().listen(
      (items) {
        if (!mounted) return;
        setState(() => _students = items);
      },
      onError: (_) {
        // ignore
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _studentsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(error: _error)
          : _groups.isEmpty
          ? _EmptyView(onAdd: () => _openEditor())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: _groups.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final g = _groups[index];
                final title = g.name == null || g.name!.trim().isEmpty
                    ? 'Group ${g.number}'
                    : 'Group ${g.number} • ${g.name!.trim()}';
                return _GroupTile(
                  name: title,
                  subtitle: 'Students: ${g.studentIds.length}',
                  onEdit: () => _openEditor(
                    groupNumber: g.number,
                    initialStudentIds: g.studentIds,
                  ),
                  onDelete: () => _confirmDelete(g.number),
                );
              },
            ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group'),
        content: const Text('Do you want to delete this group?'),
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
      await _repo!.deleteGroup(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _openEditor({
    String? groupNumber,
    List<String>? initialStudentIds,
  }) async {
    final parsed = _tryParseGroupId(groupNumber ?? '');

    String? faculty = parsed?.faculty;
    int year = parsed?.year ?? _currentYearTwoDigits();
    final groupNoController = TextEditingController(text: parsed?.number ?? '');

    final existingGroupIds = {for (final g in _groups) g.number};
    final initialGroupId = (groupNumber ?? '').trim();
    if (initialGroupId.isNotEmpty) {
      existingGroupIds.add(initialGroupId);
    }

    final oldMembersByGroup = <String, Set<String>>{
      for (final g in _groups) g.number: g.studentIds.toSet(),
    };

    final studentToGroup = <String, String?>{};
    for (final g in _groups) {
      for (final sid in g.studentIds) {
        studentToGroup[sid] = g.number;
      }
    }

    String query = '';

    final result = await showModalBottomSheet<_GroupDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setState) {
            final years = _yearOptions();

            final currentGroupId = (groupNumber != null)
                ? groupNumber.trim()
                : _composeGroupId(
                    faculty: faculty,
                    year: year,
                    numberRaw: groupNoController.text,
                  );

            final isDuplicate =
                groupNumber == null &&
                currentGroupId.isNotEmpty &&
                existingGroupIds.contains(currentGroupId);

            String? validationMessage;
            if (groupNumber == null) {
              final rawNo = groupNoController.text.trim();
              if (rawNo.isNotEmpty && _normalizeTwoDigits(rawNo).isEmpty) {
                validationMessage = 'Group number must be 01–99';
              } else if (isDuplicate) {
                validationMessage = 'Group $currentGroupId already exists';
              }
            }
            final canEditAssignments = currentGroupId.isNotEmpty;

            final q = query.trim().toLowerCase();
            final visibleStudents = q.isEmpty
                ? _students
                : _students
                      .where(
                        (s) =>
                            s.id.toLowerCase().contains(q) ||
                            s.fullName.toLowerCase().contains(q),
                      )
                      .toList(growable: false);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: mq.viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: mq.size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupNumber == null ? 'Add group' : 'Edit group',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<String>>(
                      stream: _facultiesRepo.watchFaculties(),
                      builder: (ctx, snapshot) {
                        final faculties = snapshot.data ?? const <String>[];
                        final effectiveFaculty =
                            faculty ??
                            (faculties.isNotEmpty ? faculties.first : null);

                        final allFaculties = <String>{
                          ...faculties,
                          ...?(effectiveFaculty == null
                              ? null
                              : <String>{effectiveFaculty}),
                        }.toList(growable: false)..sort();

                        if (groupNumber == null &&
                            faculty == null &&
                            effectiveFaculty != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() => faculty = effectiveFaculty);
                          });
                        }

                        Future<void> addFaculty() async {
                          final c = await _promptFacultyCode(ctx);
                          if (c == null) return;
                          try {
                            await _facultiesRepo.upsertFaculty(c);
                            if (!mounted) return;
                            setState(() => faculty = _normalizeFaculty(c));
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Add faculty failed: $e')),
                            );
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      effectiveFaculty ?? 'no-faculty',
                                    ),
                                    initialValue: effectiveFaculty,
                                    decoration: const InputDecoration(
                                      labelText: 'Faculty',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final f in allFaculties)
                                        DropdownMenuItem(
                                          value: f,
                                          child: Text(f),
                                        ),
                                    ],
                                    onChanged: groupNumber != null
                                        ? null
                                        : (v) {
                                            if (v == null) return;
                                            setState(() => faculty = v);
                                          },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: addFaculty,
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                            if (snapshot.hasError)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Failed to load faculties. Check Firestore rules/deploy.',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(year),
                            initialValue: year,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final y in years)
                                DropdownMenuItem(
                                  value: y,
                                  child: Text(_twoDigits(y)),
                                ),
                            ],
                            onChanged: groupNumber != null
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setState(() => year = v);
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: groupNoController,
                            enabled: groupNumber == null,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Group number',
                              hintText: '17',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    TextField(
                      onChanged: (v) => setState(() => query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search by name or ID',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!canEditAssignments)
                      Text(
                        'Select faculty/year and enter a 2-digit group number to edit students.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      )
                    else
                      Text(
                        'Tap to move/remove students (showing ${visibleStudents.length}).',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Material(
                        color: Theme.of(ctx).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: visibleStudents.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final s = visibleStudents[index];
                            final assigned = studentToGroup[s.id];
                            final inCurrent =
                                assigned != null && assigned == currentGroupId;

                            final trailing = <Widget>[];
                            if (assigned != null) {
                              trailing.add(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    assigned,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                              trailing.add(const SizedBox(width: 8));
                            }

                            if (!canEditAssignments) {
                              // no actions
                            } else if (inCurrent) {
                              trailing.add(
                                IconButton(
                                  tooltip: 'Remove from group',
                                  onPressed: () => setState(
                                    () => studentToGroup[s.id] = null,
                                  ),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              );
                            } else {
                              trailing.add(
                                IconButton(
                                  tooltip: assigned == null
                                      ? 'Add to this group'
                                      : 'Move to this group',
                                  onPressed: () => setState(
                                    () => studentToGroup[s.id] = currentGroupId,
                                  ),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              );

                              if (assigned != null) {
                                trailing.add(
                                  IconButton(
                                    tooltip: 'Remove from group',
                                    onPressed: () => setState(
                                      () => studentToGroup[s.id] = null,
                                    ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                );
                              }
                            }

                            final title = s.fullName.isEmpty
                                ? s.id
                                : s.fullName;
                            final subtitle = assigned == null
                                ? s.id
                                : '${s.id} • in group $assigned';

                            return ListTile(
                              dense: true,
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(subtitle),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: trailing,
                              ),
                              onTap: !canEditAssignments
                                  ? null
                                  : () {
                                      setState(() {
                                        if (inCurrent) {
                                          studentToGroup[s.id] = null;
                                        } else {
                                          studentToGroup[s.id] = currentGroupId;
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (validationMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          validationMessage,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: currentGroupId.isEmpty || isDuplicate
                            ? null
                            : () {
                                Navigator.of(ctx).pop(
                                  _GroupDraft(
                                    groupId: currentGroupId,
                                    studentToGroup: Map<String, String?>.from(
                                      studentToGroup,
                                    ),
                                    knownGroupIds: existingGroupIds.toList(
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
      final current = result.groupId.trim();
      if (current.isEmpty) throw ArgumentError('group id is empty');

      // Build new members per group based on final assignments.
      final newMembersByGroup = <String, Set<String>>{};
      for (final sid in result.studentToGroup.keys) {
        final g = result.studentToGroup[sid]?.trim();
        if (g == null || g.isEmpty) continue;
        (newMembersByGroup[g] ??= <String>{}).add(sid);
      }

      // Update only groups that changed (including those becoming empty).
      final allGroups = <String>{
        ...result.knownGroupIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
        current,
        ...newMembersByGroup.keys,
        ...oldMembersByGroup.keys,
      };

      for (final g in allGroups) {
        final oldSet = oldMembersByGroup[g] ?? const <String>{};
        final newSet = newMembersByGroup[g] ?? const <String>{};
        if (_setEquals(oldSet, newSet)) continue;
        final ids = newSet.toList(growable: false)..sort();
        await _repo!.upsertGroup(number: g, studentIds: ids);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  static int _currentYearTwoDigits() {
    return DateTime.now().year % 100;
  }

  static List<int> _yearOptions() {
    final current = _currentYearTwoDigits();
    final start = current < 14 ? 14 : current;
    return [for (var y = start; y >= 14; y--) y];
  }

  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  static String _normalizeFaculty(String raw) {
    final upper = raw.trim().toUpperCase();
    if (upper.isEmpty) return '';
    return upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String _normalizeTwoDigits(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (!RegExp(r'^\d+$').hasMatch(t)) return '';
    final n = int.tryParse(t);
    if (n == null) return '';
    if (n < 1 || n > 99) return '';
    return n.toString().padLeft(2, '0');
  }

  static String _composeGroupId({
    required String? faculty,
    required int year,
    required String numberRaw,
  }) {
    final f = faculty == null ? '' : _normalizeFaculty(faculty);
    final y = _normalizeTwoDigits(year.toString());
    final n = _normalizeTwoDigits(numberRaw);
    if (f.isEmpty || y.isEmpty || n.isEmpty) return '';
    return '$f-$y-$n';
  }

  static ({String faculty, int year, String number})? _tryParseGroupId(
    String raw,
  ) {
    final t = raw.trim().toUpperCase();
    final m = RegExp(r'^([A-Z0-9]{2,10})-(\d{2})-(\d{2})$').firstMatch(t);
    if (m == null) return null;
    final y = int.tryParse(m.group(2) ?? '');
    if (y == null) return null;
    return (faculty: m.group(1)!, year: y, number: m.group(3)!);
  }

  Future<String?> _promptFacultyCode(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add faculty'),
        content: TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Faculty code',
            hintText: 'CIE',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final normalized = code == null ? '' : _normalizeFaculty(code);
    return normalized.isEmpty ? null : normalized;
  }
}

class _GroupDraft {
  const _GroupDraft({
    required this.groupId,
    required this.studentToGroup,
    required this.knownGroupIds,
  });

  final String groupId;
  final Map<String, String?> studentToGroup;
  final List<String> knownGroupIds;
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.name,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
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
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_outlined, size: 48),
            const SizedBox(height: 10),
            Text(
              'No groups yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a group to bind students to lessons.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add group'),
            ),
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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 10),
            Text(
              'Failed to load groups',
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
