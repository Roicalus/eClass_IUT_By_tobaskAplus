import 'dart:async';

import 'package:flutter/material.dart';

import '../../repo/students_firestore_repo.dart';

class StudentsManageScreen extends StatefulWidget {
  const StudentsManageScreen({super.key});

  @override
  State<StudentsManageScreen> createState() => _StudentsManageScreenState();
}

class _StudentsManageScreenState extends State<StudentsManageScreen> {
  final _repo = StudentsFirestoreRepository();
  StreamSubscription? _sub;

  var _loading = true;
  Object? _error;
  var _students = const <({String id, String fullName})>[];

  String _query = '';

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchAllStudents().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
          _students = [for (final s in items) (id: s.id, fullName: s.fullName)];
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
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visibleStudents = q.isEmpty
        ? _students
        : _students
              .where(
                (s) =>
                    s.fullName.toLowerCase().contains(q) ||
                    s.id.toLowerCase().contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openStudentEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(error: _error, onRetry: _retry)
          : _students.isEmpty
          ? _EmptyView(onAdd: () => _openStudentEditor())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
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
                ),
                Expanded(
                  child: visibleStudents.isEmpty
                      ? const Center(child: Text('No matches'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: visibleStudents.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final s = visibleStudents[index];
                            return _StudentTile(
                              id: s.id,
                              fullName: s.fullName,
                              onEdit: () => _openStudentEditor(
                                initialId: s.id,
                                initialName: s.fullName,
                                idLocked: true,
                              ),
                              onDelete: () => _confirmDelete(s.id),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _sub?.cancel();
    _sub = _repo.watchAllStudents().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
          _students = [for (final s in items) (id: s.id, fullName: s.fullName)];
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
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete student'),
        content: Text('Delete $id?'),
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
      await _repo.deleteStudent(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _openStudentEditor({
    String? initialId,
    String? initialName,
    bool idLocked = false,
  }) async {
    final idController = TextEditingController(text: initialId ?? '');
    final nameController = TextEditingController(text: initialName ?? '');

    final result = await showModalBottomSheet<({String id, String name})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: mq.viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                initialId == null ? 'Add student' : 'Edit student',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: idController,
                enabled: !idLocked,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(
                      ctx,
                    ).pop((id: idController.text, name: nameController.text));
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    try {
      await _repo.upsertStudent(id: result.id, fullName: result.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.id,
    required this.fullName,
    required this.onEdit,
    required this.onDelete,
  });

  final String id;
  final String fullName;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(id, style: Theme.of(context).textTheme.bodyMedium),
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
            const Icon(Icons.people_alt_outlined, size: 48),
            const SizedBox(height: 10),
            Text(
              'No students yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a student to start taking attendance.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add student'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

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
              'Failed to load students',
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
            const SizedBox(height: 10),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
