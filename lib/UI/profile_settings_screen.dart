import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/services/app_theme_service.dart';
import 'package:first_app/services/chat_repository.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _repo = ChatRepository();
  String? _photoUrl;
  final bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Always reload from Auth to get latest state
    await user.reload();
    final freshUser = FirebaseAuth.instance.currentUser;

    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(freshUser!.uid)
            .get();
    final firestoreUrl = doc.data()?['photoUrl'] as String?;
    final url =
        (firestoreUrl != null && firestoreUrl.isNotEmpty)
            ? firestoreUrl
            : freshUser.photoURL;
    if (mounted) setState(() => _photoUrl = url);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  ImageProvider? _buildAvatarImage() {
    if (_photoUrl == null || _photoUrl!.isEmpty) return null;
    if (_photoUrl!.startsWith('data:image')) {
      try {
        final base64Str = _photoUrl!.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(_photoUrl!);
  }

  Future<void> _showEditProfileSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => _EditProfileSheet(
            photoUrl: _photoUrl,
            onSaved: () async {
              // Reload profile from Firestore after any change
              await _loadProfile();
            },
          ),
    );
    // Reload after sheet closes in case onSaved wasn't triggered
    if (mounted) await _loadProfile();
  }

  void _showAccentColorSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accent Color',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Changes the color of buttons, highlights, and icons across the app.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: AppThemeService.instance,
                builder: (_, _) {
                  final current = AppThemeService.instance.seedColor;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children:
                        AppThemeService.presets.map((p) {
                          final isSelected =
                              current.toARGB32() == p.color.toARGB32();
                          return Tooltip(
                            message: p.label,
                            child: GestureDetector(
                              onTap: () {
                                AppThemeService.instance.setSeedColor(p.color);
                                Navigator.pop(ctx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: p.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow:
                                      isSelected
                                          ? [
                                            BoxShadow(
                                              color: p.color.withValues(
                                                alpha: 0.6,
                                              ),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                          : null,
                                ),
                                child:
                                    isSelected
                                        ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 24,
                                        )
                                        : null,
                              ),
                            ),
                          );
                        }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupedContainer({required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final borderColor =
        isDark ? const Color(0xFF3F4752) : const Color(0xFFBFC7D4);
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark ? const Color(0xFF3F4752) : const Color(0xFFBFC7D4);
    return Column(
      children: [
        ListTile(
          leading: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          trailing:
              trailing ??
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          onTap: onTap,
        ),
        if (showDivider)
          Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final isDark = theme.brightness == Brightness.dark;

    final profileCardBg =
        isDark ? const Color(0xFF1C1B1B) : const Color(0xFFF0F4FC);
    final borderColor =
        isDark ? const Color(0xFF3F4752) : const Color(0xFFBFC7D4);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: AppLoadingOverlay(
        isLoading: _busy,
        message: 'Saving changes...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: profileCardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: cs.surfaceContainerHighest,
                        backgroundImage: _buildAvatarImage(),
                        child:
                            _photoUrl == null || _photoUrl!.isEmpty
                                ? Icon(
                                  Icons.person,
                                  size: 30,
                                  color: cs.onSurfaceVariant,
                                )
                                : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'User',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Account Settings',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              _buildGroupedContainer(
                children: [
                  _buildTile(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Edit Profile',
                    onTap: _showEditProfileSheet,
                  ),
                  _buildTile(
                    icon: Icons.notifications_none_outlined,
                    title: 'Notifications',
                    onTap: () => _showSnack('Notifications clicked'),
                  ),
                  _buildTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy',
                    onTap: () => _showSnack('Privacy clicked'),
                  ),
                  _buildTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Security',
                    showDivider: false,
                    onTap: () => _showSnack('Security clicked'),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Preferences & Help',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              _buildGroupedContainer(
                children: [
                  _buildTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark Mode',
                    trailing: ListenableBuilder(
                      listenable: AppThemeService.instance,
                      builder: (context, _) {
                        final currentMode = AppThemeService.instance.themeMode;
                        final isCurrentlyDark =
                            currentMode == ThemeMode.dark ||
                            (currentMode == ThemeMode.system &&
                                MediaQuery.platformBrightnessOf(context) ==
                                    Brightness.dark);
                        return Switch(
                          value: isCurrentlyDark,
                          activeThumbColor: cs.primaryContainer,
                          onChanged: (val) {
                            AppThemeService.instance.setThemeMode(
                              val ? ThemeMode.dark : ThemeMode.light,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  _buildTile(
                    icon: Icons.palette_outlined,
                    title: 'Accent Color',
                    onTap: _showAccentColorSheet,
                  ),
                  _buildTile(
                    icon: Icons.help_outline,
                    title: 'Help',
                    showDivider: false,
                    onTap: () => _showSnack('Help clicked'),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _logout,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'VibeStream Version 4.22.0 (Stable)',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Edit Profile Sheet ───────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.photoUrl, required this.onSaved});

  final String? photoUrl;

  /// Called after any successful save so the parent can reload.
  final VoidCallback onSaved;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _repo = ChatRepository();
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Uint8List? _newPhotoBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nicknameController.text =
        FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) setState(() => _newPhotoBytes = bytes);
    } catch (e) {
      if (mounted) _showSnack('Could not pick image: $e');
    }
  }

  /// FIX: Combined save — photo + nickname in one tap
  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      // ── 1. Save photo if a new one was picked ──────────────────────
      if (_newPhotoBytes != null) {
        // FIX: Check size — base64 of >100KB will be too large for Firestore
        // document (1MB limit). Warn user if image is too large.
        if (_newPhotoBytes!.lengthInBytes > 700 * 1024) {
          _showSnack(
            'Image too large. Please pick a smaller image (under 700KB).',
          );
          setState(() => _busy = false);
          return;
        }
        await _repo.updateProfilePhoto(_newPhotoBytes!);
        setState(() => _newPhotoBytes = null);
      }

      // ── 2. Save nickname if changed ────────────────────────────────
      final newNick = _nicknameController.text.trim();
      final currentNick =
          FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      if (newNick != currentNick) {
        await _repo.changeNickname(newNick);
      }

      // ── 3. Notify parent to reload, then close ─────────────────────
      widget.onSaved();
      if (mounted) {
        _showSnack('Profile updated!');
        Navigator.pop(context);
      }
    } on NicknameTakenException {
      if (mounted) {
        _showSnack('"${_nicknameController.text.trim()}" is already taken.');
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto() async {
    setState(() => _busy = true);
    try {
      await _repo.deleteProfilePhoto();
      widget.onSaved();
      if (mounted) {
        setState(() => _newPhotoBytes = null);
        _showSnack('Profile photo removed');
      }
    } catch (e) {
      if (mounted) _showSnack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ImageProvider? _buildAvatarImage() {
    // Prefer freshly picked bytes
    if (_newPhotoBytes != null) return MemoryImage(_newPhotoBytes!);
    if (widget.photoUrl == null || widget.photoUrl!.isEmpty) return null;
    if (widget.photoUrl!.startsWith('data:image')) {
      try {
        final base64Str = widget.photoUrl!.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(widget.photoUrl!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhoto =
        _newPhotoBytes != null || (widget.photoUrl?.isNotEmpty == true);

    return AppLoadingOverlay(
      isLoading: _busy,
      message: 'Updating profile...',
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Text(
                'Edit Profile',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // ── Avatar Section ─────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: cs.surfaceContainerHighest,
                        backgroundImage: _buildAvatarImage(),
                        child:
                            !hasPhoto
                                ? Icon(
                                  Icons.person,
                                  size: 40,
                                  color: cs.onSurfaceVariant,
                                )
                                : null,
                      ),
                      // Small camera badge
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: cs.primary,
                          child: Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    () => _pickPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library, size: 18),
                                label: const Text('Gallery'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickPhoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: const Text('Camera'),
                              ),
                            ),
                          ],
                        ),
                        if (_newPhotoBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '✓ New photo selected — tap Save Changes',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green,
                              ),
                            ),
                          ),
                        if (hasPhoto && _newPhotoBytes == null)
                          TextButton(
                            onPressed: _busy ? null : _deletePhoto,
                            child: Text(
                              'Remove Photo',
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Nickname Section ───────────────────────────────────
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    hintText: 'your_nickname',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Enter a nickname';
                    if (!ChatRepository.isValidNicknameFormat(s)) {
                      return 'Use 3–20 letters, numbers, or _';
                    }
                    return null;
                  },
                ),
              ),

              const SizedBox(height: 24),

              // ── Single Save Button for everything ─────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _saveAll,
                  child:
                      _busy
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Save Changes'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
