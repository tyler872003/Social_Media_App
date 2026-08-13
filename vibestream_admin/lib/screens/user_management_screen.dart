import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Your `users` documents don't currently have a `status` field, so every
/// user shows as Active until you suspend one — suspending sets status:
/// 'suspended' the same way removing a post sets status: 'removed'.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final List<_AdminUser> _users = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('users').orderBy(FieldPath.documentId);
    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    final snap = await q.limit(25).get();
    setState(() {
      _users.addAll(snap.docs.map((d) => _AdminUser.fromDoc(d)));
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
      _hasMore = snap.docs.length == 25;
      _loading = false;
    });
  }

  Future<void> _setStatus(_AdminUser user, String status) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'status': status,
    });
    setState(() {
      final i = _users.indexWhere((u) => u.uid == user.uid);
      if (i != -1) _users[i] = user.copyWith(status: status);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('User Management', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 4),
          Text('View and manage all registered users.',
              style: TextStyle(color: AppColors.onSurfaceVariant)),
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
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                          _loadMore();
                        }
                        return false;
                      },
                      child: ListView.separated(
                        itemCount: _users.length + 1,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.outlineVariant),
                        itemBuilder: (context, i) {
                          if (i == _users.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _loading
                                    ? const CircularProgressIndicator()
                                    : (!_hasMore ? const Text('No more users') : const SizedBox()),
                              ),
                            );
                          }
                          return _buildUserRow(_users[i]);
                        },
                      ),
                    ),
                  ),
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
        fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.onSurfaceVariant, letterSpacing: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text('USER', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          SizedBox(width: 100, child: Text('ACTIONS', style: style)),
        ],
      ),
    );
  }

  Widget _buildUserRow(_AdminUser user) {
    final isActive = user.status != 'suspended';
    return Padding(
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
                  backgroundImage:
                      user.photoUrl != null && user.photoUrl!.startsWith('http')
                          ? NetworkImage(user.photoUrl!)
                          : null,
                  child: user.photoUrl == null || !user.photoUrl!.startsWith('http')
                      ? const Icon(Icons.person, size: 16, color: AppColors.onSurfaceVariant)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(user.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.tertiary.withValues(alpha: 0.12)
                    : AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isActive ? 'Active' : 'Suspended',
                style: TextStyle(
                  color: isActive ? AppColors.tertiary : AppColors.secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: TextButton(
              onPressed: () => _setStatus(user, isActive ? 'suspended' : 'active'),
              child: Text(
                isActive ? 'Suspend' : 'Reactivate',
                style: TextStyle(color: isActive ? AppColors.secondary : AppColors.tertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String status;

  _AdminUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.status,
  });

  factory _AdminUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return _AdminUser(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Unnamed user',
      photoUrl: data['photoUrl'],
      status: data['status'] ?? 'active',
    );
  }

  _AdminUser copyWith({String? status}) => _AdminUser(
        uid: uid,
        displayName: displayName,
        photoUrl: photoUrl,
        status: status ?? this.status,
      );
}
