import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/UI/add_post_screen.dart';
import 'package:first_app/UI/home_chats_screen.dart';
import 'package:first_app/UI/user_profile_screen.dart';
import 'package:first_app/UI/view_story_screen.dart';
import 'package:first_app/services/friends_repository.dart';
import 'package:first_app/services/post_repository.dart';
import 'package:first_app/services/story_repository.dart';
import 'package:first_app/utils/post_media_utils.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:first_app/widgets/post_media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:first_app/widgets/report_post_sheet.dart';

const List<String> _reactionOptions = [
  'like',
  'love',
  'haha',
  'wow',
  'sad',
  'angry',
];

const Map<String, String> _reactionLabels = {
  'like': 'Like',
  'love': 'Love',
  'haha': 'Haha',
  'wow': 'Wow',
  'sad': 'Sad',
  'angry': 'Angry',
};

const Map<String, IconData> _reactionIcons = {
  'like': Icons.thumb_up,
  'love': Icons.favorite,
  'haha': Icons.sentiment_very_satisfied,
  'wow': Icons.emoji_emotions,
  'sad': Icons.sentiment_dissatisfied,
  'angry': Icons.sentiment_very_dissatisfied_rounded,
};

const _privacyOptions = [
  {'value': 'public', 'label': 'Public', 'icon': Icons.public},
  {'value': 'friends', 'label': 'Friends', 'icon': Icons.people},
  {'value': 'closedFriends', 'label': 'Closed Friends', 'icon': Icons.star},
  {'value': 'private', 'label': 'Only Me', 'icon': Icons.lock},
];

/// Formats a timestamp the way social feeds usually do:
/// "Just now" -> "5 min" -> "1 hr" -> "3 d" -> full date once it's old.
String formatTimeAgo(dynamic createdAt) {
  DateTime? dateTime;
  if (createdAt is Timestamp) {
    dateTime = createdAt.toDate();
  } else if (createdAt is DateTime) {
    dateTime = createdAt;
  } else if (createdAt is int) {
    dateTime = DateTime.fromMillisecondsSinceEpoch(createdAt);
  }
  if (dateTime == null) return '';

  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) {
    return 'Just now';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min';
  } else if (diff.inHours < 24) {
    return '${diff.inHours} hr';
  } else if (diff.inDays < 30) {
    return '${diff.inDays} d';
  } else {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }
}

class NewsfeedScreen extends StatefulWidget {
  const NewsfeedScreen({super.key});

  @override
  State<NewsfeedScreen> createState() => _NewsfeedScreenState();
}

class _NewsfeedScreenState extends State<NewsfeedScreen> {
  final _scrollController = ScrollController();
  final _postRepo = PostRepository();
  final _friendsRepo = FriendsRepository();
  final _storyRepo = StoryRepository();
  final _auth = FirebaseAuth.instance;

