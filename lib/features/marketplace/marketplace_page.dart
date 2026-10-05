import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_detail_page.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});
  @override State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final api = ApiClient();
  final search = TextEditingController();
  bool loading = true;
  String? error;
  String? categoryId;
  String sort = 'newest';
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> categories = [];

  @override void initState() { super.initState(); load(); }
  @override void dispose() { search.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final params = <String, String>{
        'status': 'active', 'limit': '30', 'page': '1', 'sort': sort,
      };
      if (categoryId != null) params['categoryId'] = categoryId!;
      if (search.text.trim().length >= 2) params['q'] = search.text.trim();
      final qs = params.entries.map((e) =>
        '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

      final r = await Future.wait([
        api.get('marketplace/products?$qs'),
        api.get('marketplace/categories?page=1&limit=50'),
      ]);
      products = (r[0]['items'] as List? ?? const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      categories = (r[1]['items'] as List? ?? const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Marketplace', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: -1)),
                          SizedBox(height: 3),
                          Text('Discover things worth having', style: TextStyle(color: EazyColors.muted)),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: EazyColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: EazyColors.border),
                      ),
                      child: IconButton(
                        onPressed: () => context.push('/cart'),
                        icon: const Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => load(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search products, brands...',
                    suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.tune_rounded)),
                  ),
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: categories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (c, i) {
                      if (i == 0) {
                        return _CategoryTile(
                          name: 'All',
                          icon: Icons.grid_view_rounded,
                          selected: categoryId == null,
                          onTap: () { setState(() => categoryId = null); load(); },
                        );
                      }
                      final x = categories[i - 1];
                      final id = x['id']?.toString();
                      return _CategoryTile(
                        name: x['name']?.toString() ?? 'Category',
                        icon: _categoryIcon(x['name']?.toString()),
                        selected: categoryId == id,
                        onTap: () { setState(() => categoryId = id); load(); },
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    const Text('Latest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    PopupMenuButton<String>(
                      initialValue: sort,
                      onSelected: (v) { setState(() => sort = v); load(); },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'newest', child: Text('Newest')),
                        PopupMenuItem(value: 'price_asc', child: Text('Price: low to high')),
                        PopupMenuItem(value: 'price_desc', child: Text('Price: high to low')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: EazyColors.surface,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: EazyColors.border),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Sort', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            SizedBox(width: 5),
                            Icon(Icons.keyboard_arrow_down_rounded, size: 17),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
            if (!loading && error != null)
              SliverFillRemaining(hasScrollBody: false, child: _State(error!, load)),
            if (!loading && error == null && products.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _State('No products match your search.', null)),
            if (!loading && products.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .68,
                  ),
                  itemCount: products.length,
                  itemBuilder: (c, i) => _Product(product: products[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, required this.icon, required this.selected, required this.onTap});
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 78,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(
                colors: [EazyColors.green, EazyColors.greenDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ) : null,
              color: selected ? null : EazyColors.surface,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: selected ? EazyColors.green : EazyColors.border),
              boxShadow: selected ? [
                BoxShadow(color: EazyColors.green.withValues(alpha: .15), blurRadius: 18, spreadRadius: 1),
              ] : null,
            ),
            child: Icon(icon, color: selected ? EazyColors.canvas : EazyColors.green, size: 25),
          ),
          const SizedBox(height: 7),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected ? EazyColors.ink : EazyColors.muted),
          ),
        ],
      ),
    ),
  );
}

IconData _categoryIcon(String? value) {
  final name = (value ?? '').toLowerCase();
  if (name.contains('elect')) return Icons.devices_rounded;
  if (name.contains('fashion') || name.contains('cloth')) return Icons.checkroom_rounded;
  if (name.contains('home')) return Icons.weekend_rounded;
  if (name.contains('beaut')) return Icons.auto_awesome_rounded;
  if (name.contains('health')) return Icons.favorite_rounded;
  if (name.contains('food') || name.contains('grocery')) return Icons.shopping_basket_rounded;
  if (name.contains('auto') || name.contains('vehicle')) return Icons.directions_car_rounded;
  if (name.contains('sport')) return Icons.sports_basketball_rounded;
  if (name.contains('book')) return Icons.menu_book_rounded;
  if (name.contains('game')) return Icons.sports_esports_rounded;
  if (name.contains('pet')) return Icons.pets_rounded;
  if (name.contains('baby') || name.contains('kid')) return Icons.child_friendly_rounded;
  if (name.contains('tool')) return Icons.handyman_rounded;
  return Icons.category_rounded;
}

class _Product extends StatelessWidget {
  const _Product({required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final media = product['media'] is List ? product['media'] as List : const [];
    final first = media.isNotEmpty && media.first is Map
        ? Map<String, dynamic>.from(media.first as Map)
        : const <String, dynamic>{};
    final url = first['url']?.toString();
    final price = product['priceAmount']?.toString() ?? '0.00';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  url != null
                      ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _ProductPlaceholder())
                      : const _ProductPlaceholder(),
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: EazyColors.canvas.withValues(alpha: .72),
                        shape: BoxShape.circle,
                        border: Border.all(color: EazyColors.border),
                      ),
                      child: const Icon(Icons.favorite_border_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name']?.toString() ?? 'Product', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 6),
                  Text('${product['currency'] ?? 'NGN'} $price',
                    style: const TextStyle(color: EazyColors.green, fontWeight: FontWeight.w900, fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder();
  @override Widget build(BuildContext context) => Container(
    color: EazyColors.surfaceRaised,
    child: const Center(child: Icon(Icons.shopping_bag_outlined, size: 42, color: EazyColors.green)),
  );
}

class _State extends StatelessWidget {
  const _State(this.text, this.action);
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 44, color: EazyColors.green),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted)),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
