import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_detail_page.dart';

class MarketplaceSearchPage extends StatefulWidget {
  const MarketplaceSearchPage({super.key, required this.query});
  final String query;
  @override
  State<MarketplaceSearchPage> createState() => _MarketplaceSearchPageState();
}

class _MarketplaceSearchPageState extends State<MarketplaceSearchPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> sellers = [];
  List<Map<String, dynamic>> categories = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('marketplace/search?q=${Uri.encodeQueryComponent(widget.query)}');
      if (!mounted) return;
      setState(() {
        products = (result['products'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        sellers = (result['sellers'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        categories = (result['categories'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Search: ${widget.query}')),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('Retry'))])) : ListView(padding: const EdgeInsets.all(16), children: [
      _heading('Products', products.length),
      if (products.isEmpty) const Text('No matching products.') else for (final product in products) Card(child: ListTile(title: Text(product['name']?.toString() ?? 'Product'), subtitle: Text('₦${product['priceAmount'] ?? '0.00'}'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))))),
      const SizedBox(height: 16), _heading('Sellers', sellers.length),
      if (sellers.isEmpty) const Text('No matching sellers.') else for (final seller in sellers) Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)), title: Text(seller['displayName']?.toString() ?? seller['username']?.toString() ?? 'Seller'), subtitle: Text('@${seller['username']} · ${seller['productCount']} listings · ${seller['ratingAverage'] ?? 'No rating'} ★'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/store/${Uri.encodeComponent(seller['username'].toString())}'))),
      const SizedBox(height: 16), _heading('Categories', categories.length),
      if (categories.isEmpty) const Text('No matching categories.') else for (final category in categories) Card(child: ListTile(leading: const Icon(Icons.grid_view_rounded), title: Text(category['name']?.toString() ?? ''), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/marketplace/search?q=${Uri.encodeQueryComponent(category['name'].toString())}'))),
    ]),
  );
  Widget _heading(String title, int count) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('$title ($count)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)));
}
