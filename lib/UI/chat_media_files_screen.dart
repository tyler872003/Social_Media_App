import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_app/UI/photo_viewer_screen.dart';
import 'package:first_app/services/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class ChatMediaFilesScreen extends StatefulWidget {
  const ChatMediaFilesScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  final String chatId;
  final String title;

  @override
  State<ChatMediaFilesScreen> createState() => _ChatMediaFilesScreenState();
}

class _ChatMediaFilesScreenState extends State<ChatMediaFilesScreen> {
  final _searchController = TextEditingController();

  String _q = '';
  bool _newestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // BASE64 IMAGE SUPPORT
  // ============================================================

  ImageProvider? _imageProviderFromMessageBase64(String? base64Data) {
    if (base64Data == null) {
      return null;
    }

    final trimmed = base64Data.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    if (!trimmed.startsWith('data:image')) {
      return null;
    }

    try {
      final commaIndex = trimmed.indexOf(',');

      if (commaIndex == -1) {
        return null;
      }

      final b64 = trimmed.substring(commaIndex + 1);

      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  bool _matchesQuery({
    required String queryLower,
    required Map<String, dynamic> m,
  }) {
    if (queryLower.isEmpty) {
      return true;
    }

    final text = (m['text'] as String?)?.toLowerCase() ?? '';

    final fileName = (m['fileName'] as String?)?.toLowerCase() ?? '';

    final type = (m['messageType'] as String?)?.toLowerCase() ?? '';

    return text.contains(queryLower) ||
        fileName.contains(queryLower) ||
        type.contains(queryLower);
  }

  // ============================================================
  // VIDEO FILE DETECTION
  // ============================================================

  bool _looksLikeVideoFileName(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) {
      return false;
    }

    final lower = fileName.toLowerCase();

    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp');
  }

  // ============================================================
  // LINKS
  // ============================================================

  List<String> _extractLinks(String text) {
    final regex = RegExp(
      r'(https?:\/\/[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    );

    final matches = regex.allMatches(text);

    return matches.map((m) => m.group(0)!).toList();
  }

  // ============================================================
  // MESSAGE DATE
  // ============================================================

  DateTime _messageTime(Map<String, dynamic> data) {
    final ts = data['createdAt'];

    if (ts is Timestamp) {
      return ts.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ============================================================
  // BASE64 DATA URI
  // ============================================================

  String _stripDataUriPrefix(String data) {
    final commaIndex = data.indexOf(',');

    if (data.startsWith('data:') && commaIndex != -1) {
      return data.substring(commaIndex + 1);
    }

    return data;
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // OPEN EXTERNAL LINK
  // ============================================================

  Future<void> _openExternalLink(String rawLink) async {
    var link = rawLink.trim();

    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      link = 'https://$link';
    }

    final uri = Uri.tryParse(link);

    if (uri == null) {
      _showSnack('Invalid link');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      _showSnack('Could not open link');
    }
  }

  // ============================================================
  // OPEN OLD BASE64 FILE
  // ============================================================

  Future<void> _openFileFromMessage(Map<String, dynamic> m) async {
    final base64Data = (m['base64Data'] as String?)?.trim();

    if (base64Data == null || base64Data.isEmpty) {
      _showSnack('File data is empty');
      return;
    }

    try {
      final bytes = base64Decode(_stripDataUriPrefix(base64Data));

      final tempDir = await getTemporaryDirectory();

      final fileName =
          (m['fileName'] as String?)?.trim().isNotEmpty == true
              ? (m['fileName'] as String).trim()
              : 'file_${DateTime.now().millisecondsSinceEpoch}';

      final file = File('${tempDir.path}/$fileName');

      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path);

      if (result.type != ResultType.done) {
        _showSnack('Saved file but could not open on this device.');
      }
    } catch (_) {
      _showSnack('Failed to open file');
    }
  }

  // ============================================================
  // DOWNLOAD OLD BASE64 FILE
  // ============================================================

  Future<void> _downloadGenericFile(
    Map<String, dynamic> m, {
    required String defaultFileName,
  }) async {
    final base64Data = (m['base64Data'] as String?)?.trim();

    if (base64Data == null || base64Data.isEmpty) {
      _showSnack('File data is empty');
      return;
    }

    try {
      final bytes = base64Decode(_stripDataUriPrefix(base64Data));

      final fileName =
          (m['fileName'] as String?)?.trim().isNotEmpty == true
              ? (m['fileName'] as String).trim()
              : defaultFileName;

      final savedUri = await fp.FilePicker.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );

      if (savedUri != null) {
        _showSnack('Saved $fileName');
      }
    } catch (_) {
      _showSnack('Failed to save file');
    }
  }

  // ============================================================
  // DOWNLOAD IMAGE
  //
  // SUPPORTS:
  //
  // NEW:
  //   mediaUrl
  //
  // OLD:
  //   base64Data
  // ============================================================

  Future<void> _downloadImage(Map<String, dynamic> m) async {
    final mediaUrl = (m['mediaUrl'] as String?)?.trim();

    // ----------------------------------------------------------
    // CLOUDINARY IMAGE
    // ----------------------------------------------------------

    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      await _downloadCloudinaryImage(mediaUrl, m);
      return;
    }

    // ----------------------------------------------------------
    // OLD BASE64 IMAGE
    // ----------------------------------------------------------

    final base64Data = (m['base64Data'] as String?)?.trim();

    if (base64Data == null || base64Data.isEmpty) {
      _showSnack('Image data is empty');
      return;
    }

    try {
      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        _showSnack(
          'Photo/video library access denied. '
          'Enable it in Settings.',
        );
        return;
      }

      final bytes = base64Decode(_stripDataUriPrefix(base64Data));

      final tempDir = await getTemporaryDirectory();

      final fileName =
          (m['fileName'] as String?)?.trim().isNotEmpty == true
              ? (m['fileName'] as String).trim()
              : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final tempFile = File('${tempDir.path}/$fileName');

      await tempFile.writeAsBytes(bytes, flush: true);

      await Gal.putImage(tempFile.path, album: 'VibeStream');

      _showSnack('Saved to gallery');
    } catch (_) {
      _showSnack('Failed to save image');
    }
  }

