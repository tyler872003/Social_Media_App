import 'package:cloud_firestore/cloud_firestore.dart';

/// Your `createdAt` fields are stored as raw millisecond ints in some
/// collections and as Firestore Timestamps in others — this handles both,
/// plus ISO date strings, so parsing never crashes on an unexpected type.
DateTime _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

/// Slim read-model for the admin panel.
/// Replace with your real `Post` model's fields once you wire this up to
/// your actual `posts` collection schema — only the fields the admin UI
/// needs are included here.
class AdminPost {
  final String id;
  final String authorId;
  final String? authorName;
  final String? caption;
  final String? imageBase64;
  final String status; // 'active' | 'removed'
  final int reportCount;
  final DateTime createdAt;

  AdminPost({
    required this.id,
    required this.authorId,
    this.authorName,
    this.caption,
    this.imageBase64,
    required this.status,
    required this.reportCount,
    required this.createdAt,
  });

  factory AdminPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AdminPost(
      id: doc.id,
      authorId: data['userId'] ?? '',
      authorName: data['authorName'],
      caption: data['caption'],
      imageBase64: data['base64Data'],
      status: data['status'] ?? 'active',
      reportCount: data['reportCount'] ?? 0,
      createdAt: _parseDate(data['createdAt']),
    );
  }
}

class AdminReport {
  final String id;
  final String postId;
  final String reporterId;
  final String reason;
  final String status; // 'pending' | 'reviewed'
  final DateTime createdAt;

  AdminReport({
    required this.id,
    required this.postId,
    required this.reporterId,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  factory AdminReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AdminReport(
      id: doc.id,
      postId: data['postId'] ?? '',
      reporterId: data['reporterId'] ?? '',
      reason: data['reason'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: _parseDate(data['createdAt']),
    );
  }
}
