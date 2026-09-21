import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/services/auth_verification_prefs.dart';

/// Thrown when another account already owns this nickname (case-insensitive).
class NicknameTakenException implements Exception {
  @override
  String toString() => 'Nickname taken';
}

class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;

  String chatIdForParticipants(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  static String nicknameDocKey(String nickname) =>
      nickname.trim().toLowerCase();

  static bool isValidNicknameFormat(String raw) {
    final t = raw.trim();
    return RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(t);
  }

  Future<void> claimNickname({
    required String uid,
    required String nickname,
  }) async {
    final display = nickname.trim();
    final key = nicknameDocKey(display);
    final nickRef = _db.collection('nicknames').doc(key);

    var taken = false;

    await _db.runTransaction((txn) async {
      final snap = await txn.get(nickRef);

      if (snap.exists) {
        final existing = snap.data()?['uid'] as String?;

        if (existing != null && existing != uid) {
          taken = true;
          return;
        }
      }

      txn.set(nickRef, {
        'uid': uid,
        'displayName': display,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (taken) {
      throw NicknameTakenException();
    }
  }

  Future<void> releaseNicknameIfOwnedBy(String nicknameKey, String uid) async {
    final ref = _db.collection('nicknames').doc(nicknameKey);

    final snap = await ref.get();

    if (snap.exists && snap.data()?['uid'] == uid) {
      await ref.delete();
    }
  }

  Future<void> ensureUserDocument({
    required String uid,
    required String email,
    String? photoUrl,
    String? displayName,
  }) async {
    final cur = _auth.currentUser;

    if (cur != null &&
        cur.uid == uid &&
        !cur.emailVerified &&
        cur.providerData.any((p) => p.providerId == 'password')) {
      return;
    }

    final docRef = _db.collection('users').doc(uid);

    final existing = await docRef.get();

    final data = <String, dynamic>{
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }

    if (displayName != null && displayName.trim().isNotEmpty) {
      data['displayName'] = displayName.trim();
    }

    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();

      data['status'] = 'active';
    }

    return docRef.set(data, SetOptions(merge: true));
  }

  Future<void> syncCurrentUserProfileDocument() async {
    final user = _auth.currentUser;

    if (user == null) return;
    if (!user.emailVerified) return;

    final pending = EmailRegistrationSession.pendingProfilePhotoBytes;

    if (pending != null) {
      try {
        await user.getIdToken();

        await updateProfilePhoto(pending);

        EmailRegistrationSession.clearPendingProfilePhoto();
      } catch (_) {}
    }

    final doc = await _db.collection('users').doc(user.uid).get();

    String? photoUrl = doc.data()?['photoUrl'] as String?;

    photoUrl ??= user.photoURL;

    await ensureUserDocument(
      uid: user.uid,
      email: user.email ?? '',
      photoUrl: photoUrl,
      displayName: user.displayName,
    );
  }

  Future<String> updateProfilePhoto(Uint8List bytes) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Not logged in');
    }

    final base64String = base64Encode(bytes);

    final photoUrl = 'data:image/jpeg;base64,$base64String';

    try {
      await user.updatePhotoURL(photoUrl);
    } catch (_) {}

    await ensureUserDocument(
      uid: user.uid,
      email: user.email ?? '',
      photoUrl: photoUrl,
      displayName: user.displayName,
    );

    return photoUrl;
  }

  /// Removes the current user's profile photo
  /// from Auth and Firestore.
  Future<void> deleteProfilePhoto() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Not logged in');
    }

    try {
      await user.updatePhotoURL(null);
    } catch (_) {}

    await _db.collection('users').doc(user.uid).update({
      'photoUrl': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Changes the current user's display name + nickname atomically.
  ///
  /// Releases the old nickname key and claims the new one
  /// in one transaction.
  ///
  /// Throws [NicknameTakenException] if the new nickname
  /// is already taken.
  Future<void> changeNickname(String newNickname) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Not logged in');
    }

    final display = newNickname.trim();
    final newKey = nicknameDocKey(display);

    final newRef = _db.collection('nicknames').doc(newKey);

    final oldKey =
        user.displayName != null ? nicknameDocKey(user.displayName!) : null;

    final oldRef =
        oldKey != null ? _db.collection('nicknames').doc(oldKey) : null;

    var taken = false;

    await _db.runTransaction((txn) async {
      final newSnap = await txn.get(newRef);

      if (newSnap.exists) {
        final existing = newSnap.data()?['uid'] as String?;

        if (existing != null && existing != user.uid) {
          taken = true;
          return;
        }
      }

      if (oldRef != null && oldKey != newKey) {
        final oldSnap = await txn.get(oldRef);

        if (oldSnap.exists && oldSnap.data()?['uid'] == user.uid) {
          txn.delete(oldRef);
        }
      }

      txn.set(newRef, {
        'uid': user.uid,
        'displayName': display,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (taken) {
      throw NicknameTakenException();
    }

    await user.updateDisplayName(display);

    await _db.collection('users').doc(user.uid).update({
      'displayName': display,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // CHAT DOCUMENT
  // ============================================================

  Future<void> ensureChatDocument({
    required String chatId,
    required List<String> participants,
  }) {
    return _db.collection('chats').doc(chatId).set({
      'participants': participants,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> chatDocument(String chatId) =>
      _db.collection('chats').doc(chatId);

  // ============================================================
  // USERS
  // ============================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> usersExceptSelf() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return _db.collection('users').limit(0).snapshots();
    }

    return _db.collection('users').snapshots();
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> sendMessage({
    required String chatId,
    String text = '',
    String messageType = 'text',
    String? base64Data,
    String? fileName,
    Map<String, dynamic>? extraData,
  }) async {
    final user = _auth.currentUser;

    if (user == null) return;

    final trimmed = text.trim();

    // ----------------------------------------------------------
    // IMPORTANT:
    //
    // A Cloudinary video does not use base64Data.
    //
    // It is stored in extraData as:
    //
    // mediaUrl
    // thumbnailUrl
    // publicId
    //
    // Therefore we must allow the message when mediaUrl exists.
    // ----------------------------------------------------------

    final mediaUrl = extraData?['mediaUrl'] as String?;

    final hasMediaUrl = mediaUrl != null && mediaUrl.trim().isNotEmpty;

    // Do not create completely empty messages.
    if (trimmed.isEmpty && base64Data == null && !hasMediaUrl) {
      return;
    }

    final batch = _db.batch();

    final chatRef = _db.collection('chats').doc(chatId);

    final messageRef = chatRef.collection('messages').doc();

    final messageData = <String, dynamic>{
      'text': trimmed,
      'senderId': user.uid,
      'senderEmail': user.email,
      'messageType': messageType,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // ----------------------------------------------------------
    // OLD BASE64 MEDIA
    // ----------------------------------------------------------

    if (base64Data != null) {
      messageData['base64Data'] = base64Data;
    }

    // ----------------------------------------------------------
    // FILE NAME
    // ----------------------------------------------------------

    if (fileName != null && fileName.trim().isNotEmpty) {
      messageData['fileName'] = fileName.trim();
    }

    // ----------------------------------------------------------
    // CLOUDINARY MEDIA
    //
    // Example:
    //
    // {
    //   mediaUrl: "...",
    //   thumbnailUrl: "...",
    //   publicId: "..."
    // }
    // ----------------------------------------------------------

    if (extraData != null && extraData.isNotEmpty) {
      messageData.addAll(extraData);
    }

    batch.set(messageRef, messageData);

    // ==========================================================
    // CHAT LIST PREVIEW
    // ==========================================================

    String lastMsg = trimmed;

    if (messageType == 'image') {
      lastMsg = '📷 Image';
    }

    if (messageType == 'video') {
      lastMsg = '📹 Video';
    }

    if (messageType == 'audio') {
      lastMsg = '🎤 Voice message';
    }

    if (messageType == 'file') {
      lastMsg = '📎 File';
    }

    if (messageType == 'call_started') {
      lastMsg = trimmed == 'video' ? '📹 Video call' : '📞 Voice call';
    }

    if (messageType == 'call_ended') {
      lastMsg =
          trimmed == 'video' ? '📹 Video call ended' : '📞 Voice call ended';
    }

    if (messageType == 'call_event') {
      lastMsg = trimmed;
    }

    batch.set(chatRef, {
      'lastMessage': lastMsg,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ============================================================
  // MESSAGE PREVIEW
  // ============================================================

  String _messagePreviewFromData(Map<String, dynamic> data) {
    final type = (data['messageType'] as String?) ?? 'text';

    final text = (data['text'] as String?)?.trim() ?? '';

    if (type == 'image') {
      return '📷 Image';
    }

    if (type == 'video') {
      return '📹 Video';
    }

    if (type == 'audio') {
      return '🎤 Voice message';
    }

    if (type == 'file') {
      return '📎 File';
    }

    if (type == 'call_started') {
      return text == 'video' ? '📹 Video call' : '📞 Voice call';
    }

    if (type == 'call_ended') {
      return text == 'video' ? '📹 Video call ended' : '📞 Voice call ended';
    }

    if (type == 'call_event') {
      return text.isEmpty ? 'Call update' : text;
    }

    return text.isEmpty ? 'Message' : text;
  }

  // ============================================================
  // DELETE MESSAGE
  // ============================================================

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) return;

    final chatRef = _db.collection('chats').doc(chatId);

    final messageRef = chatRef.collection('messages').doc(messageId);

    final snap = await messageRef.get();

    if (!snap.exists) return;

    final data = snap.data() ?? <String, dynamic>{};

    final senderId = data['senderId'] as String?;

    if (senderId != user.uid) {
      throw Exception('You can only delete your own messages.');
    }

    await messageRef.delete();

    final latest =
        await chatRef
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

    final lastMessage =
        latest.docs.isEmpty
            ? ''
            : _messagePreviewFromData(latest.docs.first.data());

    await chatRef.set({
      'lastMessage': lastMessage,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================================
  // GROUP CHAT
  // ============================================================

  Future<String> createGroupChat(
    String groupName,
    List<String> participantIds,
  ) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Not logged in');
    }

    final chatRef = _db.collection('chats').doc();

    if (!participantIds.contains(user.uid)) {
      participantIds.add(user.uid);
    }

    await chatRef.set({
      'isGroup': true,
      'groupName': groupName,
      'admin': user.uid,
      'participants': participantIds,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': 'Group created',
    });

    return chatRef.id;
  }

  /// Adds [newMemberIds] to an existing group chat.
  Future<void> addMembersToGroup(
    String chatId,
    List<String> newMemberIds,
  ) async {
    if (newMemberIds.isEmpty) return;

    await _db.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion(newMemberIds),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> groupChatsStream() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return Stream.value([]);
    }

    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final docs =
              snapshot.docs
                  .where((doc) => doc.data()['isGroup'] == true)
                  .toList();

          docs.sort((a, b) {
            final timeA =
                (a.data()['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);

            final timeB =
                (b.data()['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);

            return timeB.compareTo(timeA);
          });

          return docs;
        });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  directChatsStream() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return Stream.value([]);
    }

    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final docs =
              snapshot.docs
                  .where((doc) => doc.data()['isGroup'] != true)
                  .toList();

          docs.sort((a, b) {
            final timeA =
                (a.data()['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);

            final timeB =
                (b.data()['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);

            return timeB.compareTo(timeA);
          });

          return docs;
        });
  }

  // ============================================================
  // CURRENT USER
  // ============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>?> currentUserStream() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return Stream.value(null);
    }

    return _db.collection('users').doc(uid).snapshots();
  }

  // ============================================================
  // BLOCKING
  // ============================================================

  Future<void> blockUser(String blockedUid) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'blockedUsers': FieldValue.arrayUnion([blockedUid]),
    }, SetOptions(merge: true));
  }

  Future<void> unblockUser(String blockedUid) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'blockedUsers': FieldValue.arrayRemove([blockedUid]),
    }, SetOptions(merge: true));
  }

  // ============================================================
  // LEAVE GROUP
  // ============================================================

  /// Removes the current user from a group chat's participants list.
  ///
  /// If they are the last member, deletes the group document.
  /// If they are the admin, transfers admin to the next member.
  Future<void> leaveGroupChat(String chatId) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return;

    final chatRef = _db.collection('chats').doc(chatId);

    final snap = await chatRef.get();

    if (!snap.exists) return;

    final data = snap.data()!;

    final participants = List<String>.from(data['participants'] ?? []);

    participants.remove(uid);

    if (participants.isEmpty) {
      await chatRef.delete();
    } else {
      final update = <String, dynamic>{
        'participants': participants,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (data['admin'] == uid) {
        update['admin'] = participants.first;
      }

      await chatRef.update(update);
    }
  }

  // ============================================================
  // FETCH USERS
  // ============================================================

  /// Fetches multiple user documents in parallel by their UIDs.
  ///
  /// Returns a map of uid -> user data.
  /// Missing users are excluded.
  Future<Map<String, Map<String, dynamic>>> fetchUsersByIds(
    List<String> uids,
  ) async {
    if (uids.isEmpty) return {};

    final snaps = await Future.wait(
      uids.map((id) => _db.collection('users').doc(id).get()),
    );

    return {
      for (final s in snaps)
        if (s.exists) s.id: s.data()!,
    };
  }
}
