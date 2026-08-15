import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart'; // pubspec: gal: ^2.3.0

/// Full-screen photo viewer opened by tapping a photo in PostMediaViewer.
/// Swipe between a post's photos, pinch to zoom. The download button only
/// shows when [canDownload] is true (owner, or owner allowed downloads).
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.images,
    required this.canDownload,
    this.initialIndex = 0,
  });

  final List<String> images; // base64 strings, same format as PostMediaViewer
  final int initialIndex;
  final bool canDownload;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadCurrentImage() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      var hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }
      if (!hasAccess) {
        _showSnack('Photo library access denied. Enable it in Settings.');
        return;
      }

      final bytes = base64Decode(
        _stripDataUriPrefix(widget.images[_currentIndex]),
      );
      await Gal.putImageBytes(
        Uint8List.fromList(bytes),
        name: 'post_${DateTime.now().millisecondsSinceEpoch}',
        album: 'VibeStream',
      );
      _showSnack('Saved to gallery');
    } catch (_) {
      _showSnack('Could not save photo');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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
    final total = widget.images.length;

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
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) {
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
                        (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 64,
                        ),
                  ),
                ),
              );
            },
          ),
          if (total > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final active = i == _currentIndex;
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
