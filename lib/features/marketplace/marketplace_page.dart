import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../home/home_shell.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});
  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final json = await api.get('marketplace/products');
      products = (json['products'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException catch (e) { error = e.message; }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: EazyPageHeader(title: 'Buy', subtitle: 'Discover things worth having', trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)))),
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 18), child: TextField(readOnly: true, decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search marketplace')))),
        if (loading) const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
        if (!loading && error != null) SliverFillRemaining(hasScrollBody: false, child: Center(child: _State(error!, load))),
        if (!loading && error == null && products.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: Center(child: _State('No products yet', null))),
        if (!loading && products.isNotEmpty) SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), sliver: SliverGrid.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .78), itemCount: products.length, itemBuilder: (context, index) => _Product(product: products[index]))),
      ]),
    ),
  );
}

class _Product extends StatelessWidget {
  const _Product({required this.product});
  final Map<String, dynamic> product;
  @override
  Widget build(BuildContext context) {
    final price = product['priceMinor'] is num ? (product['priceMinor'] as num).toInt() / 100 : 0;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Container(decoration: BoxDecoration(color: EazyColors.surfaceRaised, borderRadius: BorderRadius.circular(18)), child: const Center(child: Icon(Icons.shopping_bag_outlined, size: 42, color: EazyColors.green)))),
      const SizedBox(height: 12),
      Text(product['name']?.toString() ?? 'Product', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('₦' + price.toStringAsFixed(2), style: const TextStyle(color: EazyColors.green, fontWeight: FontWeight.w900)),
    ]));
  }
}

class _State extends StatelessWidget {
  const _State(this.text, this.action);
  final String text;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.storefront_outlined, size: 44, color: EazyColors.green), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted)), if (action != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: action, child: const Text('Try again'))]]);
}
