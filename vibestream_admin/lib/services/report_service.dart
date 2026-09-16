import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ReportReason { spam, inappropriateMedia, harassment, other }

extension ReportReasonLabel on ReportReason {
  String get label {
    switch (this) {
      case ReportReason.spam:
        return 'Spam';

      case ReportReason.inappropriateMedia:
        return 'Inappropriate media';

      case ReportReason.harassment:
        return 'Harassment or bullying';

      case ReportReason.other:
        return 'Other';
    }
  }
}

// ============================================================
// REPORT COUNTS
// ============================================================

class ReportCounts {
  const ReportCounts({required this.total, required this.last30Days});

  final int total;
  final int last30Days;
}

// ============================================================
// REPORT SERVICE
// ============================================================

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // CREATE REPORT
  // ============================================================

  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('You need to be signed in to report a post.');
    }

    // Prevent the same user from submitting another pending
    // report for the same post.
    final existing = await _db
        .collection('reports')
        .where('postId', isEqualTo: postId)
        .where('reporterId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('You\'ve already reported this post.');
    }

    await _db.collection('reports').add({
      'postId': postId,
      'reporterId': user.uid,
      'reason': reason.label,
      'details': details,
      'status': 'pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ============================================================
  // GET POSTS FOR A USER
  // ============================================================

  Future<List<String>> _postIdsForUser(String uid) async {
    final snap = await _db
        .collection('posts')
        .where('userId', isEqualTo: uid)
        .get();

    return snap.docs.map((doc) => doc.id).toList();
  }

  // ============================================================
  // CHUNK LIST
  // ============================================================

  List<List<String>> _chunk(List<String> items, int size) {
    final chunks = <List<String>>[];

    for (var i = 0; i < items.length; i += size) {
      chunks.add(
        items.sublist(i, i + size > items.length ? items.length : i + size),
      );
    }

    return chunks;
  }

  // ============================================================
  // REPORT COUNTS FOR USER
  // ============================================================

  Future<ReportCounts> reportCountsForUser(String uid) async {
    final postIds = await _postIdsForUser(uid);

    if (postIds.isEmpty) {
      return const ReportCounts(total: 0, last30Days: 0);
    }

    final cutoffMillis = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    var total = 0;
    var last30Days = 0;

    // Firestore whereIn has a limit, so process post IDs
    // in chunks.
    for (final chunk in _chunk(postIds, 30)) {
      final snap = await _db
          .collection('reports')
          .where('postId', whereIn: chunk)
          .get();

      total += snap.docs.length;

      for (final doc in snap.docs) {
        final createdAt = doc.data()['createdAt'];

        if (createdAt is int && createdAt >= cutoffMillis) {
          last30Days++;
        }

        if (createdAt is Timestamp &&
            createdAt.toDate().millisecondsSinceEpoch >= cutoffMillis) {
          last30Days++;
        }
      }
    }

    return ReportCounts(total: total, last30Days: last30Days);
  }

  // ============================================================
  // REPORTS FOR USER
  // ============================================================

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> reportsForUser(
    String uid, {
    int limit = 50,
  }) async* {
    final postIds = await _postIdsForUser(uid);

    if (postIds.isEmpty) {
      yield <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    // Firestore whereIn supports a limited number of values.
    final chunk = postIds.take(30).toList();

    yield* _db
        .collection('reports')
        .where('postId', whereIn: chunk)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs);
  }

  // ============================================================
  // RESOLVE REPORT
  // ============================================================

  Future<void> resolveReport({
    required String reportId,
    required String resolutionNote,
  }) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolutionNote': resolutionNote,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}
