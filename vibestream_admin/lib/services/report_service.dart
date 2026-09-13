import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reasons shown to the reporting user. Matches the categories the admin
/// moderation queue displays (Spam / Inappropriate Media / Harassment).
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

/// Aggregate counts shown on the "Total Reports" stat card.
class ReportCounts {
  const ReportCounts({required this.total, required this.last30Days});
  final int total;
  final int last30Days;
}

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Submits a report for [postId]. Returns without writing anything if the
  /// signed-in user already has a pending report on this post, so repeated
  /// taps don't create duplicates.
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('You need to be signed in to report a post.');
    }

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
      // Matches your posts collection's convention of storing createdAt
      // as a millisecond int rather than a Firestore Timestamp.
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Admin audit screen support ─────────────────────────
  //
  // Reports in this schema only reference a `postId` — there's no field
  // recording which user is being reported. So "reports for user X" is a
  // two-step join: find X's post ids, then find reports against those
  // posts. Firestore's `whereIn` caps out at 30 values per query, so
  // this chunks into batches of 30 and merges the results.

  Future<List<String>> _postIdsForUser(String uid) async {
    final snap = await _db
        .collection('posts')
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  List<List<String>> _chunk(List<String> items, int size) {
    final chunks = <List<String>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(
        items.sublist(i, i + size > items.length ? items.length : i + size),
      );
    }
    return chunks;
  }

  /// One-time counts for the "Total Reports" stat card: total reports
  /// against this user's posts, and how many of those landed in the last
  /// 30 days.
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
    for (final chunk in _chunk(postIds, 30)) {
      final snap = await _db
          .collection('reports')
          .where('postId', whereIn: chunk)
          .get();
      total += snap.docs.length;
      last30Days += snap.docs.where((d) {
        final createdAt = d.data()['createdAt'];
        return createdAt is int && createdAt >= cutoffMillis;
      }).length;
    }
    return ReportCounts(total: total, last30Days: last30Days);
  }

  /// Live list of reports against this user's posts, newest first, for
  /// the "Recent Reports" panel.
  ///
  /// NOTE: this only re-runs the join when the stream itself is
  /// (re)subscribed — e.g. re-entering the audit screen — not on every
  /// new post the user makes or new report someone files. True real-time
  /// updates would need a `reportedUserId` field written onto each report
  /// at creation time (denormalized from the post's author) so this can
  /// be a single direct query instead of a join. Worth adding if this
  /// screen needs to stay open and live-update during a report session.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> reportsForUser(
    String uid, {
    int limit = 50,
  }) async* {
    final postIds = await _postIdsForUser(uid);
    if (postIds.isEmpty) {
      yield <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    // Firestore whereIn caps at 30 values; if a user has more posts than
    // that, only their most recent 30 posts' reports are watched live.
    final chunk = postIds.take(30).toList();
    yield* _db
        .collection('reports')
        .where('postId', whereIn: chunk)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs);
  }

  Future<void> resolveReport({
    required String reportId,
    required String resolutionNote,
  }) {
    return _db.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolutionNote': resolutionNote,
      'resolvedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
