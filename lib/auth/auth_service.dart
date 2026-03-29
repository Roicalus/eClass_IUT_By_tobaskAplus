import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.sendEmailVerification();
  }

  Future<void> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return _auth.signInWithPopup(provider);
    }

    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

    final account = await googleSignIn.signIn();
    if (account == null) {
      throw StateError('Sign-in aborted');
    }

    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // Ignore: Firebase signOut below is authoritative.
      }
    }
    await _auth.signOut();
  }
}
