import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../home/home_shell.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  Map<String, dynamic>? wallet;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final json = await api.get('me/wallet', auth: true);
      wallet = Map<String, dynamic>.from((json['wallet'] as Map?) ?? {});
    } on ApiException catch (e) { error = e.message; }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
    EazyPageHeader(title: 'Wallet', subtitle: 'Your money, clearly organised', trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _Balance(wallet: wallet, loading: loading)),
    const SizedBox(height: 16),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
      Expanded(child: _Action(icon: Icons.arrow_upward_rounded, label: 'Send')),
      const SizedBox(width: 10),
      Expanded(child: _Action(icon: Icons.add_rounded, label: 'Add money')),
      const SizedBox(width: 10),
      Expanded(child: _Action(icon: Icons.receipt_long_rounded, label: 'History')),
    ])),
    const SizedBox(height: 24),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(error!, style: const TextStyle(color: EazyColors.muted))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Recent activity', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
    const SizedBox(height: 10),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Card(child: Padding(padding: EdgeInsets.all(24), child: Row(children: [Icon(Icons.receipt_long_outlined, color: EazyColors.muted), SizedBox(width: 12), Expanded(child: Text('No transactions to show yet.', style: TextStyle(color: EazyColors.muted)))])))),
  ])));

}

class _Balance extends StatelessWidget {
  const _Balance({required this.wallet, required this.loading});
  final Map<String, dynamic>? wallet;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final minor = wallet?['availableBalanceMinor'];
    final amount = minor is num ? minor / 100 : 0;
    return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(EazyRadius.xl), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [EazyColors.greenDeep, Color(0xFF0B4D32)])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Text('Available balance', style: TextStyle(color: Colors.white70)), Spacer(), Icon(Icons.shield_outlined, color: Colors.white70)]),
      const SizedBox(height: 10),
      Text(loading ? '••••••' : '₦' + amount.toStringAsFixed(2), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
      const SizedBox(height: 18),
      Text(wallet?['status']?.toString() ?? 'Eazy Wallet', style: const TextStyle(color: Colors.white70)),
    ]);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 17), child: Column(children: [Icon(icon, color: EazyColors.green), const SizedBox(height: 7), Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))])));
}
