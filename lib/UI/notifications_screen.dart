import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:first_app/services/friends_repository.dart';
import 'package:first_app/services/notification_feed_repository.dart';
import 'package:first_app/services/notification_model.dart';
import 'package:first_app/UI/post_detail_screen.dart';
import 'package:first_app/UI/user_profile_screen.dart';
import 'package:first_app/UI/view_story_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notificationRepo = NotificationFeedRepository();
  final _friendsRepo = FriendsRepository();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationRepo.notificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return _EmptyState(colorScheme: colorScheme);
          }

          final groups = _groupByDate(notifications);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];

              return _NotificationGroup(
                label: group.label,
                notifications: group.items,
                onTap: _handleTap,
                onAccept: _handleAccept,
              );
            },
          );
        },
      ),
    );
  }

  List<_Group> _groupByDate(List<AppNotification> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayItems = <AppNotification>[];
    final yesterdayItems = <AppNotification>[];
    final earlierItems = <AppNotification>[];

    for (final n in notifications) {
      final d = DateTime(n.timestamp.year, n.timestamp.month, n.timestamp.day);

      if (d == today) {
        todayItems.add(n);
      } else if (d == yesterday) {
        yesterdayItems.add(n);
      } else {
        earlierItems.add(n);
      }
    }

    final groups = <_Group>[];

    if (todayItems.isNotEmpty) {
      groups.add(_Group('TODAY', todayItems));
    }

    if (yesterdayItems.isNotEmpty) {
      groups.add(_Group('YESTERDAY', yesterdayItems));
    }

    if (earlierItems.isNotEmpty) {
      groups.add(_Group('EARLIER', earlierItems));
    }

    return groups;
  }

  Future<void> _handleTap(AppNotification n) async {
    if (!n.isRead) {
      await _notificationRepo.markAsRead(n.id);
    }

    if (!mounted) return;

    switch (n.type) {
      case NotificationType.story:
        if (n.storyId == null) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    ViewStoryScreen(storyId: n.storyId!, user: {}, stories: []),
          ),
        );
        break;

      case NotificationType.friendRequest:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: n.fromUserId),
          ),
        );
        break;

      case NotificationType.newPost:
        if (n.postId == null) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: n.postId!),
          ),
        );
        break;
    }
  }

  Future<void> _handleAccept(AppNotification n) {
    return _friendsRepo.acceptFriendRequest(n.fromUserId);
  }
}

class _Group {
  final String label;
  final List<AppNotification> items;

