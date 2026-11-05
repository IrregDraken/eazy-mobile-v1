import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

enum _ActivationStage { form, pending, verified, failed, pin, account }

class WalletActivationPage extends StatefulWidget {
  const WalletActivationPage({super.key});

  @override
  State<WalletActivationPage> createState() => _WalletActivationPageState();
}

class _WalletActivationPageState extends State<WalletActivationPage> {
  final api = ApiClient();
  final first = TextEditingController();
  final middle = TextEditingController();
  final last = TextEditingController();
  final phone = TextEditingController();
  final accountNumber = TextEditingController();
  final bvn = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();

  List<Map<String, dynamic>> banks = [];
  String? bankCode;
  String? bankName;
  String verifiedPhone = '';
  String? failureReason;
  Map<String, dynamic>? virtualAccount;
  _ActivationStage stage = _ActivationStage.form;
  int step = 1;
  bool loading = true;
  bool busy = false;
  bool providerAvailable = false;
  bool virtualAccountsAvailable = false;
  bool consent = false;
  bool pinConfigured = false;
  bool polling = false;
  Timer? pollTimer;
  int pollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadPrerequisites();
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    for (final controller in [
      first, middle, last, phone, accountNumber, bvn, pin, confirmPin,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _loadPrerequisites() async {
    setState(() => loading = true);
    try {
      final profileResult = await api.get('profiles/me', auth: true);
      final userResult = await api.get('auth/me', auth: true);
      final bankResult = await api.get('banks?currency=NGN', auth: true);
      final capabilities = await api.get('wallet/virtual-account/capabilities', auth: true);
      final accountResult = await api.get('wallet/virtual-account', auth: true);
      final pinStatus = await api.get('wallet/payment-pin/status', auth: true);

      final profile = _map(profileResult['profile']);
      final user = _map(userResult['user']);
      final name = (profile['displayName'] ?? '').toString().trim();
      final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

      first.text = (profile['firstName'] ?? (parts.isNotEmpty ? parts.first : '')).toString();
      middle.text = (profile['middleName'] ?? '').toString();
      last.text = (profile['lastName'] ?? (parts.length > 1 ? parts.skip(1).join(' ') : '')).toString();
      verifiedPhone = (user['phone'] ?? '').toString().trim();
      phone.text = verifiedPhone;

      banks = (bankResult['banks'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['code'] != null && entry['name'] != null && entry['active'] != false)
          .toList();

      providerAvailable = capabilities['providerAvailable'] == true;
      virtualAccountsAvailable = capabilities['virtualAccountsAvailable'] == true;
      virtualAccount = _map(accountResult['virtualAccount']).isEmpty
          ? null
          : _map(accountResult['virtualAccount']);
      pinConfigured = pinStatus['configured'] == true;

      if (virtualAccount?['status']?.toString().toLowerCase() == 'active') {
        stage = pinConfigured ? _ActivationStage.account : _ActivationStage.verified;
      } else if (virtualAccount?['status']?.toString().toLowerCase() == 'pending') {
        stage = _ActivationStage.pending;
        _startPolling();
      } else if (virtualAccount?['status']?.toString().toLowerCase() == 'failed') {
        failureReason = virtualAccount?['failureReason']?.toString();
        stage = _ActivationStage.failed;
      }
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Eazy could not load the wallet verification requirements. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _maskedBvn() {
    final value = bvn.text.trim();
    if (value.length < 4) return '•••••••••••';
    return '•••••••' + value.substring(value.length - 4);
  }

  Future<void> _submitActivation() async {
    if (busy) return;
    if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
      _showError('Enter your first and last names.');
      setState(() => step = 1);
      return;
    }
    if (verifiedPhone.isEmpty || phone.text.trim() != verifiedPhone) {
      _showError('A verified phone number is required for wallet activation.');
      setState(() => step = 1);
      return;
    }
    if (bankCode == null || accountNumber.text.trim().length != 10 || bvn.text.trim().length != 11) {
      _showError('Complete the bank and identity details before continuing.');
      setState(() => step = 2);
      return;
    }
    if (!consent) {
      _showError('Review and accept the wallet verification consent to continue.');
      return;
    }

    setState(() {
      busy = true;
      stage = _ActivationStage.pending;
      failureReason = null;
    });
    try {
      final result = await api.post(
        'wallet/virtual-account',
        auth: true,
        body: {
          'consent': true,
          'firstName': first.text.trim(),
          if (middle.text.trim().isNotEmpty) 'middleName': middle.text.trim(),
          'lastName': last.text.trim(),
          'phone': verifiedPhone,
          'preferredBank': bankCode,
          'country': 'NG',
          'accountNumber': accountNumber.text.trim(),
          'bvn': bvn.text.trim(),
          'bankCode': bankCode,
        },
      );
      virtualAccount = _map(result['virtualAccount']);
      bvn.clear();
      if (_isActive) {
        stage = pinConfigured ? _ActivationStage.account : _ActivationStage.verified;
      } else if (_isFailed) {
        stage = _ActivationStage.failed;
        failureReason = virtualAccount?['failureReason']?.toString();
      } else {
        stage = _ActivationStage.pending;
        _startPolling();
      }
    } on ApiException catch (error) {
      // Provider submission may persist a failed/pending state before returning
      // an error. Read the authoritative state before choosing the screen.
      await _refreshActivationStatus(showErrors: false);
      if (!_isActive && !_isFailed && mounted) {
        _showError(error.message);
        setState(() => stage = _ActivationStage.form);
      }
    } catch (_) {
      _showError('Wallet verification could not be submitted. Check your connection and try again.');
      if (mounted) setState(() => stage = _ActivationStage.form);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get _isActive =>
      virtualAccount?['status']?.toString().toLowerCase() == 'active';

  bool get _isFailed =>
      virtualAccount?['status']?.toString().toLowerCase() == 'failed';

  void _startPolling() {
    pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      polling = true;
      pollAttempts = 0;
      stage = _ActivationStage.pending;
    });
    pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || pollAttempts >= 12 || _isActive || _isFailed) {
        timer.cancel();
        if (mounted) setState(() => polling = false);
        return;
      }
      pollAttempts++;
      await _refreshActivationStatus(showErrors: false);
      if (_isActive || _isFailed) {
        timer.cancel();
        if (mounted) {
          setState(() {
            polling = false;
            stage = _isActive
                ? (pinConfigured ? _ActivationStage.account : _ActivationStage.verified)
                : _ActivationStage.failed;
            failureReason = virtualAccount?['failureReason']?.toString();
          });
        }
      }
    });
  }

  Future<void> _refreshActivationStatus({bool showErrors = true}) async {
    try {
      final result = await api.get('wallet/virtual-account', auth: true);
      final account = _map(result['virtualAccount']);
      if (!mounted) return;
      setState(() {
        virtualAccount = account.isEmpty ? virtualAccount : account;
        if (_isActive) {
          stage = pinConfigured ? _ActivationStage.account : _ActivationStage.verified;
        } else if (_isFailed) {
          stage = _ActivationStage.failed;
          failureReason = virtualAccount?['failureReason']?.toString();
        }
      });
    } on ApiException catch (error) {
      if (showErrors) _showError(error.message);
    }
  }

  Future<void> _continueAfterVerification() async {
    if (!mounted) return;
    try {
      final status = await api.get('wallet/payment-pin/status', auth: true);
      pinConfigured = status['configured'] == true;
      if (pinConfigured) {
        await _refreshActivationStatus();
        if (mounted) setState(() => stage = _ActivationStage.account);
      } else {
        setState(() => stage = _ActivationStage.pin);
      }
    } on ApiException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _createPaymentPin() async {
    if (busy) return;
    if (pin.text.length != 4 || confirmPin.text.length != 4 || pin.text != confirmPin.text) {
      _showError('Enter and confirm the same 4-digit payment PIN.');
      return;
    }
    setState(() => busy = true);
    try {
      final codeRequest = await api.post(
        'wallet/payment-pin/request-code',
        auth: true,
        body: const {},
      );
      final challengeId = codeRequest['challengeId']?.toString();
      if (challengeId == null || challengeId.isEmpty) {
        throw const ApiException('Eazy could not start payment PIN verification. Try again.');
      }
      final codeController = TextEditingController();
      String? code;
      try {
        code = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Verify your payment PIN'),
            content: TextField(
              controller: codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-digit email verification code',
                counterText: '',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (codeController.text.length == 6) {
                    Navigator.pop(dialogContext, codeController.text);
                  }
                },
                child: const Text('Verify'),
              ),
            ],
          ),
        );
      } finally {
        codeController.dispose();
      }
      if (code == null || !mounted) return;
      await api.post(
        'wallet/payment-pin/setup',
        auth: true,
        body: {
          'pin': pin.text,
          'confirmation': confirmPin.text,
          'challengeId': challengeId,
          'code': code,
        },
      );
      pinConfigured = true;
      pin.clear();
      confirmPin.clear();
      await _refreshActivationStatus();
      if (mounted) setState(() => stage = _ActivationStage.account);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copyAccountNumber() async {
    final number = virtualAccount?['accountNumber']?.toString() ?? '';
    if (number.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account number copied')),
      );
    }
  }

  void _returnHome() => context.go('/home');

  void _nextStep() {
    if (step == 1) {
      if (first.text.trim().isEmpty || last.text.trim().isEmpty || verifiedPhone.isEmpty) {
        _showError('Complete your verified personal details first.');
        return;
      }
    }
    if (step == 2) {
      if (bankCode == null || accountNumber.text.trim().length != 10 || bvn.text.trim().length != 11) {
        _showError('Enter a valid bank, 10-digit account number and 11-digit BVN.');
        return;
      }
    }
    setState(() => step = (step + 1).clamp(1, 3));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activate Eazy Wallet')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (stage) {
            _ActivationStage.form => 'Activate Eazy Wallet',
            _ActivationStage.pending => 'Verification pending',
            _ActivationStage.verified => 'Wallet verified',
            _ActivationStage.failed => 'Verification result',
            _ActivationStage.pin => 'Secure your wallet',
            _ActivationStage.account => 'Your Eazy account',
          },
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          child: switch (stage) {
            _ActivationStage.form => _buildForm(),
            _ActivationStage.pending => _buildPending(),
            _ActivationStage.verified => _buildVerified(),
            _ActivationStage.failed => _buildFailed(),
            _ActivationStage.pin => _buildPinSetup(),
            _ActivationStage.account => _buildAccountDetails(),
          },
        ),
      ),
    );
  }

  Widget _buildForm() => ListView(
    key: const ValueKey('wallet-activation-form'),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    children: [
      Text(
        'A receiving account, built around your identity.',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        'Complete three short steps. Your details are sent to Eazy’s regulated payment provider for verification.',
        style: TextStyle(color: context.eazyMuted, height: 1.45),
      ),
      const SizedBox(height: 22),
      _stepProgress(),
      const SizedBox(height: 22),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: switch (step) {
          1 => _personalDetails(),
          2 => _bankDetails(),
          _ => _reviewDetails(),
        },
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          if (step > 1)
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => setState(() => step--),
                child: const Text('Back'),
              ),
            ),
          if (step > 1) const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: busy
                  ? null
                  : step < 3
                      ? _nextStep
                      : (providerAvailable && virtualAccountsAvailable ? _submitActivation : null),
              child: Text(
                busy
                    ? 'Submitting…'
                    : step < 3
                        ? 'Continue'
                        : 'Submit for verification',
              ),
            ),
          ),
        ],
      ),
      if (!providerAvailable || !virtualAccountsAvailable) ...[
        const SizedBox(height: 14),
        Text(
          'Wallet activation is temporarily unavailable because the payment provider is not configured.',
          style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.4),
        ),
      ],
    ],
  );

  Widget _stepProgress() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Step $step of 3',
        style: TextStyle(
          color: context.eazyAccent,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: List.generate(3, (index) {
          final active = index < step;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 7),
              decoration: BoxDecoration(
                color: active ? context.eazyAccent : context.eazyBorder,
                borderRadius: BorderRadius.circular(99),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: context.eazyAccent.withValues(alpha: .24),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
            ),
          );
        }),
      ),
    ],
  );

  Widget _sectionTitle(String title, String detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(detail, style: TextStyle(color: context.eazyMuted, height: 1.4)),
      const SizedBox(height: 18),
    ],
  );

  Widget _personalDetails() => Column(
    key: const ValueKey('wallet-step-personal'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Personal details', 'Make sure your name matches your verified identity.'),
      TextField(
        controller: first,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'First name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: middle,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Middle name (optional)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: last,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Last name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: phone,
        readOnly: true,
        decoration: InputDecoration(
          labelText: 'Verified Eazy phone number',
          prefixIcon: const Icon(Icons.verified_user_outlined),
          helperText: 'Your wallet account must use this verified number.',
          suffixIcon: Icon(Icons.lock_outline_rounded, color: context.eazyMuted),
        ),
      ),
    ],
  );

  Widget _bankDetails() => Column(
    key: const ValueKey('wallet-step-bank'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Bank and identity verification', 'These details are validated by the payment provider. Your BVN is not displayed after submission.'),
      DropdownMenu<String>(
        width: double.infinity,
        enableFilter: true,
        enableSearch: true,
        label: const Text('Preferred bank'),
        initialSelection: bankCode,
        dropdownMenuEntries: [
          for (final bank in banks)
            DropdownMenuEntry<String>(
              value: bank['code'].toString(),
              label: bank['name'].toString(),
            ),
        ],
        onSelected: (value) {
          setState(() {
            bankCode = value;
            bankName = banks
                .firstWhere((entry) => entry['code'].toString() == value, orElse: () => const {})['name']
                ?.toString();
          });
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: accountNumber,
        keyboardType: TextInputType.number,
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Bank account number',
          counterText: '',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: bvn,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 11,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '11-digit BVN',
          counterText: '',
        ),
      ),
    ],
  );

  Widget _reviewDetails() => Column(
    key: const ValueKey('wallet-step-review'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Review and consent', 'Check the details before sending them for provider verification.'),
      _reviewRow('Full name', [first.text, middle.text, last.text].where((value) => value.trim().isNotEmpty).join(' ')),
      _reviewRow('Verified phone', verifiedPhone),
      _reviewRow('Preferred bank', bankName ?? 'Not selected'),
      _reviewRow('Account number', accountNumber.text),
      _reviewRow('BVN', _maskedBvn()),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: context.eazyAccent.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(14),
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: (value) => setState(() => consent = value == true),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I consent to Eazy sharing these details with its regulated payment provider for identity validation and wallet account assignment.',
            style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Submitting does not guarantee approval. The provider will determine whether an account can be assigned.',
        style: TextStyle(color: context.eazyMuted, fontSize: 12, height: 1.4),
      ),
    ],
  );

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 126, child: Text(label, style: TextStyle(color: context.eazyMuted))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    ),
  );

  Widget _statusIcon(IconData icon, Color color) => Container(
    width: 84,
    height: 84,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: .12),
    ),
    child: Icon(icon, size: 42, color: color),
  );

  Widget _buildPending() => Center(
    key: const ValueKey('wallet-activation-pending'),
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statusIcon(Icons.hourglass_top_rounded, context.eazyAccent),
          const SizedBox(height: 22),
          Text(
            'We’re checking your details',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 9),
          Text(
            'Your request has been submitted. Eazy is checking the payment provider’s verification status. We will show the result here when the provider responds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eazyMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (polling) const LinearProgressIndicator(),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : _refreshActivationStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check status'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _returnHome, child: const Text('Return to home')),
        ],
      ),
    ),
  );

  Widget _buildVerified() => Center(
    key: const ValueKey('wallet-activation-verified'),
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statusIcon(Icons.verified_rounded, context.eazyAccent),
          const SizedBox(height: 22),
          Text(
            'Congratulations. You’re verified.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 9),
          Text(
            'Your wallet receiving account has been approved. Create your transaction PIN to secure payments and reveal your virtual account details.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eazyMuted, height: 1.5),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _continueAfterVerification,
              child: const Text('Create payment PIN'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildFailed() => Center(
    key: const ValueKey('wallet-activation-failed'),
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statusIcon(Icons.error_outline_rounded, Theme.of(context).colorScheme.error),
          const SizedBox(height: 22),
          Text(
            'We could not verify this request',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 9),
          Text(
            (failureReason == null || failureReason!.trim().isEmpty)
                ? 'The payment provider did not approve this wallet activation. Contact Eazy support for guidance.'
                : failureReason!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eazyMuted, height: 1.5),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _returnHome, child: const Text('Return to home')),
          ),
          TextButton(
            onPressed: () => setState(() {
              stage = _ActivationStage.form;
              step = 1;
              consent = false;
            }),
            child: const Text('Review details and try again'),
          ),
        ],
      ),
    ),
  );

  Widget _buildPinSetup() => ListView(
    key: const ValueKey('wallet-activation-pin'),
    padding: const EdgeInsets.all(22),
    children: [
      _statusIcon(Icons.lock_outline_rounded, context.eazyAccent),
      const SizedBox(height: 18),
      Text(
        'Create your 4-digit payment PIN',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 8),
      Text(
        'A verification code will be sent to your verified email before your PIN is saved.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.eazyMuted, height: 1.45),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: pin,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Create 4-digit PIN', counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: confirmPin,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Confirm payment PIN', counterText: ''),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : _createPaymentPin,
        child: Text(busy ? 'Saving PIN…' : 'Verify and create PIN'),
      ),
    ],
  );

  Widget _buildAccountDetails() {
    final account = virtualAccount ?? const <String, dynamic>{};
    final accountName = account['accountName']?.toString() ?? '';
    final number = account['accountNumber']?.toString() ?? '';
    final bank = account['bankName']?.toString() ?? '';
    return ListView(
      key: const ValueKey('wallet-activation-account'),
      padding: const EdgeInsets.all(22),
      children: [
        _statusIcon(Icons.account_balance_rounded, context.eazyAccent),
        const SizedBox(height: 18),
        Text(
          'Your Eazy account is ready',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Your receiving account details are supplied by the payment provider.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.eazyMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACCOUNT NAME', style: TextStyle(color: context.eazyMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 5),
                Text(
                  accountName.isEmpty ? 'Account name not returned by provider' : accountName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 18),
                Text('ACCOUNT NUMBER', style: TextStyle(color: context.eazyMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        number.isEmpty ? 'Not yet supplied' : number,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.2),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy account number',
                      onPressed: number.isEmpty ? null : _copyAccountNumber,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('BANK', style: TextStyle(color: context.eazyMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 5),
                Text(bank.isEmpty ? 'Bank name not returned by provider' : bank, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text('NGN • Eazy Wallet', style: TextStyle(color: context.eazyMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _returnHome,
            child: const Text('Return to home'),
          ),
        ),
      ],
    );
  }
}
