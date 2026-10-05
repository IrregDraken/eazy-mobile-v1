import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final api = ApiClient();
  final storage = const FlutterSecureStorage();
  bool loading = true, busy = false;
  String? error;
  Map<String, dynamic>? wallet;
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic>? virtualAccount;

  @override void initState() { super.initState(); load(); }

  String idempotency(String prefix) =>
      prefix + '-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + Random.secure().nextInt(1 << 32).toString();

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      var result = await api.get('wallet', auth: true);
      wallet = result['wallet'] is Map ? Map<String, dynamic>.from(result['wallet'] as Map) : null;
      if (wallet == null) {
        result = await api.post('wallet', auth: true, body: {'currency': 'NGN'});
        wallet = result['wallet'] is Map ? Map<String, dynamic>.from(result['wallet'] as Map) : null;
      }
      final transactionResult = await api.get('wallet/transactions?page=1&limit=20', auth: true);
      transactions = (transactionResult['items'] as List? ?? const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      try {
        final accountResult = await api.get('wallet/virtual-account', auth: true);
        virtualAccount = accountResult['virtualAccount'] is Map
            ? Map<String, dynamic>.from(accountResult['virtualAccount'] as Map)
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
    final controller = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add money'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₦ ', hintText: '1000.00'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !RegExp(r'^(?:0|[1-9][0-9]{0,17})\.[0-9]{2}$').hasMatch(amount)) return;

    setState(() => busy = true);
    try {
      final result = await api.post(
        'payments/initialize',
        auth: true,
        headers: {'Idempotency-Key': idempotency('deposit')},
        body: {'purpose': 'wallet_deposit', 'amount': amount, 'currency': 'NGN'},
      );
      final payment = result['payment'] is Map ? Map<String, dynamic>.from(result['payment'] as Map) : <String, dynamic>{};
      final transaction = result['transaction'] is Map ? Map<String, dynamic>.from(result['transaction'] as Map) : <String, dynamic>{};
      final transactionId = transaction['id']?.toString();
      if (transactionId != null) await storage.write(key: 'eazy.pendingPayment', value: transactionId);
      final url = payment['authorizationUrl']?.toString();
      if (url == null || url.isEmpty) throw const ApiException('Payment provider did not return a checkout link.', kind: ApiErrorKind.provider);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw const ApiException('Could not open the payment checkout.', kind: ApiErrorKind.provider);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyPending() async {
    final id = await storage.read(key: 'eazy.pendingPayment');
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pending payment found.')));
      return;
    }
    setState(() => busy = true);
    try {
      await api.post('payments/' + id + '/verify', auth: true);
      await storage.delete(key: 'eazy.pendingPayment');
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment verified and wallet updated.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transfer() async {
    final username = TextEditingController();
    final amount = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send money'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Recipient username', prefixText: '@ ')),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '₦ ', hintText: '1000.00')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {'username': username.text.trim(), 'amount': amount.text.trim()}), child: const Text('Send')),
        ],
      ),
    );
    username.dispose();
    amount.dispose();
    if (values == null) return;

    final handle = values['username'] ?? '';
    final value = values['amount'] ?? '';
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(handle.toLowerCase()) ||
        !RegExp(r'^(?:0|[1-9][0-9]{0,17})\.[0-9]{2}$').hasMatch(value)) return;

    setState(() => busy = true);
    try {
      await api.post(
        'wallet/transfers',
        auth: true,
        headers: {'Idempotency-Key': idempotency('transfer')},
        body: {'recipientUsername': handle.toLowerCase(), 'amount': value, 'currency': 'NGN'},
      );
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Money sent successfully.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestVirtualAccount() async {
    setState(() => busy = true);
    try {
      final result = await api.post('wallet/virtual-account', auth: true, body: {'consent': true});
      virtualAccount = result['virtualAccount'] is Map ? Map<String, dynamic>.from(result['virtualAccount'] as Map) : null;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override Widget build(BuildContext context) {
    final currency = wallet?['currency']?.toString() ?? 'NGN';
    final balance = wallet?['balance']?.toString() ?? '0.00';
    return SafeArea(child: RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Wallet', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            SizedBox(height: 3), Text('Your money, clearly organised', style: TextStyle(color: EazyColors.muted)),
          ])),
          IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [EazyColors.greenDeep, Color(0xFF0B4D32)],
          )),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Available balance', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(loading ? '••••••' : currency + ' ' + balance, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 14),
            Text(wallet?['status']?.toString() ?? 'Wallet', style: const TextStyle(color: Colors.white70)),
          ]),
        )),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          Expanded(child: _Action(icon: Icons.arrow_upward_rounded, label: 'Send', onTap: busy ? null : transfer)),
          const SizedBox(width: 10),
          Expanded(child: _Action(icon: Icons.add_rounded, label: 'Add money', onTap: busy ? null : deposit)),
          const SizedBox(width: 10),
          Expanded(child: _Action(icon: Icons.verified_outlined, label: 'Verify', onTap: busy ? null : verifyPending)),
        ])),
        if (error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Text(error!, style: const TextStyle(color: EazyColors.red))),
        const SizedBox(height: 18),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.account_balance_outlined, color: EazyColors.green), SizedBox(width: 10), Text('Receive by bank', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))]),
          const SizedBox(height: 8),
          if (virtualAccount == null) ...[
            const Text('Create a dedicated NGN receiving account for bank deposits.', style: TextStyle(color: EazyColors.muted, height: 1.4)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy ? null : requestVirtualAccount, child: const Text('Create receiving account'))),
          ] else ...[
            _Info('Bank', virtualAccount!['bankName']?.toString() ?? 'Pending'),
            _Info('Account number', virtualAccount!['accountNumber']?.toString() ?? 'Pending'),
            _Info('Account name', virtualAccount!['accountName']?.toString() ?? 'Pending'),
            _Info('Status', virtualAccount!['status']?.toString() ?? 'pending'),
          ],
        ])))),
        const SizedBox(height: 20),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Recent activity', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Card(child: Padding(padding: EdgeInsets.all(22), child: Text('No transactions yet.', style: TextStyle(color: EazyColors.muted)))))
        else
          ...transactions.map((x) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: EazyColors.green.withValues(alpha: .12), child: const Icon(Icons.receipt_long_rounded, color: EazyColors.green)),
            title: Text(x['type']?.toString() ?? 'Transaction', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(x['status']?.toString() ?? '', style: const TextStyle(color: EazyColors.muted)),
            trailing: Text((x['currency']?.toString() ?? currency) + ' ' + (x['amount']?.toString() ?? '0.00'), style: const TextStyle(fontWeight: FontWeight.w900)),
          )))),
      ]),
    ));
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label, value;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 7), child: Row(children: [
    SizedBox(width: 105, child: Text(label, style: const TextStyle(color: EazyColors.muted, fontSize: 12))),
    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800))),
  ]));
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback? onTap;
  @override Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(EazyRadius.lg), child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(children: [Icon(icon, color: EazyColors.green), const SizedBox(height: 7), Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]),
  )));
}
