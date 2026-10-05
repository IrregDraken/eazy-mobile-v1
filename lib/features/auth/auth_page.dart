import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/ui/eazy_artwork.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth});
  final AuthController auth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();

  bool register = false;
  bool obscure = true;
  bool remember = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (register && password.text != confirmPassword.text) {
      setState(() => error = 'Your passwords do not match.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (register) {
        await widget.auth.registerEmail(email.text, password.text);
        if (mounted) await _verificationDialog();
      } else {
        await widget.auth.signInEmail(email.text, password.text);
        if (mounted && widget.auth.isSignedIn) context.go('/home');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> social(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try {
      await action();
      if (mounted && widget.auth.isSignedIn) context.go('/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'We could not complete sign-in. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verificationDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: EazyColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EazyArtwork(kind: EazyArtworkKind.verify, height: 190),
            const SizedBox(height: 18),
            const Text('Check your inbox', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            const Text(
              'We sent a verification link to your email. Verify it, then return here to finish creating your Eazy account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EazyColors.muted, height: 1.45),
            ),
            const SizedBox(height: 10),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I verified'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      await widget.auth.finishVerifiedEmailRegistration();
      if (mounted && widget.auth.isSignedIn) context.go('/onboarding');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _resetPassword() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Enter your email first.');
      return;
    }
    try {
      await widget.auth.sendPasswordReset(email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artwork = register ? EazyArtworkKind.createAccount : EazyArtworkKind.signIn;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/welcome'),
                  style: IconButton.styleFrom(
                    backgroundColor: EazyColors.surface,
                    side: const BorderSide(color: EazyColors.border),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Spacer(),
                const _MiniLogo(),
              ],
            ),
            const SizedBox(height: 14),
            EazyArtwork(kind: artwork, height: 220),
            const SizedBox(height: 22),
            Text(
              register ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 29),
            ),
            const SizedBox(height: 7),
            Text(
              register
                  ? 'Join Eazy and bring your people, products and payments together.'
                  : 'Sign in to continue to your Eazy world.',
              style: const TextStyle(color: EazyColors.muted, height: 1.45),
            ),
            const SizedBox(height: 22),
            if (error != null) _ErrorBanner(message: error!),
            _Field(
              controller: email,
              label: 'Email or phone number',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 11),
            _Field(
              controller: password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscure: obscure,
              suffix: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
              onSubmitted: (_) => submit(),
            ),
            if (register) ...[
              const SizedBox(height: 11),
              _Field(
                controller: confirmPassword,
                label: 'Confirm password',
                icon: Icons.verified_user_outlined,
                obscure: obscure,
              ),
            ],
            if (!register) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    value: remember,
                    onChanged: (v) => setState(() => remember = v ?? true),
                  ),
                  const Text('Remember me', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: busy ? null : _resetPassword,
                    child: const Text('Forgot password?', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(register ? 'Create account' : 'Sign in'),
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
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() { register = !register; error = null; }),
                child: Text(
                  register ? 'Already have an account? Sign in' : 'New to Eazy? Create an account',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniLogo extends StatelessWidget {
  const _MiniLogo();

  @override
  Widget build(BuildContext context) => const Text.rich(
    TextSpan(
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -1.5),
      children: [
        TextSpan(text: 'ea', style: TextStyle(color: EazyColors.ink)),
        TextSpan(text: 'zy', style: TextStyle(color: EazyColors.green)),
      ],
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
  Widget build(BuildContext context) => Row(
    children: const [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('or continue with', style: TextStyle(color: EazyColors.muted, fontSize: 11)),
      ),
      Expanded(child: Divider()),
    ],
  );
}

enum _Provider { google, apple }

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({required this.provider, required this.label, required this.onTap});

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
