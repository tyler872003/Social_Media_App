import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }

  return DateTime.now();
}

class AdminPost {
  final String id;
  final String authorId;

  // User information
  final String? authorName;
  final String? authorEmail;

  // Post content
  final String? caption;

  // Legacy media
  final String? imageBase64;
  final List<String> images;

  // Cloudinary media
  final List<Map<String, dynamic>> media;

  // Compatibility fields
  final String? publicId;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? mediaType;

  final String status;
  final int reportCount;
  final DateTime createdAt;

  AdminPost({
    required this.id,
    required this.authorId,
    this.authorName,
    this.authorEmail,
    this.caption,
    this.imageBase64,
    this.images = const [],
    this.media = const [],
    this.publicId,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaType,
    required this.status,
    required this.reportCount,
    required this.createdAt,
  });

  bool get isVideo {
    if (media.isNotEmpty) {
      final type = media.first['type']?.toString().toLowerCase();

      return type == 'video';
    }

    return mediaType?.toLowerCase() == 'video';
  }

  /// First Cloudinary media item
  Map<String, dynamic>? get firstMedia {
    if (media.isEmpty) return null;

    return media.first;
  }

  /// First media URL
  String? get firstMediaUrl {
    if (media.isNotEmpty) {
      return media.first['url']?.toString();
    }

    return mediaUrl;
  }

  /// First video thumbnail
  String? get firstThumbnailUrl {
    if (media.isNotEmpty) {
      return media.first['thumbnailUrl']?.toString();
    }

    return thumbnailUrl;
  }

  AdminPost copyWith({
    String? authorName,
    String? authorEmail,
    String? status,
  }) {
    return AdminPost(
      id: id,
      authorId: authorId,

      authorName: authorName ?? this.authorName,
      authorEmail: authorEmail ?? this.authorEmail,

      caption: caption,

      imageBase64: imageBase64,
      images: images,
      media: media,

      publicId: publicId,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      mediaType: mediaType,

      status: status ?? this.status,
      reportCount: reportCount,
      createdAt: createdAt,
    );
  }

  factory AdminPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    // -----------------------------
    // Caption
    // -----------------------------
    final caption = data['caption']?.toString();

    // -----------------------------
    // Legacy images
    // -----------------------------
    final List<String> parsedImages = [];

    final rawImages = data['images'];

    if (rawImages is List) {
      for (final item in rawImages) {
        final value = item?.toString() ?? '';

        if (value.isNotEmpty) {
          parsedImages.add(value);
        }
      }
    }

    final base64 = data['base64Data']?.toString();

    // -----------------------------
    // New Cloudinary media[]
    // -----------------------------
    final List<Map<String, dynamic>> parsedMedia = [];

    final rawMedia = data['media'];

    if (rawMedia is List) {
      for (final item in rawMedia) {
        if (item is Map) {
          parsedMedia.add(Map<String, dynamic>.from(item));
        }
      }
    }

    // -----------------------------
    // Transitional top-level fields
    // -----------------------------
    final topLevelUrl = data['url']?.toString();
    final topLevelType = data['type']?.toString();
    final topLevelThumbnail = data['thumbnailUrl']?.toString();
    final topLevelPublicId = data['publicId']?.toString();

    // If there is no media[] but the document has
    // top-level Cloudinary fields, support them too.
    if (parsedMedia.isEmpty && topLevelUrl != null && topLevelUrl.isNotEmpty) {
      parsedMedia.add({
        'url': topLevelUrl,
        'type': topLevelType ?? 'image',
        'thumbnailUrl': topLevelThumbnail,
        'publicId': topLevelPublicId,
      });
    }

    return AdminPost(
      id: doc.id,

      authorId: data['userId']?.toString() ?? '',

      // User information
      authorName:
          data['authorName']?.toString() ?? data['displayName']?.toString(),

      authorEmail: data['authorEmail']?.toString(),

      // Post content
      caption: caption,

      // Legacy media
      imageBase64: base64,
      images: parsedImages,

      // Cloudinary media
      media: parsedMedia,

      // Compatibility fields
      publicId: topLevelPublicId,
      mediaUrl: topLevelUrl,
      thumbnailUrl: topLevelThumbnail,
      mediaType: topLevelType,

      status: data['status']?.toString() ?? 'active',

      reportCount: data['reportCount'] is int ? data['reportCount'] as int : 0,

      createdAt: _parseDate(data['createdAt']),
    );
  }
}

class AdminReport {
  final String id;
  final String postId;
  final String reporterId;
  final String reason;
  final String status;
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
    final data = doc.data() ?? {};

    return AdminReport(
      id: doc.id,

      postId: data['postId']?.toString() ?? '',

      reporterId: data['reporterId']?.toString() ?? '',

      reason: data['reason']?.toString() ?? '',

      status: data['status']?.toString() ?? 'pending',

      createdAt: _parseDate(data['createdAt']),
    );
  }
}