  // ============================================================
  // DOWNLOAD CLOUDINARY IMAGE
  // ============================================================

  Future<void> _downloadCloudinaryImage(
    String mediaUrl,
    Map<String, dynamic> m,
  ) async {
    try {
      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        _showSnack(
          'Photo/video library access denied. '
          'Enable it in Settings.',
        );
        return;
      }

      final uri = Uri.tryParse(mediaUrl);

      if (uri == null) {
        _showSnack('Invalid image URL');
        return;
      }

      _showSnack('Downloading image...');

      final client = HttpClient();

      try {
        final request = await client.getUrl(uri);

        final response = await request.close();

        if (response.statusCode != 200) {
          _showSnack(
            'Image download failed '
            '(${response.statusCode}).',
          );
          return;
        }

        final tempDir = await getTemporaryDirectory();

        final originalName = (m['fileName'] as String?)?.trim();

        final fileName =
            originalName != null && originalName.isNotEmpty
                ? originalName
                : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final tempFile = File('${tempDir.path}/$fileName');

        final sink = tempFile.openWrite();

        await response.pipe(sink);

        await Gal.putImage(tempFile.path, album: 'VibeStream');

        _showSnack('Saved to gallery');
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      _showSnack('Failed to download image');
    }
  }

  // ============================================================
  // DOWNLOAD VIDEO
  //
  // SUPPORTS BOTH:
  //
  // OLD:
  //   base64Data
  //
  // NEW:
  //   mediaUrl
  //   thumbnailUrl
  // ============================================================

  Future<void> _downloadVideo(Map<String, dynamic> m) async {
    final mediaUrl = (m['mediaUrl'] as String?)?.trim();

    final base64Data = (m['base64Data'] as String?)?.trim();

    // ----------------------------------------------------------
    // NEW CLOUDINARY VIDEO
    // ----------------------------------------------------------

    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      await _downloadCloudinaryVideo(mediaUrl, m);
      return;
    }

    // ----------------------------------------------------------
    // OLD BASE64 VIDEO
    // ----------------------------------------------------------

    if (base64Data == null || base64Data.isEmpty) {
      _showSnack('Video data is empty');
      return;
    }

