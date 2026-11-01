import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_detail_page.dart';

class SellerStorefrontPage extends StatefulWidget {
  const SellerStorefrontPage({super.key, required this.username});
  final String username;
  @override
  State<SellerStorefrontPage> createState() => _SellerStorefrontPageState();
}

class _SellerStorefrontPageState extends State<SellerStorefrontPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> products = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final a = await api.get('profiles/${Uri.encodeComponent(widget.username)}');
      final b = await api.get('marketplace/sellers/${Uri.encodeComponent(widget.username)}/products?page=1&limit=50');
      if (!mounted) return;
      setState(() { profile = Map<String, dynamic>.from(a['profile'] as Map); products = (b['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final seller = products.isNotEmpty && products.first['seller'] is Map ? Map<String, dynamic>.from(products.first['seller'] as Map) : <String, dynamic>{};
    final avatar = profile?['avatarUrl']?.toString() ?? '';
    return Scaffold(appBar: AppBar(title: Text('@${widget.username}')), body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('Retry'))])) : RefreshIndicator(onRefresh: load, child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        CircleAvatar(radius: 36, backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null, child: avatar.startsWith('http') ? null : const Icon(Icons.storefront_rounded, size: 32)),
        const SizedBox(height: 10), Text(profile?['displayName']?.toString() ?? widget.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text('@${widget.username}'), if ((profile?['bio']?.toString() ?? '').isNotEmpty) Text(profile!['bio'].toString(), textAlign: TextAlign.center),
        const SizedBox(height: 8), Text('${seller['ratingAverage'] ?? 'No rating'} ★ · ${seller['reviewCount'] ?? 0} reviews · ${products.length} listings'),
        Wrap(spacing: 8, children: [OutlinedButton(onPressed: () => context.push('/seller-reviews/${Uri.encodeComponent(widget.username)}'), child: const Text('Reviews')), FilledButton(onPressed: () => context.go('/home?tab=chat&username=${Uri.encodeComponent(widget.username)}'), child: const Text('Message seller'))]),
      ]))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text('Shop products', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))),
      if (products.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('This seller has no active listings yet.')))
      else SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverGrid.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .68), itemCount: products.length, itemBuilder: (context, i) => _StoreProduct(product: products[i]))),
    ])));
  }
}

class _StoreProduct extends StatelessWidget {
  const _StoreProduct({required this.product});
  final Map<String, dynamic> product;
  @override
  Widget build(BuildContext context) {
    final media = product['media'] as List? ?? const [];
    final first = media.isNotEmpty && media.first is Map ? Map<String, dynamic>.from(media.first as Map) : <String, dynamic>{};
    final url = first['url']?.toString();
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))), child: Padding(padding: const EdgeInsets.all(9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: url != null ? Image.network(url, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined)) : const Icon(Icons.image_outlined)),
      Text(product['name']?.toString() ?? 'Product', maxLines: 2, overflow: TextOverflow.ellipsis),
      Text('₦${product['priceAmount'] ?? '0.00'}', style: const TextStyle(fontWeight: FontWeight.w900)),
    ]))));
  }
}
