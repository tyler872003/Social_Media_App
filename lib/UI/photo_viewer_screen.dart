import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

/// Full-screen photo viewer.
///
/// Supports:
/// - Old Base64 photos
/// - New Cloudinary photos
/// - Swiping between multiple photos
/// - Pinch-to-zoom
/// - Downloading photos
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    this.images = const [],
    this.media = const [],
    this.initialIndex = 0,
    required this.canDownload,
  });

  /// Old Base64 images.
  final List<String> images;

  /// New Cloudinary media.
  ///
  /// Example:
  /// {
  ///   "url": "https://res.cloudinary.com/...",
  ///   "type": "image"
  /// }
  final List<Map<String, dynamic>> media;

  final int initialIndex;
  final bool canDownload;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  bool _isDownloading = false;

  /// Number of photos available.
  int get _total {
    if (widget.media.isNotEmpty) {
      return widget.media.length;
    }

    return widget.images.length;
  }

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    if (_currentIndex < 0) {
      _currentIndex = 0;
    }

    if (_total > 0 && _currentIndex >= _total) {
      _currentIndex = _total - 1;
    }

    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isCloudinaryMedia() {
    return widget.media.isNotEmpty;
  }

  String? _currentUrl() {
    if (!_isCloudinaryMedia()) {
      return null;
    }

    if (_currentIndex >= widget.media.length) {
      return null;
    }

    final url = widget.media[_currentIndex]['url'];

    if (url is String && url.isNotEmpty) {
      return url;
    }

    return null;
  }

  Future<void> _downloadCurrentImage() async {
    if (_isDownloading || _total == 0) {
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        _showSnack('Photo library access denied. Enable it in Settings.');
        return;
      }

      Uint8List bytes;

      // ─────────────────────────────────────────
      // NEW CLOUDINARY PHOTO
      // ─────────────────────────────────────────
      if (_isCloudinaryMedia()) {
        final url = _currentUrl();

        if (url == null) {
          throw Exception('Photo URL is empty');
        }

        final response = await http.get(Uri.parse(url));

        if (response.statusCode != 200) {
          throw Exception(
            'Could not download image: '
            '${response.statusCode}',
          );
        }

        bytes = response.bodyBytes;
      }
      // ─────────────────────────────────────────
      // OLD BASE64 PHOTO
      // ─────────────────────────────────────────
      else {
        final base64Data = _stripDataUriPrefix(widget.images[_currentIndex]);

        bytes = Uint8List.fromList(base64Decode(base64Data));
      }

      await Gal.putImageBytes(
        bytes,
        name: 'post_${DateTime.now().millisecondsSinceEpoch}',
        album: 'VibeStream',
      );

      _showSnack('Saved to gallery');
    } catch (e) {
      debugPrint('❌ Download photo error: $e');

      _showSnack('Could not save photo');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  String _stripDataUriPrefix(String data) {
    final commaIndex = data.indexOf(',');

    if (data.startsWith('data:') && commaIndex != -1) {
      return data.substring(commaIndex + 1);
    }

    return data;
  }

  void _showSnack(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;

    if (total == 0) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,

        title: total > 1 ? Text('${_currentIndex + 1} / $total') : null,

        actions: [
          if (widget.canDownload)
            IconButton(
              tooltip: 'Download photo',
              onPressed: _isDownloading ? null : _downloadCurrentImage,
              icon:
                  _isDownloading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.download),
            ),
        ],
      ),

      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: total,

            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },

            itemBuilder: (context, index) {
              // ───────────────────────────────
              // CLOUDINARY IMAGE
              // ───────────────────────────────
              if (widget.media.isNotEmpty) {
                final item = widget.media[index];

                final type = item['type']?.toString() ?? '';

                final url = item['url']?.toString() ?? '';

                // Full-screen viewer is for photos.
                if (type == 'video') {
                  return const Center(
                    child: Text(
                      'Video',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  );
                }

                if (url.isEmpty) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  );
                }

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, _, _) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 64,
                          ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) {
                          return child;
                        }

                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                    ),
                  ),
                );
              }

              // ───────────────────────────────
              // OLD BASE64 IMAGE
              // ───────────────────────────────
              try {
                final bytes = base64Decode(
                  _stripDataUriPrefix(widget.images[index]),
                );

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(
                      Uint8List.fromList(bytes),
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, _, _) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 64,
                          ),
                    ),
                  ),
                );
              } catch (_) {
                return const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                );
              }
            },
          ),

          // PAGE INDICATORS
          if (total > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (index) {
                  final active = index == _currentIndex;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 8 : 6,
                    height: active ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? Colors.white : Colors.white38,
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