  Stream<List<Map<String, dynamic>>>? _newsfeedStream;
  List<String> _friendsList = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() async {
    _friendsList = await _friendsRepo.getFriendsList();
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _currentUserData = await _getUserData(uid);
    }
    setState(() {
      _newsfeedStream = _postRepo.getNewsfeedStream(_friendsList);
    });
    _friendsRepo.currentUserStream().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _friendsList = List<String>.from(snapshot.data()?['friends'] ?? []);
          _currentUserData = snapshot.data();
          _newsfeedStream = _postRepo.getNewsfeedStream(_friendsList);
        });
      }
    });
    _storyRepo.startPeriodicCleanup();
  }

  Future<void> _refreshNewsfeed() async {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    final uid = _auth.currentUser?.uid;
    final freshFriendsList = await _friendsRepo.getFriendsList();
    Map<String, dynamic>? freshUserData;
    if (uid != null) {
      _userCache.remove(uid);
      freshUserData = await _getUserData(uid);
    }
    if (!mounted) return;
    setState(() {
      _friendsList = freshFriendsList;
      _currentUserData = freshUserData ?? _currentUserData;
      _newsfeedStream = _postRepo.getNewsfeedStream(_friendsList);
    });
  }

  Future<void> _openAddPost() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPostScreen()),
    );
  }

  @override
  void dispose() {
    _storyRepo.stopPeriodicCleanup();
    _scrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getUserData(String uid) async {
    if (_userCache.containsKey(uid)) return _userCache[uid]!;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      _userCache[uid] = doc.data()!;
      return doc.data()!;
    }
    return {};
  }

  void _showPostMenu(Map<String, dynamic> post) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final postId = post['id'] as String;
    final isOwner = post['userId'] == uid;
    final currentPrivacy = post['privacy'] as String? ?? 'public';

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
                const SizedBox(height: 8),
                if (isOwner) ...[
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Edit Privacy'),
                    subtitle: Text(
                      'Currently: ${_privacyLabel(currentPrivacy)}',
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPrivacyEditor(postId, currentPrivacy);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: const Text(
                      'Delete Post',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeletePost(postId);
                    },
                  ),
                ] else
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, color: Colors.red),
                    title: const Text(
                      'Report Post',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      showReportPostSheet(context, postId: postId);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
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

  String _privacyLabel(String privacy) {
    return (_privacyOptions.firstWhere(
          (o) => o['value'] == privacy,
          orElse: () => _privacyOptions.first,
        )['label']
        as String);
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold/bottom nav here anymore — this screen is embedded as a
    // tab body inside MainNavigationScreen, which owns the persistent
    // bottom navigation bar.
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: _buildNewsfeed(),
    );
  }

  Widget _buildNewsfeed() {
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _refreshNewsfeed,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Floating + snap: the title scrolls away with the feed instead of
          // permanently eating screen space, and slides back in as soon as
          // the user scrolls up even slightly.
          SliverAppBar(
            backgroundColor: colorScheme.surface,
            elevation: 0,
            floating: true,
            snap: true,
            pinned: false,
            centerTitle: true,
            title: Text(
              'VibeStream',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildStoriesSection()),
          SliverToBoxAdapter(child: _buildComposer()),
          SliverToBoxAdapter(
            child: AppLoadingGate(
              isLoading: _newsfeedStream == null,
              loading: const AppLoadingScreen(message: 'Loading your feed...'),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _newsfeedStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const AppLoadingScreen(message: 'Loading posts...');
                  }
                  final posts = snapshot.data ?? [];
                  if (posts.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('No posts yet. Be the first to post!'),
                      ),
                    );
                  }
                  return ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: posts.length,
                    itemBuilder:
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPostCard(posts[index]),
                        ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = _currentUserData?['photoUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Material(
        color: colorScheme.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildAvatar(photoUrl, 18),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _openAddPost,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      "What's on your mind?",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _openAddPost,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoriesSection() {
    return Container(
      height: 105,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Theme.of(context).colorScheme.surface,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _storyRepo.activeStoriesStream(),
        builder: (context, snapshot) {
          final stories = snapshot.data?.docs ?? [];
          final grouped =
              <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in stories) {
            final uid = doc.data()['userId'] as String;
            grouped.putIfAbsent(uid, () => []).add(doc);
          }
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: grouped.keys.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const AddStoryItem();
              }
              final uid = grouped.keys.elementAt(index - 1);
              return _buildStoryItem(uid, grouped[uid]!);
            },
          );
        },
      ),
    );
  }

  Widget _buildStoryItem(
    String userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> stories,
  ) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserData(userId),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final photoUrl = userData?['photoUrl'] as String?;
        final displayName = userData?['displayName'] as String? ?? 'User';

        return GestureDetector(
          onTap: () {
            if (userData != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => ViewStoryScreen(
                        user: userData,
                        stories: stories,
                        storyId: '',
                      ),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.blue, Colors.pink],
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: _buildAvatar(photoUrl, 30),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final uid = _auth.currentUser?.uid;
    final postId = post['id'] as String;
    final userId = post['userId'] as String;
    final isOwner = userId == uid;
    final caption = post['caption'] as String? ?? '';
    final images = PostMediaUtils.getImages(post);
    final isStatus = images.isEmpty;
    final likes = List<String>.from(post['likes'] ?? []);
    final reactions = Map<String, dynamic>.from(post['reactions'] ?? {});
    final myReaction = uid == null ? null : reactions[uid] as String?;
    final commentsCount = post['commentsCount'] as int? ?? 0;
    final timeAgo = formatTimeAgo(post['createdAt']);

    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserData(userId),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final displayName = userData?['displayName'] as String? ?? 'User';
        final photoUrl = userData?['photoUrl'] as String?;
        final colorScheme = Theme.of(context).colorScheme;

        if (isStatus) {
          return _buildStatusPostCard(
            postId: postId,
            userId: userId,
            isOwner: isOwner,
            displayName: displayName,
            photoUrl: photoUrl,
            caption: caption,
            timeAgo: timeAgo,
            likesCount: likes.length,
            commentsCount: commentsCount,
            myReaction: myReaction,
            post: post,
          );
        }

        return Material(
          color: colorScheme.surface,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(userId: userId),
                            ),
                          ),
                      child: _buildAvatar(photoUrl, 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => UserProfileScreen(userId: userId),
                              ),
                            ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onPressed: () => _showPostMenu(post),
                    ),
                  ],
                ),
              ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Text(
                    caption,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: PostMediaViewer(
                  images: images,
                  aspectRatio: images.length > 1 ? 1.1 : 4 / 5,
                  canDownload:
                      uid != null && PostMediaUtils.canUserDownload(post, uid),
                ),
              ),
              const SizedBox(height: 10),
              _buildPostActions(
                postId: postId,
                myReaction: myReaction,
                likesCount: likes.length,
                commentsCount: commentsCount,
                colorScheme: colorScheme,
                lightIcons: false,
              ),
              if (likes.isNotEmpty || caption.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Text(
                    '${likes.length} ${likes.length == 1 ? 'like' : 'likes'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (commentsCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: GestureDetector(
                    onTap: () => _openCommentsSheet(postId),
                    child: Text(
                      'View all $commentsCount comments',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusPostCard({
    required String postId,
    required String userId,
    required bool isOwner,
    required String displayName,
    required String? photoUrl,
    required String caption,
    required String timeAgo,
    required int likesCount,
    required int commentsCount,
    required String? myReaction,
    required Map<String, dynamic> post,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: userId),
                      ),
                    ),
                child: _buildAvatar(photoUrl, 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.more_horiz,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                onPressed: () => _showPostMenu(post),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            caption,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 8),
          _buildPostActions(
            postId: postId,
            myReaction: myReaction,
            likesCount: likesCount,
            commentsCount: commentsCount,
            colorScheme: Theme.of(context).colorScheme,
            lightIcons: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPostActions({
    required String postId,
    required String? myReaction,
    required int likesCount,
    required int commentsCount,
    required ColorScheme colorScheme,
    required bool lightIcons,
  }) {
    final iconColor = lightIcons ? Colors.white : colorScheme.onSurface;
    final mutedColor =
        lightIcons
            ? Colors.white.withValues(alpha: 0.85)
            : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap:
                () => _postRepo.setReaction(
                  postId,
                  myReaction == null ? 'like' : null,
                ),
            onLongPress: () => _showReactionPicker(postId, myReaction),
            child: Row(
              children: [
                Icon(
                  myReaction == null
                      ? Icons.favorite_border
                      : (_reactionIcons[myReaction] ?? Icons.favorite),
                  color: myReaction == null ? iconColor : Colors.red,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  '$likesCount',
                  style: TextStyle(color: mutedColor, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: () => _openCommentsSheet(postId),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: iconColor, size: 21),
                const SizedBox(width: 6),
                Text(
                  '$commentsCount',
                  style: TextStyle(color: mutedColor, fontSize: 13),
                ),
              ],
            ),
          ),
          const Spacer(),
          Icon(Icons.share_outlined, color: iconColor, size: 21),
        ],
      ),
    );
  }

  Future<void> _showReactionPicker(
    String postId,
    String? currentReaction,
  ) async {
    final reaction = await showModalBottomSheet<String?>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final option in _reactionOptions)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        avatar: Icon(_reactionIcons[option], size: 18),
                        label: Text(_reactionLabels[option] ?? option),
                        onPressed: () => Navigator.pop(context, option),
                      ),
                    ),
                  if (currentReaction != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        avatar: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                        onPressed: () => Navigator.pop(context, '__remove__'),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
    if (reaction == null) return;
    await _postRepo.setReaction(
      postId,
      reaction == '__remove__' ? null : reaction,
    );
  }

  void _openCommentsSheet(String postId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CommentsSheet(postId: postId, postRepo: _postRepo),
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
}

