import 'dart:convert';
import 'package:flutter/material.dart';

/// Renders a post's image from raw base64 data (your `posts` collection
/// stores the image itself in `base64Data`, not a hosted URL).
/// Falls back to a placeholder icon if the data is missing or malformed.
class PostThumbnail extends StatelessWidget {
  final String? base64Data;
  final double size;

  const PostThumbnail({super.key, required this.base64Data, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final data = base64Data;
    if (data == null || data.isEmpty) {
      return _placeholder(Icons.image_not_supported);
    }

    try {
      // Strip a `data:image/jpeg;base64,` prefix if present.
      final commaIndex = data.indexOf(',');
      final raw = data.startsWith('data:') && commaIndex != -1
          ? data.substring(commaIndex + 1)
          : data;
      final bytes = base64Decode(raw);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image),
        ),
      );
    } catch (_) {
      return _placeholder(Icons.broken_image);
    }
  }

  Widget _placeholder(IconData icon) => Container(
    width: size,
    height: size,
    color: Colors.grey.shade200,
    child: Icon(icon, color: Colors.grey.shade500),
  );
}
