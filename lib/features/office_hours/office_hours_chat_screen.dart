import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'office_hours_firestore_repo.dart';

enum _OfficeHoursPanel { chat, people }

class OfficeHoursChatScreen extends StatefulWidget {
  const OfficeHoursChatScreen.meeting({
    super.key,
    required this.ownerUid,
    required this.meetingId,
    required this.meetingLabel,
  }) : isGlobal = false,
       title = null;

  const OfficeHoursChatScreen.global({
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
  State<OfficeHoursChatScreen> createState() => _OfficeHoursChatScreenState();
}

class _OfficeHoursChatScreenState extends State<OfficeHoursChatScreen> {
  final _repo = OfficeHoursFirestoreRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  _OfficeHoursPanel _selectedPanel = _OfficeHoursPanel.chat;
  bool _stickToBottom = true;
  bool _inputHasFocus = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _inputFocusNode.addListener(() {
      if (!mounted) return;
      setState(() => _inputHasFocus = _inputFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) < 96;
    if (nearBottom != _stickToBottom) {
      setState(() => _stickToBottom = nearBottom);
    }
  }

  void _selectPanel(_OfficeHoursPanel panel) {
    if (_selectedPanel == panel) return;
    if (panel == _OfficeHoursPanel.people) {
      _inputFocusNode.unfocus();
    }
    setState(() => _selectedPanel = panel);
    if (panel == _OfficeHoursPanel.chat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (target <= 0) return;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _scrollController.jumpTo(target);
  }

  String get _effectiveOwnerUid => widget.ownerUid;

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
                subtitle: const Text('Open Meet and then paste the link here.'),
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
      await _repo.updateGlobalMeetUrl(
        ownerUid: _effectiveOwnerUid,
        meetUrl: trimmed,
      );
    } else {
      final meetingId = widget.meetingId;
      if (meetingId == null) return;
      await _repo.updateMeetUrl(
        ownerUid: _effectiveOwnerUid,
        meetingId: meetingId,
        meetUrl: trimmed,
      );
    }

    await launch(trimmed);
  }

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

  Future<void> _startAndOpenMeet(String? meetUrl) async {
    await _startMeeting();
    if (!mounted) return;
    await _openMeetUrlOrNew(meetUrl);
  }

  Future<void> _copyMeetLink(String meetUrl) async {
    await Clipboard.setData(ClipboardData(text: meetUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Meet link copied')));
  }

  static String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }

  String _statusLabel({required bool isLive, required bool isEnded}) {
    if (isLive) return 'Live now';
    if (isEnded) return 'Call finished';
    return 'Ready to start';
  }

  String _statusSubtitle({required bool isLive, required bool isEnded}) {
    if (isLive) return 'Discussion is active';
    if (isEnded) return 'Messages stay available after the call';
    return 'Chat stays open before the meeting starts';
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
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () => Navigator.of(ctx).pop('copy'),
              ),
              if (isMe)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
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

    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
      return;
    }

    if (action != 'delete') return;
    if (widget.isGlobal) {
      await _repo.deleteGlobalMessage(
        ownerUid: _effectiveOwnerUid,
        messageId: m.id,
      );
      return;
    }

    final meetingId = widget.meetingId;
    if (meetingId == null) return;
    await _repo.deleteMessage(
      ownerUid: _effectiveOwnerUid,
      meetingId: meetingId,
      messageId: m.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    if (widget.isGlobal) {
      return StreamBuilder<OfficeHoursCallState?>(
        stream: _repo.watchGlobalCallState(ownerUid: _effectiveOwnerUid),
        builder: (context, snap) {
          final state = snap.data;
          return _buildChatScaffold(
            title: widget.title ?? 'General chat',
            meetUrl: state?.meetUrl,
            planned: null,
            isLive: state?.isLive ?? false,
            isEnded: state?.endedAt != null,
            ownerUid: _effectiveOwnerUid,
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
        ownerUid: _effectiveOwnerUid,
        meetingId: meetingId,
      ),
      builder: (context, meetingSnap) {
        final meeting = meetingSnap.data;
        return _buildChatScaffold(
          title: widget.meetingLabel,
          meetUrl: meeting?.meetUrl,
          planned: meeting?.plannedStartAt,
          isLive: meeting?.isLive ?? false,
          isEnded: meeting?.endedAt != null,
          ownerUid: _effectiveOwnerUid,
          user: user,
        );
      },
    );
  }

  Widget _buildChatScaffold({
    required String title,
    required String? meetUrl,
    required DateTime? planned,
    required bool isLive,
    required bool isEnded,
    required String ownerUid,
    required User user,
  }) {
    final trimmedMeet = (meetUrl ?? '').trim();
    final hasMeet = trimmedMeet.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFE7EFF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4D88BF),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        titleSpacing: 0,
        title: Row(
          children: [
            _InitialAvatar(
              label: title,
              size: 40,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _statusSubtitle(isLive: isLive, isEnded: isEnded),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: hasMeet ? 'Join Meet' : 'Open Meet',
            onPressed: () => _openMeetUrlOrNew(meetUrl),
            icon: const Icon(Icons.videocam_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDCEAF6), Color(0xFFF7FAFD)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: _ChatSummaryCard(
                    title: title,
                    subtitle: widget.isGlobal
                        ? 'One shared room for announcements, links and quick questions.'
                        : 'Keep the meeting clear, friendly and easy to follow.',
                    statusLabel: _statusLabel(isLive: isLive, isEnded: isEnded),
                    statusColor: isLive
                        ? const Color(0xFF2A9D70)
                        : isEnded
                        ? const Color(0xFF7C8895)
                        : const Color(0xFF4D88BF),
                    plannedLabel: planned == null
                        ? null
                        : _formatDateTime(planned),
                    hasMeetLink: hasMeet,
                    isLive: isLive,
                    isEnded: isEnded,
                    onOpenMeet: () => _openMeetUrlOrNew(meetUrl),
                    onStartCall: () => _startAndOpenMeet(meetUrl),
                    onEndCall: isLive ? _endMeeting : null,
                    onCopyLink: hasMeet
                        ? () => _copyMeetLink(trimmedMeet)
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _PanelSwitcher(
                    selectedPanel: _selectedPanel,
                    onSelected: _selectPanel,
                  ),
                ),
                Expanded(
                  child: _ChatBackdrop(
                    child: StreamBuilder<List<OfficeHoursChatMessage>>(
                      stream: widget.isGlobal
                          ? _repo.watchGlobalMessages(ownerUid: ownerUid)
                          : _repo.watchMessages(
                              ownerUid: ownerUid,
                              meetingId: widget.meetingId!,
                            ),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _ChatStateCard(
                            icon: Icons.error_outline_rounded,
                            title: 'Unable to load messages',
                            subtitle: '${snapshot.error}',
                          );
                        }

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final messages =
                            snapshot.data ?? const <OfficeHoursChatMessage>[];

                        if (_selectedPanel == _OfficeHoursPanel.chat &&
                            _stickToBottom &&
                            messages.length != _lastMessageCount) {
                          _lastMessageCount = messages.length;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _scrollToBottom();
                          });
                        }

                        final names = <String>{};
                        for (final message in messages) {
                          final authorName = message.authorName.trim();
                          if (authorName.isNotEmpty) {
                            names.add(authorName);
                          }
                        }
                        final participants = names.toList()
                          ..sort(
                            (a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()),
                          );

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _selectedPanel == _OfficeHoursPanel.people
                              ? ParticipantsList(
                                  key: const ValueKey('people'),
                                  names: participants,
                                )
                              : ChatArea(
                                  key: const ValueKey('chat'),
                                  messages: messages,
                                  myUid: user.uid,
                                  controller: _scrollController,
                                  onLongPress: (message) => _onMessageLongPress(
                                    message,
                                    message.authorUid == user.uid,
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ),
                if (_selectedPanel == _OfficeHoursPanel.chat)
                  _buildChatInput(user, ownerUid: ownerUid),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput(User user, {required String ownerUid}) {
    final mq = MediaQuery.of(context);
    final canSend = _controller.text.trim().isNotEmpty;
    final bottomPadding = math.max(mq.padding.bottom, mq.viewPadding.bottom);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _inputHasFocus
                      ? const Color(0xFF5B97CE)
                      : const Color(0xFFD7E3EE),
                  width: _inputHasFocus ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4D88BF).withValues(alpha: 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFF4D88BF),
                    ),
                    onPressed: _onAttachPressed,
                    tooltip: 'Attach file or photo',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        hintStyle: TextStyle(color: Color(0xFF7E92A6)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 0,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _sendMessage(user, ownerUid),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: canSend
                  ? const LinearGradient(
                      colors: [Color(0xFF5D9FD9), Color(0xFF3778B2)],
                    )
                  : null,
              color: canSend ? null : const Color(0xFFAFC0D1),
              boxShadow: canSend
                  ? [
                      BoxShadow(
                        color: const Color(0xFF3778B2).withValues(alpha: 0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: IconButton(
              tooltip: 'Send',
              onPressed: canSend ? () => _sendMessage(user, ownerUid) : null,
              icon: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _onAttachPressed() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attach not implemented yet')));
  }

  Future<void> _sendMessage(User user, String ownerUid) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {});

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

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });
  }
}

class _ChatSummaryCard extends StatelessWidget {
  const _ChatSummaryCard({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.hasMeetLink,
    required this.isLive,
    required this.isEnded,
    required this.onOpenMeet,
    required this.onStartCall,
    this.plannedLabel,
    this.onEndCall,
    this.onCopyLink,
  });

  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final String? plannedLabel;
  final bool hasMeetLink;
  final bool isLive;
  final bool isEnded;
  final VoidCallback onOpenMeet;
  final VoidCallback onStartCall;
  final VoidCallback? onEndCall;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F9FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4D88BF).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InitialAvatar(
                label: title,
                size: 52,
                backgroundColor: const Color(0xFFD9E8F6),
                foregroundColor: const Color(0xFF2E638F),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF19354A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF667A8E),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: isLive
                    ? Icons.radio_button_checked_rounded
                    : isEnded
                    ? Icons.history_rounded
                    : Icons.schedule_rounded,
                label: statusLabel,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                foregroundColor: statusColor,
              ),
              if (plannedLabel != null)
                _InfoChip(
                  icon: Icons.event_rounded,
                  label: plannedLabel!,
                  backgroundColor: const Color(0xFFEAF1F8),
                  foregroundColor: const Color(0xFF5F7488),
                ),
              _InfoChip(
                icon: hasMeetLink ? Icons.link_rounded : Icons.link_off_rounded,
                label: hasMeetLink ? 'Meet linked' : 'Meet not linked',
                backgroundColor: const Color(0xFFEAF1F8),
                foregroundColor: const Color(0xFF5F7488),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionPill(
                icon: hasMeetLink
                    ? Icons.videocam_rounded
                    : Icons.add_link_rounded,
                label: hasMeetLink ? 'Open Meet' : 'Add Meet',
                primary: true,
                onTap: onOpenMeet,
              ),
              if (!isLive)
                _ActionPill(
                  icon: isEnded
                      ? Icons.restart_alt_rounded
                      : Icons.play_circle_fill_rounded,
                  label: isEnded ? 'Restart call' : 'Start call',
                  onTap: onStartCall,
                ),
              if (isLive && onEndCall != null)
                _ActionPill(
                  icon: Icons.stop_circle_rounded,
                  label: 'End call',
                  foregroundColor: const Color(0xFFB42318),
                  onTap: onEndCall!,
                ),
              if (onCopyLink != null)
                _ActionPill(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy link',
                  onTap: onCopyLink!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelSwitcher extends StatelessWidget {
  const _PanelSwitcher({required this.selectedPanel, required this.onSelected});

  final _OfficeHoursPanel selectedPanel;
  final ValueChanged<_OfficeHoursPanel> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E5F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PanelButton(
              icon: Icons.chat_bubble_rounded,
              label: 'Chat',
              selected: selectedPanel == _OfficeHoursPanel.chat,
              onTap: () => onSelected(_OfficeHoursPanel.chat),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PanelButton(
              icon: Icons.group_rounded,
              label: 'People',
              selected: selectedPanel == _OfficeHoursPanel.people,
              onTap: () => onSelected(_OfficeHoursPanel.people),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF4D88BF) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : const Color(0xFF6C7F92),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF6C7F92),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4D88BF).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE8F1F8), Color(0xFFF8FBFE)],
                ),
              ),
            ),
            Positioned(
              top: -30,
              left: -10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF9EC6E8).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 120, height: 120),
              ),
            ),
            Positioned(
              right: -22,
              bottom: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFB8D7EF).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 150, height: 150),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChatStateCard extends StatelessWidget {
  const _ChatStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFD7E3EE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4D88BF).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F0F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 30, color: const Color(0xFF4D88BF)),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1C3A52),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6D8091),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.label,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      initials = parts.first.substring(0, 1).toUpperCase();
    } else {
      initials = (parts.first.substring(0, 1) + parts.last.substring(0, 1))
          .toUpperCase();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.36),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final fg =
        foregroundColor ?? (primary ? Colors.white : const Color(0xFF456884));
    final bg = primary ? null : Colors.white.withValues(alpha: 0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFF5D9FD9), Color(0xFF3778B2)],
                  )
                : null,
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: primary ? null : Border.all(color: const Color(0xFFD6E2EE)),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: const Color(0xFF3778B2).withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
    if (names.isEmpty) {
      return const _ChatStateCard(
        icon: Icons.group_outlined,
        title: 'No participants yet',
        subtitle:
            'People will appear here after they send their first message.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      itemCount: names.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final name = names[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD8E3EE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4D88BF).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _InitialAvatar(
                label: name,
                size: 44,
                backgroundColor: const Color(0xFFD9E8F6),
                foregroundColor: const Color(0xFF2E638F),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF18374E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Active in this conversation',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6C8093),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF88A0B6),
              ),
            ],
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const _ChatStateCard(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        subtitle:
            'Start with a quick hello, a question, or drop the Meet link here.',
      );
    }

    final maxBubbleWidth = math
        .min(MediaQuery.of(context).size.width * 0.76, 440.0)
        .toDouble();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final previous = index > 0 ? messages[index - 1] : null;
        final next = index + 1 < messages.length ? messages[index + 1] : null;
        final isMe = message.authorUid == myUid;

        final showDayLabel =
            previous == null ||
            !_sameDay(previous.timestamp, message.timestamp);
        final closeToPrevious =
            previous != null &&
            _sameDay(previous.timestamp, message.timestamp) &&
            previous.authorUid == message.authorUid &&
            (message.timestampMs - previous.timestampMs).abs() < 5 * 60 * 1000;
        final closeToNext =
            next != null &&
            _sameDay(next.timestamp, message.timestamp) &&
            next.authorUid == message.authorUid &&
            (next.timestampMs - message.timestampMs).abs() < 5 * 60 * 1000;

        final showAvatar = !isMe && !closeToPrevious;
        final showAuthor = !isMe && !closeToPrevious;
        final bubbleRadius = BorderRadius.only(
          topLeft: Radius.circular(isMe ? 24 : (closeToPrevious ? 10 : 24)),
          topRight: Radius.circular(isMe ? (closeToPrevious ? 10 : 24) : 24),
          bottomLeft: Radius.circular(isMe ? 24 : (closeToNext ? 10 : 24)),
          bottomRight: Radius.circular(isMe ? (closeToNext ? 10 : 24) : 24),
        );

        final bubbleShadow = [
          BoxShadow(
            color: (isMe ? const Color(0xFF3778B2) : const Color(0xFF3F566B))
                .withValues(alpha: isMe ? 0.18 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDayLabel)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 12, bottom: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD8E3EE)),
                    ),
                    child: Text(
                      _dayLabel(message.timestamp),
                      style: const TextStyle(
                        color: Color(0xFF698095),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!isMe)
                  SizedBox(
                    width: 38,
                    child: showAvatar
                        ? Align(
                            alignment: Alignment.bottomLeft,
                            child: _InitialAvatar(
                              label: message.authorName,
                              size: 32,
                              backgroundColor: const Color(0xFFD9E8F6),
                              foregroundColor: const Color(0xFF2E638F),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => onLongPress(message),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: Container(
                        margin: EdgeInsets.only(
                          top: showDayLabel
                              ? 0
                              : closeToPrevious
                              ? 4
                              : 12,
                          bottom: closeToNext ? 2 : 6,
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? null
                              : Colors.white.withValues(alpha: 0.92),
                          gradient: isMe
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF5D9FD9),
                                    Color(0xFF3778B2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          borderRadius: bubbleRadius,
                          border: isMe
                              ? null
                              : Border.all(color: const Color(0xFFD9E5F0)),
                          boxShadow: bubbleShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showAuthor)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  message.authorName,
                                  style: const TextStyle(
                                    color: Color(0xFF5E7487),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            Text(
                              message.text,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : const Color(0xFF18374D),
                                fontSize: 15,
                                height: 1.32,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _hhmm(message.timestamp),
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white.withValues(alpha: 0.80)
                                          : const Color(0xFF718497),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (isMe) const SizedBox(width: 4),
                                  if (isMe)
                                    Icon(
                                      Icons.done_all_rounded,
                                      size: 15,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
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
              ],
            ),
          ],
        );
      },
    );
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime(date.year, date.month, date.day);
    final diff = current.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }
}
