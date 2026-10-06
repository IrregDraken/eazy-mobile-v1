import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth, this.initialRegister = false});
  final AuthController auth;
  final bool initialRegister;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final code = TextEditingController();

  late bool register;
  bool phoneMode = false;
  bool verificationStep = false;
  bool obscure = true;
  bool remember = true;
  bool busy = false;
  String? error;
  EmailVerificationChallenge? emailChallenge;
  String? phoneVerificationId;

  @override
  void initState() {
    super.initState();
    register = widget.initialRegister;
  }

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    confirmPassword.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (verificationStep) {
        if (code.text.trim().length != 6)
          throw const ApiException('Enter the 6-digit verification code.');
        if (phoneMode) {
          await widget.auth.verifyPhoneCode(phoneVerificationId!, code.text);
        } else {
          await widget.auth.verifyEmailCode(emailChallenge!, code.text);
        }
        if (mounted && widget.auth.isSignedIn)
          context.go(widget.auth.needsOnboarding ? '/onboarding' : '/home');
        return;
      }

      if (phoneMode) {
        phoneVerificationId = await widget.auth.requestPhoneCode(
          identifier.text,
        );
        if (mounted) setState(() => verificationStep = true);
      } else if (register) {
        if (password.text.length < 6)
          throw const ApiException(
            'Choose a password with at least 6 characters.',
          );
        if (password.text != confirmPassword.text)
          throw const ApiException('Your passwords do not match.');
        emailChallenge = await widget.auth.registerEmail(
          identifier.text,
          password.text,
        );
        if (mounted) setState(() => verificationStep = true);
      } else {
        await widget.auth.signInEmail(identifier.text, password.text);
        if (mounted && widget.auth.isSignedIn)
          context.go(widget.auth.needsOnboarding ? '/onboarding' : '/home');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'We could not complete that action. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendCode() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (phoneMode) {
        phoneVerificationId = await widget.auth.requestPhoneCode(
          identifier.text,
        );
      } else {
        emailChallenge = await widget.auth.requestEmailVerificationCode(
          identifier.text,
        );
      }
      if (mounted) {
        code.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new verification code is on its way.'),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> social(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted && widget.auth.isSignedIn)
        context.go(widget.auth.needsOnboarding ? '/onboarding' : '/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'We could not complete sign-in. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void switchMode(bool nextRegister) {
    setState(() {
      register = nextRegister;
      verificationStep = false;
      error = null;
      code.clear();
    });
  }

  void switchInput(bool nextPhone) {
    setState(() {
      phoneMode = nextPhone;
      verificationStep = false;
      error = null;
      identifier.clear();
      code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed:
                      () =>
                          verificationStep
                              ? setState(() => verificationStep = false)
                              : context.go('/welcome'),
                  style: IconButton.styleFrom(
                    backgroundColor: EazyColors.surface,
                    side: const BorderSide(color: EazyColors.border),
                  ),
                  icon: Icon(
                    verificationStep
                        ? Icons.arrow_back_rounded
                        : Icons.close_rounded,
                  ),
                ),
                const Spacer(),
                const Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'ea',
                        style: TextStyle(color: EazyColors.ink),
                      ),
                      TextSpan(
                        text: 'zy',
                        style: TextStyle(color: EazyColors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(EazyRadius.xl),
              child: SizedBox(
                height: 232,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/eazy_auth_hero.png',
                      fit: BoxFit.cover,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD906100B)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 17,
                      child: Text(
                        verificationStep
                            ? 'One small step\nthen you are in.'
                            : register
                            ? 'Create your\nEazy account.'
                            : 'Welcome back\nto Eazy.',
                        style: const TextStyle(
                          fontSize: 26,
                          height: .98,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!verificationStep) ...[
              _ModeTabs(register: register, onChanged: switchMode),
              const SizedBox(height: 18),
              Text(
                register ? 'Create Account' : 'Sign In',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 29),
              ),
              const SizedBox(height: 7),
              Text(
                register
                    ? 'Start with your email or phone number.'
                    : 'Enter your details to continue.',
                style: const TextStyle(color: EazyColors.muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              _InputTabs(phoneMode: phoneMode, onChanged: switchInput),
              const SizedBox(height: 13),
              if (error != null) _ErrorBanner(message: error!),
              _Field(
                controller: identifier,
                label: phoneMode ? 'Phone number' : 'Email address',
                icon:
                    phoneMode
                        ? Icons.phone_rounded
                        : Icons.alternate_email_rounded,
                keyboardType:
                    phoneMode
                        ? TextInputType.phone
                        : TextInputType.emailAddress,
                onSubmitted: (_) => submit(),
              ),
              if (!phoneMode) ...[
                const SizedBox(height: 11),
                _Field(
                  controller: password,
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  obscure: obscure,
                  suffix: IconButton(
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                if (register) ...[
                  const SizedBox(height: 11),
                  _Field(
                    controller: confirmPassword,
                    label: 'Confirm password',
                    icon: Icons.verified_user_outlined,
                    obscure: obscure,
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Checkbox(
                        value: remember,
                        onChanged:
                            (value) => setState(() => remember = value ?? true),
                      ),
                      const Text(
                        'Remember Me',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: busy ? null : _resetPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                const SizedBox(height: 11),
                const Text(
                  'We will send a one-time verification code by SMS.',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child:
                      busy
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(
                            phoneMode
                                ? 'Send Verification Code'
                                : register
                                ? 'Create Account'
                                : 'Sign In',
                          ),
                ),
              ),
              const SizedBox(height: 18),
              const _OrDivider(),
              const SizedBox(height: 14),
              _ProviderButton(
                provider: _Provider.google,
                label: 'Continue with Google',
                onTap: busy ? null : () => social(widget.auth.signInGoogle),
              ),
              const SizedBox(height: 10),
              _ProviderButton(
                provider: _Provider.apple,
                label: 'Continue with Apple',
                onTap: busy ? null : () => social(widget.auth.signInApple),
              ),
              const SizedBox(height: 19),
              Center(
                child: TextButton(
                  onPressed: busy ? null : () => switchMode(!register),
                  child: Text(
                    register
                        ? 'Already Have An Account? Sign In'
                        : 'New to Eazy? Create Account',
                  ),
                ),
              ),
            ] else ...[
              Text(
                'Verify your account',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 29),
              ),
              const SizedBox(height: 7),
              Text(
                phoneMode
                    ? 'Enter the 6-digit code sent to ${identifier.text.trim()}.'
                    : 'Enter the 6-digit code sent to ${identifier.text.trim()}.',
                style: const TextStyle(color: EazyColors.muted, height: 1.45),
              ),
              const SizedBox(height: 22),
              if (error != null) _ErrorBanner(message: error!),
              _Field(
                controller: code,
                label: 'Verification code',
                icon: Icons.password_rounded,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child:
                      busy
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Verify And Continue'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: busy ? null : resendCode,
                  child: const Text('Resend Code'),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your code expires shortly. Never share it with anyone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EazyColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword() async {
    if (identifier.text.trim().isEmpty) {
      setState(() => error = 'Enter your email first.');
      return;
    }
    try {
      await widget.auth.sendPasswordReset(identifier.text);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.register, required this.onChanged});
  final bool register;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: EazyColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: EazyColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Tab(
            label: 'Create Account',
            selected: register,
            onTap: () => onChanged(true),
          ),
        ),
        Expanded(
          child: _Tab(
            label: 'Sign In',
            selected: !register,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    ),
  );
}

class _InputTabs extends StatelessWidget {
  const _InputTabs({required this.phoneMode, required this.onChanged});
  final bool phoneMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Pill(
        label: 'Email',
        selected: !phoneMode,
        onTap: () => onChanged(false),
      ),
      const SizedBox(width: 8),
      _Pill(label: 'Phone', selected: phoneMode, onTap: () => onChanged(true)),
    ],
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color:
            selected
                ? EazyColors.green.withValues(alpha: .14)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? EazyColors.green : EazyColors.muted,
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:
            selected
                ? EazyColors.green.withValues(alpha: .14)
                : EazyColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              selected
                  ? EazyColors.green.withValues(alpha: .5)
                  : EazyColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? EazyColors.green : EazyColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscure,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
    ),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'or continue with',
          style: TextStyle(color: EazyColors.muted, fontSize: 11),
        ),
      ),
      Expanded(child: Divider()),
    ],
  );
}

enum _Provider { google, apple }

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.provider,
    required this.label,
    required this.onTap,
  });
  final _Provider provider;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final isApple = provider == _Provider.apple;
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isApple ? EazyColors.ink : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(
                isApple ? '●' : 'G',
                style: TextStyle(
                  color: isApple ? Colors.black : const Color(0xFF4285F4),
                  fontSize: isApple ? 12 : 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Spacer(),
            Text(label),
            const Spacer(),
            const SizedBox(width: 26),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: EazyColors.red.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: EazyColors.red.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: EazyColors.red),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}
