import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/UI/friends_list_screen.dart';
import 'package:first_app/UI/profile_settings_screen.dart';
import 'package:first_app/services/friends_repository.dart';
import 'package:first_app/services/post_repository.dart';
import 'package:first_app/utils/post_media_utils.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:first_app/widgets/post_media_viewer.dart';
import 'package:flutter/material.dart';

const _privacyOptions = [
  {'value': 'public', 'label': 'Public', 'icon': Icons.public},
  {'value': 'friends', 'label': 'Friends', 'icon': Icons.people},
  {'value': 'closedFriends', 'label': 'Closed Friends', 'icon': Icons.star},
  {'value': 'private', 'label': 'Only Me', 'icon': Icons.lock},
];

const _reactionIcons = {
  'like': Icons.thumb_up,
  'love': Icons.favorite,
  'haha': Icons.sentiment_very_satisfied,
  'wow': Icons.emoji_emotions,
  'sad': Icons.sentiment_dissatisfied,
  'angry': Icons.sentiment_very_dissatisfied_rounded,
};

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _postRepo = PostRepository();
  final _friendsRepo = FriendsRepository();
  List<String> _friendsList = [];

  bool get _isOwnProfile =>
      FirebaseAuth.instance.currentUser?.uid == widget.userId;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await _friendsRepo.getFriendsList();
    if (mounted) setState(() => _friendsList = friends);
  }

  String _privacyLabel(String privacy) {
    return (_privacyOptions.firstWhere(
          (o) => o['value'] == privacy,
          orElse: () => _privacyOptions.first,
        )['label']
        as String);
  }

  void _showPrivacyEditor(String postId, String currentPrivacy) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Change Privacy',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                for (final option in _privacyOptions)
                  ListTile(
                    leading: Icon(
                      option['icon'] as IconData,
                      color:
                          currentPrivacy == option['value']
                              ? Theme.of(context).colorScheme.primary
                              : null,
                    ),
                    title: Text(option['label'] as String),
                    trailing:
                        currentPrivacy == option['value']
                            ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _postRepo.updatePostPrivacy(
                        postId,
                        option['value'] as String,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Privacy changed to ${option['label']}',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _confirmDeletePost(String postId) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Post?'),
            content: const Text('This post will be permanently deleted.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _postRepo.deletePost(postId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Post deleted.')),
                    );
                  }
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  void _openPostDetail(Map<String, dynamic> post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder:
          (context) => _PostDetailSheet(
            post: post,
            isOwner: _isOwnProfile,
            postRepo: _postRepo,
            onDeleted: () => Navigator.pop(context),
            onEditPrivacy: _showPrivacyEditor,
          ),
    );
  }

  void _openFriendsList(List<String> friends) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FriendsListScreen(friendIds: friends)),
    );
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(
              base64Decode(photoUrl.split(',').last),
            ),
          );
        } catch (_) {}
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOwnProfile ? 'My Profile' : 'Profile'),
        actions: [
          if (_isOwnProfile)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileSettingsScreen(),
                    ),
                  ),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('users')
                .doc(widget.userId)
                .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting &&
              !userSnapshot.hasData) {
            return const AppLoadingScreen(message: 'Loading profile...');
          }

          final userData = userSnapshot.data?.data() ?? {};
          final displayName = userData['displayName'] as String? ?? 'User';
          final photoUrl = userData['photoUrl'] as String?;
          final email = userData['email'] as String?;
          final friends = List<String>.from(userData['friends'] ?? []);
          final isFriend = _friendsList.contains(widget.userId);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildAvatar(photoUrl, 42),
                          const SizedBox(width: 24),
                          Expanded(
                            child: StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _postRepo.getUserPostsStream(
                                widget.userId,
                                _friendsList,
                              ),
                              builder: (context, postSnapshot) {
                                final postCount =
                                    postSnapshot.data?.length ?? 0;
                                return Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _StatColumn(
                                      count: postCount,
                                      label: 'Posts',
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _openFriendsList(friends),
                                      child: _StatColumn(
                                        count: friends.length,
                                        label: 'Friends',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isOwnProfile &&
                          email != null &&
                          email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!_isOwnProfile) ...[
                        const SizedBox(height: 12),
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _friendsRepo.requestStatusStream(
                            widget.userId,
                          ),
                          builder: (context, reqSnap) {
                            final reqType =
                                reqSnap.data?.data()?['type'] as String?;

                            if (isFriend) {
                              return OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Friends'),
                              );
                            }

                            if (reqType == 'sent') {
                              return OutlinedButton.icon(
                                onPressed: () async {
                                  await _friendsRepo.declineFriendRequest(
                                    widget.userId,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Friend request cancelled'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.schedule_send, size: 18),
                                label: const Text('Request Sent'),
                              );
                            }

                            if (reqType == 'received') {
                              return Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        try {
                                          await _friendsRepo
                                              .acceptFriendRequest(
                                                widget.userId,
                                              );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Friend accepted!'),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Error: $e'),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Accept'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await _friendsRepo.declineFriendRequest(
                                          widget.userId,
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Request declined'),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Decline'),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return OutlinedButton.icon(
                              onPressed: () async {
                                await _friendsRepo.sendFriendRequest(
                                  widget.userId,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Friend request sent'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_add, size: 18),
                              label: const Text('Add Friend'),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _postRepo.getUserPostsStream(
                  widget.userId,
                  _friendsList,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      child: AppLoadingScreen(message: 'Loading posts...'),
                    );
                  }

                  final posts = snapshot.data ?? [];
                  if (posts.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _isOwnProfile
                              ? 'You have not posted anything yet.'
                              : 'No posts to show.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                            childAspectRatio: 1,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final post = posts[index];
                        final images = PostMediaUtils.getImages(post);
                        final isStatus = images.isEmpty;
                        final postId = post['id'] as String;
                        final currentPrivacy =
                            post['privacy'] as String? ?? 'public';

                        return GestureDetector(
                          onTap: () => _openPostDetail(post),
                          onLongPress:
                              _isOwnProfile
                                  ? () {
                                    showModalBottomSheet<void>(
                                      context: context,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                      ),
                                      builder:
                                          (ctx) => SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 8),
                                                Container(
                                                  width: 38,
                                                  height: 4,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        colorScheme
                                                            .outlineVariant,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.lock_outline,
                                                  ),
                                                  title: const Text(
                                                    'Edit Privacy',
                                                  ),
                                                  subtitle: Text(
                                                    'Currently: ${_privacyLabel(currentPrivacy)}',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _showPrivacyEditor(
                                                      postId,
                                                      currentPrivacy,
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  title: const Text(
                                                    'Delete Post',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _confirmDeletePost(postId);
                                                  },
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                            ),
                                          ),
                                    );
                                  }
                                  : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: colorScheme.surfaceContainerHighest,
                                child:
                                    isStatus
                                        ? Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF2563EB),
                                                Color(0xFF7C3AED),
                                              ],
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          child: Center(
                                            child: Text(
                                              (post['caption'] as String? ?? '')
                                                  .trim(),
                                              maxLines: 4,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        )
                                        : Image.memory(
                                          base64Decode(images.first),
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, __, ___) => const Icon(
                                                Icons.broken_image,
                                              ),
                                        ),
                              ),
                              if (images.length > 1)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.collections,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${images.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_isOwnProfile && currentPrivacy != 'public')
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      currentPrivacy == 'friends'
                                          ? Icons.people
                                          : currentPrivacy == 'closedFriends'
                                          ? Icons.star
                                          : Icons.lock,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }, childCount: posts.length),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Post Detail Sheet ──────────────────────────────────

class _PostDetailSheet extends StatefulWidget {
  const _PostDetailSheet({
    required this.post,
    required this.isOwner,
    required this.postRepo,
    required this.onDeleted,
    required this.onEditPrivacy,
  });

  final Map<String, dynamic> post;
  final bool isOwner;
  final PostRepository postRepo;
  final VoidCallback onDeleted;
  final void Function(String postId, String currentPrivacy) onEditPrivacy;

  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _commentController = TextEditingController();
  bool _sending = false;
  String? _replyToCommentId;
  String? _replyToUserName;
  String? _replyToUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _setReplyTo(String commentId, String userName, String userId) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToUserName = userName;
      _replyToUserId = userId;
    });
  }

  void _clearReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUserName = null;
      _replyToUserId = null;
    });
  }

  Future<void> _send(String postId) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_replyToCommentId != null) {
        await widget.postRepo.replyToComment(
          postId: postId,
          text: text,
          replyToCommentId: _replyToCommentId!,
          replyToUserName: _replyToUserName!,
          replyToUserId: _replyToUserId!,
        );
      } else {
        await widget.postRepo.addComment(postId, text);
      }
      _commentController.clear();
      _clearReply();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.post['caption'] as String? ?? '';
    final images = PostMediaUtils.getImages(widget.post);
    final isStatus = images.isEmpty;
    final reactions = Map<String, dynamic>.from(widget.post['reactions'] ?? {});
    final postId = widget.post['id'] as String;
    final currentPrivacy = widget.post['privacy'] as String? ?? 'public';
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            if (isStatus)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                  ),
                ),
                child: Text(
                  caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PostMediaViewer(images: images, aspectRatio: 4 / 3),
              ),
            if (!isStatus && caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(caption),
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'Comments'),
                Tab(text: 'Reactions (${reactions.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: widget.postRepo.commentsStream(postId),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return const Center(
                                child: Text('No comments yet.'),
                              );
                            }
                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final data = docs[index].data();
                                final commentId = docs[index].id;
                                final isMine =
                                    data['userId'] ==
                                    FirebaseAuth.instance.currentUser?.uid;
                                final userName =
                                    data['userName'] as String? ?? 'User';
                                final commentUserId =
                                    data['userId'] as String? ?? '';
                                final text = data['text'] as String? ?? '';
                                final replyToName =
                                    data['replyToName'] as String?;
                                final isReply = replyToName != null;

                                return Padding(
                                  padding: EdgeInsets.only(
                                    left: isReply ? 40 : 0,
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: 16,
                                      child: Text(
                                        userName.isNotEmpty
                                            ? userName[0].toUpperCase()
                                            : '?',
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          userName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (isReply) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_forward,
                                            size: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            replyToName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(text),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap:
                                              () => _setReplyTo(
                                                commentId,
                                                userName,
                                                commentUserId,
                                              ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Text(
                                              'Reply',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (isMine)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                            ),
                                            onPressed:
                                                () => widget.postRepo
                                                    .deleteOwnComment(
                                                      postId,
                                                      commentId,
                                                    ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      if (_replyToUserName != null)
                        Container(
                          color: colorScheme.surfaceContainerHighest,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.reply,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Replying to $_replyToUserName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _clearReply,
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 12,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                          top: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                minLines: 1,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText:
                                      _replyToUserName != null
                                          ? 'Reply to $_replyToUserName...'
                                          : 'Add a comment...',
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _sending ? null : () => _send(postId),
                              icon:
                                  _sending
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  reactions.isEmpty
                      ? const Center(child: Text('No reactions yet.'))
                      : ListView.builder(
                        itemCount: reactions.length,
                        itemBuilder: (context, index) {
                          final uid = reactions.keys.elementAt(index);
                          final reaction = reactions[uid] as String;
                          return FutureBuilder<
                            DocumentSnapshot<Map<String, dynamic>>
                          >(
                            future:
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .get(),
                            builder: (context, snap) {
                              final name =
                                  snap.data?.data()?['displayName']
                                      as String? ??
                                  'User';
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(name),
                                trailing: Icon(
                                  _reactionIcons[reaction] ?? Icons.thumb_up,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              );
                            },
                          );
                        },
                      ),
                ],
              ),
            ),
            if (widget.isOwner) ...[
              const Divider(height: 1),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.lock_outline),
                      label: Text('Privacy: $currentPrivacy'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEditPrivacy(postId, currentPrivacy);
                      },
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (ctx) => AlertDialog(
                                title: const Text('Delete Post?'),
                                content: const Text(
                                  'This will be permanently deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                        );
                        if (confirm == true) {
                          await widget.postRepo.deletePost(postId);
                          widget.onDeleted();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
