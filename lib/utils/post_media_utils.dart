/// Helpers for reading post image data with backward compatibility.
class PostMediaUtils {
  PostMediaUtils._();

  static const int maxImages = 5;

  /// Returns all base64 image strings for a post (empty for status-only).
  static List<String> getImages(Map<String, dynamic> post) {
    final images = post['images'];
    if (images is List && images.isNotEmpty) {
      return images.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final legacy = post['base64Data'] as String? ?? '';
    if (legacy.isNotEmpty) return [legacy];
    return [];
  }

  static bool isStatusPost(Map<String, dynamic> post) => getImages(post).isEmpty;

  static String getPostType(Map<String, dynamic> post) =>
      isStatusPost(post) ? 'status' : 'photo';

  /// Whether the post owner (person A) has allowed others to download photos.
  /// Defaults to false — owner must opt in.
  static bool isDownloadAllowed(Map<String, dynamic> post) =>
      post['allowDownload'] == true;

  /// Whether [currentUserId] is permitted to download this post's photos.
  /// The owner can always download their own photos; others need
  /// [isDownloadAllowed] to be true.
  static bool canUserDownload(Map<String, dynamic> post, String currentUserId) {
    final ownerId = post['userId']?.toString() ?? post['ownerId']?.toString();
    if (ownerId != null && ownerId == currentUserId) return true;
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
