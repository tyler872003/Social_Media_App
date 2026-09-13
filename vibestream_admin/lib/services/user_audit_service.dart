import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Backend for the admin User Audit screen: profile lookups, strikes,
/// warnings, suspend/reactivate, and password-reset actions.
///
/// Schema this relies on:
///  - users/{uid}.strikes            (int, default 0)
///  - users/{uid}.status             ('active' | 'flagged' | 'suspended')
///  - users/{uid}/warnings           (subcollection: message + createdAt)
///
/// Auto-suspend rule: every warning increments `strikes` by 1. If the new
/// total reaches [strikeSuspensionThreshold] (10), the account is
/// suspended in the SAME atomic transaction as the strike increment — so
/// strikes and status can never disagree with each other, even if the app
/// is killed mid-write.
///
/// Email delivery: since the project is on the Spark (no-billing) plan,
/// the Trigger Email extension (which requires Blaze) is not available.
/// Warning emails are instead sent client-side via EmailJS's REST API
/// (https://www.emailjs.com/) directly from this admin app. EmailJS is
/// designed for exactly this — its public key is meant to be exposed in
/// client code, unlike a normal API secret.
class UserAuditService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int strikeSuspensionThreshold = 10;

  // ── EmailJS config ──────────────────────────────────────
  // Fill these in from your EmailJS dashboard (Account > General for the
  // public key, Email Services for the service ID, Email Templates for
  // the template ID). The template should expect variables matching the
  // keys used in `templateParams` below (e.g. {{to_email}}, {{subject}},
  // {{message}}) — adjust the keys here to match whatever variable names
  // you set up in your actual EmailJS template.
  static const String _emailJsServiceId = 'VibeStream';
  static const String _emailJsTemplateId = 'template_oyz237o';
  static const String _emailJsPublicKey = 'AcKXL4Rid-DHNCqww';
  static const String _emailJsPrivateKey = 'Rq-9J_PkUVjuNcfs-VPVj';
  static const String _emailJsEndpoint =
      'https://api.emailjs.com/api/v1.0/email/send';

  Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> warningsForUser(
    String uid, {
    int limit = 20,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('warnings')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Live count of this user's own posts, so "Posts" on the profile card
  /// reflects real data instead of a stored counter.
  Future<int> postCountForUser(String uid) async {
    final snap = await _db
        .collection('posts')
        .where('userId', isEqualTo: uid)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Live count of this user's friends, for the "Total Friends" stat.
  Future<int> friendCountForUser(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<void> setStatus(String uid, String status) {
    return _db.collection('users').doc(uid).update({
      'status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Suspends the account and emails [email] to let the user know.
  /// The Firestore status update and the email are independent steps —
  /// same tradeoff as sendWarning: if the email fails, the suspension
  /// still goes through, since that's the part with real consequences.
  Future<void> suspendUser(String uid, String email) async {
    await setStatus(uid, 'suspended');
    await _sendEmailJs(
      toEmail: email,
      subject: 'Your VibeStream account has been suspended',
      message:
          'Your account has been suspended due to repeated violations of '
          'our community guidelines. If you believe this is a mistake, '
          'please contact support.',
    );
  }

  /// Reactivates the account and emails [email] to let the user know.
  Future<void> reactivateUser(String uid, String email) async {
    await setStatus(uid, 'active');
    await _sendEmailJs(
      toEmail: email,
      subject: 'Your VibeStream account has been reactivated',
      message:
          'Your account has been reactivated and you can now sign back '
          'in to VibeStream.',
    );
  }

  /// Records a warning: increments the strike counter, logs the message
  /// (shows up in warningsForUser / Account History), and sends the
  /// warning email directly via EmailJS. If this warning pushes strikes
  /// to [strikeSuspensionThreshold], the account is suspended in the
  /// same transaction that logs the warning.
  ///
  /// Note: the EmailJS call happens AFTER the Firestore transaction
  /// commits, not inside it — EmailJS has no relation to Firestore's
  /// atomicity guarantees, so there's no way to roll back an email send.
  /// If the transaction succeeds but the email call fails (e.g. no
  /// network, bad EmailJS config), the strike/warning record still
  /// exists — the email is just a best-effort side effect. Consider
  /// showing an error to the admin if `_sendEmailJs` returns false, so
  /// they know to resend or contact the user another way.
  ///
  /// Note: if this warning triggers auto-suspension (strikes reach
  /// [strikeSuspensionThreshold]), only the warning email is sent here —
  /// not a separate suspension email — to avoid sending two emails for
  /// one action. Call suspendUser directly when suspending outside of
  /// the warning flow (e.g. a manual "Suspend" action) to get the
  /// suspension-specific email instead.
  Future<void> sendWarning({
    required String uid,
    required String email,
    required String message,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final warningRef = userRef.collection('warnings').doc();

    await _db.runTransaction((txn) async {
      final snap = await txn.get(userRef);
      final currentStrikes = (snap.data()?['strikes'] as num?)?.toInt() ?? 0;
      final newStrikes = currentStrikes + 1;
      final willSuspend = newStrikes >= strikeSuspensionThreshold;

      final userUpdate = <String, dynamic>{
        'strikes': newStrikes,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (willSuspend) {
        userUpdate['status'] = 'suspended';
        userUpdate['statusUpdatedAt'] = FieldValue.serverTimestamp();
      }
      txn.set(userRef, userUpdate, SetOptions(merge: true));

      txn.set(warningRef, {
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await _sendEmailJs(
      toEmail: email,
      subject: 'Warning regarding your VibeStream account',
      message: message,
    );
  }

  /// Sends an email via EmailJS's REST API. Returns true on success.
  /// Does not throw — logs and swallows errors so a flaky network
  /// doesn't crash the admin screen; the warning/strike is already
  /// safely recorded in Firestore regardless of email outcome.
  Future<bool> _sendEmailJs({
    required String toEmail,
    required String subject,
    required String message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_emailJsEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _emailJsServiceId,
          'template_id': _emailJsTemplateId,
          'user_id': _emailJsPublicKey,
          'accessToken': _emailJsPrivateKey,
          'template_params': {
            'to_email': toEmail,
            'subject': subject,
            'message': message,
          },
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        // ignore: avoid_print
        print('EmailJS send failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      // ignore: avoid_print
      print('EmailJS send error: $e');
      return false;
    }
  }

  /// Sends a password-reset email to [email]. This does not require
  /// signing in as that user — Firebase Auth allows triggering a reset
  /// email for any account by address.
  Future<void> sendPasswordReset(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  /// Maps a strike count to a coarse risk label for the "Account Risk"
  /// stat card, scaled against the 10-strike suspension threshold.
  static String riskLevelForStrikes(int strikes) {
    if (strikes >= 7) return 'High';
    if (strikes >= 3) return 'Medium';
    return 'Low';
  }
}
