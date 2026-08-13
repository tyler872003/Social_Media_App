import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/services/post_repository.dart';
import 'package:first_app/utils/post_media_utils.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AddPostScreen extends StatefulWidget {
  const AddPostScreen({super.key});

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final _captionController = TextEditingController();
  final _postRepo = PostRepository();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  final List<File> _imageFiles = [];
  String _privacy = 'public';
  bool _allowDownload = false;
  Map<String, dynamic>? _userData;

  static const _privacyOptions = [
    {
      'value': 'public',
      'label': 'Everyone',
      'icon': Icons.public,
      'desc': 'Everyone can see this post',
    },
    {
      'value': 'friends',
      'label': 'Friends',
      'icon': Icons.people,
      'desc': 'Only your friends can see this',
    },
    {
      'value': 'closedFriends',
      'label': 'Closed Friends',
      'icon': Icons.star,
      'desc': 'Only your closed friends list',
    },
    {
      'value': 'private',
      'label': 'Only Me',
      'icon': Icons.lock,
      'desc': 'Only you can see this',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (mounted && doc.exists) {
      setState(() => _userData = doc.data());
    }
  }

  bool get _canPost {
    return _captionController.text.trim().isNotEmpty || _imageFiles.isNotEmpty;
  }

  Future<void> _pickImages() async {
    if (_imageFiles.length >= PostMediaUtils.maxImages) {
      _showSnack('You can add up to ${PostMediaUtils.maxImages} photos.');
      return;
    }

    final picker = ImagePicker();
    final remaining = PostMediaUtils.maxImages - _imageFiles.length;
    final picked = await picker.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1080,
      limit: remaining,
    );

    if (picked.isEmpty) return;

    setState(() {
      for (final item in picked) {
        if (_imageFiles.length >= PostMediaUtils.maxImages) break;
        _imageFiles.add(File(item.path));
      }
    });
  }

  void _removeImage(int index) {
    setState(() => _imageFiles.removeAt(index));
  }

  Future<void> _createPost() async {
    if (!_canPost) {
      _showSnack('Write something or add at least one photo.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final base64Images = <String>[];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      List<String> closedFriendsIds = [];
      if (_privacy == 'closedFriends') {
        closedFriendsIds = await _postRepo.getClosedFriends();
      }

      await _postRepo.createPost(
        base64Images: base64Images,
        caption: _captionController.text.trim(),
        privacy: _privacy,
        closedFriendsIds: closedFriendsIds,
        allowDownload: base64Images.isNotEmpty ? _allowDownload : false,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPrivacyPicker() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Who can see this post?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              for (final option in _privacyOptions)
                ListTile(
                  leading: Icon(
                    option['icon'] as IconData,
                    color:
                        _privacy == option['value']
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  title: Text(option['label'] as String),
                  subtitle: Text(
                    option['desc'] as String,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing:
                      _privacy == option['value']
                          ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : null,
                  onTap: () {
                    setState(() => _privacy = option['value'] as String);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openManageClosedFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageClosedFriendsScreen()),
    );
  }

  String get _privacyLabel {
    return (_privacyOptions.firstWhere(
          (o) => o['value'] == _privacy,
          orElse: () => _privacyOptions.first,
        )['label']
        as String);
  }

  IconData get _privacyIcon {
    return (_privacyOptions.firstWhere(
          (o) => o['value'] == _privacy,
          orElse: () => _privacyOptions.first,
        )['icon']
        as IconData);
  }

  String get _displayName {
    return _userData?['displayName'] as String? ??
        _auth.currentUser?.displayName ??
        'User';
  }

  String? get _photoUrl => _userData?['photoUrl'] as String?;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppLoadingOverlay(
      isLoading: _isLoading,
      message: 'Posting...',
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          elevation: 0,
          leading: TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          leadingWidth: 80,
          title: const Text(
            'New Post',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _isLoading || !_canPost ? null : _createPost,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Post'),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(_photoUrl, 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _showPrivacyPicker,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _privacyIcon,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _privacyLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _captionController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "What's on your mind?",
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 18,
                  ),
                  border: InputBorder.none,
                ),
                maxLines: null,
                minLines: 4,
                style: const TextStyle(fontSize: 18, height: 1.4),
              ),
              if (_imageFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: _imageFiles.length == 1 ? 280 : 120,
                  child:
                      _imageFiles.length == 1
                          ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  _imageFiles.first,
                                  width: double.infinity,
                                  height: 280,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: _RemovePhotoButton(
                                  onTap: () => _removeImage(0),
                                ),
                              ),
                            ],
                          )
                          : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _imageFiles.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      _imageFiles[index],
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: _RemovePhotoButton(
                                      onTap: () => _removeImage(index),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_imageFiles.length}/${PostMediaUtils.maxImages} photos',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  _imageFiles.isEmpty
                      ? 'Add photos (up to ${PostMediaUtils.maxImages})'
                      : 'Add more photos',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_imageFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowDownload,
                  onChanged: (val) => setState(() => _allowDownload = val),
                  title: const Text('Allow others to download these photos'),
                  subtitle: const Text(
                    "If off, only you can save these photos to a gallery.",
                  ),
                ),
              ],
              if (_privacy == 'closedFriends') ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Manage Closed Friends'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openManageClosedFriends,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(
              base64Decode(photoUrl.split(',').last),
            ),
          );
        } catch (_) {}
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius),
    );
  }
}

class _RemovePhotoButton extends StatelessWidget {
  const _RemovePhotoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Manage Closed Friends Screen ───────────────────────

class ManageClosedFriendsScreen extends StatefulWidget {
  const ManageClosedFriendsScreen({super.key});

  @override
  State<ManageClosedFriendsScreen> createState() =>
      _ManageClosedFriendsScreenState();
}

class _ManageClosedFriendsScreenState extends State<ManageClosedFriendsScreen> {
  final _postRepo = PostRepository();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<String> _closedFriends = [];
  List<Map<String, dynamic>> _allFriends = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final closed = await _postRepo.getClosedFriends();
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final friendIds = List<String>.from(userDoc.data()?['friends'] ?? []);

    final friendData = <Map<String, dynamic>>[];
    for (final fid in friendIds) {
      final fdoc = await _firestore.collection('users').doc(fid).get();
      if (fdoc.exists) {
        friendData.add({'uid': fid, ...?fdoc.data()});
      }
    }

    if (mounted) {
      setState(() {
        _closedFriends = closed;
        _allFriends = friendData;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _postRepo.saveClosedFriends(_closedFriends);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Closed friends list saved.')),
      );
      Navigator.pop(context);
    }
  }

  void _toggle(String uid) {
    setState(() {
      if (_closedFriends.contains(uid)) {
        _closedFriends.remove(uid);
      } else {
        _closedFriends.add(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Closed Friends'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child:
                _saving
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Save'),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _allFriends.isEmpty
              ? const Center(child: Text('You have no friends yet.'))
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Select friends to add to your closed friends list.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _allFriends.length,
                      itemBuilder: (context, index) {
                        final friend = _allFriends[index];
                        final uid = friend['uid'] as String;
                        final name = friend['displayName'] as String? ?? 'User';
                        final isSelected = _closedFriends.contains(uid);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) => _toggle(uid),
                          title: Text(name),
                          secondary: CircleAvatar(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
