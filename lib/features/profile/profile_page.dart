import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.auth, this.username});
  final AuthController auth;
  final String? username;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final api = ApiClient();
  bool loading = true;
  bool saving = false;
  Map<String, dynamic> stats = {};
  late Map<String, dynamic> profile;
  List<Map<String, dynamic>> ownPosts = [];
  String? error;
  int contentTab = 0;
  bool isFollowing = false;
  bool followBusy = false;
  bool get isOwnProfile => widget.username == null || widget.username!.toLowerCase() == (profile['username']?.toString().toLowerCase() ?? '');

  @override
  void initState() {
    super.initState();
    profile = Map<String, dynamic>.from(widget.auth.profile ?? const {});
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final requested = widget.username?.trim().toLowerCase();
      final currentUsername = widget.auth.profile?['username']?.toString().toLowerCase();
      final own = requested == null || requested.isEmpty || requested == currentUsername;
      final fetched = await api.get(own ? 'profiles/me' : 'profiles/$requested', auth: own);
      final fetchedProfile = fetched['profile'];
      if (fetchedProfile is! Map) throw const ApiException('Eazy could not load this profile.');
      final nextProfile = Map<String, dynamic>.from(fetchedProfile);
      nextProfile['displayName'] ??= nextProfile['display_name'];
      nextProfile['firstName'] ??= nextProfile['first_name'];
      nextProfile['lastName'] ??= nextProfile['last_name'];
      nextProfile['avatarUrl'] ??= nextProfile['avatar_url'];
      nextProfile['userId'] ??= nextProfile['user_id'];
      final actualUsername = (nextProfile['username'] ?? nextProfile['user_name'])?.toString().toLowerCase();
      if (actualUsername == null || actualUsername.isEmpty) throw const ApiException('This profile has no username yet.');
      final results = await Future.wait([
        api.get('posts/profile/$actualUsername?page=1&limit=50', auth: true),
        if (own) api.get('profiles/me/stats', auth: true),
        if (!own) api.get('social/followers/$actualUsername?page=1&limit=1', auth: true),
        if (!own) api.get('social/following/$actualUsername?page=1&limit=1', auth: true),
        if (!own) api.get('social/relationship/$actualUsername', auth: true),
      ]);
      final postResult = results[0];
      final rawPosts = postResult['items'] as List? ?? const [];
      final fetchedStats = own ? results[1]['stats'] : null;
      final relationship = own ? const <String, dynamic>{} : Map<String, dynamic>.from(results[3]['following'] is Map ? results[3]['following'] as Map : results[3] as Map);
      final followState = own ? false : relationship['following'] == true;
      final newStats = own && fetchedStats is Map
          ? Map<String, dynamic>.from(fetchedStats)
          : <String, dynamic>{
              'posts': (postResult['meta'] is Map ? (postResult['meta'] as Map)['total'] : rawPosts.length) ?? rawPosts.length,
              'followers': (own ? 0 : ((results[1]['meta'] is Map ? (results[1]['meta'] as Map)['total'] : 0) ?? 0)),
              'following': (own ? 0 : ((results[2]['meta'] is Map ? (results[2]['meta'] as Map)['total'] : 0) ?? 0)),
            };
      // The public list endpoints return totals in their meta fields.
      if (!own) {
        newStats['followers'] = (results[1]['meta'] is Map ? (results[1]['meta'] as Map)['total'] : 0) ?? 0;
        newStats['following'] = (results[2]['meta'] is Map ? (results[2]['meta'] as Map)['total'] : 0) ?? 0;
      }
      if (mounted) setState(() {
        profile = nextProfile;
        stats = newStats;
        ownPosts = rawPosts.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        isFollowing = followState;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> toggleFollow() async {
    final username = profile['username']?.toString() ?? '';
    if (username.isEmpty || followBusy) return;
    final wasFollowing = isFollowing;
    setState(() { isFollowing = !wasFollowing; followBusy = true; });
    try {
      if (wasFollowing) {
        await api.delete('social/follow/$username', auth: true);
      } else {
        await api.post('social/follow/$username', auth: true);
      }
      await load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => isFollowing = wasFollowing);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally { if (mounted) setState(() => followBusy = false); }
  }

  String _count(dynamic value) {
    final n = int.tryParse(value?.toString() ?? '') ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 < 100000 ? 0 : 1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(n % 1000 < 100 ? 0 : 1)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> editProfile() async {
    final first = TextEditingController(text: profile['firstName']?.toString() ?? '');
    final last = TextEditingController(text: profile['lastName']?.toString() ?? '');
    final username = TextEditingController(text: profile['username']?.toString() ?? '');
    final bio = TextEditingController(text: profile['bio']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Edit your profile', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Keep your Eazy identity up to date.', style: TextStyle(color: EazyColors.muted)),
              const SizedBox(height: 18),
              TextFormField(controller: first, decoration: const InputDecoration(labelText: 'First name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Add your first name' : null),
              const SizedBox(height: 10),
              TextFormField(controller: last, decoration: const InputDecoration(labelText: 'Last name')),
              const SizedBox(height: 10),
              TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username', prefixText: '@'), validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim()) ? null : 'Use 3–32 letters, numbers or underscores'),
              const SizedBox(height: 10),
              TextFormField(controller: bio, maxLength: 150, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', alignLabelWithHint: true)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  Navigator.pop(ctx, {
                    'firstName': first.text.trim(),
                    'lastName': last.text.trim(),
                    'username': username.text.trim().toLowerCase(),
                    'bio': bio.text.trim(),
                  });
                },
                child: const Text('Save changes'),
              )),
            ],
          )),
        ),
      ),
    );
    first.dispose(); last.dispose(); username.dispose(); bio.dispose();
    if (values == null) return;
    setState(() { saving = true; error = null; });
    try {
      final result = await api.patch('profiles/me', auth: true, body: values);
      final updated = result['profile'];
      if (mounted) setState(() => profile = Map<String, dynamic>.from(updated is Map ? updated : {...profile, ...values}));
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = profile['username']?.toString() ?? '';
    final name = profile['displayName']?.toString().trim().isNotEmpty == true
        ? profile['displayName'].toString()
        : [profile['firstName'], profile['lastName']].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    final avatar = profile['avatarUrl']?.toString();
    final bio = profile['bio']?.toString() ?? '';
    final postsCount = stats['posts'] ?? profile['postsCount'] ?? 0;
    final followers = stats['followers'] ?? profile['followersCount'] ?? 0;
    final following = stats['following'] ?? profile['followingCount'] ?? 0;

    return SafeArea(child: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
          child: Row(children: [
            Expanded(child: Row(children: [
              if (profile['isPrivate'] == true) const Padding(padding: EdgeInsets.only(right: 7), child: Icon(Icons.lock_outline_rounded, size: 18)),
              Flexible(child: Text(username.isEmpty ? 'Your profile' : '@$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.7))),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
            ])),
            IconButton(tooltip: 'Create a post', onPressed: () => context.go('/home'), icon: const Icon(Icons.add_box_outlined)),
            IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.menu_rounded)),
          ]),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: EazyColors.green.withValues(alpha: .75), width: 2)),
                child: CircleAvatar(
                  radius: 43,
                  backgroundColor: EazyColors.surfaceRaised,
                  backgroundImage: avatar != null && avatar.startsWith('http') ? NetworkImage(avatar) : null,
                  child: avatar == null || !avatar.startsWith('http') ? const Icon(Icons.person_rounded, size: 42, color: EazyColors.green) : null,
                ),
              ),
              const SizedBox(width: 22),
              Expanded(child: StatsRow(
                posts: _count(postsCount),
                followers: _count(followers),
                following: _count(following),
                loading: loading,
                onFollowers: () => _showSocialList('Followers'),
                onFollowing: () => _showSocialList('Following'),
              )),
            ]),
            const SizedBox(height: 16),
            Text(name.isEmpty ? 'Make Eazy yours' : name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (profile['category']?.toString().isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 3), child: Text(profile['category'].toString(), style: const TextStyle(color: EazyColors.muted, fontSize: 12))),
            if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(bio, style: const TextStyle(height: 1.45))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: saving ? null : editProfile, child: Text(saving ? 'Saving…' : 'Edit profile'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile sharing will be available when Eazy links are enabled.'))), icon: const Icon(Icons.ios_share_rounded, size: 17), label: const Text('Share profile'))),
              const SizedBox(width: 8),
              IconButton.filledTonal(tooltip: 'Discover people', onPressed: () => context.push('/discovery'), icon: const Icon(Icons.person_add_alt_1_rounded)),
            ]),
            const SizedBox(height: 8),
            if (error != null) Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: EazyColors.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(EazyRadius.md)),
              child: Text(error!, style: const TextStyle(color: EazyColors.red)),
            ),
          ]),
        )),
        SliverToBoxAdapter(child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: EazyColors.border))),
          child: Row(children: [
            ProfileTab(icon: Icons.grid_on_rounded, selected: contentTab == 0, onTap: () => setState(() => contentTab = 0)),
            ProfileTab(icon: Icons.play_circle_outline_rounded, selected: contentTab == 1, onTap: () => setState(() => contentTab = 1)),
            ProfileTab(icon: Icons.person_pin_outlined, selected: contentTab == 2, onTap: () => setState(() => contentTab = 2)),
          ]),
        )),
        if (loading && ownPosts.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))),
        if (!loading && contentTab == 0 && ownPosts.isNotEmpty)
          SliverPadding(padding: const EdgeInsets.all(2), sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) => ProfilePostTile(post: ownPosts[index]), childCount: ownPosts.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2, childAspectRatio: 1),
          )),
        if (!loading && (contentTab != 0 || ownPosts.isEmpty))
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 42, 28, 100),
            child: Column(children: [
              Icon(contentTab == 0 ? Icons.add_a_photo_outlined : contentTab == 1 ? Icons.play_circle_outline_rounded : Icons.person_pin_outlined, size: 42, color: EazyColors.green),
              const SizedBox(height: 12),
              Text(contentTab == 0 ? ((int.tryParse(postsCount.toString()) ?? 0) > 0 ? 'Your posts are not in the current feed page yet' : 'Share your first moment') : contentTab == 1 ? 'Your Reels will live here' : 'Photos you are tagged in will appear here', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text(contentTab == 0 ? 'Build your corner of Eazy, one post at a time.' : 'This view will fill with content when the matching Eazy feature is available.', textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted, height: 1.45)),
              if (contentTab == 0) Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton.icon(onPressed: () => context.go('/home'), icon: const Icon(Icons.add_rounded), label: const Text('Create a post'))),
            ]),
          )),
        if (error != null && ownPosts.isEmpty && !loading)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Text('Could not refresh all profile content. Pull down to retry.', style: const TextStyle(color: EazyColors.muted)))),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ]),
    ));
  }

  void _showSocialList(String title) {
    final username = profile['username']?.toString() ?? '';
    final direction = title.toLowerCase() == 'followers' ? 'followers' : 'following';
    final search = TextEditingController();
    List<Map<String, dynamic>> people = [];
    bool listLoading = true;
    String? listError;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: EazyColors.surface,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        if (listLoading && people.isEmpty && listError == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              final result = await api.get('social/$direction/$username?page=1&limit=50', auth: true);
              people = (result['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            } on ApiException catch (e) { listError = e.message; }
            listLoading = false;
            if (ctx.mounted) setSheetState(() {});
          });
        }
        final filtered = people.where((person) {
          final q = search.text.trim().toLowerCase();
          return q.isEmpty || (person['username']?.toString().toLowerCase().contains(q) ?? false) || (person['displayName']?.toString().toLowerCase().contains(q) ?? false);
        }).toList();
        return SafeArea(child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .72,
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
              controller: search,
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search $direction', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
            )),
            const SizedBox(height: 8),
            Expanded(child: listLoading
                ? const Center(child: CircularProgressIndicator())
                : listError != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(listError!, textAlign: TextAlign.center)))
                    : filtered.isEmpty
                        ? Center(child: Text(people.isEmpty ? 'No $direction yet.' : 'No matching people.', style: const TextStyle(color: EazyColors.muted)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                            itemBuilder: (_, index) {
                              final person = filtered[index];
                              final avatar = person['avatarUrl']?.toString();
                              final name = person['displayName']?.toString() ?? person['username']?.toString() ?? 'Eazy user';
                              final handle = person['username']?.toString() ?? '';
                              return ListTile(
                                leading: CircleAvatar(backgroundColor: EazyColors.surfaceRaised, backgroundImage: avatar != null && avatar.startsWith('http') ? NetworkImage(avatar) : null, child: avatar == null || !avatar.startsWith('http') ? const Icon(Icons.person_rounded, color: EazyColors.green) : null),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('@$handle'),
                                onTap: handle.isEmpty ? null : () { Navigator.pop(ctx); context.push('/profile/$handle'); },
                              );
                            },
                          )),
          ]),
        ));
      }),
    ).whenComplete(search.dispose);
  }
}

