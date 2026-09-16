import 'dart:convert';

import 'package:flutter/material.dart';

/// Displays the thumbnail of a post.
///
/// Supports:
///
/// OLD:
/// - Base64 image
/// - images[]
///
/// NEW:
/// - media[]
///   - url
///   - type
///   - thumbnailUrl
///   - publicId
///
/// It also supports the older top-level Cloudinary fields for compatibility.
class PostThumbnail extends StatelessWidget {
  /// Old Base64 image.
  final String? base64Data;

  /// Old/transitional Cloudinary URL.
  final String? mediaUrl;

  /// Old/transitional Cloudinary video thumbnail.
  final String? thumbnailUrl;

  /// Old/transitional media type.
  final String? mediaType;

  /// NEW Cloudinary media list.
  final List<Map<String, dynamic>> media;

  final double size;

  const PostThumbnail({
    super.key,
    this.base64Data,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaType,
    this.media = const [],
    this.size = 72,
  });

  // ===========================================================================
  // FIRST MEDIA ITEM
  // ===========================================================================

  Map<String, dynamic>? get _firstMedia {
    for (final item in media) {
      final url = item['url']?.toString().trim() ?? '';

      if (url.isNotEmpty) {
        return item;
      }
    }

    return null;
  }

  // ===========================================================================
  // MEDIA TYPE
  // ===========================================================================

  String get _resolvedMediaType {
    final first = _firstMedia;

    if (first != null) {
      final type = first['type']?.toString().toLowerCase().trim() ?? '';

      if (type.isNotEmpty) {
        return type;
      }
    }

    return mediaType?.toLowerCase().trim() ?? '';
  }

  bool get _isVideo => _resolvedMediaType == 'video';

  // ===========================================================================
  // MEDIA URL
  // ===========================================================================

  String? get _resolvedMediaUrl {
    final first = _firstMedia;

    if (first != null) {
      final url = first['url']?.toString().trim() ?? '';

      if (url.isNotEmpty) {
        return url;
      }
    }

    if (mediaUrl != null && mediaUrl!.trim().isNotEmpty) {
      return mediaUrl!.trim();
    }

    return null;
  }

  // ===========================================================================
  // THUMBNAIL URL
  // ===========================================================================

  String? get _resolvedThumbnailUrl {
    final first = _firstMedia;

    if (first != null) {
      final url = first['thumbnailUrl']?.toString().trim() ?? '';

      if (url.isNotEmpty) {
        return url;
      }
    }

    if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty) {
      return thumbnailUrl!.trim();
    }

    return null;
  }

  // ===========================================================================
  // FINAL NETWORK SOURCE
  // ===========================================================================

  String? get _networkSource {
    if (_isVideo) {
      // For videos, use Cloudinary thumbnail first.
      final thumbnail = _resolvedThumbnailUrl;

      if (thumbnail != null && thumbnail.isNotEmpty) {
        return thumbnail;
      }

      // Fallback to video URL.
      return _resolvedMediaUrl;
    }

    // For images, use Cloudinary URL.
    return _resolvedMediaUrl;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final networkSource = _networkSource;

    Widget child;

    // -------------------------------------------------------------------------
    // CLOUDINARY
    // -------------------------------------------------------------------------

    if (networkSource != null && networkSource.isNotEmpty) {
      child = Image.network(
        networkSource,
        width: size,
        height: size,
        fit: BoxFit.cover,

        loadingBuilder: (context, image, loadingProgress) {
          if (loadingProgress == null) {
            return image;
          }

          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },

        errorBuilder: (context, error, stackTrace) {
          return _placeholder(_isVideo ? Icons.video_file : Icons.broken_image);
        },
      );
    }
    // -------------------------------------------------------------------------
    // LEGACY BASE64
    // -------------------------------------------------------------------------
    else if (base64Data != null && base64Data!.trim().isNotEmpty) {
      child = _base64Image();
    }
    // -------------------------------------------------------------------------
    // NOTHING
    // -------------------------------------------------------------------------
    else {
      child = _placeholder(
        _isVideo ? Icons.video_file : Icons.image_not_supported,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(width: size, height: size, child: child),

          // -------------------------------------------------------------------
          // VIDEO PLAY ICON
          // -------------------------------------------------------------------
          if (_isVideo && networkSource != null && networkSource.isNotEmpty)
            Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: size * 0.25,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BASE64
  // ===========================================================================

  Widget _base64Image() {
    try {
      final data = base64Data!.trim();

      String raw = data;

      final commaIndex = data.indexOf(',');

      if (data.startsWith('data:') && commaIndex != -1) {
        raw = data.substring(commaIndex + 1);
      }

      final bytes = base64Decode(raw);

      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _placeholder(Icons.broken_image);
        },
      );
    } catch (_) {
      return _placeholder(Icons.broken_image);
    }
  }

  // ===========================================================================
  // PLACEHOLDER
  // ===========================================================================

  Widget _placeholder(IconData icon) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      child: Icon(icon, color: Colors.grey.shade500),
    );
  }
}