  _Group(this.label, this.items);
}

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({
    required this.label,
    required this.notifications,
    required this.onTap,
    required this.onAccept,
  });

  final String label;
  final List<AppNotification> notifications;
  final void Function(AppNotification) onTap;
  final void Function(AppNotification) onAccept;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (int i = 0; i < notifications.length; i++) ...[
                  _NotificationTile(
                    notification: notifications[i],
                    onTap: () => onTap(notifications[i]),
                    onAccept: () => onAccept(notifications[i]),
                  ),
                  if (i != notifications.length - 1)
                    Divider(
                      height: 1,
                      indent: 76,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onAccept,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final n = notification;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color:
            n.isRead
                ? Colors.transparent
                : colorScheme.primary.withValues(alpha: 0.04),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(notification: n),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessage(context),
                  const SizedBox(height: 4),
                  Text(
                    _timeLabel(n.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildTrailing(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(BuildContext context) {
    const style = TextStyle(fontSize: 14, height: 1.3);

    String action;

    switch (notification.type) {
      case NotificationType.story:
        action = 'posted a new story';
        break;

      case NotificationType.friendRequest:
        action = 'sent you a friend request';
        break;

      case NotificationType.newPost:
        action = 'added a new post';
        break;
    }

    return RichText(
      text: TextSpan(
        style: style.copyWith(color: Theme.of(context).colorScheme.onSurface),
        children: [
          TextSpan(
            text: notification.fromUserName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' $action'),
        ],
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    final thumb = notification.postThumbnail;

    if (notification.type == NotificationType.newPost &&
        thumb != null &&
        thumb.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _NotificationThumbnail(thumbnail: thumb),
      );
    }

    if (notification.type == NotificationType.friendRequest) {
      return _AcceptButton(
        fromUserId: notification.fromUserId,
        onAccept: onAccept,
      );
    }

    return const SizedBox.shrink();
  }
}

/// Displays notification post thumbnails.
///
/// Supports:
/// 1. Cloudinary HTTP/HTTPS image URLs
/// 2. data:image/...;base64,...
/// 3. Old plain Base64 strings
///
/// Invalid thumbnail data will show a placeholder instead of crashing.
class _NotificationThumbnail extends StatelessWidget {
  const _NotificationThumbnail({required this.thumbnail});

  final String thumbnail;

  @override
  Widget build(BuildContext context) {
    final value = thumbnail.trim();

    // NEW: Cloudinary / normal network image.
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _brokenImage();
        },
      );
    }

    try {
      String base64Value = value;

      // Supports:
      // data:image/jpeg;base64,/9j/4AAQ...
      if (value.startsWith('data:')) {
        final commaIndex = value.indexOf(',');

        if (commaIndex == -1) {
          return _brokenImage();
        }

        base64Value = value.substring(commaIndex + 1);
      }

      return Image.memory(
        base64Decode(base64Value),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _brokenImage();
        },
      );
    } catch (_) {
      // Never allow malformed notification thumbnail data
      // to crash the Notifications screen.
      return _brokenImage();
    }
  }

  Widget _brokenImage() {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported_outlined, size: 22),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.fromUserId, required this.onAccept});

  final String fromUserId;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FriendsRepository().requestStatusStream(fromUserId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();

        final isPendingReceived = data != null && data['type'] == 'received';

        if (!isPendingReceived) {
          return const SizedBox.shrink();
        }

        return ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text('Accept'),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final provider = decodeAvatarImage(notification.fromUserPhoto);

    final badge = _badgeFor(notification.type);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          backgroundImage: provider,
          child: provider == null ? const Icon(Icons.person, size: 24) : null,
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: badge.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: Icon(badge.icon, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }

  _Badge _badgeFor(NotificationType type) {
    switch (type) {
      case NotificationType.story:
        return _Badge(Icons.play_circle_fill_rounded, Colors.pinkAccent);

      case NotificationType.friendRequest:
        return _Badge(Icons.person_add_rounded, Colors.deepPurpleAccent);

      case NotificationType.newPost:
        return _Badge(Icons.grid_on_rounded, Colors.blueAccent);
    }
  }
}

class _Badge {
  final IconData icon;
  final Color color;

  _Badge(this.icon, this.color);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  final today = DateTime(now.year, now.month, now.day);

  final dtDay = DateTime(dt.year, dt.month, dt.day);

  if (dtDay == today) {
    if (diff.inMinutes < 1) {
      return 'Just now';
    }

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }

    return '${diff.inHours}h ago';
  }

  if (dtDay == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }

  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }

  return '${dt.month}/${dt.day}/${dt.year}';
}

/// Supports:
/// - HTTP/HTTPS profile URLs
/// - data:image/...;base64,...
/// - old bare Base64 strings
ImageProvider? decodeAvatarImage(String? photo) {
  if (photo == null || photo.isEmpty) {
    return null;
  }

  if (photo.startsWith('http')) {
    return NetworkImage(photo);
  }

  if (photo.startsWith('data:')) {
    final commaIndex = photo.indexOf(',');

    if (commaIndex == -1) {
      return null;
    }

    try {
      return MemoryImage(base64Decode(photo.substring(commaIndex + 1)));
    } catch (_) {
      return null;
    }
  }

  try {
    return MemoryImage(base64Decode(photo));
  } catch (_) {
    return null;
  }
}
