import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late final TextEditingController emailController;
  late final TextEditingController emailPasswordController;
  late final TextEditingController phoneController;
  late final TextEditingController phoneCodeController;
  late final TextEditingController currentPasswordController;
  late final TextEditingController newPasswordController;
  late final TextEditingController confirmPasswordController;

  String? phoneVerificationId;
  bool emailBusy = false;
  bool phoneBusy = false;
  bool passwordBusy = false;
  bool refreshing = false;

  User? get user => widget.auth.firebaseUser;
  bool get hasPassword => widget.auth.hasPasswordProvider;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    emailPasswordController = TextEditingController();
    phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    phoneCodeController = TextEditingController();
    currentPasswordController = TextEditingController();
    newPasswordController = TextEditingController();
    confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    emailPasswordController.dispose();
    phoneController.dispose();
    phoneCodeController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? EazyColors.red : null,
      ),
    );
  }

  Future<void> refreshIdentity() async {
    setState(() => refreshing = true);
    try {
      await widget.auth.refreshAccountIdentity();
      if (!mounted) return;
      setState(() {
        phoneController.text = user?.phoneNumber ?? '';
        phoneVerificationId = null;
        phoneCodeController.clear();
      });
      showMessage('Account details refreshed.');
    } on ApiException catch (error) {
      showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> requestEmailChange() async {
    setState(() => emailBusy = true);
    try {
      await widget.auth.requestEmailChange(
        emailController.text,
        currentPassword: hasPassword ? emailPasswordController.text : null,
      );
      emailController.clear();
      emailPasswordController.clear();
      showMessage('Verification link sent. Your email changes after you verify the new address.');
    } on ApiException catch (error) {
      showMessage(error.message, error: true);
    } on FirebaseAuthException catch (error) {
      showMessage(error.message ?? 'We could not send the verification email.', error: true);
    } finally {
      if (mounted) setState(() => emailBusy = false);
    }
  }

  Future<void> sendPhoneCode() async {
    setState(() {
      phoneBusy = true;
      phoneVerificationId = null;
      phoneCodeController.clear();
    });
    try {
      final verificationId = await widget.auth.requestPhoneLinkCode(phoneController.text);
      if (!mounted) return;
      if (verificationId.isEmpty) {
        setState(() => phoneController.text = user?.phoneNumber ?? phoneController.text);
        showMessage('Phone number verified and saved.');
      } else {
        setState(() => phoneVerificationId = verificationId);
        showMessage('SMS verification code sent.');
      }
    } on ApiException catch (error) {
      showMessage(error.message, error: true);
    } catch (_) {
      showMessage('We could not send a verification code. Check the number and try again.', error: true);
    } finally {
      if (mounted) setState(() => phoneBusy = false);
    }
  }

  Future<void> verifyPhoneCode() async {
    final verificationId = phoneVerificationId;
    if (verificationId == null) return;
    setState(() => phoneBusy = true);
    try {
      await widget.auth.verifyPhoneLinkCode(verificationId, phoneCodeController.text);
      if (!mounted) return;
      setState(() {
        phoneVerificationId = null;
        phoneCodeController.clear();
        phoneController.text = user?.phoneNumber ?? phoneController.text;
      });
      showMessage('Phone number verified and saved.');
    } on ApiException catch (error) {
      showMessage(error.message, error: true);
    } catch (_) {
      showMessage('That code could not be verified. Request a new code if it has expired.', error: true);
    } finally {
      if (mounted) setState(() => phoneBusy = false);
    }
  }

  Future<void> changePassword() async {
    if (newPasswordController.text != confirmPasswordController.text) {
      showMessage('The new passwords do not match.', error: true);
      return;
    }
    setState(() => passwordBusy = true);
    try {
      await widget.auth.changePassword(
        currentPassword: currentPasswordController.text,
        newPassword: newPasswordController.text,
      );
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      showMessage('Password updated.');
    } on ApiException catch (error) {
      showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => passwordBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = user?.email ?? 'No email address linked';
    final phone = user?.phoneNumber;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account details', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Refresh account details',
            onPressed: refreshing ? null : refreshIdentity,
            icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Email address'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(currentEmail, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        user?.emailVerified == true ? Icons.verified_rounded : Icons.info_outline_rounded,
                        size: 17,
                        color: user?.emailVerified == true ? EazyColors.green : EazyColors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(user?.emailVerified == true ? 'Verified' : 'Not verified'),
                      const Spacer(),
                      if (user?.emailVerified != true)
                        TextButton(
                          onPressed: emailBusy ? null : () async {
                            try {
                              await widget.auth.sendCurrentEmailVerification();
                              showMessage('Verification email sent.');
                            } on ApiException catch (error) {
                              showMessage(error.message, error: true);
                            }
                          },
                          child: const Text('Verify'),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'New email address',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  if (hasPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: emailBusy ? null : requestEmailChange,
                      child: emailBusy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Send verification link'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your current email stays active until you verify the new address. Eazy updates your account after Firebase confirms it.',
                    style: TextStyle(color: EazyColors.muted, height: 1.35, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Phone number'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phone == null || phone.isEmpty ? 'No phone number linked' : phone,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        phone == null || phone.isEmpty ? Icons.info_outline_rounded : Icons.verified_rounded,
                        size: 17,
                        color: phone == null || phone.isEmpty ? EazyColors.muted : EazyColors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(phone == null || phone.isEmpty ? 'Not added' : 'Verified by Firebase'),
                    ],
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+2348012345678',
                      helperText: 'Include your country code.',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: phoneBusy ? null : sendPhoneCode,
                      icon: const Icon(Icons.sms_outlined),
                      label: Text(phone == null || phone.isEmpty ? 'Verify phone number' : 'Verify new number'),
                    ),
                  ),
                  if (phoneVerificationId != null) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: phoneCodeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'SMS verification code',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: phoneBusy ? null : verifyPhoneCode,
                        child: phoneBusy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Confirm phone number'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'We verify the number with an SMS code before linking or replacing it. Your existing sign-in account is kept intact.',
                    style: TextStyle(color: EazyColors.muted, height: 1.35, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Password'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: hasPassword
                  ? Column(
                      children: [
                        TextField(
                          controller: currentPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: newPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'New password',
                            helperText: 'Use at least 8 characters.',
                            prefixIcon: Icon(Icons.lock_reset_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: passwordBusy ? null : changePassword,
                            child: passwordBusy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Update password'),
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'This account does not use an email-and-password sign-in method. Password changes are managed by your linked sign-in provider.',
                      style: TextStyle(color: EazyColors.muted, height: 1.4),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      title,
      style: const TextStyle(color: EazyColors.muted, fontWeight: FontWeight.w800),
    ),
  );
}
