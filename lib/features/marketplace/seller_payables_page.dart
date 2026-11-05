import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SellerPayablesPage extends StatefulWidget {
  const SellerPayablesPage({super.key});
  @override
  State<SellerPayablesPage> createState() => _SellerPayablesPageState();
}

class _SellerPayablesPageState extends State<SellerPayablesPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> entries = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('orders/seller/payables?page=1&limit=50', auth: true);
      if (!mounted) return;
      setState(() { entries = (result['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  String amount(Object? value) => '₦${((int.tryParse(value?.toString() ?? '') ?? 0) / 100).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seller payables')),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('Retry'))]))
      : entries.isEmpty ? const Center(child: Text('No held or released payables yet.'))
      : RefreshIndicator(onRefresh: load, child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: entries.length, itemBuilder: (context, i) {
        final item = entries[i];
        final released = item['entryType'] == 'release';
        return Card(child: ListTile(
          leading: Icon(released ? Icons.check_circle_outline : Icons.lock_clock_outlined),
          title: Text(released ? 'Released' : 'Held in escrow'),
          subtitle: Text('Order ${item['orderId']} · ${item['createdAt']}'),
          trailing: Text(amount(item['amountKobo']), style: const TextStyle(fontWeight: FontWeight.w800)),
        ));
      })),
  );
}
