import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// TODO: fix this import path to match where post_repository.dart actually
// lives in your project.
import 'package:first_app/services/post_repository.dart';

/// Shows one specific post — reached from a "friend added a post"
/// notification. Has its own AppBar (with a back button) so it slots on
/// top of the notifications screen without touching newsfeed navigation.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _postRepo = PostRepository();
  final _commentController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('posts').doc(widget.postId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('This post is no longer available.'),
            );
          }

          final post = snapshot.data!.data()!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    _PostHeader(userId: post['userId'] as String? ?? ''),
                    if ((post['base64Data'] as String? ?? '').isNotEmpty)
                      Image.memory(
                        base64Decode(post['base64Data']),
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    if ((post['caption'] as String? ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          post['caption'],
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    _ReactionBar(
                      postId: widget.postId,
                      post: post,
                      postRepo: _postRepo,
                    ),
                    const Divider(height: 24),
                    _CommentsList(postId: widget.postId, postRepo: _postRepo),
                  ],
                ),
              ),
              _CommentInput(
                controller: _commentController,
                onSend: () {
                  final text = _commentController.text;
                  if (text.trim().isEmpty) return;
                  _postRepo.addComment(widget.postId, text);
                  _commentController.clear();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = data?['displayName'] as String? ?? 'Someone';
        // photoUrl holds a full data:image/...;base64,... URI — same shape
        // as notifications_screen.dart's decodeAvatarImage handles.
        final photo = data?['photoUrl'] as String?;
        ImageProvider? provider;
        if (photo != null && photo.isNotEmpty) {
          if (photo.startsWith('http')) {
            provider = NetworkImage(photo);
          } else if (photo.startsWith('data:')) {
            final commaIndex = photo.indexOf(',');
            if (commaIndex != -1) {
              provider = MemoryImage(
                base64Decode(photo.substring(commaIndex + 1)),
              );
            }
          } else {
            provider = MemoryImage(base64Decode(photo));
          }
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: provider,
                child: provider == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.postId,
    required this.post,
    required this.postRepo,
  });

  final String postId;
  final Map<String, dynamic> post;
  final PostRepository postRepo;

  static const _reactions = {
    'like': '👍',
    'love': '❤️',
    'haha': '😂',
    'wow': '😮',
    'sad': '😢',
  };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final reactions = Map<String, dynamic>.from(post['reactions'] ?? {});
    final myReaction = uid != null ? reactions[uid] as String? : null;
    final totalReactions = reactions.length;
    final commentsCount = post['commentsCount'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (totalReactions > 0 || commentsCount > 0)
            Text(
              '$totalReactions reaction${totalReactions == 1 ? '' : 's'} · '
              '$commentsCount comment${commentsCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children:
                _reactions.entries.map((entry) {
                  final selected = myReaction == entry.key;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap:
                        () => postRepo.setReaction(
                          postId,
                          selected ? null : entry.key,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            selected
                                ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CommentsList extends StatelessWidget {
  const _CommentsList({required this.postId, required this.postRepo});
  final String postId;
  final PostRepository postRepo;

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: postRepo.commentsStream(postId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No comments yet — be the first to say something.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return Column(
          children:
              docs.map((doc) {
                final c = doc.data();
                final isMine = c['userId'] == myUid;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        child: Icon(Icons.person, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['userName'] as String? ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (c['replyToName'] != null)
                              Text(
                                'replying to ${c['replyToName']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Text(c['text'] as String? ?? ''),
                          ],
                        ),
                      ),
                      if (isMine)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed:
                              () => postRepo.deleteOwnComment(postId, doc.id),
                        ),
                    ],
                  ),
                );
              }).toList(),
        );
      },
    );
  }
}

class _CommentInput extends StatelessWidget {
  const _CommentInput({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Write a comment…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send_rounded), onPressed: onSend),
          ],
        ),
      ),
    );
  }
}
