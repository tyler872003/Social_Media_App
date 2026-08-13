import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/services/auth_verification_prefs.dart';
import 'package:first_app/services/auth_verification_settings.dart';
import 'package:first_app/services/chat_repository.dart';
import 'package:first_app/services/login_attempt_service.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _confirmPasswordFieldKey = GlobalKey<FormFieldState<String>>();
  bool _busy = false;
  bool _isRegister = false;
  bool _passwordObscured = true;
  bool _confirmPasswordObscured = true;

  /// Picked image + bytes for preview and upload (registration only).
  XFile? _profileImage;
  Uint8List? _profileImageBytes;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _clearProfilePhoto() {
    setState(() {
      _profileImage = null;
      _profileImageBytes = null;
    });
  }

  String _contentTypeFor(XFile file) {
    final m = file.mimeType;
    if (m != null && m.isNotEmpty) return m;
    final p = file.path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _profileImage = picked;
      _profileImageBytes = bytes;
    });
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.camera);
                },
              ),
              if (_profileImageBytes != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _clearProfilePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isRegister) {
        EmailRegistrationSession.beginPasswordRegistration();
        try {
          final cred = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: email, password: password);
          final user = cred.user;
          if (user != null) {
            final trimmedNick = _nicknameController.text.trim();
            final nickKey = ChatRepository.nicknameDocKey(trimmedNick);
            final repo = ChatRepository();
            try {
              await repo.claimNickname(uid: user.uid, nickname: trimmedNick);
              await user.updateDisplayName(trimmedNick);
              await user.reload();
            } on NicknameTakenException {
              await user.delete();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'That nickname is already taken. Pick another.',
                  ),
                ),
              );
              return;
            } catch (e) {
              await repo.releaseNicknameIfOwnedBy(nickKey, user.uid);
              try {
                await user.delete();
              } catch (_) {}
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not save nickname: $e')),
              );
              return;
            }
            EmailRegistrationSession.mark(user.uid);
            await setMustVerifyEmailPending(user.uid);
            if (_profileImageBytes != null && _profileImage != null) {
              EmailRegistrationSession.setPendingProfilePhoto(
                _profileImageBytes!,
                contentType: _contentTypeFor(_profileImage!),
              );
            }
            try {
              await user.reload();
              final fresh = FirebaseAuth.instance.currentUser;
              if (fresh == null) return;
              await fresh.sendEmailVerification(
                firebaseEmailActionCodeSettings(),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Check your inbox to verify your email before using the app.',
                  ),
                ),
              );
            } on FirebaseAuthException catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Account created, but verification email failed: ${e.message ?? e.code}. '
                    'Use the mail icon on the next screen to resend.',
                  ),
                ),
              );
            }
            _clearProfilePhoto();
          }
        } finally {
          EmailRegistrationSession.endPasswordRegistration();
        }
      } else {
        // ── Login flow with brute-force lockout (client-side, Firestore) ──

        // 1. Check lockout status before attempting sign-in.
        final checkResult = await LoginAttemptService.checkAllowed(email);
        if (!checkResult.allowed) {
          final minutes = (checkResult.secondsLeft / 60).ceil();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Too many failed attempts. Try again in $minutes minute(s).',
              ),
            ),
          );
          return;
        }

        await clearMustVerifyEmailPending();
        EmailRegistrationSession.clearPendingProfilePhoto();

        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          // 2. Success — clear the failed-attempt counter.
          unawaited(LoginAttemptService.clearAttempts(email));
          // Firestore profile is synced from [HomeChatsScreen] after sign-in.
        } on FirebaseAuthException catch (e) {
          if (e.code == 'wrong-password' ||
              e.code == 'user-not-found' ||
              e.code == 'invalid-credential') {
            // 3. Record the failed attempt (fire-and-forget).
            unawaited(LoginAttemptService.recordFailedAttempt(email));
          }
          rethrow; // handled by the outer catch (FirebaseAuthException) below
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message =
          e.code == 'email-already-in-use' && _isRegister
              ? 'That email is still an account in Firebase Authentication '
                  '(deleting Firestore data does not remove it). Use Sign in or '
                  'Forgot password, or delete the user in Console → Authentication → Users.'
              : e.code == 'too-many-requests'
              ? 'Too many failed attempts. Firebase has temporarily blocked '
                  'sign-in for this account. Please wait a few minutes, or '
                  'reset your password, before trying again.'
              : (e.message ?? e.code);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openForgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder:
          (_) =>
              _PasswordResetDialog(initialEmail: _emailController.text.trim()),
    );
    if (!mounted || sent != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If an account exists for that email, a reset link was sent.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return AppLoadingOverlay(
      isLoading: _busy,
      message: _isRegister ? 'Creating account...' : 'Signing in...',
      child: Scaffold(
        body: Stack(
          children: [
            // Background blurs
            Positioned(
              top: -size.height * 0.1,
              left: -size.width * 0.1,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 120,
                      spreadRadius: 60,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -size.height * 0.1,
              right: -size.width * 0.1,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.secondary.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.secondary.withValues(alpha: 0.15),
                      blurRadius: 120,
                      spreadRadius: 60,
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 32),
                          // VibeStream Gradient Logo Text
                          ShaderMask(
                            shaderCallback:
                                (bounds) => LinearGradient(
                                  colors: [
                                    colorScheme.primary,
                                    colorScheme.secondary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                            child: Text(
                              'VibeStream',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isRegister
                                ? 'Join the vibe.'
                                : 'Welcome back to the vibe.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 40),

                          if (_isRegister) ...[
                            Text(
                              'Profile photo (optional)',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _busy ? null : _showPhotoOptions,
                                customBorder: const CircleBorder(),
                                child: Ink(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colorScheme.surfaceContainerHighest,
                                    image:
                                        _profileImageBytes != null
                                            ? DecorationImage(
                                              image: MemoryImage(
                                                _profileImageBytes!,
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                            : null,
                                  ),
                                  child:
                                      _profileImageBytes == null
                                          ? Icon(
                                            Icons.add_a_photo_outlined,
                                            size: 32,
                                            color: colorScheme.onSurfaceVariant,
                                          )
                                          : null,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : _showPhotoOptions,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: Text(
                                _profileImageBytes == null
                                    ? 'Add photo'
                                    : 'Change photo',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nicknameController,
                              textCapitalization: TextCapitalization.none,
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                hintText: 'Nickname',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                            const SizedBox(height: 16),
                          ],

                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              hintText: 'Email',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return 'Enter email';
                              if (!s.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _passwordObscured,
                            autofillHints: const [AutofillHints.password],
                            onChanged:
                                _isRegister
                                    ? (_) {
                                      final state =
                                          _confirmPasswordFieldKey.currentState;
                                      if (state != null &&
                                          _confirmPasswordController
                                              .text
                                              .isNotEmpty) {
                                        state.validate();
                                      }
                                    }
                                    : null,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                tooltip:
                                    _passwordObscured
                                        ? 'Show password'
                                        : 'Hide password',
                                onPressed:
                                    () => setState(
                                      () =>
                                          _passwordObscured =
                                              !_passwordObscured,
                                    ),
                                icon: Icon(
                                  _passwordObscured
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final s = v ?? '';
                              if (s.length < 6) return 'At least 6 characters';
                              return null;
                            },
                          ),

                          if (_isRegister) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              key: _confirmPasswordFieldKey,
                              controller: _confirmPasswordController,
                              obscureText: _confirmPasswordObscured,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                hintText: 'Confirm password',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: IconButton(
                                  tooltip:
                                      _confirmPasswordObscured
                                          ? 'Show password'
                                          : 'Hide password',
                                  onPressed:
                                      () => setState(
                                        () =>
                                            _confirmPasswordObscured =
                                                !_confirmPasswordObscured,
                                      ),
                                  icon: Icon(
                                    _confirmPasswordObscured
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                final s = v ?? '';
                                if (s.isEmpty) return 'Confirm your password';
                                if (s != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],

                          if (!_isRegister) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _busy ? null : _openForgotPassword,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: colorScheme.primary,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else
                            const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                              ),
                              child:
                                  _busy
                                      ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.onPrimary,
                                        ),
                                      )
                                      : Text(
                                        _isRegister ? 'Register' : 'Log In',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                            ),
                          ),

                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isRegister
                                    ? "Already have an account?"
                                    : "Don't have an account?",
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap:
                                    _busy
                                        ? null
                                        : () {
                                          setState(() {
                                            _isRegister = !_isRegister;
                                            if (!_isRegister) {
                                              _profileImage = null;
                                              _profileImageBytes = null;
                                              _confirmPasswordController
                                                  .clear();
                                              _nicknameController.clear();
                                            }
                                          });
                                        },
                                child: Text(
                                  _isRegister ? 'Log in' : 'Sign up',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final addr = _emailController.text.trim();
    var closed = false;
    try {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: addr,
          actionCodeSettings: firebaseEmailActionCodeSettings(),
        );
        if (!mounted) return;
        closed = true;
        Navigator.of(context).pop(true);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          if (!mounted) return;
          closed = true;
          Navigator.of(context).pop(true);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    } finally {
      if (!closed && mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Enter email';
            if (!s.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child:
              _busy
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Send link'),
        ),
      ],
    );
  }
}
