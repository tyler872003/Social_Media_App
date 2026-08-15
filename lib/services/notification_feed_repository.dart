import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_model.dart';
import 'notification_repository.dart'; // your existing settings repo (mute/category toggles)

/// Handles reading the signed-in user's notification FEED and writing new
/// entries to it.
///
/// Deliberately a separate class from your existing [NotificationRepository]
/// (users/{uid}/settings/notifications — mute state and category toggles).
/// This one owns a different subcollection: users/{uid}/notifications/{id},
/// the actual list of "so-and-so did X" entries shown on screen. Same name
/// would've collided with your file, so this one's named for what it is —
/// the feed, not the settings.
class NotificationFeedRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationRepository _settingsRepo = NotificationRepository();

  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _notificationsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  // ── Reading ────────────────────────────────────────────

  Stream<List<AppNotification>> notificationsStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _notificationsRef(uid)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromDoc).toList());
  }

  Stream<int> unreadCountStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(0);

    return _notificationsRef(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markAsRead(String notificationId) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _notificationsRef(uid).doc(notificationId).update({'isRead': true});
  }

  Future<void> markAllAsRead() async {
    final uid = currentUserId;
    if (uid == null) return;

    final unread =
        await _notificationsRef(uid).where('isRead', isEqualTo: false).get();
    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Writing ────────────────────────────────────────────

  /// Fetches [fromUserId]'s display name/photo so each notification carries
  /// its own copy — the list screen doesn't need to re-fetch the sender
  /// per row.
  ///
  /// Both field names confirmed from your Firestore console: 'displayName'
  /// and 'photoUrl' (the latter holds a full data:image/...;base64,... URI,
  /// decoded at render time — see decodeAvatarImage in notifications_screen.dart).
  Future<Map<String, String?>> _senderInfo(String fromUserId) async {
    final doc = await _firestore.collection('users').doc(fromUserId).get();
    final data = doc.data() ?? {};
    final name = data['displayName'] as String? ?? 'Someone';
    final photo = data['photoUrl'] as String?;
    return {'name': name, 'photo': photo};
  }

  /// Checks [toUserId]'s notification settings doc to decide whether this
  /// type should be written to their feed at all. Maps our 3 feed types
  /// onto your existing category keys where one exists:
  /// - friendRequest → notifyFriendRequests
  /// - story         → notifyStories
  /// - newPost has no matching category in your settings repo yet, so it's
  ///   always allowed — add a 'notifyNewPosts' toggle later if you want one.
  /// Defaults to true (matches isCategoryEnabled's own default) if the
  /// settings doc doesn't exist yet, or if the recipient isn't reachable.
  Future<bool> _recipientAllows(String toUserId, NotificationType type) async {
    final key = switch (type) {
      NotificationType.friendRequest => 'notifyFriendRequests',
      NotificationType.story => 'notifyStories',
      NotificationType.newPost => null,
    };
    if (key == null) return true;

    final settingsDoc = await _firestore
        .collection('users')
        .doc(toUserId)
        .collection('settings')
        .doc('notifications')
        .get();
    return _settingsRepo.isCategoryEnabled(settingsDoc.data(), key);
  }

  Future<void> _create({
    required String toUserId,
    required NotificationType type,
    required String fromUserId,
    String? postId,
    String? storyId,
    String? postThumbnail,
  }) async {
    if (toUserId == fromUserId) return; // never notify yourself
    if (!await _recipientAllows(toUserId, type)) return;

    final sender = await _senderInfo(fromUserId);
    final ref = _notificationsRef(toUserId).doc();
    await ref.set({
      'type': typeToString(type),
      'fromUserId': fromUserId,
      'fromUserName': sender['name'],
      'fromUserPhoto': sender['photo'],
      'postId': postId,
      'storyId': storyId,
      'postThumbnail': postThumbnail,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> notifyFriendRequest({
    required String toUserId,
    required String fromUserId,
  }) {
    return _create(
      toUserId: toUserId,
      type: NotificationType.friendRequest,
      fromUserId: fromUserId,
    );
  }

  Future<void> notifyNewStory({
    required List<String> friendIds,
    required String fromUserId,
    required String storyId,
  }) {
    return Future.wait(
      friendIds.map(
        (friendId) => _create(
          toUserId: friendId,
          type: NotificationType.story,
          fromUserId: fromUserId,
          storyId: storyId,
        ),
      ),
    );
  }

  Future<void> notifyNewPost({
    required List<String> friendIds,
    required String fromUserId,
    required String postId,
    String? thumbnail,
  }) {
    return Future.wait(
      friendIds.map(
        (friendId) => _create(
          toUserId: friendId,
          type: NotificationType.newPost,
          fromUserId: fromUserId,
          postId: postId,
          postThumbnail: thumbnail,
        ),
      ),
    );
  }
}
