import 'package:flutter/material.dart';
import '../services/admin_auth_service.dart';
import '../theme/app_theme.dart';
import '../screens/dashboard_screen.dart';
import '../screens/moderation_queue_screen.dart';
import '../screens/user_management_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/login_screen.dart';

/// Persistent left-sidebar + top-bar layout, matching the design system.
/// Swaps content in place via IndexedStack rather than pushing new routes,
/// so the sidebar and top bar never rebuild when switching sections.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selected = 0;
  final _authService = AdminAuthService();

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.people_outline, label: 'User Management'),
    (icon: Icons.shield_outlined, label: 'Content Moderation'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ];

  void _navigateTo(int index) => setState(() => _selected = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                const Divider(height: 1, color: AppColors.outlineVariant),
                Expanded(
                  child: IndexedStack(
                    index: _selected,
                    children: [
                      DashboardScreen(onNavigate: _navigateTo),
                      const UserManagementScreen(),
                      const ModerationQueueScreen(embedded: true),
                      const SettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VibeStream',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w800)),
                Text('Admin Console',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SidebarItem(
                icon: _destinations[i].icon,
                label: _destinations[i].label,
                selected: _selected == i,
                onTap: () => _navigateTo(i),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _authService.signOut();
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search users, reports...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Icon(Icons.notifications_none, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 16),
          const Icon(Icons.help_outline, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceContainerHigh,
            child: Icon(Icons.person, size: 18, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          const Text('Admin Profile',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.primary : AppColors.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
