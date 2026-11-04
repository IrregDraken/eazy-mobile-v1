import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/ui/eazy_skeleton.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final api = ApiClient();
  bool loading = true, busy = false;
  String? error;
  Map<String, dynamic> cart = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      cart = await api.get('cart', auth: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> remove(String productId) async {
    setState(() => busy = true);
    try {
      await api.delete('cart/items/$productId', auth: true);
      await load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> updateQty(String productId, int quantity) async {
    setState(() => busy = true);
    try {
      await api.patch(
        'cart/items/$productId',
        auth: true,
        body: {'quantity': quantity},
      );
      await load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        (cart['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    final subtotal = cart['subtotal']?.toString() ?? '0.00';
    final currency = cart['currency']?.toString() ?? 'NGN';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [IconButton(tooltip: 'My orders', onPressed: () => context.push('/orders'), icon: const Icon(Icons.receipt_long_rounded))],
      ),
      body:
          loading
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: const [
                    EazySkeletonBox(width: 140, height: 22),
                    SizedBox(height: 18),
                    EazySkeletonBox(width: double.infinity, height: 116, radius: 18),
                    SizedBox(height: 12),
                    EazySkeletonBox(width: double.infinity, height: 116, radius: 18),
                    SizedBox(height: 12),
                    EazySkeletonBox(width: double.infinity, height: 116, radius: 18),
                  ],
                )
              : error != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: loading ? null : load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
              : items.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: context.eazyAccent.withValues(alpha: .10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 48,
                          color: context.eazyAccent,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Your Cart is empty',
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Find physical goods and services worth adding to your Cart.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.eazyMuted, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => context.go('/home?tab=shop'),
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Discover'),
                      ),
                    ],
                  ),
                ),
              )
              : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (c, i) {
                        final x = items[i];
                        final productName = x['name']?.toString() ?? 'Product';
                        final seller =
                            x['seller'] is Map
                                ? (x['seller'] as Map)['displayName']
                                        ?.toString() ??
                                    'Seller'
                                : 'Seller';
                        final qty = (x['quantity'] as num?)?.toInt() ?? 1;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    color: context.eazyAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        seller,
                                        style: TextStyle(
                                          color: context.eazyMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        '$currency ${x['unitPrice'] ?? '0.00'}',
                                        style: TextStyle(
                                          color: context.eazyAccent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      onPressed:
                                          busy
                                              ? null
                                              : () => remove(
                                                x['productId'].toString(),
                                              ),
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed:
                                              busy || qty <= 1
                                                  ? null
                                                  : () => updateQty(
                                                    x['productId'].toString(),
                                                    qty - 1,
                                                  ),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 20,
                                          ),
                                        ),
                                        Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed:
                                              busy
                                                  ? null
                                                  : () => updateQty(
                                                    x['productId'].toString(),
                                                    qty + 1,
                                                  ),
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.eazyBorder)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Subtotal',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                            Text(
                              '$currency $subtotal',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: busy ? null : () => context.push('/checkout'),
                            child:
                                busy
                                    ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Checkout'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}
