// lib/services/suspension_guard.dart   (USER app, not the admin app)
//
// Uses cloud_firestore and firebase_auth, which the user app already has.
//
// The Firestore rules already block suspended users from all app data; this
// helper makes the app itself react by signing them out.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SuspensionGuard {
  SuspensionGuard._();

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Call right after a successful sign-in (any method).
  /// If the account is suspended it signs the user out and returns true, so
  /// the caller can show "Your account has been suspended." and stop.
  static Future<bool> blockIfSuspended() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (snap.data()?['status'] == 'suspended') {
        await FirebaseAuth.instance.signOut();
        return true;
      }
    } catch (_) {
      // If the check fails, don't lock everyone out; the Firestore rules
      // still protect the data.
    }
    return false;
  }

  /// Start after login (e.g. in the home screen's initState).
  /// Watches the user's own profile; when it flips to suspended, signs the
  /// user out and calls [onSuspended] once (use it to go to the login screen
  /// and show the suspended message).
  static void startWatching(void Function() onSuspended) {
    stopWatching();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) async {
      if (snap.data()?['status'] == 'suspended') {
        stopWatching();
        await FirebaseAuth.instance.signOut();
        onSuspended();
      }
    }, onError: (_) {});
  }

  /// Call from dispose() and when the user signs out normally.
  static void stopWatching() {
    _sub?.cancel();
    _sub = null;
  }
}
