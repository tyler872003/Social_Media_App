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
}
