// ignore_for_file: unused_element, unused_element_parameter

import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'office_hours_chat_screen.dart';
import 'office_hours_firestore_repo.dart';
import 'office_hours_sessions_firestore_repo.dart';

// --- Helper methods for OfficeHoursScreen ---
DateTime? _parsePlannedStart({required String date, required String time}) {
  final d = date.trim();
  final t = time.trim();
  final dm = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(d);
  if (dm == null) return null;
  final day = int.tryParse(dm.group(1) ?? '');
  final month = int.tryParse(dm.group(2) ?? '');
  final year = int.tryParse(dm.group(3) ?? '');
  if (day == null || month == null || year == null) return null;
  final tm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (tm == null) return null;
  final hh = int.tryParse(tm.group(1) ?? '');
  final mm = int.tryParse(tm.group(2) ?? '');
  if (hh == null || mm == null) return null;
  if (hh < 0 || hh > 23) return null;
  if (mm < 0 || mm > 59) return null;
  return DateTime(year, month, day, hh, mm);
}

String _dateKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d.$m.$y $hh:$mm';
}

class OfficeHoursScreen extends StatefulWidget {
  const OfficeHoursScreen({super.key});

  @override
  State<OfficeHoursScreen> createState() => _OfficeHoursScreenState();
}

class _OfficeHoursScreenState extends State<OfficeHoursScreen> {
  final _repo = OfficeHoursFirestoreRepository();
  final _sessionsRepo = OfficeHoursSessionsFirestoreRepository();

  bool _isEditing = false;
  String? _editingId;
  String? _selectedDay;

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _themeController = TextEditingController();
  final TextEditingController _meetUrlController = TextEditingController();

  final List<String> _daysOptions = const [
    'Every Monday',
    'Every Tuesday',
    'Every Wednesday',
    'Every Thursday',
    'Every Friday',
    'Every Saturday',
    'Every Sunday',
    'Single meeting',
  ];

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _themeController.dispose();
    _meetUrlController.dispose();

