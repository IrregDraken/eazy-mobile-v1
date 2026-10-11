import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  int registerStage = 0;
  bool obscure = true;
  bool remember = true;
  bool busy = false;
  String? error;
  EmailVerificationChallenge? challenge;
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
      if (register) {
        if (phoneMode) {
          if (registerStage == 0) {
            phoneVerificationId = await widget.auth.requestPhoneCode(
              identifier.text,
            );
            if (mounted) setState(() => registerStage = 1);
          } else {
            await widget.auth.verifyPhoneCode(phoneVerificationId!, code.text);
            if (mounted) context.go('/onboarding');
          }
        } else if (registerStage == 0) {
          challenge = await widget.auth.beginEmailRegistration(identifier.text);
          if (mounted) setState(() => registerStage = 1);
        } else if (registerStage == 1) {
          await widget.auth.verifyEmailRegistration(challenge!, code.text);
          if (mounted) setState(() => registerStage = 2);
        } else {
          if (password.text.length < 6)
            throw const ApiException(
              'Choose a password with at least 6 characters.',
            );
          if (password.text != confirmPassword.text)
            throw const ApiException('Your passwords do not match.');
          await widget.auth.registerEmailAfterVerification(
            identifier.text,
            password.text,
          );
          if (mounted) context.go('/onboarding');
        }
      } else {
        await widget.auth.signInEmail(identifier.text, password.text);
        if (mounted)
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

  Future<void> social(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted)
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

  Future<void> resend() async {
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
        challenge = await widget.auth.beginEmailRegistration(identifier.text);
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

  void switchMode(bool nextRegister) => setState(() {
    register = nextRegister;
    registerStage = 0;
    error = null;
    password.clear();
    confirmPassword.clear();
    code.clear();
  });

  void switchInput(bool nextPhone) => setState(() {
    phoneMode = nextPhone;
    registerStage = 0;
    error = null;
    identifier.clear();
    code.clear();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF031E13), Color(0xFF062B1B), Color(0xFF0B5C3C)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  compact ? 8 : 18,
                  18,
                  compact ? 8 : 18,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed:
                              () =>
                                  registerStage > 0
                                      ? setState(() => registerStage--)
                                      : context.go('/welcome'),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                compact
                                    ? constraints.maxHeight * .58
                                    : constraints.maxHeight * .50,
                            maxHeight:
                                compact
                                    ? constraints.maxHeight * .86
                                    : constraints.maxHeight * .78,
                          ),
                          child: _FormCard(compact: compact),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _FormCard({required bool compact}) {
    final title =
        !register
            ? 'Welcome back'
            : registerStage == 0
            ? 'Create your account'
            : registerStage == 1
            ? 'Check your code'
            : 'Set your password';
    final subtitle =
        !register
            ? 'Sign in to continue to Eazy.'
            : registerStage == 0
            ? 'Start with your email or phone number.'
            : registerStage == 1
            ? 'Enter the 6-digit code we sent you.'
            : 'Use this password for future email sign-ins.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        18,
        compact ? 16 : 22,
        18,
        compact ? 12 : 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF082117),
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF5B6C63), fontSize: 13),
          ),
          SizedBox(height: compact ? 12 : 16),
          if (!register) ...[
            _EntryField(
              controller: identifier,
              label: 'Email address',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            _EntryField(
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
            const SizedBox(height: 2),
            Row(
              children: [
                Checkbox(
                  value: remember,
                  onChanged: (v) => setState(() => remember = v ?? true),
                  activeColor: const Color(0xFF0E9D61),
                  visualDensity: VisualDensity.compact,
                ),
                const Text(
                  'Remember me',
                  style: TextStyle(color: Color(0xFF40534A), fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _resetPassword,
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ] else if (registerStage == 2) ...[
            _EntryField(
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
            const SizedBox(height: 10),
            _EntryField(
              controller: confirmPassword,
              label: 'Confirm password',
              icon: Icons.verified_user_outlined,
              obscure: obscure,
            ),
          ] else ...[
            _ToggleRow(phone: phoneMode, onChanged: switchInput),
            const SizedBox(height: 10),
            _EntryField(
              controller: identifier,
              label: phoneMode ? 'Phone number' : 'Email address',
              icon:
                  phoneMode
                      ? Icons.phone_outlined
                      : Icons.alternate_email_rounded,
              keyboardType:
                  phoneMode ? TextInputType.phone : TextInputType.emailAddress,
            ),
            if (registerStage == 1) ...[
              const SizedBox(height: 10),
              _EntryField(
                controller: code,
                label: '6-digit verification code',
                icon: Icons.password_rounded,
                keyboardType: TextInputType.number,
              ),
            ],
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xFFC03935), fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: compact ? 48 : 52,
            child: FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0E9D61),
                foregroundColor: Colors.white,
              ),
              child:
                  busy
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        !register
                            ? 'Sign in'
                            : registerStage == 0
                            ? 'Send verification code'
                            : registerStage == 1
                            ? 'Verify code'
                            : 'Create account',
                      ),
            ),
          ),
          if (register && registerStage == 1)
            Center(
              child: TextButton(
                onPressed: busy ? null : resend,
                child: const Text('Resend code'),
              ),
            ),
          if (registerStage == 0) ...[
            SizedBox(height: compact ? 7 : 10),
            const _OrDivider(),
            SizedBox(height: compact ? 7 : 10),
            _ProviderButton(
              label: 'Continue with Google',
              icon: const _GoogleMark(),
              onPressed: busy ? null : () => social(widget.auth.signInGoogle),
            ),
            const SizedBox(height: 7),
            _ProviderButton(
              label: 'Continue with Apple',
              icon: const Icon(Icons.apple, color: Color(0xFF082117), size: 20),
              onPressed: busy ? null : () => social(widget.auth.signInApple),
            ),
          ],
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: busy ? null : () => switchMode(!register),
              child: Text(
                register
                    ? 'Already have an account? Sign in'
                    : 'New to Eazy? Create account',
                style: const TextStyle(
                  color: Color(0xFF087A4A),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.phone, required this.onChanged});
  final bool phone;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF3ED),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Toggle(
            label: 'Email',
            selected: !phone,
            onTap: () => onChanged(false),
          ),
        ),
        Expanded(
          child: _Toggle(
            label: 'Phone',
            selected: phone,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF082117) : const Color(0xFF667970),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}

class _EntryField extends StatelessWidget {
  const _EntryField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(
      color: Color(0xFF082117),
      fontWeight: FontWeight.w600,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF718179), fontSize: 13),
      prefixIcon: Icon(icon, color: Color(0xFF0E9D61), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF5FAF6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6E5DA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6E5DA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0E9D61), width: 1.5),
      ),
    ),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: Color(0xFFD6E5DA))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          'or continue with',
          style: TextStyle(color: Color(0xFF718179), fontSize: 11),
        ),
      ),
      const Expanded(child: Divider(color: Color(0xFFD6E5DA))),
    ],
  );
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 43,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF082117),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFD6E5DA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: CustomPaint(painter: _GoogleMarkPainter()),
  );
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .36;
    final stroke = size.width * .18;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final colors = <Color>[
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final starts = <double>[
      -math.pi / 4,
      math.pi / 4,
      3 * math.pi / 4,
      5 * math.pi / 4,
    ];
    for (var i = 0; i < colors.length; i++) {
      canvas.drawArc(
        rect,
        starts[i],
        math.pi / 2 + .08,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx,
        center.dy - stroke / 2,
        radius + stroke / 2,
        stroke,
      ),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
