/// Helpers for reading post media data with backward compatibility.
class PostMediaUtils {
  PostMediaUtils._();

  static const int maxImages = 5;

  /// Returns old Base64 image strings.
  ///
  /// This keeps backward compatibility with old posts.
  static List<String> getImages(Map<String, dynamic> post) {
    final images = post['images'];

    if (images is List && images.isNotEmpty) {
      return images
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final legacy = post['base64Data'] as String? ?? '';

    if (legacy.isNotEmpty) {
      return [legacy];
    }

    return [];
  }

  /// Returns the new Cloudinary media list.
  ///
  /// Firestore structure:
  ///
  /// media:
  ///   [
  ///     {
  ///       url: "...",
  ///       type: "video",
  ///       thumbnailUrl: "...",
  ///       publicId: "..."
  ///     }
  ///   ]
  static List<Map<String, dynamic>> getMedia(Map<String, dynamic> post) {
    final media = post['media'];

    if (media is! List || media.isEmpty) {
      return [];
    }

    return media
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Returns the first Cloudinary media item.
  static Map<String, dynamic>? getFirstMedia(Map<String, dynamic> post) {
    final media = getMedia(post);

    if (media.isEmpty) {
      return null;
    }

    return media.first;
  }

  /// Returns the first Cloudinary media URL.
  static String? getMediaUrl(Map<String, dynamic> post) {
    final media = getFirstMedia(post);

    final url = media?['url'];

    if (url is String && url.isNotEmpty) {
      return url;
    }

    return null;
  }

  /// Returns the first Cloudinary media type.
  ///
  /// Possible values:
  /// - image
  /// - video
  static String? getMediaType(Map<String, dynamic> post) {
    final media = getFirstMedia(post);

    final type = media?['type'];

    if (type is String && type.isNotEmpty) {
      return type;
    }

    return null;
  }

  /// Returns the first Cloudinary video thumbnail.
  static String? getThumbnailUrl(Map<String, dynamic> post) {
    final media = getFirstMedia(post);

    final thumbnail = media?['thumbnailUrl'];

    if (thumbnail is String && thumbnail.isNotEmpty) {
      return thumbnail;
    }

    return null;
  }

  /// Returns true when the post contains either:
  /// - old Base64 images
  /// - new Cloudinary media
  static bool hasMedia(Map<String, dynamic> post) {
    return getImages(post).isNotEmpty || getMedia(post).isNotEmpty;
  }

  /// Returns true only for a caption/status-only post.
  static bool isStatusPost(Map<String, dynamic> post) {
    return !hasMedia(post);
  }

  /// Returns the post type.
  static String getPostType(Map<String, dynamic> post) {
    if (isStatusPost(post)) {
      return 'status';
    }

    final media = getMedia(post);

    if (media.isEmpty) {
      return 'photo';
    }

    final hasVideo = media.any((item) => item['type']?.toString() == 'video');

    final hasImage = media.any((item) => item['type']?.toString() == 'image');

    if (hasVideo && hasImage) {
      return 'mixed';
    }

    if (hasVideo) {
      return 'video';
    }

    return 'photo';
  }

  /// Whether the post owner has allowed others to download photos.
  /// Defaults to false — owner must opt in.
  static bool isDownloadAllowed(Map<String, dynamic> post) =>
      post['allowDownload'] == true;

  /// Whether [currentUserId] is permitted to download this post's photos.
  /// The owner can always download their own photos.
  static bool canUserDownload(Map<String, dynamic> post, String currentUserId) {
    final ownerId = post['userId']?.toString() ?? post['ownerId']?.toString();

    if (ownerId != null && ownerId == currentUserId) {
      return true;
    }

    return isDownloadAllowed(post);
  }

  static String timeAgo(dynamic timestamp) {
    DateTime? date;

    if (timestamp is DateTime) {
      date = timestamp;
    } else if (timestamp != null && timestamp.toString().isNotEmpty) {
      try {
        date = DateTime.tryParse(timestamp.toString());
      } catch (_) {}
    }

    date ??= DateTime.now();

    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    }

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }

    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }

    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    }

    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
