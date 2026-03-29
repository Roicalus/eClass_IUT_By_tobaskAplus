// ignore_for_file: unused_element, unused_local_variable, unused_parameter

import 'package:flutter/material.dart';

import '../../auth/auth_service.dart';
import '../../ui/app_top_bar.dart';
import '../../ui/app_theme.dart';
import 'groups_manage_screen.dart';
import 'lessons_manage_screen.dart';
import 'students_manage_screen.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  static final _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const AppTopBar(
        title: 'Workspace Control',
        subtitle: 'eClass IUT',
        icon: Icons.tune_rounded,
        badgeLabel: 'Manage',
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.pageGradient),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 122),
          children: [
            const _ManageHero(),
            const SizedBox(height: 18),
            _SectionLabel(
              title: 'Academics',
              subtitle:
                  'Everything you need to keep classes structured and ready.',
            ),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.people_alt_outlined,
              title: 'Students',
              subtitle: 'Shared list for all teachers',
              accent: const Color(0xFF5B97CE),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StudentsManageScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.group_outlined,
              title: 'Groups',
              subtitle: 'Organize students into reusable groups',
              accent: const Color(0xFF2A9D70),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GroupsManageScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.calendar_month_outlined,
              title: 'Lessons and Schedule',
              subtitle: 'Private weekly timetable for your account',
              accent: const Color(0xFFF2A54A),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LessonsManageScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            _SectionLabel(
              title: 'Account',
              subtitle:
                  'Security and session controls for this teacher account.',
            ),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'Leave this account on this device',
              showChevron: false,
              accent: Theme.of(context).colorScheme.error,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'Are you sure you want to sign out of this account?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Sign out'),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed == true) {
                  await _auth.signOut();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageHero extends StatelessWidget {
  const _ManageHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandDeep.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.grid_view_rounded, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(
            'Manage your workspace',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students, groups and lessons all live here now with clearer entry points and faster navigation.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.brandDeep,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accent,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.94),
                AppTheme.bgTop.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: accent.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandDeep.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.brandDeep,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                if (showChevron)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: accent.withValues(alpha: 0.72),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
