import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PostRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // ── Posts ──────────────────────────────────────────────

  Future<void> createPost({
    List<String> base64Images = const [],
    required String caption,
    required String privacy,
    List<String> closedFriendsIds = const [],
    bool allowDownload = false,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final trimmedCaption = caption.trim();
    if (trimmedCaption.isEmpty && base64Images.isEmpty) {
      throw ArgumentError('Add a caption or at least one photo.');
    }
    if (base64Images.length > 5) {
      throw ArgumentError('You can upload up to 5 photos.');
    }

    final postType = base64Images.isEmpty ? 'status' : 'photo';
    final docRef = _firestore.collection('posts').doc();
    await docRef.set({
      'id': docRef.id,
      'userId': uid,
      'postType': postType,
      'images': base64Images,
      'base64Data': base64Images.isNotEmpty ? base64Images.first : '',
      'caption': trimmedCaption,
      'privacy': privacy,
      'closedFriendsIds': closedFriendsIds,
      'allowDownload': allowDownload,
      'likes': [],
      'reactions': <String, String>{},
      'sharesCount': 0,
      'commentsCount': 0,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updatePostDownloadPermission(String postId, bool allow) async {
    final uid = currentUserId;
    if (uid == null) return;

    final doc = await _firestore.collection('posts').doc(postId).get();
    if (doc.data()?['userId'] != uid) return;

    await _firestore.collection('posts').doc(postId).update({
      'allowDownload': allow,
    });
  }

  Future<void> deletePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return;

    final doc = await _firestore.collection('posts').doc(postId).get();
    if (doc.data()?['userId'] != uid) return;

    final comments =
        await _firestore
            .collection('posts')
            .doc(postId)
            .collection('comments')
            .get();

    final batch = _firestore.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    batch.delete(_firestore.collection('posts').doc(postId));
    await batch.commit();
  }

  Future<void> deleteAllMyPosts() async {
    final uid = currentUserId;
    if (uid == null) return;

    final posts =
        await _firestore
            .collection('posts')
            .where('userId', isEqualTo: uid)
            .get();

    for (final post in posts.docs) {
      await deletePost(post.id);
    }
  }

  Future<void> updatePostPrivacy(String postId, String privacy) async {
    final uid = currentUserId;
    if (uid == null) return;

    final doc = await _firestore.collection('posts').doc(postId).get();
    if (doc.data()?['userId'] != uid) return;

    await _firestore.collection('posts').doc(postId).update({
      'privacy': privacy,
    });
  }

  Stream<List<Map<String, dynamic>>> getNewsfeedStream(
    List<String> friendsList,
  ) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final posts = <Map<String, dynamic>>[];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final postUserId = data['userId'] as String;
            final privacy = data['privacy'] as String? ?? 'public';

            final canView =
                postUserId == uid ||
                privacy == 'public' ||
                (privacy == 'friends' && friendsList.contains(postUserId)) ||
                (privacy == 'closedFriends' && _isInClosedFriends(data, uid));

            if (canView) posts.add(data);
          }
          return posts;
        });
  }

  bool _isInClosedFriends(Map<String, dynamic> data, String uid) {
    final allowed = List<String>.from(data['closedFriendsIds'] ?? []);
    return allowed.contains(uid);
  }

  Stream<List<Map<String, dynamic>>> getUserPostsStream(
    String profileUserId,
    List<String> friendsList,
  ) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) {
          final posts = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if ((data['userId'] as String?) != profileUserId) continue;

            final privacy = data['privacy'] as String? ?? 'public';
            final canView =
                profileUserId == uid ||
                privacy == 'public' ||
                (privacy == 'friends' && friendsList.contains(profileUserId)) ||
                (privacy == 'closedFriends' && _isInClosedFriends(data, uid));

            if (canView) posts.add(data);
          }
          return posts;
        });
  }

  // ── Reactions & Likes ──────────────────────────────────

  Future<void> setReaction(String postId, String? reaction) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore.collection('posts').doc(postId).update({
      'reactions.$uid': reaction ?? FieldValue.delete(),
      'likes':
          reaction == null
              ? FieldValue.arrayRemove([uid])
              : FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> recordShare(String postId) async {
    await _firestore.collection('posts').doc(postId).update({
      'sharesCount': FieldValue.increment(1),
    });
  }

  // ── Comments ───────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp')
        .snapshots();
  }

  Future<void> addComment(String postId, String text) async {
    final uid = currentUserId;
    final trimmed = text.trim();
    if (uid == null || trimmed.isEmpty) return;

    final postRef = _firestore.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc();
    final user = _auth.currentUser;

    await _firestore.runTransaction((transaction) async {
      transaction.set(commentRef, {
        'id': commentRef.id,
        'postId': postId,
        'userId': uid,
        'userName': user?.displayName ?? user?.email ?? 'User',
        'text': trimmed,
        'timestamp': FieldValue.serverTimestamp(),
        'replyTo': null, // null means top-level comment
        'replyToName': null, // display name of who they replied to
        'replyToUserId': null, // uid of who they replied to
      });
      transaction.update(postRef, {'commentsCount': FieldValue.increment(1)});
    });
  }

  Future<void> replyToComment({
    required String postId,
    required String text,
    required String replyToCommentId,
    required String replyToUserName,
    required String replyToUserId,
  }) async {
    final uid = currentUserId;
    final trimmed = text.trim();
    if (uid == null || trimmed.isEmpty) return;

    final postRef = _firestore.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc();
    final user = _auth.currentUser;

    await _firestore.runTransaction((transaction) async {
      transaction.set(commentRef, {
        'id': commentRef.id,
        'postId': postId,
        'userId': uid,
        'userName': user?.displayName ?? user?.email ?? 'User',
        'text': trimmed,
        'timestamp': FieldValue.serverTimestamp(),
        'replyTo': replyToCommentId,
        'replyToName': replyToUserName,
        'replyToUserId': replyToUserId,
      });
      transaction.update(postRef, {'commentsCount': FieldValue.increment(1)});
    });
  }

  Future<void> deleteOwnComment(String postId, String commentId) async {
    final uid = currentUserId;
    if (uid == null) return;

    final postRef = _firestore.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    final snapshot = await commentRef.get();
    if (snapshot.data()?['userId'] != uid) return;

    await _firestore.runTransaction((transaction) async {
      transaction.delete(commentRef);
      transaction.update(postRef, {'commentsCount': FieldValue.increment(-1)});
    });
  }

  // ── Closed Friends ─────────────────────────────────────

  Future<List<String>> getClosedFriends() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final doc = await _firestore.collection('users').doc(uid).get();
    return List<String>.from(doc.data()?['closedFriends'] ?? []);
  }

  Future<void> saveClosedFriends(List<String> uids) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'closedFriends': uids,
    });
  }
}
