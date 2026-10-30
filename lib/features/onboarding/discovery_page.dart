import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../chat/chat_page.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final api = ApiClient();
  final search = TextEditingController();
  Timer? _debounce;
  bool productsLoading = true;
  bool peopleLoading = false;
  String? error;
  List<Map<String, dynamic>> people = [];
  List<Map<String, dynamic>> products = [];
  final followed = <String>{};
  final followBusy = <String>{};
  String? messageBusy;
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        productsLoading = true;
        error = null;
      });
    }
    try {
      final result = await api.get('discover?type=products&page=1&limit=8');
      if (mounted) setState(() => products = _items(result));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => productsLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      _searchRequest++;
      setState(() {
        people = [];
        peopleLoading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchPeople(query),
    );
  }

  Future<void> _searchPeople(String query) async {
    final request = ++_searchRequest;
    if (mounted) {
      setState(() {
        peopleLoading = true;
        error = null;
      });
    }
    try {
      final result = await api.get(
        'discover?type=people&q=${Uri.encodeQueryComponent(query)}&page=1&limit=20',
        auth: true,
      );
      if (mounted && request == _searchRequest) {
        setState(() => people = _items(result));
      }
    } on ApiException catch (e) {
      if (mounted && request == _searchRequest) {
        setState(() => error = e.message);
      }
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => peopleLoading = false);
      }
    }
  }

  Future<void> load() async {
    await Future.wait([
      _loadProducts(),
      if (search.text.trim().length >= 2) _searchPeople(search.text.trim()),
    ]);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) =>
      (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  String _username(Map<String, dynamic> person) =>
      (person['username'] ?? person['user_name'] ?? '')
          .toString()
          .replaceFirst('@', '')
          .trim();

  String _name(Map<String, dynamic> person) {
    final name =
        (person['displayName'] ??
                person['display_name'] ??
                person['fullName'] ??
                person['full_name'] ??
                '')
            .toString()
            .trim();
    return name.isNotEmpty
        ? name
        : (_username(person).isEmpty ? 'Eazy member' : _username(person));
  }

  String? _avatar(Map<String, dynamic> person) {
    final value =
        (person['avatarUrl'] ??
                person['avatar_url'] ??
                person['profilePicture'] ??
                person['profile_picture'])
            ?.toString();
    return value == null || value.trim().isEmpty ? null : value;
  }

  Future<void> follow(Map<String, dynamic> person) async {
    final username = _username(person);
    final key = username.toLowerCase();
    if (username.isEmpty ||
        followed.contains(key) ||
        followBusy.contains(key)) {
      return;
    }
    setState(() => followBusy.add(key));
    try {
      await api.post(
        'social/follow/${Uri.encodeComponent(username)}',
        auth: true,
      );
      if (mounted) setState(() => followed.add(key));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => followBusy.remove(key));
    }
  }

  Future<void> message(Map<String, dynamic> person) async {
    final username = _username(person);
    if (username.isEmpty || messageBusy != null) return;
    setState(() => messageBusy = username);
    try {
      final result = await api.post(
        'chat/conversations',
        auth: true,
        body: {'username': username},
      );
      final conversation = result['conversation'];
      if (mounted && conversation is Map) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                (_) => ConversationPage(
                  api: api,
                  conversation: Map<String, dynamic>.from(conversation),
                ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => messageBusy = null);
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
            Text(
              'Find your people',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Follow friends, start conversations, and make Eazy yours.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EazyColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: search,
              onChanged: _onSearchChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                if (value.trim().length >= 2) _searchPeople(value.trim());
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search by name, username, email or phone',
                suffixIcon: IconButton(
                  onPressed: () {
                    _debounce?.cancel();
                    if (search.text.trim().length >= 2) {
                      _searchPeople(search.text.trim());
                    }
                  },
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Search people',
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'People',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (peopleLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (search.text.trim().length < 2)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Search for at least 2 characters to find Eazy users.',
                  style: TextStyle(color: EazyColors.muted),
                ),
              )
            else if (!peopleLoading && people.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No matching people yet. Try another name or username.',
                  style: TextStyle(color: EazyColors.muted),
                ),
              )
            else
              ...people.map(_personTile),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: EazyColors.red)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: load,
                  child: const Text('Try again'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Explore listings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (productsLoading && products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No listings are available yet. You can come back later.',
                  style: TextStyle(color: EazyColors.muted),
                ),
              )
            else
              ...products.map(_productTile),
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
    final username = _username(person);
    final name = _name(person);
    final key = username.toLowerCase();
    final isFollowed =
        followed.contains(key) ||
        person['isFollowing'] == true ||
        person['is_following'] == true;
    final avatar = _avatar(person);
    return Column(
      children: [
        InkWell(
          onTap:
              username.isEmpty
                  ? null
                  : () =>
                      context.push('/profile/${Uri.encodeComponent(username)}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFE6F5EB),
                  foregroundColor: const Color(0xFF176B42),
                  backgroundImage: avatar == null ? null : NetworkImage(avatar),
                  onBackgroundImageError: avatar == null ? null : (_, _) {},
                  child:
                      avatar == null
                          ? Text(
                            name.isEmpty
                                ? '?'
                                : name.characters.first.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          )
                          : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        username.isEmpty ? 'Eazy member' : '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: EazyColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 94,
                      height: 34,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed:
                            isFollowed ||
                                    username.isEmpty ||
                                    followBusy.contains(key)
                                ? null
                                : () => follow(person),
                        child:
                            followBusy.contains(key)
                                ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(isFollowed ? 'Following' : 'Follow'),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 94,
                      height: 34,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed:
                            username.isEmpty || messageBusy != null
                                ? null
                                : () => message(person),
                        child:
                            messageBusy == username
                                ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text('Message'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 62),
      ],
    );
  }

  Widget _productTile(Map<String, dynamic> product) {
    final media = (product['media'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final imageUrl = media.isEmpty ? null : media.first['url']?.toString();
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 54,
              height: 54,
              child: imageUrl != null && imageUrl.startsWith('http')
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _productPlaceholder(),
                    )
                  : _productPlaceholder(),
            ),
          ),
          title: Text(
            product['name']?.toString() ?? 'Eazy listing',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${product['currency'] ?? 'NGN'} ${product['priceAmount'] ?? ''}',
            style: const TextStyle(
              color: EazyColors.greenDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _productPlaceholder() => Container(
    color: EazyColors.greenDeep.withValues(alpha: .10),
    alignment: Alignment.center,
    child: const Icon(Icons.shopping_bag_outlined, color: EazyColors.greenDeep),
  );
}