    try {
      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        _showSnack(
          'Photo/video library access denied. '
          'Enable it in Settings.',
        );
        return;
      }

      final bytes = base64Decode(_stripDataUriPrefix(base64Data));

      final tempDir = await getTemporaryDirectory();

      final fileName =
          (m['fileName'] as String?)?.trim().isNotEmpty == true
              ? (m['fileName'] as String).trim()
              : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final tempFile = File('${tempDir.path}/$fileName');

      await tempFile.writeAsBytes(bytes, flush: true);

      await Gal.putVideo(tempFile.path, album: 'VibeStream');

      _showSnack('Saved to gallery');
    } catch (_) {
      _showSnack('Failed to save video');
    }
  }

  // ============================================================
  // DOWNLOAD CLOUDINARY VIDEO
  // ============================================================

  Future<void> _downloadCloudinaryVideo(
    String mediaUrl,
    Map<String, dynamic> m,
  ) async {
    try {
      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        _showSnack(
          'Photo/video library access denied. '
          'Enable it in Settings.',
        );
        return;
      }

      final uri = Uri.tryParse(mediaUrl);

      if (uri == null) {
        _showSnack('Invalid video URL');
        return;
      }

      _showSnack('Downloading video...');

      final client = HttpClient();

      try {
        final request = await client.getUrl(uri);

        final response = await request.close();

        if (response.statusCode != 200) {
          _showSnack(
            'Video download failed '
            '(${response.statusCode}).',
          );
          return;
        }

        final tempDir = await getTemporaryDirectory();

        final originalName = (m['fileName'] as String?)?.trim();

        final fileName =
            originalName != null && originalName.isNotEmpty
                ? originalName
                : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

        final tempFile = File('${tempDir.path}/$fileName');

        final sink = tempFile.openWrite();

        await response.pipe(sink);

        await Gal.putVideo(tempFile.path, album: 'VibeStream');

        _showSnack('Saved to gallery');
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      _showSnack('Failed to download video');
    }
  }

  // ============================================================
  // OPEN OLD BASE64 PHOTO VIEWER
  // ============================================================

  void _openPhotoViewer(String base64Data) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => PhotoViewerScreen(images: [base64Data], canDownload: true),
      ),
    );
  }

  // ============================================================
  // OPEN CLOUDINARY PHOTO
  // ============================================================

  void _openCloudinaryPhoto(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenCloudinaryImage(imageUrl: imageUrl),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: _newestFirst ? 'Newest first' : 'Oldest first',
              onPressed: () {
                setState(() {
                  _newestFirst = !_newestFirst;
                });
              },
              icon: Icon(
                _newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Photos'),
              Tab(text: 'Files'),
              Tab(text: 'Videos'),
              Tab(text: 'Audio'),
              Tab(text: 'Links'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) {
                    setState(() {
                      _q = v.trim().toLowerCase();
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search media & files',
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: Colors.grey),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ChatRepository().messages(widget.chatId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  final messages = docs.map((d) => d.data()).toList();

                  final queryLower = _q;

                  final photos = <Map<String, dynamic>>[];

                  final files = <Map<String, dynamic>>[];

                  final videos = <Map<String, dynamic>>[];

                  final audio = <Map<String, dynamic>>[];

                  final links = <String>[];

                  for (final m in messages) {
                    final type = m['messageType'] as String? ?? 'text';

                    if (!_matchesQuery(queryLower: queryLower, m: m)) {
                      continue;
                    }

                    if (type == 'image') {
                      photos.add(m);
                    } else if (type == 'video') {
                      videos.add(m);
                    } else if (type == 'file') {
                      if (_looksLikeVideoFileName(m['fileName'] as String?)) {
                        videos.add(m);
                      } else {
                        files.add(m);
                      }
                    } else if (type == 'audio') {
                      audio.add(m);
                    }

                    final text = (m['text'] as String?) ?? '';

                    links.addAll(_extractLinks(text));
                  }

                  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
                    final left = _messageTime(a);

                    final right = _messageTime(b);

                    return _newestFirst
                        ? right.compareTo(left)
                        : left.compareTo(right);
                  }

                  photos.sort(cmp);
                  files.sort(cmp);
                  videos.sort(cmp);
                  audio.sort(cmp);

                  final uniqueLinks = links.toSet().toList();

                  uniqueLinks.sort((a, b) => _newestFirst ? -1 : 1);

                  return TabBarView(
                    children: [
                      // ------------------------------------------------
                      // PHOTOS
                      // ------------------------------------------------
                      _PhotosTab(
                        items: photos,
                        imageProviderFor: _imageProviderFromMessageBase64,
                        onOpenPhoto: _openPhotoViewer,
                        onOpenCloudinaryPhoto: _openCloudinaryPhoto,
                        onDownloadPhoto: _downloadImage,
                      ),

                      // ------------------------------------------------
                      // FILES
                      // ------------------------------------------------
                      _FilesTab(
                        items: files,
                        onOpenFile: _openFileFromMessage,
                        onDownloadFile:
                            (m) => _downloadGenericFile(
                              m,
                              defaultFileName:
                                  'file_${DateTime.now().millisecondsSinceEpoch}',
                            ),
                      ),

                      // ------------------------------------------------
                      // VIDEOS
                      // ------------------------------------------------
                      _VideosTab(
                        items: videos,
                        onOpenVideoFile: _openVideoMessage,
                        onDownloadVideo: _downloadVideo,
                      ),

                      // ------------------------------------------------
                      // AUDIO
                      // ------------------------------------------------
                      _AudioTab(
                        items: audio,
                        onDownloadAudio:
                            (m) => _downloadGenericFile(
                              m,
                              defaultFileName:
                                  'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
                            ),
                      ),

                      // ------------------------------------------------
                      // LINKS
                      // ------------------------------------------------
                      _LinksTab(
                        items: uniqueLinks,
                        onOpenLink: _openExternalLink,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // OPEN VIDEO MESSAGE
  //
  // CLOUDINARY:
  //   mediaUrl
  //
  // OLD BASE64:
  //   base64Data
  // ============================================================

  Future<void> _openVideoMessage(Map<String, dynamic> message) async {
    final mediaUrl = (message['mediaUrl'] as String?)?.trim();

    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => _FullScreenVideoScreen(
                videoUrl: mediaUrl,
                title: (message['fileName'] as String?) ?? 'Video',
              ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // OLD BASE64 VIDEO
    // ----------------------------------------------------------

    await _openFileFromMessage(message);
  }
}

// ================================================================
// PHOTOS TAB
// ================================================================

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({
    required this.items,
    required this.imageProviderFor,
    required this.onOpenPhoto,
    required this.onOpenCloudinaryPhoto,
    required this.onDownloadPhoto,
  });

  final List<Map<String, dynamic>> items;

  final ImageProvider? Function(String? base64Data) imageProviderFor;

  final void Function(String base64Data) onOpenPhoto;

  final void Function(String imageUrl) onOpenCloudinaryPhoto;

  final Future<void> Function(Map<String, dynamic> message) onDownloadPhoto;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No photos found.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final m = items[index];

        final mediaUrl = (m['mediaUrl'] as String?)?.trim();

        final base64Data = m['base64Data'] as String?;

        // ======================================================
        // NEW CLOUDINARY IMAGE
        // ======================================================

        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          return Stack(
            children: [
              Positioned.fill(
                child: InkWell(
                  onTap: () => onOpenCloudinaryPhoto(mediaUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      mediaUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) {
                          return child;
                        }

                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 35),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Download button
              Positioned(
                right: 4,
                bottom: 4,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onDownloadPhoto(m),
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(
                        Icons.download,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // ======================================================
        // OLD BASE64 IMAGE
        // ======================================================

        final provider = imageProviderFor(base64Data);

        if (provider == null || base64Data == null || base64Data.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: Icon(Icons.broken_image)),
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: () => onOpenPhoto(base64Data),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(image: provider, fit: BoxFit.cover),
                ),
              ),
            ),

            // Download button
            Positioned(
              right: 4,
              bottom: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onDownloadPhoto(m),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.download, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ================================================================
// FILES TAB
// ================================================================

class _FilesTab extends StatelessWidget {
  const _FilesTab({
    required this.items,
    required this.onOpenFile,
    required this.onDownloadFile,
  });

  final List<Map<String, dynamic>> items;

  final Future<void> Function(Map<String, dynamic> message) onOpenFile;

  final Future<void> Function(Map<String, dynamic> message) onDownloadFile;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No files found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final m = items[index];

        final fileName = m['fileName'] as String? ?? 'Document';

        final subtitle = (m['text'] as String?)?.trim();

        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE3F2FD),
            child: Icon(Icons.insert_drive_file, color: Colors.blue),
          ),
          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: () => onDownloadFile(m),
          ),
          onTap: () => onOpenFile(m),
        );
      },
    );
  }
}

// ================================================================
// VIDEOS TAB
// ================================================================

class _VideosTab extends StatelessWidget {
  const _VideosTab({
    required this.items,
    required this.onOpenVideoFile,
    required this.onDownloadVideo,
  });

  final List<Map<String, dynamic>> items;

  final Future<void> Function(Map<String, dynamic> message) onOpenVideoFile;

  final Future<void> Function(Map<String, dynamic> message) onDownloadVideo;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No videos found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final m = items[index];

        final fileName = m['fileName'] as String? ?? 'Video';

        final mediaUrl = (m['mediaUrl'] as String?)?.trim();

        final thumbnailUrl = (m['thumbnailUrl'] as String?)?.trim();

        final isCloudinaryVideo = mediaUrl != null && mediaUrl.isNotEmpty;

        return ListTile(
          leading: SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  thumbnailUrl != null && thumbnailUrl.isNotEmpty
                      ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, _, _) => Container(
                              color: Colors.indigo.shade50,
                              child: const Icon(
                                Icons.videocam,
                                color: Colors.indigo,
                              ),
                            ),
                      )
                      : Container(
                        color: Colors.indigo.shade50,
                        child: const Icon(Icons.videocam, color: Colors.indigo),
                      ),
            ),
          ),
          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isCloudinaryVideo
                ? 'Cloudinary video • Tap to play'
                : 'Tap to open',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Save to gallery',
            onPressed: () => onDownloadVideo(m),
          ),
          onTap: () => onOpenVideoFile(m),
        );
      },
    );
  }
}

