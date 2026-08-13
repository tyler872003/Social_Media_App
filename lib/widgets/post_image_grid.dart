import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/post_media_utils.dart';
import '../UI/photo_viewer_screen.dart';

/// Renders a post's photos as a tappable grid inside the newsfeed card.
/// Tapping any photo opens PhotoViewerScreen at that photo's index.
class PostImageGrid extends StatelessWidget {
  final Map<String, dynamic> post;
  final String currentUserId;

  const PostImageGrid({
    super.key,
    required this.post,
    required this.currentUserId,
  });

  Uint8List _decode(String data) {
    final commaIndex = data.indexOf(',');
    final raw =
        data.startsWith('data:') && commaIndex != -1
            ? data.substring(commaIndex + 1)
            : data;
    return Uint8List.fromList(base64Decode(raw));
  }

  void _open(BuildContext context, List<String> images, int index) {
    final canDownload = PostMediaUtils.canUserDownload(post, currentUserId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PhotoViewerScreen(
              images: images,
              initialIndex: index,
              canDownload: canDownload,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = PostMediaUtils.getImages(post);
    if (images.isEmpty) return const SizedBox.shrink();

    // Single photo: full-width, natural aspect ratio.
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => _open(context, images, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _decode(images[0]),
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      );
    }

    // Multiple photos: grid, with a "+N" overlay if there are more than
    // fit on screen (feed shows up to 4 tiles, viewer holds all of them).
    final visibleCount = images.length > 4 ? 4 : images.length;
    final overflow = images.length - visibleCount;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: visibleCount,
          itemBuilder: (context, index) {
            final isLastTile = index == visibleCount - 1 && overflow > 0;
            return GestureDetector(
              onTap: () => _open(context, images, index),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_decode(images[index]), fit: BoxFit.cover),
                  if (isLastTile)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Text(
                        '+$overflow',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
