import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:first_app/UI/photo_viewer_screen.dart';

/// Displays one or more base64-encoded post images.
/// Single image: static view. Multiple: swipeable carousel with dot indicators.
/// Tapping any image opens a full-screen viewer (pinch-zoom, swipe between
/// photos, and a download button when [canDownload] is true).
class PostMediaViewer extends StatefulWidget {
  const PostMediaViewer({
    super.key,
    required this.images,
    this.aspectRatio = 4 / 5,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
    this.canDownload = false,
  });

  final List<String> images;
  final double aspectRatio;
  final double borderRadius;
  final BoxFit fit;
  final bool canDownload;

  @override
  State<PostMediaViewer> createState() => _PostMediaViewerState();
}

class _PostMediaViewerState extends State<PostMediaViewer> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.images.length > 1 ? 0.92 : 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreen(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PhotoViewerScreen(
              images: widget.images,
              initialIndex: index,
              canDownload: widget.canDownload,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();
    if (widget.images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: GestureDetector(
            onTap: () => _openFullScreen(0),
            child: _buildImage(widget.images.first),
          ),
        ),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  right: index < widget.images.length - 1 ? 8 : 0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: GestureDetector(
                    onTap: () => _openFullScreen(index),
                    child: _buildImage(widget.images[index]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.images.length, (index) {
            final active = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 8 : 6,
              height: active ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildImage(String base64Data) {
    return Image.memory(
      base64Decode(base64Data),
      fit: widget.fit,
      width: double.infinity,
      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
    );
  }
}