    super.dispose();
  }

  String? get _ownerUidOrNull => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _saveMeeting() async {
    final selected = _selectedDay;
    final time = _timeController.text.trim();
    if (selected == null || time.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a day and time')),
      );
      return;
    }

    final dayIndex = _daysOptions.indexOf(selected);
    final isSingle = selected == 'Single meeting';
    final finalTitle = isSingle
        ? _dateController.text.trim()
        : selected.replaceFirst('Every ', '').trim();

    final planned = isSingle
        ? _parsePlannedStart(date: _dateController.text, time: time)
        : null;

    final uid = _ownerUidOrNull;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }

    final meeting = OfficeHoursMeeting(
      id: _editingId ?? '',
      title: finalTitle,
      time: time,
      description: _themeController.text.trim(),
      meetUrl: _meetUrlController.text.trim().isEmpty
          ? null
          : _meetUrlController.text.trim(),
      isSingle: isSingle,
      dayIndex: isSingle ? 7 : dayIndex,
      plannedStartAt: planned,
    );

    await _repo.upsertMeeting(uid, meeting);
    _cancelAndGoHome();
  }

  Future<void> _confirmDelete(OfficeHoursMeeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: const Text('Do you want to delete meeting?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Yes',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final uid = _ownerUidOrNull;
    if (uid == null) return;
    await _repo.deleteMeeting(uid, m.id);
  }

  void _openChat(OfficeHoursMeeting m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meeting'),
        content: const Text('Do you want to start meeting?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              final uid = _ownerUidOrNull;
              if (uid == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfficeHoursChatScreen.meeting(
                    ownerUid: uid,
                    meetingLabel: '${m.title} • ${m.time}',
                    meetingId: m.id,
                  ),
                ),
              );
            },
            child: const Text(
              'Yes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelAndGoHome() {
    setState(() {
      _dateController.clear();
      _timeController.clear();
      _themeController.clear();
      _meetUrlController.clear();
      _selectedDay = null;
      _editingId = null;
      _isEditing = false;
    });
  }

  void _startEdit(OfficeHoursMeeting m) {
    setState(() {
      _isEditing = true;
      _editingId = m.id;
      if (m.isSingle) {
        _selectedDay = 'Single meeting';
        final planned = m.plannedStartAt;
        if (planned != null) {
          final day = planned.day.toString().padLeft(2, '0');
          final month = planned.month.toString().padLeft(2, '0');
          _dateController.text = '$day.$month.${planned.year}';
          final hh = planned.hour.toString().padLeft(2, '0');
          final mm = planned.minute.toString().padLeft(2, '0');
          _timeController.text = '$hh:$mm';
        } else {
          _dateController.text = m.title;
        }
      } else {
        _selectedDay = 'Every ${m.title}';
      }
      if (!m.isSingle) {
        _timeController.text = m.time;
      }
      _themeController.text = m.description;
      _meetUrlController.text = m.meetUrl ?? '';
      if (_selectedDay != null && !_daysOptions.contains(_selectedDay)) {
        _selectedDay = null;
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      final day = picked.day.toString().padLeft(2, '0');
      final month = picked.month.toString().padLeft(2, '0');
      _dateController.text = '$day.$month.${picked.year}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<OfficeHoursMeeting>>(
      stream: _repo.watchMeetings(user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Office Hours')),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 9),
                      Text(
                        'Failed to load meetings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Office Hours')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final meetings = snapshot.data ?? const <OfficeHoursMeeting>[];

        return Scaffold(
          appBar: AppBar(title: const Text('Office Hours')),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTab(
                            context,
                            'THIS WEEK',
                            !_isEditing,
                            () => _cancelAndGoHome(),
                          ),
                        ),
                        Expanded(
                          child: _buildTab(
                            context,
                            _editingId == null ? 'EDIT MEETINGS' : 'EDITING',
                            _isEditing,
                            () => setState(() => _isEditing = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _isEditing
                      ? _buildEditScreen(context)
                      : _buildListScreen(meetings),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(
    BuildContext context,
    String text,
    bool isActive,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? cs.primary : cs.outlineVariant),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isActive ? cs.onPrimary : cs.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildListScreen(List<OfficeHoursMeeting> meetings) {
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final todayDow = now.weekday;
    final todayMeetings = meetings
        .where((m) => !m.isSingle && m.dayIndex == todayDow)
        .toList(growable: false);

    if (meetings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_available_outlined, size: 48),
              const SizedBox(height: 10),
              Text(
                'No meetings yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Create office hours and start a chat for a meeting.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.add),
                label: const Text('Add meeting'),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<OfficeHoursTodaySession>(
      stream: _sessionsRepo.watchToday(
        ownerUid: _ownerUidOrNull!,
        dateKey: todayKey,
      ),
      builder: (context, sessionSnap) {
        final session = sessionSnap.data;
        final isEnded = session?.isEnded ?? false;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            Text(
              'Today',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (todayMeetings.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  'No meetings today',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              for (final m in todayMeetings)
                _MeetingCard(
                  meeting: m,
                  onTap: isEnded ? null : () => _openChat(m),
                  onEdit: () => _startEdit(m),
                  onDelete: () => _confirmDelete(m),
                  subtitle: isEnded
                      ? 'Session ended for today'
                      : 'Tap to start now',
                ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isEnded
                    ? null
                    : () async {
                        final uid = _ownerUidOrNull;
                        if (uid == null) return;
                        await _sessionsRepo.endToday(
                          ownerUid: uid,
                          dateKey: todayKey,
                        );
                      },
                child: const Text('End office hours for today'),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'All meetings',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...meetings.map(
              (m) => _MeetingCard(
                meeting: m,
                onTap: () => _openChat(m),
                onEdit: () => _startEdit(m),
                onDelete: () => _confirmDelete(m),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add meeting'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedDay,
            decoration: const InputDecoration(
              labelText: 'Day',
              border: OutlineInputBorder(),
            ),
            items: _daysOptions
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (val) => setState(() => _selectedDay = val),
          ),
          const SizedBox(height: 9),
          if (_selectedDay == 'Single meeting')
            _buildDatePickerField(
              'Date',
              'Select Date',
              _dateController,
              Icons.calendar_month,
              () => _selectDate(context),
            ),
          TextField(
            controller: _timeController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Time',
              hintText: 'e.g. 20:00',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.access_time),
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _themeController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Theme (optional)',
              hintText: 'max 50 symbols',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _meetUrlController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Google Meet link (optional)',
              hintText: 'https://meet.google.com/xxx-xxxx-xxx',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.video_call),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: FilledButton(
              onPressed: _saveMeeting,
              child: Text(
                _editingId == null ? 'SAVE' : 'UPDATE',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({
    required this.meeting,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.subtitle,
  });

  final OfficeHoursMeeting meeting;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = meeting.isSingle
        ? 'Single • ${meeting.title}'
        : meeting.title;
    final planned = meeting.plannedStartAt;
    final statusText = meeting.isLive
        ? 'LIVE'
        : (meeting.endedAt != null ? 'Ended' : 'Not started');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: cs.surface,
        elevation: 1,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        planned != null
                            ? _formatDateTime(planned)
                            : meeting.time,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle ?? statusText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: meeting.isLive
                              ? cs.primary
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (meeting.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meeting.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: cs.error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegacyOfficeHoursChatScreen extends StatefulWidget {
  const _LegacyOfficeHoursChatScreen.meeting({
    super.key,
    required this.ownerUid,
    required this.meetingId,
    required this.meetingLabel,
  }) : isGlobal = false,
       title = null;

  const _LegacyOfficeHoursChatScreen.global({
    super.key,
    required this.ownerUid,
    required this.title,
  }) : meetingId = null,
       meetingLabel = '',
       isGlobal = true;

  final String ownerUid;
  final String? meetingId;
  final String meetingLabel;
  final bool isGlobal;
  final String? title;

  @override
  State<_LegacyOfficeHoursChatScreen> createState() =>
      _OfficeHoursChatScreenState();
}

class _OfficeHoursChatScreenState extends State<_LegacyOfficeHoursChatScreen> {
  final _repo = OfficeHoursFirestoreRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  int _selectedIndex = 1;

  bool _stickToBottom = true;
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      // When close to the bottom, keep auto-scrolling on new messages.
      final nearBottom = (pos.maxScrollExtent - pos.pixels) < 80;
      if (nearBottom != _stickToBottom) {
        setState(() => _stickToBottom = nearBottom);
      }
    });
  }

  Future<void> _openMeetUrlOrNew(String? meetUrl) async {
    Future<void> showInvalid() async {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid Meet link')));
    }

    Future<void> launch(String raw) async {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null) {
        await showInvalid();
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open Google Meet')),
        );
      }
    }

    final existing = (meetUrl ?? '').trim();
    if (existing.isNotEmpty) {
      await launch(existing);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_to_home_screen),
                title: const Text('Start a new Google Meet'),
                subtitle: const Text('Opens Meet. Then paste the link here.'),
                onTap: () => Navigator.of(ctx).pop('new'),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Paste Meet link'),
                onTap: () => Navigator.of(ctx).pop('paste'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (action == null) return;

    if (action == 'new') {
      await launch('https://meet.google.com/new');
      if (!mounted) return;
    }

    if (!mounted) return;

    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Meet link'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              hintText: 'https://meet.google.com/xxx-xxxx-xxx',
              prefixIcon: Icon(Icons.video_call),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final trimmed = (pasted ?? '').trim();
    if (trimmed.isEmpty) return;
    if (Uri.tryParse(trimmed) == null) {
      await showInvalid();
      return;
    }

    if (widget.isGlobal) {
      final uid = _effectiveOwnerUid;
      await _repo.updateGlobalMeetUrl(ownerUid: uid, meetUrl: trimmed);
    } else {
      final uid = _effectiveOwnerUid;
      final meetingId = widget.meetingId;
      if (meetingId == null) return;
      await _repo.updateMeetUrl(
        ownerUid: uid,
        meetingId: meetingId,
        meetUrl: trimmed,
      );
    }

    await launch(trimmed);
  }

  String get _effectiveOwnerUid => widget.ownerUid;

  Future<void> _startMeeting() async {
    final uid = _effectiveOwnerUid;
    if (widget.isGlobal) {
      await _repo.startGlobalCall(ownerUid: uid);
      return;
    }
    final meetingId = widget.meetingId;
    if (meetingId == null) return;
    await _repo.startMeeting(ownerUid: uid, meetingId: meetingId);
  }

  Future<void> _endMeeting() async {
    final uid = _effectiveOwnerUid;
    if (widget.isGlobal) {
      await _repo.endGlobalCall(ownerUid: uid);
      return;
    }
    final meetingId = widget.meetingId;
    if (meetingId == null) return;
    await _repo.endMeeting(ownerUid: uid, meetingId: meetingId);
  }

  static String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }

  Future<void> _onMessageLongPress(OfficeHoursChatMessage m, bool isMe) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () => Navigator.of(ctx).pop('copy'),
              ),
              if (isMe)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied')));
      return;
    }

    if (action == 'delete') {
      if (widget.isGlobal) {
        await _repo.deleteGlobalMessage(
          ownerUid: _effectiveOwnerUid,
          messageId: m.id,
        );
      } else {
        final meetingId = widget.meetingId;
        if (meetingId == null) return;
        await _repo.deleteMessage(
          ownerUid: _effectiveOwnerUid,
          meetingId: meetingId,
          messageId: m.id,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final effectiveOwnerUid = _effectiveOwnerUid;

    if (widget.isGlobal) {
      return StreamBuilder<OfficeHoursCallState?>(
        stream: _repo.watchGlobalCallState(ownerUid: effectiveOwnerUid),
        builder: (context, snap) {
          final state = snap.data;
          final meetUrl = state?.meetUrl;
          final isLive = state?.isLive ?? false;
          final isEnded = state?.endedAt != null;

          return _buildChatScaffold(
            context,
            title: widget.title ?? 'General chat',
            meetUrl: meetUrl,
            planned: null,
            isLive: isLive,
            isEnded: isEnded,
            ownerUid: effectiveOwnerUid,
            user: user,
          );
        },
      );
    }

    final meetingId = widget.meetingId;
    if (meetingId == null) {
      return const Scaffold(body: Center(child: Text('Meeting not found')));
    }

    return StreamBuilder<OfficeHoursMeeting?>(
      stream: _repo.watchMeeting(
        ownerUid: effectiveOwnerUid,
        meetingId: meetingId,
      ),
      builder: (context, meetingSnap) {
        final meeting = meetingSnap.data;
        final planned = meeting?.plannedStartAt;
        final isLive = meeting?.isLive ?? false;
        final isEnded = meeting?.endedAt != null;
        final meetUrl = meeting?.meetUrl;

        return _buildChatScaffold(
          context,
          title: widget.meetingLabel,
          meetUrl: meetUrl,
          planned: planned,
          isLive: isLive,
          isEnded: isEnded,
          ownerUid: effectiveOwnerUid,
          user: user,
        );
      },
    );
  }

  Widget _buildChatScaffold(
    BuildContext context, {
    required String title,
    required String? meetUrl,
    required DateTime? planned,
    required bool isLive,
    required bool isEnded,
    required String ownerUid,
    required User user,
  }) {
    final cs = Theme.of(context).colorScheme;
    final status = isLive ? 'LIVE' : (isEnded ? 'Ended' : 'Not started');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: (meetUrl ?? '').trim().isEmpty
                ? 'Start/Join Meet'
                : 'Join Meet',
            onPressed: () => _openMeetUrlOrNew(meetUrl),
            icon: const Icon(Icons.video_call),
          ),
          IconButton(
            tooltip: 'Start call',
            onPressed: () async {
              await _startMeeting();
              if (!mounted) return;
              await _openMeetUrlOrNew(meetUrl);
            },
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'End call',
            onPressed: isLive ? _endMeeting : null,
            icon: const Icon(Icons.stop),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (planned != null)
                            Text(
                              'Planned: ${_formatDateTime(planned)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          if (planned != null) const SizedBox(height: 4),
                          Text(
                            'Status: $status',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isLive
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if ((meetUrl ?? '').trim().isNotEmpty)
                      IconButton(
                        tooltip: 'Copy Meet link',
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: meetUrl!.trim()),
                          );
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Meet link copied')),
                          );
                        },
                        icon: const Icon(Icons.link),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: StreamBuilder<List<OfficeHoursChatMessage>>(
              stream: widget.isGlobal
                  ? _repo.watchGlobalMessages(ownerUid: ownerUid)
                  : _repo.watchMessages(
                      ownerUid: ownerUid,
                      meetingId: widget.meetingId!,
                    ),
              builder: (context, snapshot) {
                final msgs = snapshot.data ?? const <OfficeHoursChatMessage>[];

                if (_selectedIndex == 1 &&
                    _stickToBottom &&
                    msgs.length != _lastMessageCount) {
                  _lastMessageCount = msgs.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (!_scrollController.hasClients) return;
                    final pos = _scrollController.position;
                    if (pos.maxScrollExtent <= 0) return;
                    _scrollController.animateTo(
                      pos.maxScrollExtent,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                    );
                  });
                }

                if (_selectedIndex == 2) {
                  final names = <String>{};
                  for (final m in msgs) {
                    if (m.authorName.trim().isNotEmpty) {
                      names.add(m.authorName);
                    }
                  }
                  final participants = names.toList()..sort();
                  return ParticipantsList(names: participants);
                }

                return ChatArea(
                  messages: msgs,
                  myUid: user.uid,
                  controller: _scrollController,
                  onLongPress: (m) =>
                      _onMessageLongPress(m, m.authorUid == user.uid),
                );
              },
            ),
          ),
          if (_selectedIndex == 1) _buildChatInput(user, ownerUid: ownerUid),
          _buildBottomBar(context, meetUrl: meetUrl),
        ],
      ),
    );
  }

  Widget _buildChatInput(User user, {required String ownerUid}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file, color: cs.primary),
                  onPressed: _onAttachPressed,
                  tooltip: 'Attach file or photo',
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 0,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(user, ownerUid),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () => _sendMessage(user, ownerUid),
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }

  void _onAttachPressed() {
    // File/photo picker and upload logic will be added in a later iteration.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attach not implemented yet')));
  }

  Future<void> _sendMessage(User user, String ownerUid) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    if (widget.isGlobal) {
      await _repo.sendGlobalMessage(
        ownerUid: ownerUid,
        authorUid: user.uid,
        authorName: user.displayName ?? 'User',
        text: text,
      );
    } else {
      final meetingId = widget.meetingId;
      if (meetingId == null) return;
      await _repo.sendMessage(
        ownerUid: ownerUid,
        meetingId: meetingId,
        authorUid: user.uid,
        authorName: user.displayName ?? 'User',
        text: text,
      );
    }
  }

  Widget _buildBottomBar(BuildContext context, {required String? meetUrl}) {
    final mq = MediaQuery.of(context);
    final bottomInset = math.max(mq.padding.bottom, mq.viewPadding.bottom);

    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(15, 0, 15, 6),
        height: 60,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Google Meet',
              onPressed: () => _openMeetUrlOrNew(meetUrl),
              icon: Icon(Icons.video_call, color: cs.primary),
            ),
            Container(
              height: 45,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _selectedIndex = 1),
                    icon: Icon(
                      Icons.chat_bubble,
                      color: _selectedIndex == 1
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _selectedIndex = 2),
                    icon: Icon(
                      Icons.group,
                      color: _selectedIndex == 2
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, color: cs.onSurface, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class ParticipantsList extends StatelessWidget {
  const ParticipantsList({super.key, required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final data = names.isEmpty ? const ['No participants yet'] : names;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (context, index) => Card(
        child: ListTile(
          title: Text(
            data[index],
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class ChatArea extends StatelessWidget {
  const ChatArea({
    super.key,
    required this.messages,
    required this.myUid,
    required this.controller,
    required this.onLongPress,
  });

  final List<OfficeHoursChatMessage> messages;
  final String myUid;
  final ScrollController controller;
  final void Function(OfficeHoursChatMessage message) onLongPress;

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.78;
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(15),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final isMe = m.authorUid == myUid;

        final prev = index > 0 ? messages[index - 1] : null;
        final sameAuthor = prev != null && prev.authorUid == m.authorUid;
        final closeInTime =
            prev != null &&
            (m.timestampMs - prev.timestampMs).abs() < 2 * 60 * 1000;
        final showHeader = !isMe && !(sameAuthor && closeInTime);

        final bubbleBg = isMe ? cs.primary : cs.surfaceContainerHighest;
        final bubbleFg = isMe ? cs.onPrimary : cs.onSurface;
        final metaFg = isMe
            ? cs.onPrimary.withValues(alpha: 0.70)
            : cs.onSurfaceVariant;

        final radius = BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: isMe
              ? const Radius.circular(14)
              : const Radius.circular(5),
          bottomRight: isMe
              ? const Radius.circular(5)
              : const Radius.circular(14),
        );

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => onLongPress(m),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                margin: EdgeInsets.only(top: showHeader ? 10 : 4, bottom: 4),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bubbleBg,
                  borderRadius: radius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          m.authorName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: metaFg,
                          ),
                        ),
                      ),
                    Text(
                      m.text,
                      style: TextStyle(
                        color: bubbleFg,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _hhmm(m.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: metaFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
