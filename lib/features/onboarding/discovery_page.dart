import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final api = ApiClient();
  final search = TextEditingController();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> people = [];
  List<Map<String, dynamic>> products = [];
  final followed = <String>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        api.get('discover?type=products&page=1&limit=8'),
      ]);
      products = _items(results.first);
      if (search.text.trim().length >= 2) {
        final peopleResult = await api.get(
          'discover?type=people&q=${Uri.encodeQueryComponent(search.text.trim())}&page=1&limit=8',
          auth: true,
        );
        people = _items(peopleResult);
      } else {
        people = [];
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) =>
      (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<void> follow(String username) async {
    final normalized = username.replaceFirst('@', '').toLowerCase();
    try {
      await api.post('social/follow/$normalized', auth: true);
      if (mounted) setState(() => followed.add(normalized));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Discover Eazy',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text('Skip'),
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            const Text(
              'Find your people',
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Search Eazy users and browse real listings before you enter your home feed.',
              style: TextStyle(color: EazyColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search people by name or username',
                suffixIcon: IconButton(
                  onPressed: load,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!loading && error != null) ...[
              const SizedBox(height: 22),
              _StateCard(message: error!, action: load),
            ],
            if (!loading &&
                error == null &&
                search.text.trim().length >= 2) ...[
              const SizedBox(height: 24),
              const Text(
                'People you may know',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (people.isEmpty)
                const _EmptyLine(text: 'No matching Eazy users yet.'),
              ...people.map(_personTile),
            ],
            if (!loading && error == null) ...[
              const SizedBox(height: 24),
              const Text(
                'Explore listings',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (products.isEmpty)
                const _EmptyLine(
                  text:
                      'No listings are available yet. You can continue and return later.',
                ),
              ...products.map(_productTile),
            ],
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('Continue to Eazy'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _personTile(Map<String, dynamic> person) {
    final username = person['username']?.toString() ?? '';
    final name =
        person['displayName']?.toString() ??
        person['display_name']?.toString() ??
        username;
    final isFollowed = followed.contains(username.toLowerCase());
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          username.isEmpty ? 'Eazy member' : '@$username',
          style: const TextStyle(color: EazyColors.muted),
        ),
        trailing: OutlinedButton(
          onPressed: isFollowed ? null : () => follow(username),
          child: Text(isFollowed ? 'Following' : 'Follow'),
        ),
      ),
    );
  }

  Widget _productTile(Map<String, dynamic> product) => Card(
    child: ListTile(
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: EazyColors.green.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.shopping_bag_outlined, color: EazyColors.green),
      ),
      title: Text(
        product['name']?.toString() ?? 'Eazy listing',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${product['currency'] ?? 'NGN'} ${product['priceAmount'] ?? ''}',
        style: const TextStyle(
          color: EazyColors.green,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: const TextStyle(color: EazyColors.muted)),
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.message, required this.action});
  final String message;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.explore_outlined, size: 42, color: EazyColors.green),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EazyColors.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: action, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
