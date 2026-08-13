import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/admin_post.dart';
import '../services/firestore_admin_service.dart';
import '../widgets/post_thumbnail.dart';

class PostBrowseScreen extends StatefulWidget {
  const PostBrowseScreen({super.key});

  @override
  State<PostBrowseScreen> createState() => _PostBrowseScreenState();
}

class _PostBrowseScreenState extends State<PostBrowseScreen> {
  final _service = FirestoreAdminService();
  final List<AdminPost> _posts = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  bool _sortByReports = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    final query = FirebaseFirestore.instance.collection('posts');
    // Fetch raw docs so we can track the DocumentSnapshot cursor;
    // FirestoreAdminService.fetchPosts wraps this same query logic.
    Query<Map<String, dynamic>> q = _sortByReports
        ? query.orderBy('reportCount', descending: true)
        : query.orderBy('createdAt', descending: true);
    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    final snap = await q.limit(25).get();

    setState(() {
      _posts.addAll(snap.docs.map((d) => AdminPost.fromDoc(d)));
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
      _hasMore = snap.docs.length == 25;
      _loading = false;
    });
  }

  void _resetAndReload({required bool sortByReports}) {
    setState(() {
      _sortByReports = sortByReports;
      _posts.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    _loadMore();
  }

  Future<void> _removePost(AdminPost post) async {
    await _service.removePost(post.id);
    setState(() {
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i != -1) {
        _posts[i] = AdminPost(
          id: post.id,
          authorId: post.authorId,
          authorName: post.authorName,
          caption: post.caption,
          imageBase64: post.imageBase64,
          status: 'removed',
          reportCount: post.reportCount,
          createdAt: post.createdAt,
        );
      }
    });
  }

  Future<void> _restorePost(AdminPost post) async {
    await _service.restorePost(post.id);
    setState(() {
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i != -1) {
        _posts[i] = AdminPost(
          id: post.id,
          authorId: post.authorId,
          authorName: post.authorName,
          caption: post.caption,
          imageBase64: post.imageBase64,
          status: 'active',
          reportCount: post.reportCount,
          createdAt: post.createdAt,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All posts'),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _sortByReports,
            onSelected: (v) => _resetAndReload(sortByReports: v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Sort: newest first')),
              PopupMenuItem(
                value: true,
                child: Text('Sort: most reported first'),
              ),
            ],
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _loadMore();
          return false;
        },
        child: ListView.builder(
          itemCount: _posts.length + 1,
          itemBuilder: (context, i) {
            if (i == _posts.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : (!_hasMore
                            ? const Text('No more posts')
                            : const SizedBox()),
                ),
              );
            }
            final post = _posts[i];
            final removed = post.status == 'removed';
            return ListTile(
              leading: PostThumbnail(base64Data: post.imageBase64, size: 48),
              title: Text(post.authorName ?? post.authorId),
              subtitle: Text(
                post.caption ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (post.reportCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(label: Text('${post.reportCount} reports')),
                    ),
                  if (removed)
                    TextButton(
                      onPressed: () => _restorePost(post),
                      child: const Text('Restore'),
                    )
                  else
                    TextButton(
                      onPressed: () => _removePost(post),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
