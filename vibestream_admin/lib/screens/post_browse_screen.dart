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
  final FirestoreAdminService _service = FirestoreAdminService();

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

  // --------------------------------------------------
  // Load posts
  // --------------------------------------------------

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;

    setState(() {
      _loading = true;
    });

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
        'posts',
      );

      query = _sortByReports
          ? query.orderBy('reportCount', descending: true)
          : query.orderBy('createdAt', descending: true);

      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snap = await query.limit(25).get();

      final newPosts = snap.docs.map((doc) => AdminPost.fromDoc(doc)).toList();

      // Load user names and emails.
      await _service.loadUsersForPosts(newPosts);

      if (!mounted) return;

      setState(() {
        _posts.addAll(newPosts);

        if (snap.docs.isNotEmpty) {
          _lastDoc = snap.docs.last;
        }

        _hasMore = snap.docs.length == 25;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load posts: $e')));
    }
  }

  // --------------------------------------------------
  // Reset
  // --------------------------------------------------

  void _resetAndReload({required bool sortByReports}) {
    setState(() {
      _sortByReports = sortByReports;
      _posts.clear();
      _lastDoc = null;
      _hasMore = true;
    });

    _loadMore();
  }

  // --------------------------------------------------
  // Remove post
  // --------------------------------------------------

  Future<void> _removePost(AdminPost post) async {
    try {
      await _service.removePost(post.id);

      if (!mounted) return;

      final index = _posts.indexWhere((p) => p.id == post.id);

      if (index != -1) {
        setState(() {
          _posts[index] = post.copyWith(status: 'removed');
        });
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post removed')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove post: $e')));
    }
  }

  // --------------------------------------------------
  // Restore post
  // --------------------------------------------------

  Future<void> _restorePost(AdminPost post) async {
    try {
      await _service.restorePost(post.id);

      if (!mounted) return;

      final index = _posts.indexWhere((p) => p.id == post.id);

      if (index != -1) {
        setState(() {
          _posts[index] = post.copyWith(status: 'active');
        });
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post restored')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to restore post: $e')));
    }
  }

  // --------------------------------------------------
  // User name
  // --------------------------------------------------

  String _getDisplayName(AdminPost post) {
    final name = _service.getUserDisplayName(post.authorId);

    if (name != null && name.isNotEmpty) {
      return name;
    }

    if (post.authorName != null && post.authorName!.isNotEmpty) {
      return post.authorName!;
    }

    return 'Unknown user';
  }

  // --------------------------------------------------
  // User email
  // --------------------------------------------------

  String? _getEmail(AdminPost post) {
    final email = _service.getUserEmail(post.authorId);

    if (email != null && email.isNotEmpty) {
      return email;
    }

    if (post.authorEmail != null && post.authorEmail!.isNotEmpty) {
      return post.authorEmail;
    }

    return null;
  }

  // --------------------------------------------------
  // User information widget
  // --------------------------------------------------

  Widget _buildUserInfo(AdminPost post) {
    final displayName = _getDisplayName(post);
    final email = _getEmail(post);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        if (email != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              email,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------
  // Build
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All posts'),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _sortByReports,
            onSelected: (value) {
              _resetAndReload(sortByReports: value);
            },
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
        onNotification: (notification) {
          if (notification.metrics.pixels >
              notification.metrics.maxScrollExtent - 300) {
            _loadMore();
          }

          return false;
        },

        child: ListView.builder(
          itemCount: _posts.length + 1,

          itemBuilder: (context, index) {
            // Loading / end indicator
            if (index == _posts.length) {
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

            final post = _posts[index];

            final removed = post.status == 'removed';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),

              // ----------------------------------------
              // Thumbnail
              // ----------------------------------------
              leading: PostThumbnail(
                media: post.media,
                base64Data: post.imageBase64,
                mediaUrl: post.mediaUrl,
                thumbnailUrl: post.thumbnailUrl,
                mediaType: post.mediaType,
                size: 56,
              ),

              // ----------------------------------------
              // User + caption
              // ----------------------------------------
              title: _buildUserInfo(post),

              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  post.caption ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // ----------------------------------------
              // Actions
              // ----------------------------------------
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
