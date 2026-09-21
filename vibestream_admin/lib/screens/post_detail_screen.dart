// lib/screens/post_detail_screen.dart
//
// Requires in pubspec.yaml:  video_player: ^2.9.0   (then FULL restart, not hot reload)

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/firestore_admin_service.dart';
import '../services/post_deletion.dart';

/// Pops with:
///  - 'deleted'  if the post was permanently deleted
///  - 'removed' / 'active' (the latest status) otherwise, if it changed
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final String displayName;
  final String? email;

  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.displayName,
    this.email,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FirestoreAdminService _service = FirestoreAdminService();

  bool _busy = false;
  String? _latestStatus;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('posts').doc(widget.postId);

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _setRemoved(bool remove) async {
    setState(() => _busy = true);
    try {
      if (remove) {
        await _service.removePost(widget.postId);
      } else {
        await _service.restorePost(widget.postId);
      }
      _latestStatus = remove ? 'removed' : 'active';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever() async {
    setState(() => _busy = true);
    final deleted = await confirmAndDeletePost(context, widget.postId);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context, 'deleted');
    } else {
      setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // Formatting helpers
  // ------------------------------------------------------------------

  String _formatValue(String key, dynamic v) {
    if (v == null) return 'null';
    if (v is Timestamp) return v.toDate().toLocal().toString();
    if (v is int && key.toLowerCase().endsWith('at') && v > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(v).toLocal().toString();
    }
    if (v is List) {
      if (v.isEmpty) return '[] (0)';
      final items = v.map((e) => e is Map ? _formatMap(e) : e.toString());
      return '(${v.length})\n${items.join('\n---\n')}';
    }
    if (v is Map) {
      if (v.isEmpty) return '{} (0)';
      return _formatMap(v);
    }
    return v.toString();
  }

  String _formatMap(Map m) =>
      m.entries.map((e) => '${e.key}: ${e.value}').join('\n');

  // ------------------------------------------------------------------
  // Media
  // ------------------------------------------------------------------

  /// Reads the `media` array: [{url, thumbnailUrl, type, publicId}, ...]
  List<Map<String, dynamic>> _mediaItems(Map<String, dynamic> d) {
    final items = <Map<String, dynamic>>[];
    final m = d['media'];
    if (m is List) {
      for (final e in m) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
    }
    return items;
  }

  Widget _buildMedia(Map<String, dynamic> d) {
    final widgets = <Widget>[];

    // 1. Legacy base64 image stored directly on the post.
    final b64 = (d['base64Data'] ?? d['imageBase64']) as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final clean = b64.contains(',') ? b64.split(',').last : b64;
        widgets.add(
          _MediaFrame(
            child: Image.memory(
              base64Decode(clean),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      } catch (_) {}
    }

    // 2. New-style media array (Cloudinary URLs).
    for (final item in _mediaItems(d)) {
      final url = item['url'] as String?;
      final thumb = item['thumbnailUrl'] as String?;
      final type = (item['type'] as String?)?.toLowerCase() ?? '';
      if (url == null || url.isEmpty) continue;

      if (type.contains('video')) {
        widgets.add(_VideoPlayerView(url: url, thumbnailUrl: thumb));
      } else {
        widgets.add(
          _MediaFrame(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, __, ___) =>
                  const _MediaPlaceholder('Could not load image'),
            ),
          ),
        );
      }
    }

    // 3. Older top-level fields (mediaUrl / thumbnailUrl).
    if (widgets.isEmpty) {
      final mediaUrl = d['mediaUrl'] as String?;
      final thumbUrl = d['thumbnailUrl'] as String?;
      final type = (d['mediaType'] as String?)?.toLowerCase() ?? '';
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        widgets.add(
          type.contains('video')
              ? _VideoPlayerView(url: mediaUrl, thumbnailUrl: thumbUrl)
              : _MediaFrame(
                  child: Image.network(
                    mediaUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const _MediaPlaceholder('Could not load image'),
                  ),
                ),
        );
      }
    }

    if (widgets.isEmpty) return const _MediaPlaceholder('No media');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in widgets)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _latestStatus);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Post details')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _ref.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Failed to load post: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.data!.exists) {
              return const Center(child: Text('This post no longer exists.'));
            }

            final data = snap.data!.data()!;
            final removed = data['status'] == 'removed';
            final caption = (data['caption'] as String?) ?? '';

            // Every field except the giant base64 blob, alphabetically.
            final keys =
                data.keys
                    .where((k) => k != 'base64Data' && k != 'imageBase64')
                    .toList()
                  ..sort();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Author
                Text(
                  widget.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.email != null)
                  Text(
                    widget.email!,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                const SizedBox(height: 16),

                // Media
                _buildMedia(data),
                const SizedBox(height: 8),

                // Caption (full, selectable)
                if (caption.isNotEmpty) ...[
                  SelectableText(caption, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                ],

                // Status banner
                if (removed)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'This post is removed'
                      '${data['removalReason'] != null ? ' — reason: ${data['removalReason']}' : ''}',
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),

                // Actions
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (removed)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _setRemoved(false),
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _setRemoved(true),
                        icon: const Icon(Icons.visibility_off),
                        label: const Text('Remove (hide)'),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: _busy ? null : _deleteForever,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete permanently'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Text(
                  'All fields',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Divider(),

                for (final k in keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(
                            k,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(_formatValue(k, data[k])),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ======================================================================
// Media widgets
// ======================================================================

class _MediaFrame extends StatelessWidget {
  final Widget child;
  const _MediaFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Center(child: child),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  final String text;
  const _MediaPlaceholder(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    );
  }
}

/// Shows the thumbnail with a play button; loads and plays the video on tap
/// (so a post with several videos doesn't download them all up front).
class _VideoPlayerView extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;

  const _VideoPlayerView({required this.url, this.thumbnailUrl});

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (e) {
      await c.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    // Playing state
    if (c != null && c.value.isInitialized) {
      return _MediaFrame(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(c),
              Container(
                color: Colors.black38,
                child: Row(
                  children: [
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, value, __) => IconButton(
                        color: Colors.white,
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: () => value.isPlaying ? c.pause() : c.play(),
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(c, allowScrubbing: true),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Thumbnail + play button
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MediaFrame(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.thumbnailUrl != null &&
                  widget.thumbnailUrl!.isNotEmpty)
                Image.network(
                  widget.thumbnailUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const _MediaPlaceholder('Video'),
                )
              else
                const _MediaPlaceholder('Video'),
              if (_loading)
                const CircularProgressIndicator()
              else
                IconButton.filled(
                  iconSize: 48,
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Could not play video in the browser.',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SelectableText(
            widget.url,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
