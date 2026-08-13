import 'package:flutter/material.dart';
import '../services/firestore_admin_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  /// Called with a sidebar index to switch sections (e.g. jump to the
  /// Content Moderation tab when "Review reports" is tapped).
  final void Function(int index)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = FirestoreAdminService();
  late Future<_Stats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<_Stats> _loadStats() async {
    final results = await Future.wait([
      _service.getTotalPostCount(),
      _service.getTotalUserCount(),
      _service.getPendingReportCount(),
    ]);
    return _Stats(
      totalPosts: results[0],
      totalUsers: results[1],
      pendingReports: results[2],
    );
  }

  void _refresh() {
    setState(() {
      _statsFuture = _loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
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
                    Text('Overview Dashboard',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 4),
                    Text('High-level metrics and recent platform activity.',
                        style: TextStyle(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 24),
          FutureBuilder<_Stats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error loading stats: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error));
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final s = snapshot.data!;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  _StatTile(
                    icon: Icons.people_outline,
                    iconColor: AppColors.primary,
                    value: '${s.totalPosts}',
                    label: 'Total Posts',
                  ),
                  _StatTile(
                    icon: Icons.groups_outlined,
                    iconColor: AppColors.tertiary,
                    value: '${s.totalUsers}',
                    label: 'Total Users',
                  ),
                  _StatTile(
                    icon: Icons.flag_outlined,
                    iconColor: AppColors.secondary,
                    value: '${s.pendingReports}',
                    label: 'Pending Reports',
                    highlight: s.pendingReports > 0,
                    onTap: () => widget.onNavigate?.call(2),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => widget.onNavigate?.call(2),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Review reports'),
          ),
        ],
      ),
    );
  }
}

class _Stats {
  final int totalPosts;
  final int totalUsers;
  final int pendingReports;
  _Stats({
    required this.totalPosts,
    required this.totalUsers,
    required this.pendingReports,
  });
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlight ? AppColors.secondary.withValues(alpha: 0.06) : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: highlight ? AppColors.secondary.withValues(alpha: 0.3) : AppColors.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 16),
            Text(value,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
