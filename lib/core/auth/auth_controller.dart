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
  bool get needsOnboarding =>
      _profile != null && _profile!['onboardingStatus'] != 'onboarding_complete';
  User? get firebaseUser => _firebaseUser;
  Map<String, dynamic>? get profile => _profile;

  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    try {
      if (!firebaseReady) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (user.emailVerified == false && user.providerData.any((p) => p.providerId == 'password')) {
        await FirebaseAuth.instance.signOut();
        return;
      }
      await _syncFirebaseUser(user, forceRefresh: true);
    } catch (_) {
      await api.clearToken();
      _firebaseUser = null;
      _profile = null;
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> signInEmail(String email, String password) async {
    await _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password);
        final user = credential.user;
        if (user == null) throw const ApiException('We could not sign you in.');
        if (!user.emailVerified) {
          throw const ApiException('Verify your email address before signing in.',
              statusCode: 403, kind: ApiErrorKind.forbidden);
        }
        await _syncFirebaseUser(user, forceRefresh: true);
      } on FirebaseAuthException catch (e) {
        throw ApiException(_firebaseMessage(e));
      }
    });
  }

  Future<void> registerEmail(String email, String password) async {
    await _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password);
        final user = credential.user;
        if (user == null) throw const ApiException('Unable to create your Eazy account.');
        await user.sendEmailVerification();
      } on FirebaseAuthException catch (e) {
        throw ApiException(_firebaseMessage(e));
      }
    });
  }

  Future<void> sendPasswordReset(String email) async {
    _requireFirebase();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw ApiException(_firebaseMessage(e));
    }
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
    if (fresh == null || !fresh.emailVerified) {
      throw const ApiException('Verify your email address, then try again.',
          statusCode: 403, kind: ApiErrorKind.forbidden);
    }
    await _syncFirebaseUser(fresh, forceRefresh: true);
  }

  Future<void> signInGoogle() async {
    await _run(() async {
      _requireFirebase();
      final google = GoogleSignIn.instance;
      await google.initialize(serverClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID', defaultValue: ''));
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException('Google did not return a valid identity token.', kind: ApiErrorKind.provider);
      }
      final result = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken));
      if (result.user == null) throw const ApiException('Google sign-in could not create your Eazy session.');
      await _syncFirebaseUser(result.user!, forceRefresh: true);
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
                redirectUri: Uri.parse(const String.fromEnvironment('APPLE_REDIRECT_URI',
                    defaultValue: '')))
            : null);
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException('Apple did not return a valid identity token.', kind: ApiErrorKind.provider);
      }
      final result = await FirebaseAuth.instance.signInWithCredential(
        OAuthProvider('apple.com').credential(idToken: idToken, rawNonce: rawNonce));
      if (result.user == null) throw const ApiException('Apple sign-in could not create your Eazy session.');
      await _syncFirebaseUser(result.user!, forceRefresh: true);
    });
  }

  Future<void> completeOnboarding(Map<String, dynamic> data) async {
    await _run(() async {
      final result = await api.patch('profiles/me', auth: true, body: data);
      _profile = _normalizeProfile(result['profile'] as Map? ?? {});
      final completed = await api.post('profiles/me/onboarding/complete', auth: true);
      _profile = _normalizeProfile(completed['profile'] as Map? ?? _profile ?? {});
    });
  }

  Future<void> refreshProfile() async {
    final result = await api.get('profiles/me', auth: true);
    _profile = _normalizeProfile(result['profile'] as Map? ?? {});
    notifyListeners();
  }

  Future<void> signOut() async {
    if (firebaseReady) await FirebaseAuth.instance.signOut();
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await api.clearToken();
    _firebaseUser = null;
    _profile = null;
    notifyListeners();
  }

  Future<void> _syncFirebaseUser(User user, {bool forceRefresh = false}) async {
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) throw const ApiException('Firebase did not return a session token.');
    await api.saveToken(token);
    try {
      // V2 authenticates the Firebase bearer token directly and provisions its
      // application session during an authenticated request. There is no
      // /auth/firebase exchange endpoint.
      final result = await api.get('auth/me', auth: true);
      _profile = _normalizeProfile(result['profile'] as Map? ?? {});
      _firebaseUser = user;
    } catch (_) {
      await api.clearToken();
      rethrow;
    }
  }

  Map<String, dynamic> _normalizeProfile(Map profile) => {
    'userId': profile['user_id'] ?? profile['userId'],
    'username': profile['username'],
    'displayName': profile['display_name'] ?? profile['displayName'],
    'firstName': profile['first_name'] ?? profile['firstName'],
    'middleName': profile['middle_name'] ?? profile['middleName'],
    'lastName': profile['last_name'] ?? profile['lastName'],
    'dateOfBirth': profile['date_of_birth'] ?? profile['dateOfBirth'],
    'bio': profile['bio'],
    'avatarUrl': profile['avatar_url'] ?? profile['avatarUrl'],
    'onboardingStatus': profile['onboarding_status'] ?? profile['onboardingStatus'],
  };

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true; notifyListeners();
    try { await action(); notifyListeners(); }
    finally { _busy = false; notifyListeners(); }
  }

  void _requireFirebase() {
    if (!firebaseReady) throw const ApiException(
      'Firebase native configuration is missing from this build.', kind: ApiErrorKind.provider);
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