// ── Comments Sheet with Reply ──────────────────────────

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId, required this.postRepo});
  final String postId;
  final PostRepository postRepo;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _replyToCommentId;
  String? _replyToUserName;
  String? _replyToUserId;

  @override
  void dispose() {
    _controller.dispose();
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_replyToCommentId != null) {
        await widget.postRepo.replyToComment(
          postId: widget.postId,
          text: text,
          replyToCommentId: _replyToCommentId!,
          replyToUserName: _replyToUserName!,
          replyToUserId: _replyToUserId!,
        );
      } else {
        await widget.postRepo.addComment(widget.postId, text);
      }
      _controller.clear();
      _clearReply();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Comments',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.postRepo.commentsStream(widget.postId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: AppLoadingIndicator(
                        message: 'Loading comments...',
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No comments yet.'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final commentId = docs[index].id;
                      final isMine =
                          data['userId'] ==
                          FirebaseAuth.instance.currentUser?.uid;
                      final userName = data['userName'] as String? ?? 'User';
                      final commentUserId = data['userId'] as String? ?? '';
                      final text = data['text'] as String? ?? '';
                      final replyToName = data['replyToName'] as String?;
                      final isReply = replyToName != null;

                      return Padding(
                        padding: EdgeInsets.only(left: isReply ? 40 : 0),
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
                                      () => widget.postRepo.deleteOwnComment(
                                        widget.postId,
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
            // Reply banner
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
            // Input
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText:
                            _replyToUserName != null
                                ? 'Reply to $_replyToUserName...'
                                : 'Add a comment...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon:
                        _sending
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
