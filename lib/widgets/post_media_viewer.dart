import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:first_app/UI/photo_viewer_screen.dart';
import 'package:video_player/video_player.dart';

class PostMediaViewer extends StatefulWidget {
  const PostMediaViewer({
    super.key,
    this.images = const [],
    this.media = const [],
    this.aspectRatio = 4 / 5,
    this.borderRadius = 16,
    this.fit = BoxFit.contain,
    this.canDownload = false,
  });

  final List<String> images;

  // Cloudinary media:
  // [
  //   {
  //     "url": "...",
  //     "type": "image" | "video",
  //     "thumbnailUrl": "...",
  //     "publicId": "..."
  //   }
  // ]
  final List<Map<String, dynamic>> media;

  // Used for normal images/status media.
  final double aspectRatio;

  final double borderRadius;

  // contain is important because cover crops horizontal videos.
  final BoxFit fit;

  final bool canDownload;

  @override
  State<PostMediaViewer> createState() => _PostMediaViewerState();
}

class _PostMediaViewerState extends State<PostMediaViewer> {
  late final PageController _pageController;

  int _currentPage = 0;

  // Stores the real aspect ratio of videos.
  final Map<int, double> _videoAspectRatios = {};

  int get _itemCount {
    if (widget.media.isNotEmpty) {
      return widget.media.length;
    }

    return widget.images.length;
  }

  bool get _hasCloudinaryMedia => widget.media.isNotEmpty;

  Map<String, dynamic>? get _currentMedia {
    if (!_hasCloudinaryMedia) return null;

    if (_currentPage < 0 || _currentPage >= widget.media.length) {
      return null;
    }

    return widget.media[_currentPage];
  }

  bool get _currentIsVideo {
    final item = _currentMedia;

    if (item == null) return false;

    return item['type']?.toString().toLowerCase() == 'video';
  }

  double get _currentAspectRatio {
    if (_currentIsVideo) {
      final videoRatio = _videoAspectRatios[_currentPage];

      if (videoRatio != null && videoRatio > 0) {
        return videoRatio;
      }

      // Temporary frame while video is loading.
      return 16 / 9;
    }

    return widget.aspectRatio;
  }

  @override
  void initState() {
    super.initState();

    _pageController = PageController(
      viewportFraction: _itemCount > 1 ? 0.92 : 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onVideoAspectRatioChanged(int index, double ratio) {
    if (!mounted) return;

    if (ratio <= 0) return;

    if (_videoAspectRatios[index] == ratio) return;

    setState(() {
      _videoAspectRatios[index] = ratio;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_itemCount == 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final aspectRatio = _currentAspectRatio;

        double height;

        if (availableWidth > 0 && aspectRatio > 0) {
          height = availableWidth / aspectRatio;
        } else {
          height = 300;
        }

        // Prevent an accidental zero/infinite height.
        if (!height.isFinite || height <= 0) {
          height = 300;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: double.infinity,
              height: height,
              child:
                  _itemCount == 1
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        child: _buildMediaItem(0),
                      )
                      : PageView.builder(
                        controller: _pageController,
                        itemCount: _itemCount,
                        onPageChanged: (index) {
                          if (!mounted) return;

                          setState(() {
                            _currentPage = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index < _itemCount - 1 ? 8 : 0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                widget.borderRadius,
                              ),
                              child: _buildMediaItem(index),
                            ),
                          );
                        },
                      ),
            ),

            // Page indicators
            if (_itemCount > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_itemCount, (index) {
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
          ],
        );
      },
    );
  }

  Widget _buildMediaItem(int index) {
    // ============================================================
    // CLOUDINARY MEDIA
    // ============================================================
    if (widget.media.isNotEmpty) {
      if (index >= widget.media.length) {
        return const SizedBox.shrink();
      }

      final item = widget.media[index];

      final type = item['type']?.toString().toLowerCase() ?? '';
      final url = item['url']?.toString() ?? '';

      if (url.isEmpty) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.white, size: 40),
          ),
        );
      }

      // ---------------- VIDEO ----------------
      if (type == 'video') {
        return PostVideoPlayer(
          key: ValueKey(url),
          url: url,
          fit: widget.fit,
          onAspectRatioChanged: (ratio) {
            _onVideoAspectRatioChanged(index, ratio);
          },
        );
      }

      // ---------------- IMAGE ----------------
      return GestureDetector(
        onTap: () {
          final imageMedia =
              widget.media
                  .where(
                    (item) => item['type']?.toString().toLowerCase() == 'image',
                  )
                  .toList();

          if (imageMedia.isEmpty) return;

          int imageIndex = 0;

          for (int i = 0; i < index; i++) {
            if (widget.media[i]['type']?.toString().toLowerCase() == 'image') {
              imageIndex++;
            }
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => PhotoViewerScreen(
                    media: imageMedia,
                    initialIndex: imageIndex,
                    canDownload: widget.canDownload,
                  ),
            ),
          );
        },
        child: Image.network(
          url,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return Container(
              color: Colors.black12,
              child: const Center(child: Icon(Icons.broken_image, size: 40)),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return const Center(child: CircularProgressIndicator());
          },
        ),
      );
    }

    // ============================================================
    // OLD BASE64 IMAGE SUPPORT
    // ============================================================
    return GestureDetector(
      onTap: () => _openFullScreen(index),
      child: _buildBase64Image(widget.images[index]),
    );
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

  Widget _buildBase64Image(String base64Data) {
    try {
      return Image.memory(
        base64Decode(base64Data),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return const Center(child: Icon(Icons.broken_image));
        },
      );
    } catch (_) {
      return const Center(child: Icon(Icons.broken_image));
    }
  }
}

// ================================================================
// CLOUDINARY VIDEO PLAYER
// ================================================================

class PostVideoPlayer extends StatefulWidget {
  const PostVideoPlayer({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.onAspectRatioChanged,
  });

  final String url;

  final BoxFit fit;

  final ValueChanged<double>? onAspectRatioChanged;

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  VideoPlayerController? _controller;

  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    debugPrint('🎥 Loading video: ${widget.url}');

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );

      _controller = controller;

      await controller.initialize();

      await controller.setLooping(true);

      if (!mounted) return;

      final ratio = controller.value.aspectRatio;

      debugPrint(
        '🎥 VIDEO SIZE: '
        '${controller.value.size.width} x '
        '${controller.value.size.height}',
      );

      debugPrint('🎥 VIDEO ASPECT RATIO: $ratio');

      setState(() {
        _loading = false;
      });

      // Tell parent the REAL video ratio.
      if (ratio > 0) {
        widget.onAspectRatioChanged?.call(ratio);
      }
    } catch (e) {
      debugPrint('❌ Video initialization error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    // ------------------------------------------------------------
    // LOADING
    // ------------------------------------------------------------
    if (_loading) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // ------------------------------------------------------------
    // ERROR
    // ------------------------------------------------------------
    if (_hasError || controller == null || !controller.value.isInitialized) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 42),
              SizedBox(height: 8),
              Text(
                'Unable to play video',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // REAL VIDEO RATIO
    final videoWidth = controller.value.size.width;
    final videoHeight = controller.value.size.height;

    final videoAspectRatio =
        videoWidth > 0 && videoHeight > 0 ? videoWidth / videoHeight : 16 / 9;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ======================================================
            // IMPORTANT:
            //
            // We DO NOT use BoxFit.cover here.
            //
            // contain = show the complete horizontal video.
            // ======================================================
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: AspectRatio(
                    aspectRatio: videoAspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),

            // ======================================================
            // PLAY BUTTON
            // ======================================================
            if (!controller.value.isPlaying)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(10),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 42,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
