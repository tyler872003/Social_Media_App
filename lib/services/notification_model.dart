import 'package:cloud_firestore/cloud_firestore.dart';

/// The three notification kinds this app currently generates:
/// - [story]: a friend posted a new story
/// - [friendRequest]: you received a friend request
/// - [newPost]: a friend published a new post
enum NotificationType { story, friendRequest, newPost }

NotificationType typeFromString(String value) {
  switch (value) {
    case 'story':
      return NotificationType.story;
    case 'friend_request':
      return NotificationType.friendRequest;
    case 'new_post':
    default:
      return NotificationType.newPost;
  }
}

String typeToString(NotificationType type) {
  switch (type) {
    case NotificationType.story:
      return 'story';
    case NotificationType.friendRequest:
      return 'friend_request';
    case NotificationType.newPost:
      return 'new_post';
  }
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String fromUserId;
  final String fromUserName;
  final String? fromUserPhoto; // base64 or URL
  final String? postId; // set when type == newPost
  final String? storyId; // set when type == story
  final String? postThumbnail; // base64 — first image of the new post, if any
  final DateTime timestamp;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.type,
    required this.fromUserId,
    required this.fromUserName,
    this.fromUserPhoto,
    this.postId,
    this.storyId,
    this.postThumbnail,
    required this.timestamp,
    this.isRead = false,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['timestamp'];
    return AppNotification(
      id: doc.id,
      type: typeFromString(data['type'] as String? ?? 'new_post'),
      fromUserId: data['fromUserId'] as String? ?? '',
      fromUserName: data['fromUserName'] as String? ?? 'Someone',
      fromUserPhoto: data['fromUserPhoto'] as String?,
      postId: data['postId'] as String?,
      storyId: data['storyId'] as String?,
      postThumbnail: data['postThumbnail'] as String?,
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
    );
  }
}
