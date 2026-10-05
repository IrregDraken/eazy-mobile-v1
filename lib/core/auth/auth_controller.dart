import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.firebaseReady});
  final ApiClient api;
  final bool firebaseReady;
  bool _restoring = true;
  bool _busy = false;
  User? _firebaseUser;
  Map<String, dynamic>? _profile;

  bool get isRestoring => _restoring;
  bool get isBusy => _busy;
  bool get isSignedIn => _firebaseUser != null && _profile != null;
  User? get firebaseUser => _firebaseUser;
  Map<String, dynamic>? get profile => _profile;

  Future<void> restore() async {
    _restoring = true; notifyListeners();
    if (firebaseReady) {
      _firebaseUser = FirebaseAuth.instance.currentUser;
      if (_firebaseUser != null) {
        try { await _syncFirebaseUser(_firebaseUser!); }
        catch (_) { _firebaseUser = null; _profile = null; await api.clearToken(); }
      }
    }
    _restoring = false; notifyListeners();
  }

  Future<void> signInEmail(String email, String password) async {
    await _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim().toLowerCase(), password: password);
        final user = credential.user;
        if (user == null) throw const ApiException('We could not sign you in.');
        if (!user.emailVerified) throw const ApiException('Verify your email address before signing in.', statusCode: 403, kind: ApiErrorKind.forbidden);
        await _syncFirebaseUser(user);
      } on FirebaseAuthException catch (e) { throw ApiException(_firebaseMessage(e)); }
    });
  }

  Future<void> registerEmail(String email, String password) async {
    await _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim().toLowerCase(), password: password);
        final user = credential.user;
        if (user == null) throw const ApiException('Unable to create your Eazy account.');
        await user.sendEmailVerification();
      } on FirebaseAuthException catch (e) { throw ApiException(_firebaseMessage(e)); }
    });
  }

  Future<void> sendPasswordReset(String email) async {
    _requireFirebase();
    try { await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim().toLowerCase()); }
    on FirebaseAuthException catch (e) { throw ApiException(_firebaseMessage(e)); }
  }

  Future<void> resendVerification() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Your registration session expired.');
    await user.sendEmailVerification();
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

  Future<void> signInGoogle() async {
    await _run(() async {
      _requireFirebase();
      final google = GoogleSignIn.instance;
      await google.initialize(serverClientId: const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: ''));
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) throw const ApiException('Google did not return a valid identity token.', kind: ApiErrorKind.provider);
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      if (result.user == null) throw const ApiException('Google sign-in could not create your Eazy session.');
      await _syncFirebaseUser(result.user!);
    });
  }

  Future<void> signInApple() async {
    await _run(() async {
      _requireFirebase();
      final rawNonce = _nonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
        webAuthenticationOptions: Platform.isAndroid
          ? WebAuthenticationOptions(
              clientId: const String.fromEnvironment('APPLE_SERVICE_ID', defaultValue: ''),
              redirectUri: Uri.parse(const String.fromEnvironment('APPLE_REDIRECT_URI', defaultValue: 'https://eazy-24e6a.firebaseapp.com/__/auth/handler')),
            )
          : null,
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) throw const ApiException('Apple did not return a valid identity token.', kind: ApiErrorKind.provider);
      final oauth = OAuthProvider('apple.com').credential(idToken: idToken, rawNonce: rawNonce);
      final result = await FirebaseAuth.instance.signInWithCredential(oauth);
      if (result.user == null) throw const ApiException('Apple sign-in could not create your Eazy session.');
      await _syncFirebaseUser(result.user!);
    });
  }

  Future<void> completeOnboarding(Map<String, dynamic> data) async {
    await _run(() async {
      final result = await api.patch('profiles/me', auth: true, body: data);
      _profile = Map<String, dynamic>.from(result['profile'] as Map? ?? _profile ?? {});
      await api.post('profiles/me/onboarding/complete', auth: true);
      notifyListeners();
    });
  }

  Future<void> _syncFirebaseUser(User user) async {
    final token = await user.getIdToken(true);
    if (token == null) throw const ApiException('Firebase did not return a session token.');
    final result = await api.post('auth/firebase', body: {'idToken': token});
    final tokens = result['tokens'] as Map<String, dynamic>?;
    final accessToken = tokens?['accessToken'] as String?;
    if (accessToken != null) await api.saveToken(accessToken);
    final profile = result['profile'] ?? result['user'];
    _profile = profile is Map ? Map<String, dynamic>.from(profile) : <String, dynamic>{};
    _firebaseUser = user;
  }

  Future<void> signOut() async {
    if (firebaseReady) await FirebaseAuth.instance.signOut();
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await api.clearToken();
    _firebaseUser = null; _profile = null; notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true; notifyListeners();
    try { await action(); notifyListeners(); } finally { _busy = false; notifyListeners(); }
  }

  void _requireFirebase() {
    if (!firebaseReady) throw const ApiException('Firebase native configuration is missing from this build.', kind: ApiErrorKind.provider);
  }

  String _nonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
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
