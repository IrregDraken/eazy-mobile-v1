import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final api = ApiClient();
  bool loading = true;
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
      final result = await api.get('orders?page=1&limit=50', auth: true);
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

  String label(String status) => switch (status) {
    'pending' => 'Pending payment',
    'paid' => 'Paid and held',
    'accepted' => 'Accepted',
    'processing' => 'Processing',
    'shipped' => 'Shipped',
    'delivered' => 'Delivered',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    'disputed' => 'Disputed',
    'refunded' => 'Refunded',
    _ => status,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My orders')),
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
                ? const Center(child: Text('You have no orders yet.'))
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final id = order['id']?.toString() ?? '';
                        return Card(
                          child: ListTile(
                            title: Text('Order ${id.length > 8 ? id.substring(0, 8) : id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${order['currency'] ?? 'NGN'} ${order['total'] ?? '0.00'} · ${label(order['status']?.toString() ?? '')}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty ? null : () => context.push('/orders/$id').then((_) => load()),
                          ),
                        );
                      },
                    ),
                  ),
  );
}

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});
  final String orderId;
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final api = ApiClient();
  bool loading = true;
  bool busy = false;
  String? error;
  Map<String, dynamic>? order;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('orders/${widget.orderId}', auth: true);
      if (mounted) setState(() => order = Map<String, dynamic>.from(result['order'] as Map));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String statusLabel(String status) => switch (status) {
    'pending' => 'Pending payment',
    'paid' => 'Paid and held',
    'accepted' => 'Accepted',
    'processing' => 'Processing',
    'shipped' => 'Shipped',
    'delivered' => 'Delivered',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    'disputed' => 'Disputed',
    'refunded' => 'Refunded',
    _ => status,
  };

  Future<void> writeReview(String itemId) async {
    final reviewText = TextEditingController();
    int rating = 5;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, updateDialog) => AlertDialog(
        title: const Text('Review this item'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: rating,
              decoration: const InputDecoration(labelText: 'Rating'),
              items: List.generate(5, (index) => DropdownMenuItem(value: index + 1, child: Text('${index + 1} star${index == 0 ? '' : 's'}'))),
              onChanged: (value) { if (value != null) updateDialog(() => rating = value); },
            ),
            const SizedBox(height: 10),
            TextField(controller: reviewText, minLines: 3, maxLines: 5, maxLength: 1000, decoration: const InputDecoration(labelText: 'Your review')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (reviewText.text.trim().isNotEmpty) Navigator.pop(dialogContext, true);
          }, child: const Text('Submit review')),
        ],
      )),
    );
    if (submitted == true && mounted) {
      setState(() => busy = true);
      try {
        await api.post('orders/${widget.orderId}/items/$itemId/review', auth: true, body: {
          'rating': rating,
          'reviewText': reviewText.text.trim(),
        });
        await load();
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    reviewText.dispose();
  }

  Future<void> confirmReceived(String fulfillmentId) async {
    setState(() => busy = true);
    try {
      await api.post('orders/${widget.orderId}/fulfillments/$fulfillmentId/confirm', auth: true);
      await load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reportProblem(String fulfillmentId) async {
    final description = TextEditingController();
    String reason = 'not_received';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, updateDialog) => AlertDialog(
        title: const Text('Report an order problem'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: const [
                DropdownMenuItem(value: 'not_received', child: Text('I have not received it')),
                DropdownMenuItem(value: 'damaged', child: Text('Item arrived damaged')),
                DropdownMenuItem(value: 'wrong_item', child: Text('Wrong item')),
                DropdownMenuItem(value: 'missing_items', child: Text('Items are missing')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) { if (value != null) updateDialog(() => reason = value); },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Describe the problem'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (description.text.trim().length >= 10) Navigator.pop(dialogContext, true);
          }, child: const Text('Submit report')),
        ],
      )),
    );
    if (submitted == true && mounted) {
      setState(() => busy = true);
      try {
        await api.post(
          'orders/${widget.orderId}/fulfillments/$fulfillmentId/disputes',
          auth: true,
          body: {'reason': reason, 'description': description.text.trim(), 'photoStorageKeys': <String>[]},
        );
        await load();
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    description.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = order ?? const <String, dynamic>{};
    final items = (data['items'] as List? ?? const []).whereType<Map>().toList();
    final fulfillments = (data['fulfillments'] as List? ?? const []).whereType<Map>().toList();
    final timeline = (data['timeline'] as List? ?? const []).whereType<Map>().toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
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
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
                    children: [
                      Text(statusLabel(data['status']?.toString() ?? ''), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('Order reference: ${data['id']}'),
                      const SizedBox(height: 12),
                      Card(child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Items', style: TextStyle(fontWeight: FontWeight.w800)),
                          for (final item in items)
                            Column(children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item['productName']?.toString() ?? 'Product'),
                                subtitle: Text('Qty ${item['quantity']}'),
                                trailing: Text('${data['currency'] ?? 'NGN'} ${item['lineTotal'] ?? '0.00'}'),
                              ),
                              if (data['status'] == 'completed' && item['reviewed'] != true)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: busy ? null : () => writeReview(item['id'].toString()),
                                    icon: const Icon(Icons.star_outline_rounded),
                                    label: const Text('Write a review'),
                                  ),
                                ),
                            ]),
                          const Divider(),
                          _total('Items subtotal', data['subtotal']),
                          _total('Delivery', data['deliveryTotal']),
                          _total('Total', data['total'], strong: true),
                        ]),
                      )),
                      const SizedBox(height: 12),
                      const Text('Fulfilment', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      for (final raw in fulfillments)
                        Builder(builder: (context) {
                          final fulfillment = Map<String, dynamic>.from(raw);
                          final id = fulfillment['id']?.toString() ?? '';
                          final status = fulfillment['status']?.toString() ?? '';
                          final disputed = status == 'disputed' || fulfillment['hasOpenDispute'] == true;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(fulfillment['sellerDisplayName']?.toString() ?? 'Seller', style: const TextStyle(fontWeight: FontWeight.w800)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: (fulfillment['sellerUsername']?.toString().isNotEmpty ?? false)
                                        ? () => context.go('/home?tab=chat&username=${Uri.encodeComponent(fulfillment['sellerUsername'].toString())}')
                                        : null,
                                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                                    label: const Text('Message seller'),
                                  ),
                                ),
                                Text('${fulfillment['deliveryMethod'] == 'delivery' ? 'Delivery' : 'Pickup'} · ${statusLabel(status)}'),
                                if (fulfillment['deliveryAddress'] is Map)
                                  Text((fulfillment['deliveryAddress'] as Map).values.where((value) => value != null).join(', ')),
                                if (status == 'delivered' && !disputed) ...[
                                  const SizedBox(height: 8),
                                  FilledButton(onPressed: busy ? null : () => confirmReceived(id), child: const Text('Confirm received')),
                                ],
                                if (['accepted', 'shipped', 'delivered'].contains(status) && !disputed)
                                  TextButton(
                                    onPressed: busy ? null : () => reportProblem(id),
                                    child: const Text('Report a problem'),
                                  ),
                                if (disputed) const Text('A problem has been reported. Seller funds remain held.'),
                              ]),
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      const Text('Order timeline', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      for (final event in timeline)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.circle, size: 10),
                          title: Text(event['description']?.toString() ?? ''),
                          subtitle: Text(event['createdAt']?.toString() ?? ''),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _total(String label, Object? amount, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w500)),
      const Spacer(),
      Text('₦${amount ?? '0.00'}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: strong ? 18 : 14)),
    ]),
  );
}
