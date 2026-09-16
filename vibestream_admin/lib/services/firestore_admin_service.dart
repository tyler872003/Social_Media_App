import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_post.dart';

class FirestoreAdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Cache user information so we don't repeatedly read
  // the same user document.
  final Map<String, Map<String, dynamic>> _userCache = {};

  // ============================================================
  // DASHBOARD STATS
  // ============================================================

  Future<int> getTotalPostCount() async {
    final snap = await _db.collection('posts').count().get();
    return snap.count ?? 0;
  }

  Future<int> getActivePostCount() async {
    final snap = await _db
        .collection('posts')
        .where('status', isEqualTo: 'active')
        .count()
        .get();

    return snap.count ?? 0;
  }

  Future<int> getTotalUserCount() async {
    final snap = await _db.collection('users').count().get();
    return snap.count ?? 0;
  }

  /// Returns the number of reports that still require moderation.
  ///
  /// A report is considered pending when:
  /// - status == "pending"
  /// - OR status is missing/empty
  ///
  /// The second condition is important for older report documents
  /// that were created before the status field was added.
  Future<int> getPendingReportCount() async {
    final snap = await _db.collection('reports').get();

    int count = 0;

    for (final doc in snap.docs) {
      final data = doc.data();

      final status = data['status']?.toString().toLowerCase().trim();

      // Existing reports without a status are treated as pending.
      if (status == null || status.isEmpty || status == 'pending') {
        count++;
      }
    }

    return count;
  }

  Future<int> getPostsCreatedSince(DateTime since) async {
    final snap = await _db
        .collection('posts')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .count()
        .get();

    return snap.count ?? 0;
  }

  // ============================================================
  // USER INFORMATION
  // ============================================================

  /// Loads users for the supplied posts.
  ///
  /// The users collection uses:
  ///
  /// users/{userId}
  ///
  /// with:
  /// displayName
  /// email
  Future<void> loadUsersForPosts(List<AdminPost> posts) async {
    final userIds = posts
        .map((post) => post.authorId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .where((id) => !_userCache.containsKey(id))
        .toList();

    if (userIds.isEmpty) return;

    // Firestore whereIn supports limited numbers of values,
    // so process users in chunks.
    const chunkSize = 10;

    for (int i = 0; i < userIds.length; i += chunkSize) {
      final end = (i + chunkSize < userIds.length)
          ? i + chunkSize
          : userIds.length;

      final chunk = userIds.sublist(i, end);

      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snap.docs) {
        _userCache[doc.id] = doc.data();
      }

      // Mark users that don't exist as empty,
      // so we don't repeatedly query them.
      for (final id in chunk) {
        if (!_userCache.containsKey(id)) {
          _userCache[id] = {};
        }
      }
    }
  }

  /// Returns the display name for a user.
  String? getUserDisplayName(String userId) {
    final user = _userCache[userId];

    if (user == null) return null;

    final displayName = user['displayName']?.toString().trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    return null;
  }

  /// Returns the email for a user.
  String? getUserEmail(String userId) {
    final user = _userCache[userId];

    if (user == null) return null;

    final email = user['email']?.toString().trim();

    if (email != null && email.isNotEmpty) {
      return email;
    }

    return null;
  }

  /// Returns both name and email.
  Map<String, String?> getUserInfo(String userId) {
    return {
      'displayName': getUserDisplayName(userId),
      'email': getUserEmail(userId),
    };
  }

  // ============================================================
  // MANUAL BROWSE
  // ============================================================

  Future<List<AdminPost>> fetchPosts({
    DocumentSnapshot? startAfter,
    int limit = 25,
    bool sortByReportsFirst = false,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('posts');

    query = sortByReportsFirst
        ? query.orderBy('reportCount', descending: true)
        : query.orderBy('createdAt', descending: true);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.limit(limit).get();

    final posts = snap.docs.map((d) => AdminPost.fromDoc(d)).toList();

    await loadUsersForPosts(posts);

    return posts;
  }

  // ============================================================
  // REPORT-DRIVEN MODERATION QUEUE
  // ============================================================

  /// Returns reports that still require moderation.
  ///
  /// Older reports may not contain a status field. Those are treated
  /// as pending so that they don't disappear from the admin queue.
  Stream<List<AdminReport>> pendingReportsStream() {
    return _db.collection('reports').snapshots().map((snap) {
      final reports = <AdminReport>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        final status = data['status']?.toString().toLowerCase().trim();

        // Treat missing/empty status as pending.
        final isPending =
            status == null || status.isEmpty || status == 'pending';

        if (isPending) {
          reports.add(AdminReport.fromDoc(doc));
        }
      }

      // Sort oldest reports first.
      reports.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;

        if (aTime == null) {
          return 0;
        }

        if (aTime == null) {
          return 1;
        }

        if (bTime == null) {
          return -1;
        }

        return aTime.compareTo(bTime);
      });

      return reports;
    });
  }

  // ============================================================
  // GET POST
  // ============================================================

  Future<AdminPost?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();

    if (!doc.exists) {
      return null;
    }

    final post = AdminPost.fromDoc(doc);

    await loadUsersForPosts([post]);

    return post;
  }

  // ============================================================
  // MODERATION ACTIONS
  // ============================================================

  /// Permanently deletes a post and resolves ALL pending reports
  /// associated with that post.
  ///
  /// This is intentionally based on postId rather than only reportId.
  /// If 5 users reported the same post, all 5 reports are resolved
  /// when the admin deletes the post.
  Future<void> removePost(
    String postId, {
    String? reportId,
    String? reason,
  }) async {
    final postRef = _db.collection('posts').doc(postId);

    final postSnapshot = await postRef.get();

    if (!postSnapshot.exists) {
      // The post may already have been deleted.
      //
      // We still resolve its reports below so that stale reports
      // do not remain in the moderation queue.
    }

    // ------------------------------------------------------------
    // Find ALL reports belonging to this post.
    // ------------------------------------------------------------
    final reportsSnapshot = await _db
        .collection('reports')
        .where('postId', isEqualTo: postId)
        .get();

    // ------------------------------------------------------------
    // Use a batch so deleting the post and resolving its reports
    // happen together.
    // ------------------------------------------------------------
    final batch = _db.batch();

    // Delete post if it still exists.
    if (postSnapshot.exists) {
      batch.delete(postRef);
    }

    // Resolve every report for this post.
    for (final reportDoc in reportsSnapshot.docs) {
      final data = reportDoc.data();

      final status = data['status']?.toString().toLowerCase().trim();

      // Don't change reports that were already resolved/reviewed.
      final isStillPending =
          status == null || status.isEmpty || status == 'pending';

      if (isStillPending) {
        batch.update(reportDoc.reference, {
          'status': 'resolved',
          'resolution': 'post_deleted',
          'resolutionNote': reason ?? 'Post deleted by admin.',
          'resolvedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  /// Restores a previously moderated post.
  Future<void> restorePost(String postId) async {
    await _db.collection('posts').doc(postId).update({
      'status': 'active',
      'removedAt': FieldValue.delete(),
      'removalReason': FieldValue.delete(),
    });
  }

  /// Keeps the reported post but resolves the report.
  Future<void> dismissReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'reviewed',
      'resolution': 'kept',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}
