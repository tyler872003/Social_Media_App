import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
//import '../scripts/backfill_user_status.dart'; // TEMPORARY — remove after running once
import 'user_audit_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  static const _pageSize = 25;

  final List<String> _statusOptions = const [
    'All Statuses',
    'Active',
    'Flagged',
    'Suspended',
  ];
  String _statusFilter = 'All Statuses';
  String _searchQuery = '';

  int _currentPage = 1;
  int _totalCount = 0;
  bool _loading = true;
  List<_AdminUser> _pageUsers = [];

  // TEMPORARY — remove after running the backfill once
  bool _backfillRunning = false;

  // _pageCursors[i] = the last document of page i, used as the
  // startAfterDocument cursor when loading page i+1.
  final List<DocumentSnapshot<Map<String, dynamic>>?> _pageCursors = [null];

  // Cache of decoded base64 avatar images, keyed by uid, so we don't
  // re-decode on every rebuild (e.g. on setState from status changes).
  final Map<String, ImageProvider> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    _resetAndLoad();
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'users',
    );
    if (_statusFilter != 'All Statuses') {
      q = q.where('status', isEqualTo: _statusFilter.toLowerCase());
    }
    return q.orderBy(FieldPath.documentId);
  }

  Future<void> _resetAndLoad() async {
    setState(() => _loading = true);
    final countSnap = await _baseQuery().count().get();
    _pageCursors
      ..clear()
      ..add(null);
    _totalCount = countSnap.count ?? 0;
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    setState(() => _loading = true);
    Query<Map<String, dynamic>> q = _baseQuery().limit(_pageSize);
    final cursor = page > 1 && _pageCursors.length >= page
        ? _pageCursors[page - 1]
        : null;
    if (cursor != null) q = q.startAfterDocument(cursor);

    final snap = await q.get();
    if (_pageCursors.length == page && snap.docs.isNotEmpty) {
      _pageCursors.add(snap.docs.last);
    }

    setState(() {
      _pageUsers = snap.docs.map((d) => _AdminUser.fromDoc(d)).toList();
      _currentPage = page;
      _loading = false;
    });
  }

  Future<void> _setStatus(_AdminUser user, String status) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      final i = _pageUsers.indexWhere((u) => u.uid == user.uid);
      if (i != -1) _pageUsers[i] = user.copyWith(status: status);
    });
  }

  void _openAudit(_AdminUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            UserAuditScreen(uid: user.uid, handle: user.displayName),
      ),
    );
  }

  // TEMPORARY — remove this method after running the backfill once.

  List<_AdminUser> get _visibleUsers {
    if (_searchQuery.isEmpty) return _pageUsers;
    final q = _searchQuery.toLowerCase();
    return _pageUsers
        .where(
          (u) =>
              u.displayName.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q),
        )
        .toList();
  }

  int get _totalPages =>
      _totalCount == 0 ? 1 : ((_totalCount - 1) ~/ _pageSize) + 1;

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

  /// Resolves a user's avatar image, supporting both real `http(s)` URLs
  /// (e.g. Firebase Storage download URLs) and legacy base64 `data:` URIs
  /// still stored on some older documents. Returns null if there's no
  /// usable photo, in which case the caller falls back to a generic icon.
  ImageProvider? _avatarImageFor(_AdminUser user) {
    final photoUrl = user.photoUrl;
    if (photoUrl == null || photoUrl.isEmpty) return null;

    final cached = _avatarCache[user.uid];
    if (cached != null) return cached;

    ImageProvider? provider;
    if (photoUrl.startsWith('data:image')) {
      try {
        final base64Part = photoUrl.split(',').last;
        provider = MemoryImage(base64Decode(base64Part));
      } catch (_) {
        provider = null; // malformed data URI — fall back to icon
      }
    } else if (photoUrl.startsWith('http')) {
      provider = NetworkImage(photoUrl);
    }

    if (provider != null) {
      _avatarCache[user.uid] = provider;
    }
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                    Text(
                      'User Management',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View and manage all registered users.',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // TEMPORARY — remove this button after running the backfill once.
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                initialValue: _statusFilter,
                onSelected: (v) {
                  setState(() => _statusFilter = v);
                  _resetAndLoad();
                },
                itemBuilder: (context) => _statusOptions
                    .map((s) => PopupMenuItem(value: s, child: Text(s)))
                    .toList(),
                child: _FilterPillDisplay(label: _statusFilter),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildHeaderRow(),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _visibleUsers.isEmpty
                        ? const Center(child: Text('No users found.'))
                        : ListView.separated(
                            itemCount: _visibleUsers.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppColors.outlineVariant,
                            ),
                            itemBuilder: (context, i) =>
                                _buildUserRow(_visibleUsers[i]),
                          ),
                  ),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  _buildFooterRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 11,
      color: AppColors.onSurfaceVariant,
      letterSpacing: 0.5,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('USER', style: style)),
          Expanded(flex: 2, child: Text('HANDLE', style: style)),
          Expanded(flex: 2, child: Text('JOIN DATE', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          SizedBox(width: 60, child: Text('ACTIONS', style: style)),
        ],
      ),
    );
  }

  Widget _buildUserRow(_AdminUser user) {
    final color = _statusColor(user.status);
    final avatarImage = _avatarImageFor(user);
    return InkWell(
      // Row tap opens the full audit screen for this user. The trailing
      // actions menu below has its own tap target and takes priority over
      // this, so "..." still opens the quick status popup instead.
      onTap: () => _openAudit(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(
                            Icons.person,
                            size: 16,
                            color: AppColors.onSurfaceVariant,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      user.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.email,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.createdAt != null ? _formatDate(user.createdAt!) : '—',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(user.status),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) => _setStatus(user, value),
                itemBuilder: (context) => [
                  if (user.status != 'active')
                    const PopupMenuItem(
                      value: 'active',
                      child: Text('Set Active'),
                    ),
                  if (user.status != 'flagged')
                    const PopupMenuItem(value: 'flagged', child: Text('Flag')),
                  if (user.status != 'suspended')
                    const PopupMenuItem(
                      value: 'suspended',
                      child: Text(
                        'Suspend',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterRow() {
    final startIndex = _totalCount == 0
        ? 0
        : (_currentPage - 1) * _pageSize + 1;
    final endIndex = (_currentPage - 1) * _pageSize + _pageUsers.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Text(
            'Showing $startIndex to $endIndex of $_totalCount results',
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
          ),
          const Spacer(),
          _PageButton(
            icon: Icons.chevron_left,
            onTap: _currentPage > 1 ? () => _loadPage(_currentPage - 1) : null,
          ),
          const SizedBox(width: 6),
          for (int p = 1; p <= _totalPages && p <= 3; p++) ...[
            _PageButton(
              label: '$p',
              selected: _currentPage == p,
              onTap: () => _loadPage(p),
            ),
            const SizedBox(width: 6),
          ],
          _PageButton(
            icon: Icons.chevron_right,
            onTap: _currentPage < _totalPages
                ? () => _loadPage(_currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

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

class _AdminUser {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String status;
  final DateTime? createdAt;

  _AdminUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.status,
    this.createdAt,
  });

  factory _AdminUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'] as Timestamp?;
    return _AdminUser(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Unnamed user',
      email: data['email'] ?? '—',
      photoUrl: data['photoUrl'],
      status: data['status'] ?? 'active',
      createdAt: ts?.toDate(),
    );
  }

  _AdminUser copyWith({String? status}) => _AdminUser(
    uid: uid,
    displayName: displayName,
    email: email,
    photoUrl: photoUrl,
    status: status ?? this.status,
    createdAt: createdAt,
  );
}

class _FilterPillDisplay extends StatelessWidget {
  const _FilterPillDisplay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    this.label,
    this.icon,
    this.selected = false,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 18,
                color: disabled
                    ? AppColors.outlineVariant
                    : AppColors.onSurfaceVariant,
              )
            : Text(
                label!,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }
}
