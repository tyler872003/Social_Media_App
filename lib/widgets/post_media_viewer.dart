import 'dart:async';
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

  // Stores the real (rotation-corrected) aspect ratio of videos.
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

  // ------------------------------------------------------------------
  // FIX: clamp the video's real aspect ratio.
  //
  // Without this, a portrait video (e.g. 9:16 ≈ 0.56) makes the card
  // height = availableWidth / 0.56 ≈ 1.78x the width — nearly the full
  // screen height, which is what made vertical videos "hard to watch".
  //
  // Clamping to a minimum of 0.75 (3:4) keeps portrait videos looking
  // like a normal social-media portrait post instead of a full-screen
  // takeover, while horizontal videos (ratio > 1) are untouched.
  // ------------------------------------------------------------------
  static const double _minVideoAspectRatio = 0.75; // 3:4
  static const double _maxVideoAspectRatio = 16 / 9;

  double get _currentAspectRatio {
    if (_currentIsVideo) {
      final videoRatio = _videoAspectRatios[_currentPage];

      if (videoRatio != null && videoRatio > 0) {
        return videoRatio.clamp(_minVideoAspectRatio, _maxVideoAspectRatio);
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

        // ------------------------------------------------------------
        // FIX: hard safety cap on top of the ratio clamp above.
        //
        // No single media card — video or image — should ever eat more
        // than ~55% of the screen height. This keeps the feed scannable
        // (multiple posts visible) instead of one video dominating the
        // whole screen like a full-screen story.
        // ------------------------------------------------------------
        final maxHeight = MediaQuery.of(context).size.height * 0.55;
        height = height.clamp(200.0, maxHeight);

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
// CLOUDINARY VIDEO PLAYER — now with YouTube-style controls:
//   - tap the video to show/hide the control bar
//   - tap the center button to play/pause
//   - drag the progress bar to seek to any second
//   - current time / total duration shown
//   - controls auto-hide after a few seconds while playing
//
// ROTATION FIX:
//   Android's video_player reports `controller.value.size` as the RAW,
//   unrotated decoder-buffer dimensions. The plugin separately exposes
//   `controller.value.rotationCorrection` (0/90/180/270) — the degrees
//   it internally rotates the actual displayed pixels by. Videos
//   recorded directly by a phone camera very often carry a 90°/270°
//   rotation flag (e.g. buffer is 1920x1080 landscape, displayed
//   pixels are 1080x1920 portrait). TikTok downloads typically have no
//   such flag (already baked-in portrait), which is why only
//   camera-recorded videos showed the bug.
//
//   Without accounting for rotationCorrection, we were computing the
//   aspect ratio from the *raw* (landscape) size while the plugin was
//   already drawing *rotated* (portrait) pixels — so the video got
//   boxed/stretched into the wrong shape. The fix: swap width/height
//   whenever rotationCorrection is 90 or 270, everywhere we read size.
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

  // Whether the bottom seek-bar/time strip is visible. The center
  // play/pause button's visibility is driven separately by whether the
  // video is actually playing (see build()).
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();

    debugPrint('🎥 Loading video: ${widget.url}');

    _initializeVideo();
  }

  // Returns true when the plugin will display the video rotated 90° or
  // 270° from the raw buffer orientation, meaning width/height need to
  // be swapped for any layout math (aspect ratio, sizing boxes, etc).
  bool _needsSwap(VideoPlayerController controller) {
    final rotation = controller.value.rotationCorrection;
    return rotation == 90 || rotation == 270;
  }

  // The *effective* (post-rotation) width/height actually shown on
  // screen — use these instead of controller.value.size directly.
  Size _effectiveSize(VideoPlayerController controller) {
    final rawSize = controller.value.size;

    if (_needsSwap(controller)) {
      return Size(rawSize.height, rawSize.width);
    }

    return rawSize;
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

      final effectiveSize = _effectiveSize(controller);

      final ratio =
          effectiveSize.height > 0
              ? effectiveSize.width / effectiveSize.height
              : controller.value.aspectRatio;

      debugPrint(
        '🎥 VIDEO RAW SIZE: '
        '${controller.value.size.width} x '
        '${controller.value.size.height}',
      );

      debugPrint(
        '🎥 ROTATION CORRECTION: ${controller.value.rotationCorrection}',
      );

      debugPrint('🎥 EFFECTIVE VIDEO ASPECT RATIO: $ratio');

      setState(() {
        _loading = false;
      });

      // Tell parent the REAL (rotation-corrected) video ratio. The
      // parent (PostMediaViewer) is responsible for clamping this to a
      // sane display range — this widget always reports the true,
      // as-displayed ratio.
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
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();

    final controller = _controller;

    // Only auto-hide while actually playing — while paused the strip
    // should stay put so the person can still see/use it.
    if (controller == null || !controller.value.isPlaying) return;

    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      setState(() {
        _showControls = false;
      });
    });
  }

  void _togglePlayPause() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _hideControlsTimer?.cancel();
      } else {
        controller.play();
        _startHideControlsTimer();
      }
    });
  }

  void _handleTapVideo() {
    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');

    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(seconds)}';
    }

    return '${d.inMinutes}:${two(seconds)}';
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

    // EFFECTIVE (rotation-corrected) VIDEO SIZE — used to size the
    // inner FittedBox content. The outer box height is already
    // clamped by PostMediaViewer using the ratio we reported earlier.
    final effectiveSize = _effectiveSize(controller);

    final videoWidth = effectiveSize.width;
    final videoHeight = effectiveSize.height;

    final videoAspectRatio =
        videoWidth > 0 && videoHeight > 0 ? videoWidth / videoHeight : 16 / 9;

    return GestureDetector(
      onTap: _handleTapVideo,
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
            // contain = show the complete video, letterboxed with
            // black bars if its ratio doesn't match the (clamped)
            // outer box — this is what keeps portrait videos fully
            // visible instead of cropped or stretched.
            //
            // The VideoPlayer widget itself already draws the pixels
            // rotated per rotationCorrection — we just need to size
            // the SizedBox/AspectRatio using the EFFECTIVE (already
            // swapped) width/height so the box shape matches what's
            // actually being drawn.
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
            // CENTER PLAY/PAUSE BUTTON
            // Always visible while paused; while playing it only
            // shows up alongside the rest of the controls.
            // ======================================================
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final show = !value.isPlaying || _showControls;

                if (!show) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                );
              },
            ),

            // ======================================================
            // BOTTOM BAR — seek bar (drag to any second) + time
            // ======================================================
            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // allowScrubbing lets the person drag (or tap)
                      // anywhere on the bar to jump straight to that
                      // point in the video — same as YouTube's bar.
                      SizedBox(
                        height: 20,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: VideoProgressColors(
                            playedColor: Theme.of(context).colorScheme.primary,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              return Text(
                                '${_formatDuration(value.position)} / '
                                '${_formatDuration(value.duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              final isMuted = controller.value.volume == 0;
                              controller.setVolume(isMuted ? 1 : 0);
                            },
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: controller,
                              builder: (context, value, _) {
                                return Icon(
                                  value.volume == 0
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                  color: Colors.white,
                                  size: 18,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
