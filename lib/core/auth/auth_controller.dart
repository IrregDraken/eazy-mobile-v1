import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../network/api_client.dart';
import '../notifications/push_registration_service.dart';
import '../network/api_exception.dart';

class EmailVerificationChallenge {
  const EmailVerificationChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
  });
  final String challengeId;
  final int expiresInSeconds;
}

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.firebaseReady});
  final ApiClient api;
  bool firebaseReady;

  bool _restoring = true;
  bool _busy = false;
  User? _firebaseUser;
  Map<String, dynamic>? _profile;
  Future<void>? _googleInitialization;

  bool get isRestoring => _restoring;
  bool get isBusy => _busy;
  bool get isSignedIn => _firebaseUser != null && _profile != null;
  bool get needsOnboarding =>
      _profile != null &&
      _profile!['onboardingStatus'] != 'onboarding_complete';
  User? get firebaseUser => _firebaseUser;
  Map<String, dynamic>? get profile => _profile;

  void setFirebaseReady(bool value) {
    firebaseReady = value;
    notifyListeners();
  }

  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    try {
      if (!firebaseReady) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
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

  Future<EmailVerificationChallenge> registerEmail(
    String email,
    String password,
  ) async {
    return _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email.trim().toLowerCase(),
              password: password,
            );
        final user = credential.user;
        if (user == null) {
          throw const ApiException('Unable to create your Eazy account.');
        }
        await _syncFirebaseUser(user, forceRefresh: true);
        return await requestEmailVerificationCode(email);
      } on FirebaseAuthException catch (e) {
        throw ApiException(_firebaseMessage(e));
      }
    });
  }

  Future<EmailVerificationChallenge> requestEmailVerificationCode(
    String email, {
    bool auth = false,
  }) async {
    final result = await api.post(
      'auth/email-verification/request-code',
      auth: auth,
      body: {'email': email.trim().toLowerCase()},
    );
    return EmailVerificationChallenge(
      challengeId: result['challengeId']?.toString() ?? '',
      expiresInSeconds:
          int.tryParse(result['expiresInSeconds']?.toString() ?? '') ?? 600,
    );
  }

  Future<EmailVerificationChallenge> beginEmailRegistration(String email) {
    return requestEmailVerificationCode(email);
  }

  Future<void> verifyEmailRegistration(
    EmailVerificationChallenge challenge,
    String code,
  ) async {
    await api.post(
      'auth/email-verification/verify-code',
      body: {'challengeId': challenge.challengeId, 'code': code.trim()},
    );
  }

  Future<void> registerEmailAfterVerification(
    String email,
    String password,
    EmailVerificationChallenge challenge,
    String code,
  ) async {
    await _run(() async {
      _requireFirebase();
      try {
        final normalizedEmail = email.trim().toLowerCase();
        UserCredential credential;
        try {
          credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
        } on FirebaseAuthException catch (error) {
          // Firebase creation can succeed even when the follow-up API call
          // fails. Sign in to that same account and safely retry verification.
          if (error.code != 'email-already-in-use') rethrow;
          credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
        }
        final user = credential.user;
        if (user == null) {
          throw const ApiException('Unable to create your Eazy account.');
        }
        await user.reload();
        final currentUser = FirebaseAuth.instance.currentUser ?? user;
        final token = await currentUser.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw const ApiException('Firebase did not return a session token.');
        }
        // The verification endpoint is mounted before normal API auth
        // provisioning, so it can safely bind this unverified identity.
        await api.saveToken(token);
      } on FirebaseAuthException catch (e) {
        throw ApiException(_firebaseMessage(e));
      }
    });

    // Bind the already-verified challenge to the newly-created Firebase user.
    // The authenticated backend request marks that exact identity as verified.
    await verifyEmailCode(challenge, code);
  }

  Future<void> verifyEmailCode(
    EmailVerificationChallenge challenge,
    String code,
  ) async {
    await api.post(
      'auth/email-verification/verify-code',
      auth: true,
      body: {'challengeId': challenge.challengeId, 'code': code.trim()},
    );
    await FirebaseAuth.instance.currentUser?.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null) {
      throw const ApiException('Your registration session expired.');
    }
    await _syncFirebaseUser(fresh, forceRefresh: true);
  }

  Future<String> requestPhoneCode(String phone) async {
    _requireFirebase();
    final completer = Completer<String>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.trim(),
      verificationCompleted: (credential) async {
        try {
          final result = await FirebaseAuth.instance.signInWithCredential(
            credential,
          );
          if (result.user != null) {
            await _syncFirebaseUser(result.user!, forceRefresh: true);
          }
        } catch (_) {
          // The code-sent path remains available when automatic verification fails.
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(ApiException(_firebaseMessage(error)));
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
    );
    return completer.future;
  }

  Future<void> verifyPhoneCode(String verificationId, String code) async {
    _requireFirebase();
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code.trim(),
      );
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = result.user;
      if (user == null) {
        throw const ApiException(
          'Phone verification did not create your Eazy session.',
        );
      }
      await _syncFirebaseUser(user, forceRefresh: true);
    } on FirebaseAuthException catch (e) {
      throw ApiException(_firebaseMessage(e));
    }
  }

  bool get hasPasswordProvider =>
      _firebaseUser?.providerData.any((provider) => provider.providerId == 'password') ??
      false;

  Future<void> requestEmailChange(
    String newEmail, {
    String? currentPassword,
  }) async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Sign in again to manage your account.');
    final email = newEmail.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw const ApiException('Enter a valid email address.');
    }
    if (email == user.email?.trim().toLowerCase()) {
      throw const ApiException('That is already your current email address.');
    }
    try {
      if (hasPasswordProvider) {
        if (currentPassword == null || currentPassword.isEmpty || user.email == null) {
          throw const ApiException('Enter your current password to confirm this change.');
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email!,
            password: currentPassword,
          ),
        );
      }
      await user.verifyBeforeUpdateEmail(email);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<void> sendCurrentEmailVerification() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Sign in again to manage your account.');
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<void> refreshAccountIdentity() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Your sign-in session has expired.');
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed == null) throw const ApiException('Your sign-in session has expired.');
      await _syncFirebaseUser(refreshed, forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<String> requestPhoneLinkCode(String phone) async {
    _requireFirebase();
    final normalizedPhone = phone.trim();
    final digits = normalizedPhone.startsWith('+') ? normalizedPhone.substring(1) : '';
    if (digits.length < 8 ||
        digits.length > 15 ||
        digits.startsWith('0') ||
        digits.codeUnits.any((digit) => digit < 48 || digit > 57)) {
      throw const ApiException('Enter a valid phone number with country code, e.g. +2348012345678.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw const ApiException('Sign in again to manage your account.');
    }
    final completer = Completer<String>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          await _applyPhoneLinkCredential(credential);
          if (!completer.isCompleted) completer.complete('');
        } catch (error) {
          if (!completer.isCompleted) completer.completeError(error);
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(ApiException(_firebaseMessage(error)));
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
    );
    return completer.future;
  }

  Future<void> verifyPhoneLinkCode(String verificationId, String code) async {
    _requireFirebase();
    if (verificationId.isEmpty || code.trim().isEmpty) {
      throw const ApiException('Enter the SMS verification code.');
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code.trim(),
      );
      await _applyPhoneLinkCredential(credential);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<void> _applyPhoneLinkCredential(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Sign in again to manage your account.');
    try {
      if (user.phoneNumber == null || user.phoneNumber!.isEmpty) {
        final linked = await user.linkWithCredential(credential);
        final updated = linked.user;
        if (updated == null) throw const ApiException('Phone number could not be linked.');
        await _syncFirebaseUser(updated, forceRefresh: true);
      } else {
        await user.updatePhoneNumber(credential);
        await user.reload();
        final updated = FirebaseAuth.instance.currentUser;
        if (updated == null) throw const ApiException('Phone number could not be updated.');
        await _syncFirebaseUser(updated, forceRefresh: true);
      }
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null || !hasPasswordProvider) {
      throw const ApiException('Password sign-in is not linked to this account.');
    }
    if (newPassword.length < 8) {
      throw const ApiException('Use a password with at least 8 characters.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );
      await user.updatePassword(newPassword);
      await _syncFirebaseUser(user, forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_firebaseMessage(error));
    }
  }

  Future<void> signInEmail(String email, String password) async {
    await _run(() async {
      _requireFirebase();
      try {
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: email.trim().toLowerCase(),
              password: password,
            );
        final signedInUser = credential.user;
        if (signedInUser == null) {
          throw const ApiException('We could not sign you in.');
        }

        // Firebase may return a cached emailVerified value after a previous
        // registration/verification session. Reload the signed-in identity
        // before deciding whether this account is allowed to continue.
        await signedInUser.reload();
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw const ApiException(
            'Your sign-in session could not be restored.',
          );
        }
        if (!user.emailVerified) {
          throw const ApiException(
            'Verify your email address before signing in.',
            statusCode: 403,
            kind: ApiErrorKind.forbidden,
          );
        }
        await _syncFirebaseUser(user, forceRefresh: true);
      } on FirebaseAuthException catch (e) {
        throw ApiException(_firebaseMessage(e));
      }
    });
  }

  Future<void> sendPasswordReset(String email) async {
    _requireFirebase();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
    } on FirebaseAuthException catch (e) {
      throw ApiException(_firebaseMessage(e));
    }
  }

  Future<void> signInGoogle() async {
    await _run(() async {
      _requireFirebase();
      final google = GoogleSignIn.instance;
      final initialization = _googleInitialization ??= google.initialize(
        serverClientId: const String.fromEnvironment(
          'GOOGLE_SERVER_CLIENT_ID',
          defaultValue:
              '370546190167-dqltoqcnuvkkrh163qk80sdm8ejfm3ta.apps.googleusercontent.com',
        ),
      );
      try {
        await initialization;
      } catch (_) {
        _googleInitialization = null;
        rethrow;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          'Google did not return a valid identity token.',
          kind: ApiErrorKind.provider,
        );
      }
      final result = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      if (result.user == null) {
        throw const ApiException(
          'Google sign-in could not create your Eazy session.',
        );
      }
      await _syncFirebaseUser(result.user!, forceRefresh: true);
    });
  }

  Future<void> signInApple() async {
    await _run(() async {
      _requireFirebase();
      final rawNonce = _nonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
        webAuthenticationOptions:
            Platform.isAndroid
                ? WebAuthenticationOptions(
                  clientId: const String.fromEnvironment(
                    'APPLE_SERVICE_ID',
                    defaultValue: '',
                  ),
                  redirectUri: Uri.parse(
                    const String.fromEnvironment(
                      'APPLE_REDIRECT_URI',
                      defaultValue: '',
                    ),
                  ),
                )
                : null,
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          'Apple did not return a valid identity token.',
          kind: ApiErrorKind.provider,
        );
      }
      final result = await FirebaseAuth.instance.signInWithCredential(
        OAuthProvider(
          'apple.com',
        ).credential(idToken: idToken, rawNonce: rawNonce),
      );
      if (result.user == null) {
        throw const ApiException(
          'Apple sign-in could not create your Eazy session.',
        );
      }
      await _syncFirebaseUser(result.user!, forceRefresh: true);
    });
  }

  Future<void> completeOnboarding(Map<String, dynamic> data) async {
    await _run(() async {
      final result = await api.patch('profiles/me', auth: true, body: data);
      _profile = _normalizeProfile(result['profile'] as Map? ?? {});
      final completed = await api.post(
        'profiles/me/onboarding/complete',
        auth: true,
      );
      _profile = _normalizeProfile(
        completed['profile'] as Map? ?? _profile ?? {},
      );
    });
  }

  Future<void> refreshProfile() async {
    final result = await api.get('profiles/me', auth: true);
    _profile = _normalizeProfile(result['profile'] as Map? ?? {});
    notifyListeners();
  }

  Future<void> signOut() async {
    await PushRegistrationService.instance.unregister(api);
    if (firebaseReady) await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await api.clearToken();
    _firebaseUser = null;
    _profile = null;
    notifyListeners();
  }

  Future<void> _syncFirebaseUser(User user, {bool forceRefresh = false}) async {
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw const ApiException('Firebase did not return a session token.');
    }
    await api.saveToken(token);
    try {
      final result = await api.get('auth/me', auth: true);
      _profile = _normalizeProfile(result['profile'] as Map? ?? {});
      _firebaseUser = user;
      unawaited(PushRegistrationService.instance.start(api));
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
    'onboardingStatus':
        profile['onboarding_status'] ?? profile['onboardingStatus'],
  };

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const ApiException(
        'Please wait for the current request to finish.',
      );
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await action();
      notifyListeners();
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _requireFirebase() {
    if (!firebaseReady) {
      throw const ApiException(
        'Firebase native configuration is missing from this build.',
        kind: ApiErrorKind.provider,
      );
    }
  }

  String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is not correct.',
    'invalid-email' => 'Enter a valid email address.',
    'email-already-in-use' => 'An account already exists for this email.',
    'weak-password' => 'Choose a stronger password.',
    'user-disabled' => 'This account has been disabled. Contact support.',
    'network-request-failed' =>
      'No connection. Check your internet and try again.',
    'too-many-requests' =>
      'Too many attempts. Please wait a moment and try again.',
    'credential-already-in-use' || 'phone-number-already-exists' =>
      'This phone number is already linked to another account.',
    'invalid-phone-number' =>
      'Enter a valid phone number in international format, including the country code.',
    'code-expired' || 'session-expired' =>
      'That verification code has expired. Request a new one.',
    'requires-recent-login' =>
      'For your security, sign in again before changing this account detail.',
    'invalid-verification-code' => 'That verification code is not correct.',
    'invalid-verification-id' =>
      'That verification session expired. Request a new code.',
    'quota-exceeded' =>
      'Verification is temporarily unavailable. Try again later.',
    _ => 'We could not complete that sign-in action. Please try again.',
  };
}