// ================================================================
// AUDIO TAB
// ================================================================

class _AudioTab extends StatelessWidget {
  const _AudioTab({required this.items, required this.onDownloadAudio});

  final List<Map<String, dynamic>> items;

  final Future<void> Function(Map<String, dynamic> message) onDownloadAudio;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No audio found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final m = items[index];

        final subtitle = (m['text'] as String?)?.trim();

        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFEBEE),
            child: Icon(Icons.mic, color: Colors.red),
          ),
          title: const Text('Voice message'),
          subtitle:
              subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: () => onDownloadAudio(m),
          ),
        );
      },
    );
  }
}

// ================================================================
// LINKS TAB
// ================================================================

class _LinksTab extends StatelessWidget {
  const _LinksTab({required this.items, required this.onOpenLink});

  final List<String> items;

  final Future<void> Function(String link) onOpenLink;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No links found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final link = items[index];

        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE0F7FA),
            child: Icon(Icons.link, color: Colors.teal),
          ),
          title: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Tap to open'),
          onTap: () => onOpenLink(link),
        );
      },
    );
  }
}

// ================================================================
// FULL SCREEN CLOUDINARY IMAGE
// ================================================================

class _FullScreenCloudinaryImage extends StatelessWidget {
  const _FullScreenCloudinaryImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }

              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 60,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Unable to load image',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ================================================================
// FULL SCREEN CLOUDINARY VIDEO PLAYER
// ================================================================

class _FullScreenVideoScreen extends StatefulWidget {
  const _FullScreenVideoScreen({required this.videoUrl, required this.title});

  final String videoUrl;
  final String title;

  @override
  State<_FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<_FullScreenVideoScreen> {
  VideoPlayerController? _controller;

  bool _initialized = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      _controller = controller;

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load this video.';
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

    if (controller == null || !_initialized) {
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(
        child:
            _error != null
                ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.white)),
                  ],
                )
                : !_initialized || controller == null
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                  onTap: _togglePlayPause,
                  child: AspectRatio(
                    aspectRatio:
                        controller.value.aspectRatio > 0
                            ? controller.value.aspectRatio
                            : 16 / 9,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(controller),

                        AnimatedOpacity(
                          opacity: controller.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(16),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
