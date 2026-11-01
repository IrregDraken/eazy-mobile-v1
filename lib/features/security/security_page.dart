import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import 'package:go_router/go_router.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final api = ApiClient();
  final storage = const FlutterSecureStorage();
  final localAuth = LocalAuthentication();
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;
  bool paymentPinConfigured = false;
  bool biometricShortcutEnabled = false;
  bool savingBiometric = false;
  int paymentPinLength = 4;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await api.get('auth/sessions', auth: true);
      final x = (r['sessions'] as List? ?? r['items'] as List? ?? []);
      if (mounted) {
        setState(() {
          sessions = x
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
    try {
      final status = await api.get('wallet/payment-pin/status', auth: true);
      final configured = status['configured'] == true;
      final length = int.tryParse(status['pinLength']?.toString() ?? '') ?? 4;
      final savedEnabled = await storage.read(key: 'eazy.wallet.biometricShortcutEnabled') == 'true';
      final savedPin = await storage.read(key: 'eazy.wallet.biometricPaymentPin');
      if (mounted) {
        setState(() {
          paymentPinConfigured = configured;
          paymentPinLength = length;
          biometricShortcutEnabled = configured && savedEnabled && savedPin != null;
        });
      }
    } on ApiException {
      if (mounted) setState(() {
        paymentPinConfigured = false;
        biometricShortcutEnabled = false;
      });
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _setBiometricShortcut(bool enabled) async {
    if (savingBiometric) return;
    if (!enabled) {
      await storage.delete(key: 'eazy.wallet.biometricShortcutEnabled');
      await storage.delete(key: 'eazy.wallet.biometricPaymentPin');
      if (mounted) setState(() => biometricShortcutEnabled = false);
      return;
    }
    if (!paymentPinConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a payment PIN in Wallet first.')),
      );
      return;
    }
    setState(() => savingBiometric = true);
    final pinController = TextEditingController();
    try {
      final pin = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enable biometric shortcut'),
          content: TextField(
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: paymentPinLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: paymentPinLength == 6 ? 'Current 6-digit PIN' : '4-digit payment PIN',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (pinController.text.length == paymentPinLength) {
                  Navigator.pop(dialogContext, pinController.text);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (pin == null || !mounted) return;
      await api.post('wallet/payment-pin/verify', auth: true, body: {'pin': pin});
      final available = await localAuth.canCheckBiometrics;
      if (!available) {
        throw const ApiException(
          'No enrolled biometrics are available on this device. Use your payment PIN instead.',
          kind: ApiErrorKind.validation,
        );
      }
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Confirm your identity to enable the Eazy payment PIN shortcut',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!authenticated) return;
      await storage.write(key: 'eazy.wallet.biometricPaymentPin', value: pin);
      await storage.write(key: 'eazy.wallet.biometricShortcutEnabled', value: 'true');
      if (mounted) {
        setState(() => biometricShortcutEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric payment shortcut enabled.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric setup could not be completed. Your PIN remains available.')),
        );
      }
    } finally {
      pinController.dispose();
      if (mounted) setState(() => savingBiometric = false);
    }
  }

  Future<void> revoke(String id) async {
    try {
      await api.post('auth/sessions/$id/revoke', auth: true);
      await load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> revokeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Revoke all sessions?'),
            content: const Text(
              'This signs out every Eazy application session, including this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Revoke all'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.post('auth/sessions/revoke-all', auth: true);
      await widget.auth.signOut();
      if (!mounted) return;
      context.go('/welcome');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Security & sessions',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body:
        loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
                children: [
                  Card(
                    child: SwitchListTile(
                      value: biometricShortcutEnabled,
                      onChanged: savingBiometric ? null : _setBiometricShortcut,
                      secondary: Icon(Icons.fingerprint_rounded, color: context.eazyAccent),
                      title: const Text('Biometric payment shortcut'),
                      subtitle: Text(
                        paymentPinConfigured
                            ? 'Optional. Use device biometrics to unlock your saved payment PIN. Off by default.'
                            : 'Create a payment PIN in Wallet before enabling this shortcut.',
                        style: TextStyle(color: context.eazyMuted, fontSize: 12),
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Eazy sessions are server-side sessions bound to your verified Firebase identity. Revoking one blocks further API use from that session.',
                        style: TextStyle(color: context.eazyMuted, height: 1.35),
                      ),
                    ),
                  ),
                  if (error.isNotEmpty)
                    Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ...sessions.map(
                    (s) => Card(
                      child: ListTile(
                        leading: Icon(
                          s['isCurrent'] == true
                              ? Icons.phone_android_rounded
                              : Icons.devices_other_rounded,
                          color: context.eazyAccent,
                        ),
                        title: Text(
                          s['isCurrent'] == true
                              ? 'This device'
                              : 'Eazy session',
                        ),
                        subtitle: Text(s['status']?.toString() ?? 'active'),
                        trailing:
                            s['isCurrent'] == true
                                ? const Icon(Icons.verified_user_rounded)
                                : TextButton(
                                  onPressed: () => revoke(s['id'].toString()),
                                  child: const Text('Revoke'),
                                ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: sessions.isEmpty ? null : revokeAll,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Revoke all sessions'),
                  ),
                ],
              ),
            ),
  );
}
