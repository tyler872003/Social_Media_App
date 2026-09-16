import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/report_service.dart';
import '../services/user_audit_service.dart';
import '../theme/app_theme.dart';

class UserAuditScreen extends StatefulWidget {
  const UserAuditScreen({super.key, required this.uid, required this.handle});

  final String uid;
  final String handle;

  @override
  State<UserAuditScreen> createState() => _UserAuditScreenState();
}

class _UserAuditScreenState extends State<UserAuditScreen> {
  final _reportService = ReportService();
  final _auditService = UserAuditService();

  ReportCounts? _reportCounts;
  String? _reportCountsError;
  int? _postCount;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await _reportService.reportCountsForUser(widget.uid);

      if (!mounted) return;

      setState(() {
        _reportCounts = counts;
        _reportCountsError = null;
      });
    } catch (e) {
      debugPrint('reportCountsForUser failed: $e');

      if (!mounted) return;

      setState(() {
        _reportCountsError = e.toString();
      });
    }

    try {
      final count = await _auditService.postCountForUser(widget.uid);

      if (!mounted) return;

      setState(() {
        _postCount = count;
      });
    } catch (e) {
      debugPrint('postCountForUser failed: $e');
    }
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _actionBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _confirmSuspend(String? currentStatus, String? email) async {
    final isSuspended = currentStatus == 'suspended';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuspended ? 'Reactivate account?' : 'Suspend account?'),
        content: Text(
          isSuspended
              ? 'This will restore ${widget.handle}\'s access to the app.'
              : 'This will block ${widget.handle} from signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSuspended ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (email == null || email.isEmpty) return;
    await _runAction(
      () => isSuspended
          ? _auditService.reactivateUser(widget.uid, email)
          : _auditService.suspendUser(widget.uid, email),
      isSuspended ? 'Account reactivated.' : 'Account suspended.',
    );
  }

  Future<void> _sendWarning(String? email) async {
    if (email == null || email.isEmpty) return;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Warning'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason for this warning...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;
    await _runAction(
      () => _auditService.sendWarning(
        uid: widget.uid,
        email: email,
        message: message,
      ),
      'Warning sent and logged.',
    );
  }

  Future<void> _resetPassword(String? email) async {
    if (email == null || email.isEmpty) return;
    await _runAction(
      () => _auditService.sendPasswordReset(email),
      'Password reset email sent to $email.',
    );
  }

  Future<void> _resolveReport(String reportId) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Report'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Warning Sent, Content Removed',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    await _runAction(
      () => _reportService.resolveReport(
        reportId: reportId,
        resolutionNote: note,
      ),
      'Report marked resolved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // This screen is now pushed as its own full route (see
    // UserManagementScreen._openAudit), so it needs its own Scaffold:
    // MaterialPageRoute does not itself provide a Material ancestor or
    // bounded layout constraints — a Scaffold is what supplies both.
    // Without it, InkWell (used by the tab buttons) has no Material to
    // ink into, and the Expanded widgets below have no height to expand
    // into, which is what caused the "No Material widget found" error
    // and the massive layout overflow.
    return Scaffold(
      appBar: AppBar(elevation: 0, title: Text('Audit: ${widget.handle}')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _auditService.profileStream(widget.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() ?? {};
          final status = (data['status'] as String?) ?? 'active';
          final strikes = (data['strikes'] as num?)?.toInt() ?? 0;
          final riskLevel = UserAuditService.riskLevelForStrikes(strikes);

          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 340,
                        // Scrollable: the profile card + admin actions
                        // card can be taller than the available height on
                        // shorter windows (this is what caused the
                        // "BOTTOM OVERFLOWED BY 65 PIXELS" error) — a
                        // fixed-height Column has nowhere to put the
                        // extra content, a scroll view does.
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildProfileCard(data, status),
                              const SizedBox(height: 20),
                              _buildAdminActionsCard(data, status),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildStatRow(riskLevel, strikes),
                            const SizedBox(height: 20),
                            Expanded(child: _buildReportsCard()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> data, String status) {
    final displayName = (data['displayName'] as String?)?.trim();
    final email = (data['email'] as String?) ?? '—';
    final photoUrl = data['photoUrl'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;
    final statusUpdatedAt = data['statusUpdatedAt'] as Timestamp?;
    final friendCount = (data['friends'] as List?)?.length ?? 0;

    ImageProvider? avatarImage;
    if (photoUrl != null && photoUrl.startsWith('http')) {
      avatarImage = NetworkImage(photoUrl);
    } else if (photoUrl != null && photoUrl.startsWith('data:image')) {
      // Stored as a base64 data URI (e.g. "data:image/jpeg;base64,/9j/...")
      // rather than a hosted URL — decode it directly instead of trying
      // to fetch it as a network image, which silently fails for these.
      final commaIndex = photoUrl.indexOf(',');
      if (commaIndex != -1) {
        try {
          avatarImage = MemoryImage(
            base64Decode(photoUrl.substring(commaIndex + 1)),
          );
        } catch (_) {
          avatarImage = null;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.surfaceContainerHigh,
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? const Icon(
                    Icons.person,
                    size: 44,
                    color: AppColors.onSurfaceVariant,
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            (displayName != null && displayName.isNotEmpty)
                ? displayName
                : 'Unnamed user',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            email,
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoPill(
                  label: 'Joined',
                  value: createdAt != null ? _formatTimestamp(createdAt) : '—',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoPill(
                  label: 'Latest Status',
                  value: statusUpdatedAt != null
                      ? _formatTimestamp(statusUpdatedAt)
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Followers/Following replaced: this schema has no follow graph,
          // so the first slot now shows account status (Active / Flagged /
          // Suspended) and the second shows a friends count. Posts stays
          // wired to a live count() query.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CountStat(
                value: _statusLabel(status),
                label: 'Status',
                valueColor: _statusColor(status),
              ),
              _CountStat(value: friendCount.toString(), label: 'Total Friends'),
              _CountStat(value: _postCount?.toString() ?? '…', label: 'Posts'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminActionsCard(Map<String, dynamic> data, String status) {
    final email = data['email'] as String?;
    final isSuspended = status == 'suspended';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.gavel_outlined, size: 18),
              SizedBox(width: 8),
              Text(
                'Admin Actions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AdminActionButton(
            icon: isSuspended ? Icons.lock_open : Icons.block,
            label: isSuspended ? 'Reactivate Account' : 'Suspend Account',
            bg: Colors.red.withValues(alpha: 0.1),
            fg: Colors.red,
            onTap: _actionBusy ? null : () => _confirmSuspend(status, email),
          ),
          const SizedBox(height: 8),
          _AdminActionButton(
            icon: Icons.warning_amber_rounded,
            label: 'Send Warning',
            bg: AppColors.surfaceContainerHigh,
            fg: Colors.black87,
            onTap: _actionBusy ? null : () => _sendWarning(email),
          ),
          const SizedBox(height: 8),
          _AdminActionButton(
            icon: Icons.lock_reset,
            label: 'Reset Password',
            bg: AppColors.surfaceContainerHigh,
            fg: Colors.black87,
            onTap: _actionBusy ? null : () => _resetPassword(email),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String riskLevel, int strikes) {
    final riskColor = switch (riskLevel) {
      'High' => Colors.red,
      'Medium' => Colors.orange,
      _ => AppColors.tertiary,
    };
    final counts = _reportCounts;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            label: 'Account Risk',
            value: riskLevel,
            valueColor: riskColor,
            sublabel:
                'Strikes: $strikes / ${UserAuditService.strikeSuspensionThreshold}',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            icon: Icons.flag_outlined,
            label: 'Total Reports',
            value: counts != null ? '${counts.total}' : '…',
            sublabel: counts != null
                ? 'Last 30 days: ${counts.last30Days}'
                : _reportCountsError,
          ),
        ),
      ],
    );
  }

  Widget _buildReportsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              'Recent Reports',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),
          Expanded(child: _buildReportsList()),
        ],
      ),
    );
  }

  Widget _buildReportsList() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _reportService.reportsForUser(widget.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Couldn\'t load reports: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No reports on file.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            return _ReportTile(
              postId: (data['postId'] as String?) ?? '',
              reason: (data['reason'] as String?) ?? 'Other',
              reporterId: (data['reporterId'] as String?) ?? 'Unknown',
              createdAt: data['createdAt'] as int?,
              body: (data['details'] as String?)?.trim().isNotEmpty == true
                  ? data['details'] as String
                  : 'No additional details provided.',
              status: (data['status'] as String?) ?? 'pending',
              resolutionNote: data['resolutionNote'] as String?,
              onResolve: () => _resolveReport(doc.id),
            );
          },
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'flagged':
        return Colors.red;
      case 'suspended':
        return AppColors.secondary;
      default:
        return AppColors.tertiary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'flagged':
        return 'Flagged';
      case 'suspended':
        return 'Suspended';
      default:
        return 'Active';
    }
  }

  String _formatTimestamp(Timestamp ts) => _formatDate(ts.toDate());

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({required this.value, required this.label, this.valueColor});
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sublabel,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? sublabel;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(
              sublabel!,
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminActionButton extends StatelessWidget {
  const _AdminActionButton({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: fg),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  const _PostPreview({required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 20,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snapshot.data?.data();
        if (data == null) {
          return Text(
            'Original post no longer exists.',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          );
        }

        final caption = (data['caption'] as String?)?.trim() ?? '';
        // Stored as a raw base64 string (no "data:image/..." prefix), per
        // PostRepository.createPost — decode directly rather than via a
        // data-URI parser.
        final base64Data = data['base64Data'] as String?;
        ImageProvider? postImage;
        if (base64Data != null && base64Data.isNotEmpty) {
          try {
            postImage = MemoryImage(base64Decode(base64Data));
          } catch (_) {
            postImage = null;
          }
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (postImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(
                    image: postImage,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  caption.isNotEmpty ? caption : '(No caption)',
                  style: const TextStyle(fontSize: 12.5, height: 1.3),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.postId,
    required this.reason,
    required this.reporterId,
    required this.createdAt,
    required this.body,
    required this.status,
    required this.resolutionNote,
    required this.onResolve,
  });

  final String postId;
  final String reason;
  final String reporterId;
  final int? createdAt;
  final String body;
  final String status;
  final String? resolutionNote;
  final VoidCallback onResolve;

  Color get _tagColor {
    switch (reason) {
      case 'Spam':
        return Colors.red;
      case 'Harassment or bullying':
        return Colors.deepOrange;
      case 'Inappropriate media':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String get _dateLabel {
    if (createdAt == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt!);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isResolved = status == 'resolved';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  reason.toUpperCase(),
                  style: TextStyle(
                    color: _tagColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Showing the reporter's uid rather than a resolved display
              // name — batch-resolving names would need one more query per
              // tile's reporterId. Swap in ChatRepository.fetchUsersByIds
              // here if you want display names instead.
              Expanded(
                child: Text(
                  'Reported by $reporterId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _dateLabel,
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (postId.isNotEmpty) _PostPreview(postId: postId),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                isResolved ? Icons.check_circle : Icons.pending_outlined,
                size: 15,
                color: isResolved ? AppColors.tertiary : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                isResolved ? (resolutionNote ?? 'Resolved') : 'Pending review',
                style: TextStyle(
                  color: isResolved ? AppColors.tertiary : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!isResolved)
                InkWell(
                  onTap: onResolve,
                  child: const Text(
                    'Mark Resolved',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
