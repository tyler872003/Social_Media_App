import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Result of a lockout check.
class LoginAttemptResult {
  final bool allowed;
  final int secondsLeft;
  LoginAttemptResult(this.allowed, this.secondsLeft);
}

/// Tracks failed login attempts per email address directly in Firestore,
/// entirely client-side (no Cloud Functions required).
///
/// Security model: Firestore security rules constrain what values a
/// client may write to `loginAttempts/{emailHash}`, so a client can't
/// simply reset its own lockout by writing `count: 0` at will. This is
/// weaker than a server-enforced lockout (a modified client could still
/// craft a technically-valid update), but it stops casual bypass and
/// demonstrates the rate-limiting pattern without needing Firebase's
/// Blaze billing plan.
class LoginAttemptService {
  static const _maxAttempts = 5;
  static const _lockoutMinutes = 15;
  static const _windowMinutes = 10;

  static String _hashEmail(String email) {
    final bytes = utf8.encode(email.trim().toLowerCase());
    return sha256.convert(bytes).toString();
  }

  static DocumentReference<Map<String, dynamic>> _docFor(String email) {
    return FirebaseFirestore.instance
        .collection('loginAttempts')
        .doc(_hashEmail(email));
  }

  /// Call before attempting sign-in. Returns whether login is currently
  /// allowed, and if not, how many seconds remain on the lockout.
  static Future<LoginAttemptResult> checkAllowed(String email) async {
    try {
      final snap = await _docFor(email).get();
      if (!snap.exists) return LoginAttemptResult(true, 0);

      final data = snap.data()!;
      final lockedUntil = data['lockedUntil'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lockedUntil != null && lockedUntil > now) {
        final secondsLeft = ((lockedUntil - now) / 1000).ceil();
        return LoginAttemptResult(false, secondsLeft);
      }
      return LoginAttemptResult(true, 0);
    } catch (_) {
      // Fail open: if the lockout check itself fails (offline, rules
      // issue, etc.), don't block login — Firebase Auth's own built-in
      // throttling is still a backstop.
      return LoginAttemptResult(true, 0);
    }
  }

  /// Call after Firebase Auth rejects a login attempt
  /// (wrong-password / user-not-found / invalid-credential).
  static Future<void> recordFailedAttempt(String email) async {
    final docRef = _docFor(email);
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        if (!snap.exists) {
          tx.set(docRef, {'count': 1, 'lastAttempt': now, 'lockedUntil': null});
          return;
        }

        final data = snap.data()!;
        final lastAttempt = data['lastAttempt'] as int;
        final withinWindow = now - lastAttempt < _windowMinutes * 60 * 1000;
        final newCount = withinWindow ? (data['count'] as int) + 1 : 1;

        int? lockedUntil;
        if (newCount >= _maxAttempts) {
          lockedUntil = now + _lockoutMinutes * 60 * 1000;
        }

        tx.update(docRef, {
          'count': newCount,
          'lastAttempt': now,
          'lockedUntil': lockedUntil,
        });
      });
    } catch (_) {
      // Non-fatal — don't let a failed write crash the login flow.
    }
  }

  /// Call after a successful login to reset the counter.
  static Future<void> clearAttempts(String email) async {
    try {
      final docRef = _docFor(email);
      final snap = await docRef.get();
      if (snap.exists) {
        await docRef.update({'count': 0, 'lockedUntil': null});
      }
    } catch (_) {
      // Non-fatal.
    }
  }
}
