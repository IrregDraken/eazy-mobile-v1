import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool busy = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; });
    try {
      if (register) {
        await widget.auth.registerEmail(email.text, password.text);
        if (mounted) await _verificationDialog();
      } else {
        await widget.auth.signInEmail(email.text, password.text);
        if (mounted) context.go('/home');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verificationDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Check your inbox'),
        content: const Text('We sent a verification link to your email. Verify it, then return here to finish creating your Eazy account.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
    if (!mounted) return;
    try {
      await widget.auth.finishVerifiedEmailRegistration();
      if (mounted && widget.auth.isSignedIn) context.go('/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: Colors.transparent, leading: IconButton(onPressed: () => context.go('/welcome'), icon: const Icon(Icons.arrow_back_rounded))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(register ? 'Create your Eazy' : 'Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
          const SizedBox(height: 8),
          Text(register ? 'One account for your social, chat, marketplace and wallet experience.' : 'Pick up where you left off.', style: const TextStyle(color: EazyColors.muted, height: 1.5)),
          const SizedBox(height: 28),
          if (error != null) _ErrorBanner(message: error!),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded))),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: obscure, onSubmitted: (_) => submit(), decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
          const SizedBox(height: 18),
          SizedBox(height: 56, child: FilledButton(onPressed: busy ? null : submit, child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(register ? 'Create account' : 'Sign in'))),
          const SizedBox(height: 18),
          const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')), Expanded(child: Divider())]),
          const SizedBox(height: 18),
          _ProviderButton(icon: Icons.g_mobiledata_rounded, label: 'Continue with Google', onTap: () => _notice('Google sign-in is being wired to the new native Flutter layer.')),
          const SizedBox(height: 10),
          _ProviderButton(icon: Icons.apple, label: 'Continue with Apple', onTap: () => _notice('Apple sign-in is being wired to the new native Flutter layer.')),
          const SizedBox(height: 24),
          Center(child: TextButton(onPressed: busy ? null : () => setState(() { register = !register; error = null; }), child: Text(register ? 'Already have an account? Sign in' : 'New to Eazy? Create an account'))),
        ],
      ),
    ),
  );

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(height: 54, width: double.infinity, child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)));
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: EazyColors.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(16), border: Border.all(color: EazyColors.red.withValues(alpha: .3))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.error_outline_rounded, color: EazyColors.red), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: EazyColors.ink, height: 1.4)))])
  );
}
