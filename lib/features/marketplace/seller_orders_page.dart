import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SellerOrdersPage extends StatefulWidget {
  const SellerOrdersPage({super.key});
  @override
  State<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends State<SellerOrdersPage> {
  final api = ApiClient();
  bool loading = true;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('orders/seller?page=1&limit=50', auth: true);
      if (!mounted) return;
      setState(() {
        orders = (result['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<String?> rejectionReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject order'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (controller.text.trim().length >= 5) Navigator.pop(dialogContext, controller.text.trim());
          }, child: const Text('Reject order')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> act(Map<String, dynamic> order, String action) async {
    final orderId = order['orderId']?.toString() ?? '';
    final fulfillmentId = order['fulfillmentId']?.toString() ?? '';
    if (orderId.isEmpty || fulfillmentId.isEmpty) return;
    String? reason;
    if (action == 'reject') {
      reason = await rejectionReason();
      if (reason == null) return;
    }
    setState(() => busy = true);
    try {
      await api.patch(
        'orders/$orderId/fulfillments/$fulfillmentId',
        auth: true,
        body: {'action': action, if (reason != null) 'reason': reason},
      );
      await load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String statusLabel(String status) => switch (status) {
    'pending' => 'Awaiting your decision',
    'accepted' => 'Accepted',
    'shipped' => 'Shipped',
    'delivered' => 'Delivered',
    'completed' => 'Completed',
    'cancelled' => 'Rejected or cancelled',
    'disputed' => 'Disputed',
    _ => status,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seller orders')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ]),
              ))
            : orders.isEmpty
                ? const Center(child: Text('No paid orders yet.'))
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final status = order['status']?.toString() ?? '';
                        final products = (order['items'] as List? ?? const []).whereType<Map>().toList();
                        final address = order['deliveryAddress'];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Order ${order['orderId']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text('${order['buyerDisplayName'] ?? 'Buyer'} · ${order['buyerUsername'] == null ? '' : '@${order['buyerUsername']}'}'),
                              const SizedBox(height: 4),
                              Text('${order['orderTotal'] ?? '0.00'} ${order['currency'] ?? 'NGN'} · ${statusLabel(status)}'),
                              const Divider(),
                              for (final item in products)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Text('${item['productName']} × ${item['quantity']}'),
                                ),
                              if (address is Map) ...[
                                const SizedBox(height: 8),
                                const Text('Delivery address', style: TextStyle(fontWeight: FontWeight.w800)),
                                Text(address.values.where((value) => value != null).join(', ')),
                              ] else if (order['deliveryMethod'] == 'pickup' && order['pickupInstructions'] != null)
                                Text('Pickup instructions: ${order['pickupInstructions']}'),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                if (status == 'pending') ...[
                                  FilledButton(onPressed: busy ? null : () => act(order, 'accept'), child: const Text('Accept')),
                                  const Text('Reject is disabled until verified refunds are available.'),
                                ],
                                if (status == 'accepted')
                                  FilledButton(onPressed: busy ? null : () => act(order, 'ship'), child: const Text('Mark shipped')),
                                if (status == 'shipped')
                                  FilledButton(onPressed: busy ? null : () => act(order, 'deliver'), child: const Text('Mark delivered')),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
  );
}
