import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'wallet_amount_input.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with WidgetsBindingObserver {
  final api = ApiClient();
  final storage = const FlutterSecureStorage();
  bool loading = true;
  bool busy = false;
  bool balanceVisible = true;
  bool paymentPinConfigured = false;
  bool reconcilingPayment = false;
  String? error;
  Map<String, dynamic>? wallet;
  Map<String, dynamic>? virtualAccount;
  Map<String, dynamic>? receiveQr;
  String? username;
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic>? pendingDeposit;
  List<Map<String, dynamic>> walletAlerts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restorePrivacyPreference();
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcilePendingPayment(silent: true);
      load();
    }
  }

  Future<void> _restorePrivacyPreference() async {
    final saved = await storage.read(key: 'eazy.wallet.balanceVisible');
    if (mounted && saved != null) {
      setState(() => balanceVisible = saved != 'false');
    }
  }

  Future<void> _toggleBalanceVisibility() async {
    final next = !balanceVisible;
    setState(() => balanceVisible = next);
    await storage.write(
      key: 'eazy.wallet.balanceVisible',
      value: next.toString(),
    );
  }

  String idempotency(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> load() async {
    // Keep an already-rendered wallet visible during refreshes and post-action
    // reconciliation. Only the first load needs a full-page loading state.
    final firstLoad = wallet == null;
    setState(() {
      if (firstLoad) loading = true;
      error = null;
    });
    try {
      var result = await api.get('wallet', auth: true);
      wallet =
          result['wallet'] is Map
              ? Map<String, dynamic>.from(result['wallet'] as Map)
              : null;
      if (wallet == null) {
        result = await api.post(
          'wallet',
          auth: true,
          body: {'currency': 'NGN'},
        );
        wallet =
            result['wallet'] is Map
                ? Map<String, dynamic>.from(result['wallet'] as Map)
                : null;
      }
      try {
        final profileResult = await api.get('profiles/me', auth: true);
        final profile = _map(profileResult['profile']);
        username = profile['username']?.toString();
      } on ApiException {
        username = null;
      }
      final transactionResult = await api.get(
        'wallet/transactions?page=1&limit=20',
        auth: true,
      );
      try {
        final pinStatus = await api.get('wallet/payment-pin/status', auth: true);
        paymentPinConfigured = pinStatus['configured'] == true;
      } on ApiException {
        paymentPinConfigured = false;
      }
      transactions =
          (transactionResult['items'] as List? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
      final pendingEntries = transactions.where(
        (entry) =>
            entry['type']?.toString().toLowerCase() == 'deposit' &&
            entry['status']?.toString().toLowerCase() == 'pending',
      );
      pendingDeposit = pendingEntries.isEmpty ? null : pendingEntries.first;
      final pendingDepositId = pendingDeposit?['id']?.toString();
      if (pendingDepositId != null && pendingDepositId.isNotEmpty) {
        await storage.write(key: 'eazy.pendingPayment', value: pendingDepositId);
      } else {
        await storage.delete(key: 'eazy.pendingPayment');
      }
      try {
        final alertResult = await api.get(
          'notifications?page=1&limit=50',
          auth: true,
        );
        walletAlerts = (alertResult['items'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .where((entry) {
              final type = entry['type']?.toString().toLowerCase();
              return type == 'payment' || type == 'order';
            })
            .toList();
      } catch (_) {
        walletAlerts = [];
      }
      try {
        final accountResult = await api.get(
          'wallet/virtual-account',
          auth: true,
        );
        virtualAccount =
            accountResult['virtualAccount'] is Map
                ? Map<String, dynamic>.from(
                  accountResult['virtualAccount'] as Map,
                )
                : null;
      } on ApiException {
        virtualAccount = null;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deposit() async {
    if (pendingDeposit != null) {
      _showError('You already have a deposit awaiting confirmation. Check its status before starting another one.');
      return;
    }
    final amount = await _amountDialog(title: 'Add money', action: 'Continue');
    if (amount == null) return;
    setState(() => busy = true);
    try {
      final result = await api.post(
        'payments/initialize',
        auth: true,
        headers: {'Idempotency-Key': idempotency('deposit')},
        body: {
          'purpose': 'wallet_deposit',
          'amount': amount,
          'currency': _currency,
        },
      );
      final payment = _map(result['payment']);
      final transaction = _map(result['transaction']);
      final transactionId = transaction['id']?.toString();
      if (transactionId != null) {
        await storage.write(key: 'eazy.pendingPayment', value: transactionId);
      }
      final url = payment['authorizationUrl']?.toString();
      if (url == null || url.isEmpty) {
        throw const ApiException(
          'Payment provider did not return a checkout link.',
          kind: ApiErrorKind.provider,
        );
      }
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw const ApiException(
          'Could not open the payment checkout.',
          kind: ApiErrorKind.provider,
        );
      }
    } on ApiException catch (e) {
      // Refresh the activity list because the backend may have persisted a pending
      // payment intent even when the provider initialization response timed out.
      await load();
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyPending() => _reconcilePendingPayment(silent: false);

  Future<void> _reconcilePendingPayment({required bool silent}) async {
    if (reconcilingPayment || busy) return;
    final id = await storage.read(key: 'eazy.pendingPayment');
    if (id == null || id.isEmpty) {
      if (!silent) _showError('No pending payment found.');
      return;
    }
    reconcilingPayment = true;
    if (mounted) setState(() => busy = true);
    try {
      final result = await api.post('payments/$id/verify', auth: true);
      final transaction = _map(result['transaction']);
      final status = transaction['status']?.toString().toLowerCase();
      if (status != 'succeeded') {
        if (!silent) {
          _showMessage(
            'Payment is not confirmed yet. Your wallet has not been credited.',
          );
        }
        return;
      }
      await storage.delete(key: 'eazy.pendingPayment');
      await load();
      if (!silent && mounted) {
        _showMessage('Payment verified and wallet updated.');
      }
    } on ApiException catch (e) {
      if (!silent) {
        if (e.statusCode == 409 && e.message.toLowerCase().contains('not confirmed')) {
          _showMessage('This deposit is still awaiting provider confirmation. No wallet credit has been posted. Do not start another deposit yet.');
        } else if (e.statusCode == 503) {
          _showMessage('We could not check this deposit right now. It remains pending. Do not start another deposit yet.');
        } else {
          _showError(e.message);
        }
      }
    } finally {
      reconcilingPayment = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendToEazyUser() async {
    final searchInput = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Find an Eazy user'),
            content: TextField(
              controller: searchInput,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name or username',
                hintText: 'e.g. Ada Okafor or ada_okafor',
                prefixIcon: Icon(Icons.search_rounded),
                helperText: 'Search by the person’s name or Eazy username.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, searchInput.text.trim()),
                child: const Text('Search'),
              ),
            ],
          ),
    );
    searchInput.dispose();
    if (query == null) return;
    if (query.trim().length < 2) {
      _showError('Enter at least two characters to search.');
      return;
    }

    List<Map<String, dynamic>> matches;
    setState(() => busy = true);
    try {
      final result = await api.get(
        'profiles/search?q=${Uri.encodeQueryComponent(query.trim())}',
        auth: true,
      );
      matches =
          (result['items'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
    } on ApiException catch (e) {
      _showError(e.message);
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    if (matches.isEmpty) {
      _showError(
        'No Eazy users matched “$query”. Check the spelling and try again.',
      );
      return;
    }

    final recipient = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Choose recipient'),
            content: SizedBox(
              width: double.maxFinite,
              height: (matches.length * 72.0).clamp(72.0, 360.0),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: matches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = matches[index];
                  final name =
                      (item['displayName'] ??
                              item['firstName'] ??
                              item['username'] ??
                              'Eazy user')
                          .toString();
                  final handle = (item['username'] ?? '').toString();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        name.isEmpty
                            ? 'E'
                            : name.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('@$handle'),
                    onTap: () => Navigator.pop(dialogContext, item),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
    if (recipient == null || !mounted) return;
    final handle =
        (recipient['username'] ?? '').toString().trim().toLowerCase();
    if (!_validUsername(handle)) {
      _showError('The selected Eazy profile has an invalid username.');
      return;
    }
    final displayName =
        (recipient['displayName'] ?? recipient['firstName'] ?? handle)
            .toString();

    final amount = await _amountDialog(
      title: 'Send to $displayName',
      action: 'Review transfer',
      showSuggestedAmounts: true,
    );
    if (amount == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Review transfer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You are sending to'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(displayName.characters.first.toUpperCase()),
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('@$handle'),
                ),
                const Divider(),
                _Info('Amount', '$_currency $amount'),
                _Info('Available balance', '$_currency $_balance'),
                const SizedBox(height: 10),
                const Text(
                  'Your device will ask you to authenticate before this transfer is submitted.',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continue securely'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => busy = true);
    try {
      final authenticated = await _authenticateTransfer(
        'Authorize sending $_currency $amount to @$handle',
      );
      if (!authenticated) return;
      final paymentPin = await _requestPaymentPin();
      if (paymentPin == null || !mounted) return;
      await api.post(
        'wallet/transfers',
        auth: true,
        headers: {
          'Idempotency-Key': idempotency('transfer'),
          'X-Payment-PIN': paymentPin,
        },
        body: {
          'recipientUsername': handle,
          'amount': amount,
          'currency': _currency,
        },
      );
      await load();
      _showMessage(
        'Transfer submitted. Check wallet activity for its confirmed status.',
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(
        'Authentication could not be completed. No transfer was submitted.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _managePaymentPin() async {
    final currentPin = TextEditingController();
    final newPin = TextEditingController();
    final confirmation = TextEditingController();
    final changing = paymentPinConfigured;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(changing ? 'Change payment PIN' : 'Create payment PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (changing) ...[
              TextField(
                controller: currentPin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Current 6-digit PIN'),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: newPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: changing ? 'New 6-digit PIN' : '6-digit PIN'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmation,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
            const SizedBox(height: 6),
            Text(
              'Use a PIN you do not use for your bank card or other accounts.',
              style: TextStyle(color: context.eazyMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (changing)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reset'),
              child: const Text('Forgot PIN?'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(changing ? 'Save new PIN' : 'Create PIN'),
          ),
        ],
      ),
    );
    if (action != null && mounted) {
      try {
        if (action == 'reset') {
          await api.post(
            'wallet/payment-pin/reset',
            auth: true,
            body: {'pin': newPin.text, 'confirmation': confirmation.text},
          );
        } else if (changing) {
          await api.post(
            'wallet/payment-pin/change',
            auth: true,
            body: {
              'currentPin': currentPin.text,
              'newPin': newPin.text,
              'confirmation': confirmation.text,
            },
          );
        } else {
          await api.post(
            'wallet/payment-pin/setup',
            auth: true,
            body: {'pin': newPin.text, 'confirmation': confirmation.text},
          );
        }
        if (mounted) {
          setState(() => paymentPinConfigured = true);
          _showMessage(action == 'reset' ? 'Payment PIN reset.' : changing ? 'Payment PIN updated.' : 'Payment PIN created.');
        }
      } on ApiException catch (e) {
        _showError(e.message);
      }
    }
    currentPin.dispose();
    newPin.dispose();
    confirmation.dispose();
  }

  Future<String?> _requestPaymentPin() async {
    if (!paymentPinConfigured) {
      _showError('Create a payment PIN in Wallet settings before sending money.');
      return null;
    }
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter payment PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '6-digit payment PIN',
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
              if (controller.text.length == 6) {
                Navigator.pop(dialogContext, controller.text);
              }
            },
            child: const Text('Authorize'),
          ),
        ],
      ),
    );
    controller.dispose();
    return pin;
  }

  Future<bool> _authenticateTransfer(String reason) async {
    final localAuth = LocalAuthentication();
    final supported = await localAuth.isDeviceSupported();
    final canCheck = await localAuth.canCheckBiometrics;
    if (!supported && !canCheck) {
      throw const ApiException(
        'Set up a device screen lock or biometric authentication before sending money.',
        kind: ApiErrorKind.validation,
      );
    }
    final authenticated = await localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
    if (!authenticated) return false;
    return true;
  }

  Future<void> sendToExternalBank() async {
    List<Map<String, dynamic>> availableBanks;
    setState(() => busy = true);
    try {
      final result = await api.get('banks?currency=$_currency', auth: true);
      availableBanks =
          (result['banks'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => item['active'] != false)
              .toList();
    } on ApiException catch (e) {
      _showError(e.message);
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    if (availableBanks.isEmpty) {
      _showError(
        'External bank transfers are unavailable because no supported banks were returned by the payment provider.',
      );
      return;
    }

    final accountNumber = TextEditingController();
    String? selectedBankCode;
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Choose bank recipient'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedBankCode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Bank'),
                        items:
                            availableBanks
                                .map(
                                  (bank) => DropdownMenuItem<String>(
                                    value: bank['code'].toString(),
                                    child: Text(
                                      bank['name'].toString(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (value) =>
                                setDialogState(() => selectedBankCode = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: accountNumber,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        decoration: const InputDecoration(
                          labelText: '10-digit account number',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Eazy will resolve and display the account name before you enter an amount.',
                        style: TextStyle(
                          color: EazyColors.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          selectedBankCode == null
                              ? null
                              : () => Navigator.pop(dialogContext, {
                                'accountNumber': accountNumber.text.trim(),
                                'bankCode': selectedBankCode!,
                                'bankName':
                                    availableBanks
                                        .firstWhere(
                                          (bank) =>
                                              bank['code'].toString() ==
                                              selectedBankCode,
                                        )['name']
                                        .toString(),
                              }),
                      child: const Text('Resolve account'),
                    ),
                  ],
                ),
          ),
    );
    accountNumber.dispose();
    if (details == null) return;

    final number = details['accountNumber'] ?? '';
    final code = details['bankCode'] ?? '';
    final selectedBank = details['bankName'] ?? '';
    if (!RegExp(r'^\d{10}$').hasMatch(number) || code.length < 2) {
      _showError('Enter a valid 10-digit account number and bank code.');
      return;
    }

    Map<String, dynamic> account;
    setState(() => busy = true);
    try {
      final resolved = await api.post(
        'banks/resolve',
        auth: true,
        body: {'accountNumber': number, 'bankCode': code},
      );
      account = _map(resolved['account']);
      if ((account['accountName']?.toString() ?? '').trim().isEmpty) {
        throw const ApiException(
          'The bank did not return a verified account name.',
        );
      }
    } on ApiException catch (e) {
      _showError(e.message);
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;

    final accountName = account['accountName'].toString();
    final amount = await _amountDialog(
      title: 'Send to $accountName',
      action: 'Review transfer',
    );
    if (amount == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Review bank transfer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Verified recipient'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.account_balance_rounded),
                  ),
                  title: Text(
                    accountName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('$selectedBank · $number'),
                ),
                const Divider(),
                _Info('Amount', '$_currency $amount'),
                _Info('Available balance', '$_currency $_balance'),
                const SizedBox(height: 10),
                const Text(
                  'Authenticate on this device before submitting the transfer.',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continue securely'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => busy = true);
    try {
      final authenticated = await _authenticateTransfer(
        'Authorize sending $_currency $amount to $accountName',
      );
      if (!authenticated) return;
      final paymentPin = await _requestPaymentPin();
      if (paymentPin == null || !mounted) return;
      await api.post(
        'bank-transfers',
        auth: true,
        headers: {
          'Idempotency-Key': idempotency('bank-transfer'),
          'X-Payment-PIN': paymentPin,
        },
        body: {
          'accountNumber': number,
          'bankCode': code,
          'accountName': accountName,
          'bankName': selectedBank,
          'amount': amount,
          'currency': _currency,
        },
      );
      await load();
      _showMessage(
        'Bank transfer submitted. Check wallet activity for its confirmed status.',
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(
        'Authentication could not be completed. No transfer was submitted.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receiveFromEazyUser() async {
    setState(() => busy = true);
    try {
      final result = await api.post(
        'wallet/qr',
        auth: true,
        body: {'expiresInDays': 30},
      );
      receiveQr = _map(result['qr']);
      if (mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ReceiveQrSheet(qr: receiveQr!, username: _username),
        );
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receiveFromExternalBank() async {
    if (virtualAccount == null) {
      await requestVirtualAccount();
    }
    if (!mounted || virtualAccount == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _BankReceiveSheet(account: virtualAccount!),
    );
  }

  Future<void> requestVirtualAccount() async {
    if (virtualAccount != null || busy) return;
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create your dedicated bank account?'),
        content: const Text(
          'Eazy will ask its bank provider to assign a dedicated NGN account '
          'for receiving transfers. Your account name, email address and phone '
          'number from your Eazy profile will be shared with the provider for '
          'this purpose. Account assignment depends on provider approval. '
          'You can cancel without creating an account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I agree, continue'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await api.post(
        'wallet/virtual-account',
        auth: true,
        body: {'consent': true},
      );
      virtualAccount = _map(result['virtualAccount']);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scanQr() async {
    final token = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));
    if (!mounted || token == null || token.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await api.post(
        'wallet/qr/resolve',
        auth: true,
        body: {'token': token},
      );
      final recipient = _map(result['recipient']);
      if (!mounted) return;
      setState(() => busy = false);
      final amount = await _amountDialog(
        title: 'Pay ${recipient['displayName'] ?? 'Eazy user'}',
        action: 'Review payment',
      );
      if (amount == null) return;
      await _confirmAndRun(
        title: 'Confirm QR payment',
        message:
            'Pay $_currency $amount to ${recipient['displayName'] ?? recipient['username'] ?? 'this Eazy user'}?',
        action: (paymentPin) => api.post(
          'wallet/qr/pay',
          auth: true,
          headers: {
            'Idempotency-Key': idempotency('qr-payment'),
            'X-Payment-PIN': paymentPin,
          },
          body: {'token': token, 'amount': amount, 'currency': _currency},
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _amountDialog({
    required String title,
    required String action,
    bool showSuggestedAmounts = false,
  }) async {
    final controller = TextEditingController();
    const suggestions = <({String label, String value})>[
      (label: '500', value: '500'),
      (label: '1,000', value: '1000'),
      (label: '2,000', value: '2000'),
      (label: '5,000', value: '5000'),
      (label: '10,000', value: '10000'),
    ];
    final result = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: Text(title),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9,.]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: '$_currency ',
                          hintText: '5000',
                        ),
                      ),
                      if (showSuggestedAmounts) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Suggested amounts',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final suggestion in suggestions)
                              ActionChip(
                                label: Text(suggestion.label),
                                onPressed: () {
                                  setDialogState(() {
                                    controller.text = suggestion.value;
                                    controller.selection =
                                        TextSelection.collapsed(
                                          offset: controller.text.length,
                                        );
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          () => Navigator.pop(
                            dialogContext,
                            controller.text.trim(),
                          ),
                      child: Text(action),
                    ),
                  ],
                ),
          ),
    );
    controller.dispose();
    if (result == null) return null;
    final normalized = normalizeWalletAmountInput(result);
    if (normalized == null) {
      _showError('Enter a valid amount greater than zero.');
      return null;
    }
    return normalized;
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<Map<String, dynamic>> Function(String paymentPin) action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      final authenticated = await _authenticateTransfer('Authorize this QR payment');
      if (!authenticated) return;
      final paymentPin = await _requestPaymentPin();
      if (paymentPin == null || !mounted) return;
      await action(paymentPin);
      await load();
      _showMessage('Transfer completed and wallet activity refreshed.');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Payment authorization could not be completed. No payment was submitted.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String get _currency => wallet?['currency']?.toString() ?? 'NGN';
  String get _username =>
      username ?? wallet?['username']?.toString() ?? 'your Eazy username';
  String get _balance => wallet?['balance']?.toString() ?? '0.00';
  bool _validUsername(String value) =>
      RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value);
  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _showMoreOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    'Wallet tools',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('Manage payments and account activity.'),
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: const Text('Orders'),
                  subtitle: const Text('View marketplace purchases'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showOrders();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Wallet settings'),
                  subtitle: const Text('Privacy and payment security'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showWalletSettings();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('Verify pending payment'),
                  subtitle: const Text(
                    'Re-check a deposit with the payment provider',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    verifyPending();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Transaction history'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showAllTransactions();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showWalletSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (sheetContext, setSheetState) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const ListTile(
                        title: Text(
                          'Wallet settings',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          'Your balance is always calculated by the server ledger.',
                        ),
                      ),
                      SwitchListTile(
                        value: balanceVisible,
                        title: const Text('Show balance'),
                        subtitle: const Text(
                          'Hide amounts on this device when switched off.',
                        ),
                        onChanged: (value) async {
                          setState(() => balanceVisible = value);
                          setSheetState(() {});
                          await storage.write(
                            key: 'eazy.wallet.balanceVisible',
                            value: value.toString(),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.password_rounded),
                        title: Text(paymentPinConfigured ? 'Change payment PIN' : 'Create payment PIN'),
                        subtitle: Text(
                          paymentPinConfigured
                              ? 'Update the 6-digit PIN used to authorize payments.'
                              : 'Create a 6-digit PIN required before sending money.',
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _managePaymentPin();
                        },
                      ),
                      const ListTile(
                        leading: Icon(Icons.fingerprint_rounded),
                        title: Text('Transfer authentication'),
                        subtitle: Text(
                          'Device screen lock or biometrics are required before submitting a transfer.',
                        ),
                      ),
                      const ListTile(
                        leading: Icon(Icons.shield_outlined),
                        title: Text('Payment confirmation'),
                        subtitle: Text(
                          'Wallet deposits are credited only after server-side provider verification.',
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _showOrders() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: FutureBuilder<Map<String, dynamic>>(
              future: api.get('orders?page=1&limit=20', auth: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load orders: ${snapshot.error}'),
                  );
                }
                final orders =
                    (snapshot.data?['items'] as List? ?? const [])
                        .whereType<Map>()
                        .map((item) => Map<String, dynamic>.from(item))
                        .toList();
                if (orders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'No orders yet. Marketplace purchases will appear here.',
                    ),
                  );
                }
                return SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Orders',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final order in orders)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.shopping_bag_outlined),
                            ),
                            title: Text(
                              'Order ${(order['id'] ?? '').toString().length > 8 ? (order['id'] as String).substring(0, 8) : order['id'] ?? 'Order'}',
                            ),
                            subtitle: Text(
                              '${order['status'] ?? 'pending'} · ${order['createdAt'] ?? ''}',
                            ),
                            trailing: Text(
                              '${order['currency'] ?? _currency} ${order['total'] ?? order['amount'] ?? '0.00'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
    );
  }

  Future<void> _readWalletAlert(String id) async {
    try {
      await api.post('notifications/$id/read', auth: true);
      await load();
    } catch (_) {}
  }

  Future<void> _showAllTransactions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TransactionHistorySheet(
        api: api,
        currency: _currency,
        balanceVisible: balanceVisible,
        onOpenTransaction: _showTransactionDetails,
      ),
    );
  }

  Future<void> _showTransactionDetails(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString();
    Map<String, dynamic> detail = entry;
    if (id != null && id.isNotEmpty) {
      try {
        final result = await api.get('wallet/transactions/$id', auth: true);
        final fetched = _map(result['transaction']);
        if (fetched.isNotEmpty) detail = fetched;
      } on ApiException {
        detail = entry;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Transaction details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Info('Type', detail['type']?.toString() ?? 'Transaction'),
                _Info('Status', detail['status']?.toString() ?? 'unknown'),
                _Info(
                  'Amount',
                  balanceVisible
                      ? '${detail['currency'] ?? _currency} ${detail['amount'] ?? '0.00'}'
                      : '••••••',
                ),
                _Info(
                  'Reference',
                  detail['reference']?.toString() ?? 'Not available',
                ),
                _Info(
                  'Date',
                  detail['createdAt']?.toString() ?? 'Not available',
                ),
              ],
            ),
            actions: [
              if (id != null &&
                  id.isNotEmpty &&
                  detail['type']?.toString().toLowerCase() == 'deposit' &&
                  detail['status']?.toString().toLowerCase() == 'pending')
                TextButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await storage.write(key: 'eazy.pendingPayment', value: id);
                    await _reconcilePendingPayment(silent: false);
                  },
                  child: const Text('Verify payment'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _showSendOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const ListTile(
                  title: Text(
                    'Send money',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('Choose where the money should go.'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Send to an Eazy user'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    sendToEazyUser();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Send to an external bank'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    sendToExternalBank();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showReceiveOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const ListTile(
                  title: Text(
                    'Receive money',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('Receive from Eazy or an external bank.'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.add_card_rounded,
                    color: EazyColors.green,
                  ),
                  title: const Text(
                    'Add money online',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text(
                    'Fund your wallet through secure Paystack checkout',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    deposit();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: const Text('Receive from an Eazy user'),
                  subtitle: Text('Show your QR code or username: @$_username'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    receiveFromEazyUser();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_rounded),
                  title: const Text('Receive from an external bank'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    receiveFromExternalBank();
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Wallet',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ),
              IconButton(
                onPressed: loading ? null : load,
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF168C58), Color(0xFF075B3A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: EazyColors.greenDeep.withValues(alpha: .28),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total Balance',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: balanceVisible ? 'Hide balance' : 'Show balance',
                      onPressed: _toggleBalanceVisibility,
                      icon: Icon(
                        balanceVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  loading || !balanceVisible
                      ? '$_currency ••••••'
                      : '$_currency $_balance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Available for transfers and payments',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.arrow_upward_rounded,
                        label: 'Send',
                        onTap: busy ? null : _showSendOptions,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.arrow_downward_rounded,
                        label: 'Receive',
                        onTap: busy ? null : _showReceiveOptions,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.qr_code_scanner_rounded,
                        label: 'Scan QR',
                        onTap: busy ? null : scanQr,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.grid_view_rounded,
                        label: 'More',
                        onTap: busy ? null : _showMoreOptions,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: EazyColors.red)),
          ],
          if (pendingDeposit != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Deposit awaiting confirmation',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          (pendingDeposit?['currency']?.toString() == 'NGN'
                                  ? '₦'
                                  : (pendingDeposit?['currency']?.toString() ?? _currency) + ' ') +
                              (pendingDeposit?['amount']?.toString() ?? '0.00'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This deposit has not been credited yet. Check its status before starting another funding attempt.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : verifyPending,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Check payment status'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (walletAlerts.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wallet alerts',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                Text('${walletAlerts.length}'),
              ],
            ),
            const SizedBox(height: 10),
            ...walletAlerts.take(5).map((alert) {
              final id = alert['id']?.toString();
              final isRead = alert['isRead'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: EazyColors.green.withValues(alpha: .12),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: EazyColors.green,
                    ),
                  ),
                  title: Text(
                    alert['title']?.toString() ?? 'Wallet update',
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(alert['body']?.toString() ?? ''),
                  trailing: isRead
                      ? null
                      : const Icon(Icons.circle, size: 9, color: EazyColors.green),
                  onTap: id == null ? null : () => _readWalletAlert(id),
                ),
              );
            }),
            const SizedBox(height: 14),
          ],
                    const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Transaction history',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: _showAllTransactions,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (transactions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  'No transactions yet.',
                  style: TextStyle(color: EazyColors.muted),
                ),
              ),
            )
          else
            ...transactions.map(
              (entry) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: EazyColors.green.withValues(alpha: .12),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: EazyColors.green,
                    ),
                  ),
                  title: Text(
                    entry['type']?.toString() ?? 'Transaction',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    entry['status']?.toString() ?? '',
                    style: const TextStyle(color: EazyColors.muted),
                  ),
                  trailing: Text(
                    balanceVisible
                        ? '${entry['currency'] ?? _currency} ${entry['amount'] ?? '0.00'}'
                        : '••••••',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  onTap: () => _showTransactionDetails(entry),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TransactionHistorySheet extends StatefulWidget {
  const _TransactionHistorySheet({
    required this.api,
    required this.currency,
    required this.balanceVisible,
    required this.onOpenTransaction,
  });

  final ApiClient api;
  final String currency;
  final bool balanceVisible;
  final Future<void> Function(Map<String, dynamic> entry) onOpenTransaction;

  @override
  State<_TransactionHistorySheet> createState() => _TransactionHistorySheetState();
}

class _TransactionHistorySheetState extends State<_TransactionHistorySheet> {
  static const _pageSize = 20;
  final _items = <Map<String, dynamic>>[];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage({bool refresh = false}) async {
    if (_loading || (!refresh && !_hasMore)) return;
    final nextPage = refresh ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) _hasMore = true;
    });
    try {
      final result = await widget.api.get(
        'wallet/transactions?page=$nextPage&limit=$_pageSize',
        auth: true,
      );
      final entries = (result['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final meta = result['meta'] is Map
          ? Map<String, dynamic>.from(result['meta'] as Map)
          : <String, dynamic>{};
      final totalPages = int.tryParse(meta['pages']?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        if (refresh) _items.clear();
        final existingIds = _items.map((item) => item['id']?.toString()).toSet();
        _items.addAll(entries.where(
          (item) => !existingIds.contains(item['id']?.toString()),
        ));
        _page = nextPage;
        _hasMore = totalPages != null
            ? nextPage < totalPages
            : entries.length == _pageSize;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load transaction history. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              'Transaction history',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadPage(refresh: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                itemCount: _items.isEmpty ? 2 : _items.length + 1,
                itemBuilder: (context, index) {
                  if (_items.isEmpty && index == 0) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_error != null) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () => _loadPage(refresh: true),
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('No transactions yet.'),
                    );
                  }
                  if (index == _items.length) {
                    if (_error != null) {
                      return Center(
                        child: TextButton(
                          onPressed: _loadPage,
                          child: const Text('Could not load more. Try again'),
                        ),
                      );
                    }
                    if (_hasMore) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : OutlinedButton(
                                  onPressed: _loadPage,
                                  child: const Text('Load more'),
                                ),
                        ),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: Text('You are all caught up.')),
                    );
                  }
                  final entry = _items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: Text(entry['type']?.toString() ?? 'Transaction'),
                      subtitle: Text(
                        '${entry['status'] ?? 'unknown'} · ${entry['createdAt'] ?? ''}',
                      ),
                      trailing: Text(
                        widget.balanceVisible
                            ? '${entry['currency'] ?? widget.currency} ${entry['amount'] ?? '0.00'}'
                            : '••••••',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => widget.onOpenTransaction(entry),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WalletAction extends StatelessWidget {
  const _WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: Colors.white, size: 29),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(color: EazyColors.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _ReceiveQrSheet extends StatelessWidget {
  const _ReceiveQrSheet({required this.qr, required this.username});
  final Map<String, dynamic> qr;
  final String username;
  @override
  Widget build(BuildContext context) {
    final content = qr['content']?.toString() ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Receive from an Eazy user',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Share this QR or your username: @$username',
              textAlign: TextAlign.center,
              style: const TextStyle(color: EazyColors.muted),
            ),
            const SizedBox(height: 18),
            if (content.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(data: content, size: 220),
              ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('QR token copied.')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy QR token'),
            ),
            const SizedBox(height: 8),
            Text(
              'Expires ${qr['expiresAt'] ?? 'soon'}',
              style: const TextStyle(color: EazyColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankReceiveSheet extends StatelessWidget {
  const _BankReceiveSheet({required this.account});
  final Map<String, dynamic> account;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Receive from an external bank',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Give these details to the sender. Eazy will update the wallet only after the configured bank webhook confirms the deposit.',
            style: TextStyle(color: EazyColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _Info('Bank', account['bankName']?.toString() ?? 'Pending'),
          _Info(
            'Account number',
            account['accountNumber']?.toString() ?? 'Pending',
          ),
          _Info(
            'Account name',
            account['accountName']?.toString() ?? 'Pending',
          ),
          _Info('Status', account['status']?.toString() ?? 'pending'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text:
                        '${account['bankName'] ?? ''}\n${account['accountNumber'] ?? ''}\n${account['accountName'] ?? ''}',
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bank details copied.')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy bank details'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Scan Eazy QR',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (handled) return;
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value == null || value.isEmpty) return;
            handled = true;
            Navigator.pop(context, value);
          },
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: EazyColors.green, width: 3),
              borderRadius: BorderRadius.circular(26),
            ),
          ),
        ),
        const Positioned(
          left: 28,
          right: 28,
          bottom: 36,
          child: Text(
            'Point your camera at an Eazy receive QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
