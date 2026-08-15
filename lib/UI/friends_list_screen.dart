import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_app/UI/user_profile_screen.dart';
import 'package:flutter/material.dart';

class FriendsListScreen extends StatelessWidget {
  const FriendsListScreen({
    super.key,
    required this.friendIds,
    this.title = 'Friends',
  });

  final List<String> friendIds;
  final String title;

  Widget _buildAvatar(BuildContext context, String? photoUrl, double radius) {
    final colorScheme = Theme.of(context).colorScheme;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          return CircleAvatar(
            radius: radius,
            backgroundColor: colorScheme.surfaceContainerHighest,
            backgroundImage: MemoryImage(
              base64Decode(photoUrl.split(',').last),
            ),
          );
        } catch (_) {}
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundColor: colorScheme.surfaceContainerHighest,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: radius,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('$title (${friendIds.length})')),
      body:
          friendIds.isEmpty
              ? Center(
                child: Text(
                  'No friends yet.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: friendIds.length,
                separatorBuilder:
                    (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                itemBuilder: (context, index) {
                  final friendId = friendIds[index];
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream:
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(friendId)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                          ),
                          title: Container(
                            height: 12,
                            width: 120,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }

                      final data = snapshot.data?.data();
                      if (data == null) return const SizedBox.shrink();

                      final displayName =
                          data['displayName'] as String? ?? 'User';
                      final photoUrl = data['photoUrl'] as String?;
                      final email = data['email'] as String?;

                      return ListTile(
                        leading: _buildAvatar(context, photoUrl, 24),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle:
                            email != null && email.isNotEmpty
                                ? Text(
                                  email,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                                : null,
                        trailing: Icon(
                          Icons.chevron_right,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => UserProfileScreen(userId: friendId),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
    );
  }
}
