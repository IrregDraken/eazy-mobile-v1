import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final api = ApiClient();
  final storage = const FlutterSecureStorage();
  bool loading = true;
  bool busy = false;
  String? error;
  Map<String, dynamic>? wallet;
  Map<String, dynamic>? virtualAccount;
  Map<String, dynamic>? receiveQr;
  String? username;
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  String idempotency(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> load() async {
    setState(() {
      loading = true;
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
      transactions =
          (transactionResult['items'] as List? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
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
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyPending() async {
    final id = await storage.read(key: 'eazy.pendingPayment');
    if (id == null || id.isEmpty) {
      _showError('No pending payment found.');
      return;
    }
    setState(() => busy = true);
    try {
      await api.post('payments/$id/verify', auth: true);
      await storage.delete(key: 'eazy.pendingPayment');
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment verified and wallet updated.')),
        );
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendToEazyUser() async {
    final username = TextEditingController();
    final amount = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Send to an Eazy user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Recipient username',
                    prefixText: '@ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '$_currency ',
                    hintText: '1000.00',
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
                    () => Navigator.pop(dialogContext, {
                      'username': username.text.trim(),
                      'amount': amount.text.trim(),
                    }),
                child: const Text('Review transfer'),
              ),
            ],
          ),
    );
    username.dispose();
    amount.dispose();
    if (values == null) return;
    final handle =
        values['username']?.replaceFirst('@', '').toLowerCase() ?? '';
    final value = values['amount'] ?? '';
    if (!_validUsername(handle) || !_validMoney(value)) {
      _showError('Enter a valid username and amount with two decimal places.');
      return;
    }
    await _confirmAndRun(
      title: 'Confirm Eazy transfer',
      message:
          'Send $_currency $value to @$handle? Your wallet balance will be debited by the server.',
      action:
          () => api.post(
            'wallet/transfers',
            auth: true,
            headers: {'Idempotency-Key': idempotency('transfer')},
            body: {
              'recipientUsername': handle,
              'amount': value,
              'currency': _currency,
            },
          ),
    );
  }

  Future<void> sendToExternalBank() async {
    final accountNumber = TextEditingController();
    final bankCode = TextEditingController();
    final bankName = TextEditingController();
    final amount = TextEditingController();
    final reason = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Send to an external bank'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: accountNumber,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Account number',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bankCode,
                    decoration: const InputDecoration(labelText: 'Bank code'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bankName,
                    decoration: const InputDecoration(
                      labelText: 'Bank name (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '$_currency ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    maxLength: 140,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Account resolution and transfer status are controlled by the bank provider. Eazy will show an unavailable state if it is not configured.',
                    style: TextStyle(
                      color: EazyColors.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, {
                      'accountNumber': accountNumber.text.trim(),
                      'bankCode': bankCode.text.trim(),
                      'bankName': bankName.text.trim(),
                      'amount': amount.text.trim(),
                      'reason': reason.text.trim(),
                    }),
                child: const Text('Resolve account'),
              ),
            ],
          ),
    );
    for (final controller in [
      accountNumber,
      bankCode,
      bankName,
      amount,
      reason,
    ]) {
      controller.dispose();
    }
    if (values == null) return;
    final number = values['accountNumber'] ?? '';
    final code = values['bankCode'] ?? '';
    final value = values['amount'] ?? '';
    if (!RegExp(r'^\d{10}$').hasMatch(number) ||
        code.length < 2 ||
        !_validMoney(value)) {
      _showError('Enter a valid 10-digit account, bank code, and amount.');
      return;
    }
    setState(() => busy = true);
    try {
      final resolved = await api.post(
        'banks/resolve',
        auth: true,
        body: {'accountNumber': number, 'bankCode': code},
      );
      final account = _map(resolved['account']);
      final resolvedName =
          account['accountName']?.toString() ?? values['bankName'] ?? '';
      if (resolvedName.isEmpty)
        throw const ApiException('The bank did not return an account name.');
      if (!mounted) return;
      setState(() => busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Confirm bank recipient'),
              content: Text(
                'Send $_currency $value to $resolvedName at ${values['bankName']?.isEmpty == true ? 'the selected bank' : values['bankName']}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Send securely'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
      setState(() => busy = true);
      await api.post(
        'bank-transfers',
        auth: true,
        headers: {'Idempotency-Key': idempotency('bank-transfer')},
        body: {
          'accountNumber': number,
          'bankCode': code,
          'accountName': resolvedName,
          'bankName': values['bankName'],
          'amount': value,
          'currency': _currency,
          'reason': values['reason'],
        },
      );
      await load();
      _showMessage(
        'Bank transfer initiated. Check its status in wallet activity.',
      );
    } on ApiException catch (e) {
      _showError(e.message);
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
        action:
            () => api.post(
              'wallet/qr/pay',
              auth: true,
              headers: {'Idempotency-Key': idempotency('qr-payment')},
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
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$_currency ',
                hintText: '1000.00',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, controller.text.trim()),
                child: Text(action),
              ),
            ],
          ),
    );
    controller.dispose();
    if (result == null || !_validMoney(result)) {
      if (result != null)
        _showError('Enter an amount with two decimal places.');
      return null;
    }
    return result;
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<Map<String, dynamic>> Function() action,
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
      await action();
      await load();
      _showMessage('Transfer completed and wallet activity refreshed.');
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showError(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _currency => wallet?['currency']?.toString() ?? 'NGN';
  String get _username =>
      username ?? wallet?['username']?.toString() ?? 'your Eazy username';
  String get _balance => wallet?['balance']?.toString() ?? '0.00';
  String get _heldBalance => wallet?['heldBalance']?.toString() ?? '0.00';
  bool _validMoney(String value) =>
      RegExp(r'^(?:0|[1-9][0-9]{0,17})\.[0-9]{2}$').hasMatch(value);
  bool _validUsername(String value) =>
      RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value);
  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

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
                      onPressed: () {},
                      icon: const Icon(
                        Icons.visibility_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  loading ? '••••••' : '$_currency $_balance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Held balance  $_currency $_heldBalance',
                  style: const TextStyle(
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
                  ],
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: EazyColors.red)),
          ],
          const SizedBox(height: 22),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push('/assist'),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: EazyColors.green.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: EazyColors.green,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Easy Access',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap to open Eazy Assist and get help with your wallet.',
                            style: TextStyle(
                              color: EazyColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: EazyColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Transaction history',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
                    '${entry['currency'] ?? _currency} ${entry['amount'] ?? '0.00'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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
