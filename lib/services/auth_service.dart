import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authChanges() => _auth.authStateChanges();

  Stream<AppUser?> profile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = AppUser(
      uid: cred.user!.uid,
      name: name.trim(),
      phone: phone.trim(),
      role: role,
    );
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> setFollowedBarangays(String uid, List<String> barangays) =>
      _db.collection('users').doc(uid).update({'followedBarangays': barangays});
}

/// Turns Firebase error codes into short messages a non-technical user understands.
String friendlyAuthError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'email-already-in-use':
        return 'This email already has an account. Please log in.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
    }
    return e.message ?? 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}
