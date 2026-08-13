import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/services/notification_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The chatId of the screen the user is currently looking at.
String? activeChatId;

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _notifRepo = NotificationRepository();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final Map<String, DateTime> _lastSeen = {};
  final List<StreamSubscription<dynamic>> _subs = [];
  final Set<String> _watchedChats = {};

  bool _initialised = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ✅ v22 fix: use named parameter 'settings'
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (details) {},
    );
    // Request notification permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    debugPrint('✅ LocalNotificationService: initialised');
    _startListening();
  }

  void stop() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _lastSeen.clear();
    _watchedChats.clear();
    _initialised = false;
    debugPrint('🛑 LocalNotificationService: stopped');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _startListening() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final chatsSub = _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
          for (final chatDoc in snapshot.docs) {
            _ensureMessageListener(chatDoc.id, uid);
          }
        });

    _subs.add(chatsSub);

    _startFriendRequestListener(uid);
    _startCommentReplyListener(uid);
  }

  void _ensureMessageListener(String chatId, String uid) {
    if (_watchedChats.contains(chatId)) return;
    _watchedChats.add(chatId);

    _lastSeen[chatId] = DateTime.now();

    final msgSub = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
          if (snapshot.docs.isEmpty) return;
          final doc = snapshot.docs.first;
          final data = doc.data();

          final senderId = data['senderId'] as String?;
          if (senderId == uid) return;

          final ts = data['createdAt'];
          DateTime? msgTime;
          if (ts is Timestamp) msgTime = ts.toDate();
          if (msgTime == null) return;

          final prev = _lastSeen[chatId];
          if (prev != null && !msgTime.isAfter(prev)) return;
          _lastSeen[chatId] = msgTime;

          if (activeChatId == chatId) return;

          final settingsSnap = await _notifRepo.settingsStream().first;
          final settings = settingsSnap?.data();
          if (_notifRepo.isMuted(settings, chatId)) return;

          final senderEmail = data['senderEmail'] as String? ?? 'Someone';
          final senderName = senderEmail.split('@').first;
          final msgType = data['messageType'] as String? ?? 'text';
          final body = switch (msgType) {
            'image' => '📷 Sent a photo',
            'audio' => '🎤 Sent a voice message',
            'file' => '📎 Sent a file',
            _ => (data['text'] as String?)?.trim() ?? 'New message',
          };

          await _showNotification(
            id: chatId.hashCode,
            title: senderName,
            body: body,
          );
        });

    _subs.add(msgSub);
  }

  /// Watches this user's incoming friend requests (users/{uid}/friendRequests)
  /// and shows a local notification for each newly-added request.
  ///
  /// Uses docChanges + a "skip the first snapshot" flag instead of a
  /// timestamp comparison, since we don't rely on a specific field name
  /// (e.g. createdAt) existing on these docs - only that a doc appearing
  /// after the initial load is a genuinely new request.
  void _startFriendRequestListener(String uid) {
    bool isFirstSnapshot = true;

    final sub = _db
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .snapshots()
        .listen((snapshot) async {
          if (isFirstSnapshot) {
            // Don't notify for requests that already existed before this
            // listener started (e.g. app just opened).
            isFirstSnapshot = false;
            debugPrint(
              '[FriendRequestListener] initial snapshot: ${snapshot.docs.length} existing request(s), skipping',
            );
            return;
          }

          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;

            final data = change.doc.data();
            if (data == null) continue;

            // Assumes the requester's uid is stored in a field called 'uid'
            // on the friendRequests doc, matching how friends_screen.dart
            // reads it (docs[index].data()['uid']).
            final requesterUid = data['uid'] as String?;
            if (requesterUid == null || requesterUid.isEmpty) {
              debugPrint(
                '[FriendRequestListener] new request doc missing "uid" field: ${change.doc.reference.path}',
              );
              continue;
            }

            final settingsSnap = await _notifRepo.settingsStream().first;
            final settings = settingsSnap?.data();
            if (!_notifRepo.isCategoryEnabled(
              settings,
              'notifyFriendRequests',
            )) {
              continue;
            }

            String requesterName = 'Someone';
            try {
              final userDoc =
                  await _db.collection('users').doc(requesterUid).get();
              final userData = userDoc.data();
              final displayName = (userData?['displayName'] as String?)?.trim();
              if (displayName != null && displayName.isNotEmpty) {
                requesterName = displayName;
              }
            } catch (e) {
              debugPrint(
                '[FriendRequestListener] failed to load requester profile: $e',
              );
            }

            await _showNotification(
              id: 'friend_request_$requesterUid'.hashCode,
              title: 'New friend request',
              body: '$requesterName sent you a friend request',
            );
          }
        });

    _subs.add(sub);
  }

  /// Watches every comment across all posts (via collectionGroup, since
  /// comments live nested under posts/{postId}/comments) and notifies this
  /// user when someone replies to one of their comments
  /// (replyToUserId == uid).
  ///
  /// NOTE: like the incoming-call listener, this is a collectionGroup query
  /// with an equality filter and will very likely need its own Firestore
  /// composite/collection-group index the first time it runs - watch for
  /// a "[CommentReplyListener] STREAM ERROR" log with a
  /// FAILED_PRECONDITION message and an index-creation link, same as we
  /// saw with the calls collection group.
  void _startCommentReplyListener(String uid) {
    bool isFirstSnapshot = true;

    final sub = _db
        .collectionGroup('comments')
        .where('replyToUserId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snapshot) async {
            if (isFirstSnapshot) {
              isFirstSnapshot = false;
              debugPrint(
                '[CommentReplyListener] initial snapshot: ${snapshot.docs.length} existing repl(y/ies), skipping',
              );
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;

              final data = change.doc.data();
              if (data == null) continue;

              final replierUid = data['userId'] as String?;
              if (replierUid == null) continue;
              // Don't notify when replying to your own comment.
              if (replierUid == uid) continue;

              final settingsSnap = await _notifRepo.settingsStream().first;
              final settings = settingsSnap?.data();
              if (!_notifRepo.isCategoryEnabled(
                settings,
                'notifyCommentReplies',
              )) {
                continue;
              }

              final replierName =
                  (data['userName'] as String?)?.trim().isNotEmpty == true
                      ? (data['userName'] as String).trim()
                      : 'Someone';
              final replyText = (data['text'] as String?)?.trim() ?? '';

              await _showNotification(
                id: change.doc.reference.path.hashCode,
                title: '$replierName replied to your comment',
                body: replyText.isEmpty ? 'New reply' : replyText,
              );
            }
          },
          onError: (e) {
            debugPrint('[CommentReplyListener] STREAM ERROR: $e');
          },
        );

    _subs.add(sub);
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    // ✅ v22 fix: use named parameters for show()
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
    debugPrint('🔔 Notification shown: [$title] $body');
  }
}
