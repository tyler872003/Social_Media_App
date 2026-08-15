import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FriendsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Stream of the current user's document to listen for friends list
  Stream<DocumentSnapshot<Map<String, dynamic>>> currentUserStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // Get friends list from user document
  Future<List<String>> getFriendsList() async {
    final uid = currentUserId;
    if (uid == null) return [];
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return [];
    return List<String>.from(doc.data()?['friends'] ?? []);
  }

  // Stream of received friend requests
  Stream<QuerySnapshot<Map<String, dynamic>>> receivedRequestsStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .where('type', isEqualTo: 'received')
        //.orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Stream of sent friend requests
  Stream<QuerySnapshot<Map<String, dynamic>>> sentRequestsStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .where('type', isEqualTo: 'sent')
        //.orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Streams the relationship status between the current user and
  /// [otherUid]: the doc (if any) at users/{me}/friendRequests/{otherUid}.
  /// Its 'type' field is 'sent' (I requested them) or 'received' (they
  /// requested me) — the doc simply doesn't exist if there's no pending
  /// request either way.
  Stream<DocumentSnapshot<Map<String, dynamic>>> requestStatusStream(
    String otherUid,
  ) {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .doc(otherUid)
        .snapshots();
  }

  Future<void> sendFriendRequest(String targetUid) async {
    final uid = currentUserId;
    if (uid == null || uid == targetUid) return;

    final timestamp = FieldValue.serverTimestamp();

    final batch = _firestore.batch();

    // Add 'sent' to current user
    final sentRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .doc(targetUid);
    batch.set(sentRef, {
      'uid': targetUid,
      'type': 'sent',
      'timestamp': timestamp,
    });

    // Add 'received' to target user
    final receivedRef = _firestore
        .collection('users')
        .doc(targetUid)
        .collection('friendRequests')
        .doc(uid);
    batch.set(receivedRef, {
      'uid': uid,
      'type': 'received',
      'timestamp': timestamp,
    });

    await batch.commit();
  }

  Future<void> acceptFriendRequest(String targetUid) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      debugPrint('=== ACCEPT START: me=$uid, target=$targetUid');

      // Step 1: Add targetUid to MY friends list
      await _firestore.collection('users').doc(uid).set({
        'friends': FieldValue.arrayUnion([targetUid]),
      }, SetOptions(merge: true));
      debugPrint('=== Step 1 done: added target to my friends');

      // Step 2: Add ME to TARGET's friends list
      await _firestore.collection('users').doc(targetUid).set({
        'friends': FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));
      debugPrint('=== Step 2 done: added me to target friends');

      // Step 3: Delete MY received request
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('friendRequests')
          .doc(targetUid)
          .delete();
      debugPrint('=== Step 3 done: deleted my received request');

      // Step 4: Delete THEIR sent request
      await _firestore
          .collection('users')
          .doc(targetUid)
          .collection('friendRequests')
          .doc(uid)
          .delete();
      debugPrint('=== Step 4 done: deleted their sent request');

      debugPrint('=== ACCEPT COMPLETE');
    } catch (e, stack) {
      debugPrint('=== ACCEPT FAILED at: $e');
      debugPrint('=== STACK: $stack');
      rethrow;
    }
  }

  /// Deletes any pending request between the current user and [targetUid],
  /// regardless of direction — works to decline a received request OR
  /// cancel a request the current user sent.
  Future<void> declineFriendRequest(String targetUid) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final batch = _firestore.batch();

      final receivedRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('friendRequests')
          .doc(targetUid);
      batch.delete(receivedRef);

      final sentRef = _firestore
          .collection('users')
          .doc(targetUid)
          .collection('friendRequests')
          .doc(uid);
      batch.delete(sentRef);

      await batch.commit();
    } catch (e) {
      debugPrint('declineFriendRequest error: $e');
      rethrow;
    }
  }

  Future<void> removeFriend(String targetUid) async {
    final uid = currentUserId;
    if (uid == null) return;

    final batch = _firestore.batch();

    final currentUserRef = _firestore.collection('users').doc(uid);
    batch.update(currentUserRef, {
      'friends': FieldValue.arrayRemove([targetUid]),
    });

    final targetUserRef = _firestore.collection('users').doc(targetUid);
    batch.update(targetUserRef, {
      'friends': FieldValue.arrayRemove([uid]),
    });

    await batch.commit();
  }
}