class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.posts, required this.followers, required this.following, required this.loading, required this.onFollowers, required this.onFollowing});
  final String posts, followers, following;
  final bool loading;
  final VoidCallback onFollowers, onFollowing;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    _Stat(posts, 'Posts', loading, () {}),
    _Stat(followers, 'Followers', loading, onFollowers),
    _Stat(following, 'Following', loading, onFollowing),
  ]);
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.loading, this.onTap);
  final String value, label;
  final bool loading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8), child: Column(children: [
      Text(loading ? '—' : value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 11, color: EazyColors.muted)),
    ])),
  );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.icon, required this.selected, required this.onTap});
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(
    onTap: onTap,
    child: Container(height: 48, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? EazyColors.green : Colors.transparent, width: 2))), child: Icon(icon, color: selected ? EazyColors.ink : EazyColors.muted, size: 22)),
  ));
}

class ProfilePostTile extends StatelessWidget {
  const ProfilePostTile({super.key, required this.post});
  final Map<String, dynamic> post;
  @override
  Widget build(BuildContext context) {
    final media = post['media'] is List ? post['media'] as List : const [];
    String? url;
    if (media.isNotEmpty && media.first is Map) {
      final m = Map<String, dynamic>.from(media.first as Map);
      url = m['url']?.toString();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(fit: StackFit.expand, children: [
        if (url != null && url.startsWith('http'))
          Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(post))
        else
          _fallback(post),
        if (media.length > 1) const Positioned(right: 6, top: 6, child: Icon(Icons.collections_rounded, color: Colors.white, size: 18)),
      ]),
    );
  }

  Widget _fallback(Map<String, dynamic> post) => ColoredBox(
    color: EazyColors.surfaceRaised,
    child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(post['content']?.toString() ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: EazyColors.ink)))),
  );
}

