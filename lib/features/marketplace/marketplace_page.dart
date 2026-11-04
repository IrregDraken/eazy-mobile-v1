import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/ui/eazy_skeleton.dart';
import 'discover_categories.dart';
import 'product_detail_page.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});
  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final api = ApiClient();
  final search = TextEditingController();
  final minPrice = TextEditingController();
  final maxPrice = TextEditingController();
  Timer? _searchDebounce;
  String availability = 'all';
  bool loading = true;
  String? error;
  String? selectedParentSlug;
  String sort = 'newest';
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> categories = [];
  bool categoriesLoaded = false;
  int cartItemCount = 0;

  @override
  void initState() {
    super.initState();
    load();
    _loadCartCount();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    search.dispose();
    minPrice.dispose();
    maxPrice.dispose();
    super.dispose();
  }

  Future<void> _loadCartCount() async {
    try {
      final result = await api.get('cart', auth: true);
      final items = result['items'] as List? ?? const [];
      final count = items.fold<int>(0, (total, value) {
        if (value is! Map) return total;
        final raw = value['quantity'];
        final quantity = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? 1;
        return total + (quantity < 0 ? 0 : quantity > 999 ? 999 : quantity);
      });
      if (mounted) setState(() => cartItemCount = count);
    } on ApiException {
      // Cart is optional to the Discover feed. Keep the last known count.
    }
  }

  Future<void> _openCart() async {
    await context.push('/cart');
    if (mounted) await _loadCartCount();
  }

  Future<void> _refreshDiscover() async {
    await load();
    await _loadCartCount();
  }

  Future<void> load() async {
    setState(() {
      if (products.isEmpty) loading = true;
      error = null;
    });
    try {
      if (!categoriesLoaded) {
        final categoryResponse = await api.get(
          'marketplace/categories?page=1&limit=50',
        );
        categories =
            (categoryResponse['items'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        categoriesLoaded = true;
      }
      if (!mounted) return;

      final params = <String, String>{
        'status': 'active',
        'limit': '30',
        'page': '1',
        'sort': sort,
      };
      if (selectedParentSlug != null) {
        final parent = discoverParentCategories.firstWhere(
          (category) => category.slug == selectedParentSlug,
        );
        final categoryIds = resolveBackendCategoryIdsForParent(
          parent,
          categories,
        );
        if (categoryIds.isEmpty) {
          products = [];
          return;
        }
        params['categoryIds'] = categoryIds.join(',');
      }
      if (search.text.trim().length >= 2) params['q'] = search.text.trim();
      if (minPrice.text.trim().isNotEmpty) params['minPrice'] = minPrice.text.trim();
      if (maxPrice.text.trim().isNotEmpty) params['maxPrice'] = maxPrice.text.trim();
      if (availability != 'all') params['availability'] = availability;
      final qs = params.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');

      final r = await api.get('marketplace/products?$qs');
      if (!mounted) return;
      products =
          (r['items'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showFilters() async {
    var selectedAvailability = availability;
    final applied = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
      title: const Text('Filter products'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: minPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum price (₦)')),
        TextField(controller: maxPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum price (₦)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: selectedAvailability, decoration: const InputDecoration(labelText: 'Availability'), items: const [DropdownMenuItem(value: 'all', child: Text('All products')), DropdownMenuItem(value: 'in_stock', child: Text('In stock')), DropdownMenuItem(value: 'out_of_stock', child: Text('Out of stock'))], onChanged: (value) { if (value != null) update(() => selectedAvailability = value); }),
      ]),
      actions: [TextButton(onPressed: () { minPrice.clear(); maxPrice.clear(); update(() => selectedAvailability = 'all'); }, child: const Text('Clear')), TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apply'))],
    )));
    if (applied == true && mounted) { setState(() => availability = selectedAvailability); load(); }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = search.text.trim().length >= 2 ||
        selectedParentSlug != null ||
        minPrice.text.trim().isNotEmpty ||
        maxPrice.text.trim().isNotEmpty ||
        availability != 'all';
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshDiscover,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discover',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Discover things worth having',
                            style: TextStyle(color: context.eazyMuted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.eazyBorder),
                      ),
                      child: IconButton(
                        tooltip: 'Become a Seller',
                        onPressed: () => context.push('/seller'),
                        icon: const Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.eazyBorder),
                      ),
                      child: IconButton(
                        tooltip: cartItemCount > 0
                            ? 'Cart, $cartItemCount items'
                            : 'Cart',
                        onPressed: _openCart,
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.shopping_bag_outlined),
                            if (cartItemCount > 0)
                              Positioned(
                                right: -9,
                                top: -8,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 17,
                                    minHeight: 17,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    cartItemCount > 99 ? '99+' : '$cartItemCount',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onError,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                      if (!mounted) return;
                      if (value.trim().isEmpty || value.trim().length >= 2) {
                        load();
                      }
                    });
                  },
                  onSubmitted: (_) {
                    final query = search.text.trim();
                    if (query.length >= 2) context.push('/marketplace/search?q=${Uri.encodeQueryComponent(query)}');
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search products, brands...',
                    suffixIcon: IconButton(
                      onPressed: () {
                        final query = search.text.trim();
                        if (query.length >= 2) context.push('/marketplace/search?q=${Uri.encodeQueryComponent(query)}');
                        else load();
                      },
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 124,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: discoverParentCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 9),
                  itemBuilder: (context, index) {
                    final parent = discoverParentCategories[index];
                    return _CategoryTile(
                      name: parent.name,
                      icon: parent.icon,
                      assetPath: parent.assetPath,
                      selected: selectedParentSlug == parent.slug,
                      onTap: () {
                        setState(() {
                          selectedParentSlug =
                              selectedParentSlug == parent.slug ? null : parent.slug;
                        });
                        load();
                      },
                    );
                  },
                ),
              ),
            ),
            if (hasActiveFilters)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (search.text.trim().length >= 2)
                              'Search: “${search.text.trim()}”',
                            if (selectedParentSlug != null)
                              discoverParentCategories
                                  .firstWhere((item) => item.slug == selectedParentSlug)
                                  .name,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.eazyMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          search.clear();
                          minPrice.clear();
                          maxPrice.clear();
                          setState(() {
                            selectedParentSlug = null;
                            availability = 'all';
                          });
                          load();
                        },
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    const Text(
                      'Latest',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(tooltip: 'Filter products', onPressed: showFilters, icon: const Icon(Icons.tune_rounded)),
                    PopupMenuButton<String>(
                      initialValue: sort,
                      onSelected: (v) {
                        setState(() => sort = v);
                        load();
                      },
                      itemBuilder:
                          (_) => const [
                            PopupMenuItem(
                              value: 'newest',
                              child: Text('Newest'),
                            ),
                            PopupMenuItem(
                              value: 'price_asc',
                              child: Text('Price: low to high'),
                            ),
                            PopupMenuItem(
                              value: 'price_desc',
                              child: Text('Price: high to low'),
                            ),
                          ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: context.eazyBorder),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Sort',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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
            if (loading && products.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const _ProductSkeletonCard(),
                    childCount: 6,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: .68,
                  ),
                ),
              ),
            if (loading && products.isNotEmpty)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (!loading && error != null && products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _State(error!, load),
              ),
            if (!loading && error != null && products.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Could not refresh listings: $error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            if (!loading && error == null && products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _State(
                  hasActiveFilters
                      ? 'No products match your search.'
                      : 'No products yet.',
                  null,
                ),
              ),
            if (products.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: .68,
                  ),
                  itemCount: products.length,
                  itemBuilder: (c, i) => _Product(product: products[i], onReturn: _loadCartCount),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductSkeletonCard extends StatelessWidget {
  const _ProductSkeletonCard();

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EazySkeletonBox(
            width: double.infinity,
            height: 132,
            radius: 14,
          ),
          const SizedBox(height: 10),
          const EazySkeletonBox(width: 112, height: 12),
          const SizedBox(height: 7),
          const EazySkeletonBox(width: 76, height: 10),
          const Spacer(),
          const EazySkeletonBox(width: 92, height: 13),
        ],
      ),
    ),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.icon,
    this.assetPath,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final String? assetPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 218,
    height: 116,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: context.eazySurfaceRaised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? EazyColors.mint : context.eazyBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: context.eazyAccent.withValues(alpha: .20),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (assetPath != null)
                  Image.asset(
                    assetPath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(context),
                  )
                else
                  _fallback(context),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x08000000),
                        Color(0x26000000),
                        Color(0xD9000000),
                      ],
                      stops: [0, .38, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 13,
                  right: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.2,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: EazyColors.mint,
                          size: 19,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _fallback(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [context.eazyAccent, EazyColors.canvas],
      ),
    ),
    child: Center(
      child: Icon(icon, color: EazyColors.mint, size: 38),
    ),
  );
}

class _Product extends StatelessWidget {
  const _Product({required this.product, this.onReturn});
  final Map<String, dynamic> product;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final media =
        product['media'] is List ? product['media'] as List : const [];
    final first =
        media.isNotEmpty && media.first is Map
            ? Map<String, dynamic>.from(media.first as Map)
            : const <String, dynamic>{};
    final url = first['url']?.toString();
    final price = product['priceAmount']?.toString() ?? '0.00';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: product),
            ),
          );
          onReturn?.call();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  url != null
                      ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ProductPlaceholder(),
                      )
                      : const _ProductPlaceholder(),
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withValues(alpha: .72),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.eazyBorder),
                      ),
                      child: const Icon(
                        Icons.favorite_border_rounded,
                        size: 18,
                      ),
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
                  Text(
                    product['name']?.toString() ?? 'Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${product['currency'] ?? 'NGN'} $price',
                    style: TextStyle(
                      color: context.eazyAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
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
  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 42,
        color: context.eazyAccent,
      ),
    ),
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
          Icon(
            Icons.storefront_outlined,
            size: 44,
            color: context.eazyAccent,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eazyMuted),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
