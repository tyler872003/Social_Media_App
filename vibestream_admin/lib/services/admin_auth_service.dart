import 'package:firebase_auth/firebase_auth.dart';

/// Handles sign-in AND verifies the `isAdmin` custom claim.
/// The claim itself must be set server-side (Cloud Function / Admin SDK) —
/// never trust a client-writable Firestore field for this.
class AdminAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Signs in, then checks the custom claim. Signs the user back out and
  /// throws if they're not an admin, so no non-admin session lingers.
  Future<void> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final tokenResult = await credential.user!.getIdTokenResult(
      true,
    ); // force refresh
    final isAdmin = tokenResult.claims?['isAdmin'] == true;

    if (!isAdmin) {
      await _auth.signOut();
      throw Exception('This account does not have admin access.');
    }
  }

  Future<void> signOut() => _auth.signOut();
}

/*
 * --- One-time setup: granting the isAdmin claim ---
 * Run this ONCE per admin user, from a trusted environment (Cloud Function
 * or a local script using the Admin SDK service account) — never from the
 * Flutter client:
 *
 *   const admin = require('firebase-admin');
 *   admin.initializeApp();
 *   admin.auth().setCustomUserClaims('<uid>', { isAdmin: true })
 *     .then(() => console.log('Claim set.'));
 *
 * The user must sign out/in (or force-refresh their ID token, as done
 * above) for the new claim to appear in tokenResult.claims.
 */
