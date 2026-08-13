import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_post.dart';

class FirestoreAdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------- Dashboard stats ----------
  // Uses Firestore's server-side count() aggregation — cheap, doesn't
  // download every document.

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

  Future<int> getPendingReportCount() async {
    final snap = await _db
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<int> getPostsCreatedSince(DateTime since) async {
    final snap = await _db
        .collection('posts')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ---------- Manual browse (paginated) ----------

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
    return snap.docs.map((d) => AdminPost.fromDoc(d)).toList();
  }

  // ---------- Report-driven queue ----------

  Stream<List<AdminReport>> pendingReportsStream() {
    return _db
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => AdminReport.fromDoc(d)).toList());
  }

  Future<AdminPost?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return AdminPost.fromDoc(doc);
  }

  // ---------- Moderation actions ----------
  // Soft delete: keeps the doc for audit/appeal history. Your main app's
  // feed queries should filter `where('status', isEqualTo: 'active')`.

  Future<void> removePost(String postId, {String? reason}) async {
    final batch = _db.batch();

    batch.update(_db.collection('posts').doc(postId), {
      'status': 'removed',
      'removedAt': FieldValue.serverTimestamp(),
      if (reason != null) 'removalReason': reason,
    });

    // Mark any reports tied to this post as reviewed.
    final reports = await _db
        .collection('reports')
        .where('postId', isEqualTo: postId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final r in reports.docs) {
      batch.update(r.reference, {'status': 'reviewed'});
    }

    await batch.commit();
  }

  Future<void> restorePost(String postId) async {
    await _db.collection('posts').doc(postId).update({
      'status': 'active',
      'removedAt': FieldValue.delete(),
      'removalReason': FieldValue.delete(),
    });
  }

  Future<void> dismissReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'reviewed',
    });
  }
}
