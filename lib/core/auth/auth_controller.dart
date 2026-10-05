import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.firebaseReady});
  final ApiClient api;
  final bool firebaseReady;
  bool _restoring = true;
  User? _firebaseUser;
  Map<String, dynamic>? _profile;

  bool get isRestoring => _restoring;
  bool get isSignedIn => _firebaseUser != null && _profile != null;
  User? get firebaseUser => _firebaseUser;
  Map<String, dynamic>? get profile => _profile;

  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    if (firebaseReady) {
      _firebaseUser = FirebaseAuth.instance.currentUser;
      if (_firebaseUser != null) {
        try {
          await _syncFirebaseUser(_firebaseUser!);
        } catch (_) {
          _firebaseUser = null;
          _profile = null;
        }
      }
    }
    _restoring = false;
    notifyListeners();
  }

  Future<void> signInEmail(String email, String password) async {
    _requireFirebase();
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim().toLowerCase(), password: password);
      final user = credential.user;
      if (user == null) throw const ApiException('We could not sign you in.');
      if (!user.emailVerified) throw const ApiException('Verify your email address before signing in.', statusCode: 403, kind: ApiErrorKind.forbidden);
      await _syncFirebaseUser(user);
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw ApiException(_firebaseMessage(e));
    }
  }

  Future<void> registerEmail(String email, String password) async {
    _requireFirebase();
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim().toLowerCase(), password: password);
      final user = credential.user;
      if (user == null) throw const ApiException('Unable to create your Eazy account.');
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw ApiException(_firebaseMessage(e));
    }
  }

  Future<void> finishVerifiedEmailRegistration() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Your registration session expired.');
    await user.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null || !fresh.emailVerified) throw const ApiException('Verify your email address, then try again.', statusCode: 403, kind: ApiErrorKind.forbidden);
    await _syncFirebaseUser(fresh);
    notifyListeners();
  }

  Future<void> _syncFirebaseUser(User user) async {
    final token = await user.getIdToken(true);
    if (token == null) throw const ApiException('Firebase did not return a session token.');
    final result = await api.post('auth/firebase', body: {'idToken': token});
    final tokens = result['tokens'] as Map<String, dynamic>?;
    final accessToken = tokens?['accessToken'] as String?;
    if (accessToken != null) await api.saveToken(accessToken);
    _profile = (result['user'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    _firebaseUser = user;
  }

  Future<void> signOut() async {
    if (firebaseReady) await FirebaseAuth.instance.signOut();
    await api.clearToken();
    _firebaseUser = null;
    _profile = null;
    notifyListeners();
  }

  void _requireFirebase() {
    if (!firebaseReady) throw const ApiException('Secure sign-in is not configured on this build yet. Add the native Firebase configuration and try again.', kind: ApiErrorKind.provider);
  }

  String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-credential' || 'wrong-password' || 'user-not-found' => 'The email or password is not correct.',
    'invalid-email' => 'Enter a valid email address.',
    'email-already-in-use' => 'An account already exists for this email.',
    'weak-password' => 'Choose a stronger password.',
    'user-disabled' => 'This account has been disabled. Contact support.',
    'network-request-failed' => 'No connection. Check your internet and try again.',
    'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
    _ => 'We could not complete that sign-in action. Please try again.',
  };
}
