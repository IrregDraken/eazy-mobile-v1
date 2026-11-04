import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/ui/eazy_skeleton.dart';
import '../../core/ui/eazy_assist_fab.dart';
import '../social/stories_tray.dart';
import '../social/video_media.dart';
import '../../core/media/media_service.dart';
import '../marketplace/product_detail_page.dart';

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
  List<Map<String, dynamic>> highlights = [];
  List<Map<String, dynamic>> sellerProducts = [];
  bool avatarBusy = false;
  String? error;
  bool isFollowing = false;
  bool followBusy = false;
  final ScrollController profileScrollController = ScrollController();
  int profilePage = 1;
  bool hasMoreProfilePosts = true;
  bool loadingMoreProfilePosts = false;
  bool get isOwnProfile =>
      widget.username == null ||
      widget.username!.toLowerCase() ==
          (profile['username']?.toString().toLowerCase() ?? '');

  @override
  void initState() {
    super.initState();
    profile = Map<String, dynamic>.from(widget.auth.profile ?? const {});
    profileScrollController.addListener(_onProfileScroll);
    load();
  }

  @override
  void dispose() {
    profileScrollController.removeListener(_onProfileScroll);
    profileScrollController.dispose();
    super.dispose();
  }

  void _onProfileScroll() {
    if (!profileScrollController.hasClients ||
        loading ||
        loadingMoreProfilePosts ||
        !hasMoreProfilePosts) {
      return;
    }
    if (profileScrollController.position.maxScrollExtent -
            profileScrollController.position.pixels <
        420) {
      _loadMoreProfilePosts();
    }
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        if (profile.isEmpty) loading = true;
        error = null;
        profilePage = 1;
        hasMoreProfilePosts = true;
      });
    }
    try {
      final requested = widget.username?.trim().toLowerCase();
      final currentUsername =
          widget.auth.profile?['username']?.toString().toLowerCase();
      final own =
          requested == null ||
          requested.isEmpty ||
          requested == currentUsername;
      final fetched = await api.get(
        own ? 'profiles/me' : 'profiles/$requested',
        auth: own,
      );
      final fetchedProfile = fetched['profile'];
      if (fetchedProfile is! Map) {
        throw const ApiException('Eazy could not load this profile.');
      }
      final nextProfile = Map<String, dynamic>.from(fetchedProfile);
      nextProfile['displayName'] ??= nextProfile['display_name'];
      nextProfile['firstName'] ??= nextProfile['first_name'];
      nextProfile['lastName'] ??= nextProfile['last_name'];
      final firstName = nextProfile['firstName']?.toString().trim() ?? '';
      final middleName =
          (nextProfile['middleName'] ?? nextProfile['middle_name'])
              ?.toString()
              .trim() ??
          '';
      final lastName = nextProfile['lastName']?.toString().trim() ?? '';
      final composedName = [
        firstName,
        middleName,
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');
      if (composedName.isNotEmpty &&
          (nextProfile['displayName'] == null ||
              nextProfile['displayName'].toString().trim().isEmpty ||
              nextProfile['displayName'].toString().trim().toLowerCase() ==
                  'eazy user')) {
        nextProfile['displayName'] = composedName;
      }
      nextProfile['avatarUrl'] ??= nextProfile['avatar_url'];
      nextProfile['coverUrl'] ??= nextProfile['cover_url'];
      nextProfile['userId'] ??= nextProfile['user_id'];
      final actualUsername =
          (nextProfile['username'] ?? nextProfile['user_name'])
              ?.toString()
              .toLowerCase();
      if (actualUsername == null || actualUsername.isEmpty) {
        throw const ApiException('This profile has no username yet.');
      }
      final results = await Future.wait([
        api.get(
          'posts/profile/$actualUsername?type=grid&page=1&limit=50',
          auth: true,
        ),
        if (own) api.get('profiles/me/stats', auth: true),
        if (!own)
          api.get(
            'social/followers/$actualUsername?page=1&limit=1',
            auth: true,
          ),
        if (!own)
          api.get(
            'social/following/$actualUsername?page=1&limit=1',
            auth: true,
          ),
        if (!own) api.get('social/relationship/$actualUsername', auth: true),
        api.get(
          'marketplace/sellers/' +
              Uri.encodeComponent(actualUsername) +
              '/products?page=1&limit=6',
          auth: true,
        ),
      ]);
      final postResult = results[0];
      final rawPosts = postResult['items'] as List? ?? const [];
      final fetchedStats = own ? results[1]['stats'] : null;
      final relationship =
          own
              ? const <String, dynamic>{}
              : Map<String, dynamic>.from(results[3] as Map);
      final followState = own ? false : relationship['following'] == true;
      final sellerResult = own ? results[2] : results[4];
      final loadedSellerProducts = (sellerResult['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final newStats =
          own && fetchedStats is Map
              ? Map<String, dynamic>.from(fetchedStats)
              : <String, dynamic>{
                'posts':
                    (postResult['meta'] is Map
                        ? (postResult['meta'] as Map)['total']
                        : rawPosts.length) ??
                    rawPosts.length,
                'followers':
                    (own
                        ? 0
                        : ((results[1]['meta'] is Map
                                ? (results[1]['meta'] as Map)['total']
                                : 0) ??
                            0)),
                'following':
                    (own
                        ? 0
                        : ((results[2]['meta'] is Map
                                ? (results[2]['meta'] as Map)['total']
                                : 0) ??
                            0)),
              };
      // The public list endpoints return totals in their meta fields.
      if (!own) {
        newStats['followers'] =
            (results[1]['meta'] is Map
                ? (results[1]['meta'] as Map)['total']
                : 0) ??
            0;
        newStats['following'] =
            (results[2]['meta'] is Map
                ? (results[2]['meta'] as Map)['total']
                : 0) ??
            0;
      }
      List<Map<String, dynamic>> loadedHighlights = [];
      try {
        final highlightResult = await api.get(
          'stories/highlights/$actualUsername',
          auth: true,
        );
        loadedHighlights =
            (highlightResult['items'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
      } catch (_) {}
      if (mounted) {
        setState(() {
          profile = nextProfile;
          stats = newStats;
          ownPosts =
              rawPosts
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
          profilePage = 1;
          final total =
              postResult['meta'] is Map
                  ? int.tryParse(
                    (postResult['meta'] as Map)['total']?.toString() ?? '',
                  )
                  : null;
          hasMoreProfilePosts =
              total == null ? rawPosts.length >= 50 : rawPosts.length < total;
          isFollowing = followState;
          highlights = loadedHighlights;
          sellerProducts = loadedSellerProducts;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadMoreProfilePosts() async {
    if (loading || loadingMoreProfilePosts || !hasMoreProfilePosts) return;
    final username = profile['username']?.toString();
    if (username == null || username.isEmpty) return;
    setState(() => loadingMoreProfilePosts = true);
    try {
      final nextPage = profilePage + 1;
      final result = await api.get(
        'posts/profile/$username?type=grid&page=$nextPage&limit=50',
        auth: true,
      );
      final raw = result['items'] as List? ?? const [];
      final items =
          raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      final total =
          result['meta'] is Map
              ? int.tryParse((result['meta'] as Map)['total']?.toString() ?? '')
              : null;
      if (mounted) {
        setState(() {
          profilePage = nextPage;
          ownPosts.addAll(items);
          hasMoreProfilePosts =
              total == null ? items.length >= 50 : ownPosts.length < total;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => loadingMoreProfilePosts = false);
    }
  }

  Future<void> toggleFollow() async {
    final username = profile['username']?.toString() ?? '';
    if (username.isEmpty || followBusy) return;
    final wasFollowing = isFollowing;
    setState(() {
      isFollowing = !wasFollowing;
      followBusy = true;
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  Future<void> _openHighlight(Map<String, dynamic> highlight) async {
    final stories =
        (highlight['stories'] as List? ?? const []).whereType<Map>().map((
          item,
        ) {
          final story = Map<String, dynamic>.from(item);
          story['username'] = profile['username']?.toString() ?? 'Eazy user';
          story['isMine'] = isOwnProfile;
          return story;
        }).toList();
    if (stories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This highlight has no available stories.'),
          ),
        );
      }
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close highlight',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder:
          (ctx, _, _) => StoryViewer(
            stories: stories,
            api: api,
            onChanged: load,
            allowDelete: false,
            markSeen: false,
          ),
      transitionBuilder:
          (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
    );
  }

  Future<void> _deleteHighlight(Map<String, dynamic> highlight) async {
    final id = highlight['id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete highlight?'),
            content: Text(
              '“${highlight['title'] ?? 'Highlight'}” will be removed from your profile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.delete('stories/highlights/$id', auth: true);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Highlight deleted')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _createHighlight() async {
    try {
      final result = await api.get('stories/feed', auth: true);
      final mine =
          (result['items'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((story) => story['isMine'] == true)
              .toList();
      if (!mounted) return;
      if (mine.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Share a story first, then save it to a highlight.'),
          ),
        );
        return;
      }
      final selected = <String>{};
      final storyIds = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (ctx) => StatefulBuilder(
              builder:
                  (ctx, setSheetState) => SafeArea(
                    child: SizedBox(
                      height: MediaQuery.of(ctx).size.height * .65,
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Choose stories',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              children:
                                  mine.map((story) {
                                    final id = story['id']?.toString() ?? '';
                                    return CheckboxListTile(
                                      value: selected.contains(id),
                                      onChanged:
                                          (value) => setSheetState(() {
                                            if (value == true) {
                                              selected.add(id);
                                            } else {
                                              selected.remove(id);
                                            }
                                          }),
                                      title: Text(
                                        story['caption']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true
                                            ? story['caption'].toString()
                                            : 'Story from ${(story['createdAt']?.toString() ?? '').split('T').first}',
                                      ),
                                      subtitle: Text(
                                        '@${story['username'] ?? ''}',
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed:
                                    selected.isEmpty
                                        ? null
                                        : () => Navigator.pop(
                                          ctx,
                                          selected.toList(),
                                        ),
                                child: Text('Continue (${selected.length})'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
      );
      if (storyIds == null || storyIds.isEmpty || !mounted) return;
      final titleController = TextEditingController();
      final title = await showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Name your highlight'),
              content: TextField(
                controller: titleController,
                maxLength: 40,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. Moments'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      () => Navigator.pop(ctx, titleController.text.trim()),
                  child: const Text('Create'),
                ),
              ],
            ),
      );
      titleController.dispose();
      if (title == null || title.trim().isEmpty) return;
      await api.post(
        'stories/highlights',
        auth: true,
        body: {'title': title.trim(), 'storyIds': storyIds},
      );
      await load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }


  String _count(dynamic value) {
    final n = int.tryParse(value?.toString() ?? '') ?? 0;
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n % 1000000 < 100000 ? 0 : 1)}M';
    }
    if (n >= 10000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 < 100 ? 0 : 1)}K';
    }
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> editProfile() async {
    final first = TextEditingController(
      text: profile['firstName']?.toString() ?? '',
    );
    final last = TextEditingController(
      text: profile['lastName']?.toString() ?? '',
    );
    final username = TextEditingController(
      text: profile['username']?.toString() ?? '',
    );
    final bio = TextEditingController(text: profile['bio']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Edit your profile',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Keep your Eazy identity up to date.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: first,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                      ),
                      validator:
                          (v) =>
                              (v ?? '').trim().isEmpty
                                  ? 'Add your first name'
                                  : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: last,
                      decoration: const InputDecoration(labelText: 'Last name'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: username,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixText: '@',
                      ),
                      validator:
                          (v) =>
                              RegExp(
                                    r'^[a-zA-Z0-9_]{3,32}$',
                                  ).hasMatch((v ?? '').trim())
                                  ? null
                                  : 'Use 3–32 letters, numbers or underscores',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: bio,
                      maxLength: 150,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          Navigator.pop(ctx, {
                            'firstName': first.text.trim(),
                            'lastName': last.text.trim(),
                            'username': username.text.trim().toLowerCase(),
                            'bio': bio.text.trim(),
                          });
                        },
                        child: const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    first.dispose();
    last.dispose();
    username.dispose();
    bio.dispose();
    if (values == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await api.patch('profiles/me', auth: true, body: values);
      final updated = result['profile'];
      if (mounted) {
        setState(
          () =>
              profile = Map<String, dynamic>.from(
                updated is Map ? updated : {...profile, ...values},
              ),
        );
      }
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _changeCover() async {
    if (!isOwnProfile || saving) return;
    setState(() => saving = true);
    try {
      final upload = await EazyMediaService(api).pickAndUpload(kind: 'cover');
      if (upload == null) return;
      await api.patch(
        'profiles/me',
        auth: true,
        body: {'coverUrl': upload.path},
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile cover updated')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not update your profile cover. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (!isOwnProfile || avatarBusy) return;
    setState(() => avatarBusy = true);
    try {
      final upload = await EazyMediaService(api).pickAndUpload(kind: 'avatar');
      if (upload == null) return;
      await api.patch(
        'profiles/me',
        auth: true,
        body: {'avatarUrl': upload.path},
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not update your profile photo. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => avatarBusy = false);
    }
  }

  Future<void> _copyProfileLink() async {
    final username = profile['username']?.toString() ?? '';
    if (username.isEmpty) return;
    final link = 'https://eazy.app/u/' + username;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile link copied')),
      );
    }
  }

  Widget _sellerProductCard(BuildContext context, Map<String, dynamic> product) {
    final media = (product['media'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final imageUrl = media.isEmpty ? null : media.first['url']?.toString();
    final currency = product['currency']?.toString() ?? 'NGN';
    final price = product['priceAmount']?.toString() ?? '0.00';
    return SizedBox(
      width: 154,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductDetailPage(product: product)),
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 112,
                width: double.infinity,
                child: imageUrl == null
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.shopping_bag_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.image_not_supported_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 3),
                child: Text(
                  product['name']?.toString() ?? 'Product',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  (currency == 'NGN' ? '₦' : currency + ' ') + price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = profile['username']?.toString() ?? '';
    final name =
        profile['displayName']?.toString().trim().isNotEmpty == true
            ? profile['displayName'].toString()
            : [profile['firstName'], profile['lastName']]
                .where((e) => e != null && e.toString().trim().isNotEmpty)
                .join(' ');
    final avatar = profile['avatarUrl']?.toString();
    final cover = profile['coverUrl']?.toString();
    final bio = profile['bio']?.toString() ?? '';
    final postsCount = stats['posts'] ?? profile['postsCount'] ?? 0;
    final followers = stats['followers'] ?? profile['followersCount'] ?? 0;
    final following = stats['following'] ?? profile['followingCount'] ?? 0;

    return Stack(
      children: [
        SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: CustomScrollView(
          controller: profileScrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (profile['isPrivate'] == true)
                            const Padding(
                              padding: EdgeInsets.only(right: 7),
                              child: Icon(Icons.lock_outline_rounded, size: 18),
                            ),
                          Flexible(
                            child: Text(
                              username.isEmpty ? 'Your profile' : '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.7,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy profile link',
                      onPressed: username.isEmpty ? null : _copyProfileLink,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                    if (isOwnProfile)
                      IconButton(
                        tooltip: 'Create a post',
                        onPressed: () => context.go('/home?action=create'),
                        icon: const Icon(Icons.add_box_outlined),
                      ),
                    if (isOwnProfile)
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => context.push('/settings'),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 118,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                        image: cover != null && cover.startsWith('http')
                            ? DecorationImage(
                                image: NetworkImage(cover),
                                fit: BoxFit.cover,
                              )
                            : null,
                        gradient: cover == null || !cover.startsWith('http')
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF168C58), Color(0xFF073F2B)],
                              )
                            : null,
                      ),
                      child: Stack(
                        children: [
                          if (cover == null || !cover.startsWith('http'))
                            Positioned(
                              left: 16,
                              bottom: 14,
                              child: Text(
                                'Your Eazy space',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .92),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          if (isOwnProfile)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: FilledButton.tonalIcon(
                                onPressed: saving ? null : _changeCover,
                                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                                label: const Text('Edit cover'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: .75),
                              width: 2,
                            ),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 43,
                                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                backgroundImage:
                                    avatar != null && avatar.startsWith('http')
                                        ? NetworkImage(avatar)
                                        : null,
                                child:
                                    avatar == null || !avatar.startsWith('http')
                                        ? Icon(
                                            Icons.person_rounded,
                                            size: 42,
                                            color: Theme.of(context).colorScheme.primary,
                                          )
                                        : null,
                              ),
                              if (isOwnProfile)
                                Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Material(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: avatarBusy ? null : _changeAvatar,
                                      child: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: Center(
                                          child: avatarBusy
                                              ? SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Theme.of(context).colorScheme.onPrimary,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.camera_alt_rounded,
                                                  size: 15,
                                                  color: Theme.of(context).colorScheme.onPrimary,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: StatsRow(
                            posts: _count(postsCount),
                            followers: _count(followers),
                            following: _count(following),
                            loading: loading,
                            onFollowers: () => _showSocialList('Followers'),
                            onFollowing: () => _showSocialList('Following'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name.isEmpty ? 'Make Eazy yours' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (profile['category']?.toString().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          profile['category'].toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(bio, style: const TextStyle(height: 1.45)),
                      ),
                    if ((profile['location'] ?? profile['city'])?.toString().trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (profile['location'] ?? profile['city']).toString(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (isOwnProfile)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving ? null : editProfile,
                              child: Text(saving ? 'Saving…' : 'Edit profile'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final link = 'https://eazy.app/u/$username';
                                await Clipboard.setData(
                                  ClipboardData(text: link),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Profile link copied'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 17,
                              ),
                              label: const Text('Copy profile link', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Discover people',
                            onPressed: () => context.push('/discovery'),
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: followBusy ? null : toggleFollow,
                              child: Text(
                                followBusy
                                    ? 'Please wait…'
                                    : isFollowing
                                    ? 'Following'
                                    : 'Follow',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.go('/home?tab=chat'),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 17,
                              ),
                              label: const Text('Message'),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    const SizedBox(height: 8),
                    if (error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(EazyRadius.md),
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isOwnProfile || highlights.isNotEmpty)
              SliverToBoxAdapter(
                child: _HighlightsRow(
                  highlights: highlights,
                  ownProfile: isOwnProfile,
                  onNew: _createHighlight,
                  onOpen: _openHighlight,
                  onDelete: _deleteHighlight,
                ),
              ),
            if (sellerProducts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Shop',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        sellerProducts.length.toString() + ' listed',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 218,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: sellerProducts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => _sellerProductCard(context, sellerProducts[index]),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Posts',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            if (loading && ownPosts.isEmpty)
              const EazyProfileGridSkeleton(),
            if (!loading && ownPosts.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(2),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProfilePostTile(post: ownPosts[index]),
                    childCount: ownPosts.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 1,
                  ),
                ),
              ),
            if (!loading && ownPosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 42, 28, 100),
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 42,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (int.tryParse(postsCount.toString()) ?? 0) > 0
                            ? 'Posts are not available on this page yet'
                            : isOwnProfile
                                ? 'Share your first moment'
                                : 'No posts yet',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isOwnProfile
                            ? 'Build your corner of Eazy, one post at a time.'
                            : 'New posts will appear here when they are shared.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      if (isOwnProfile)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: FilledButton.icon(
                            onPressed: () => context.go('/home'),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create a post'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (loadingMoreProfilePosts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (error != null && ownPosts.isEmpty && !loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Could not refresh all profile content. Pull down to retry.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    ),
        if (widget.username != null)
          const Positioned(
            right: 16,
            bottom: 24,
            child: EazyAssistFab(),
          ),
      ],
    );
  }

  void _showSocialList(String title) {
    final username = profile['username']?.toString() ?? '';
    final direction =
        title.toLowerCase() == 'followers' ? 'followers' : 'following';
    final search = TextEditingController();
    List<Map<String, dynamic>> people = [];
    bool listLoading = true;
    bool listLoadingMore = false;
    bool listHasMore = true;
    int listPage = 1;
    String? listError;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setSheetState) {
              if (listLoading && people.isEmpty && listError == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    final result = await api.get(
                      'social/$direction/$username?page=1&limit=50',
                      auth: true,
                    );
                    people =
                        (result['items'] as List? ?? const [])
                            .whereType<Map>()
                            .map((e) => Map<String, dynamic>.from(e))
                            .toList();
                    final total =
                        result['meta'] is Map
                            ? int.tryParse(
                              (result['meta'] as Map)['total']?.toString() ??
                                  '',
                            )
                            : null;
                    listHasMore =
                        total == null
                            ? people.length >= 50
                            : people.length < total;
                  } on ApiException catch (e) {
                    listError = e.message;
                  }
                  listLoading = false;
                  if (ctx.mounted) setSheetState(() {});
                });
              }
              Future<void> loadMorePeople() async {
                if (listLoading || listLoadingMore || !listHasMore) return;
                listLoadingMore = true;
                setSheetState(() {});
                try {
                  final nextPage = listPage + 1;
                  final result = await api.get(
                    'social/$direction/$username?page=$nextPage&limit=50',
                    auth: true,
                  );
                  final raw =
                      (result['items'] as List? ?? const [])
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList();
                  final total =
                      result['meta'] is Map
                          ? int.tryParse(
                            (result['meta'] as Map)['total']?.toString() ?? '',
                          )
                          : null;
                  people.addAll(raw);
                  listPage = nextPage;
                  listHasMore =
                      total == null ? raw.length >= 50 : people.length < total;
                } on ApiException catch (e) {
                  if (mounted && ctx.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                } finally {
                  listLoadingMore = false;
                  if (ctx.mounted) setSheetState(() {});
                }
              }

              final filtered =
                  people.where((person) {
                    final q = search.text.trim().toLowerCase();
                    return q.isEmpty ||
                        (person['username']?.toString().toLowerCase().contains(
                              q,
                            ) ??
                            false) ||
                        (person['displayName']
                                ?.toString()
                                .toLowerCase()
                                .contains(q) ??
                            false);
                  }).toList();
              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * .72,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Search $direction',
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child:
                            listLoading
                                ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                                : listError != null
                                ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      listError!,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                                : filtered.isEmpty
                                ? Center(
                                  child: Text(
                                    people.isEmpty
                                        ? 'No $direction yet.'
                                        : 'No matching people.',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                                : ListView.separated(
                                  itemCount:
                                      filtered.length + (listHasMore ? 1 : 0),
                                  separatorBuilder:
                                      (_, _) =>
                                          const Divider(height: 1, indent: 72),
                                  itemBuilder: (_, index) {
                                    if (index >= filtered.length) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Center(
                                          child: TextButton.icon(
                                            onPressed:
                                                listLoadingMore
                                                    ? null
                                                    : loadMorePeople,
                                            icon:
                                                listLoadingMore
                                                    ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                    : const Icon(
                                                      Icons.expand_more_rounded,
                                                    ),
                                            label: Text(
                                              listLoadingMore
                                                  ? 'Loading…'
                                                  : 'Load more',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final person = filtered[index];
                                    final avatar =
                                        person['avatarUrl']?.toString();
                                    final name =
                                        person['displayName']?.toString() ??
                                        person['username']?.toString() ??
                                        'Eazy user';
                                    final handle =
                                        person['username']?.toString() ?? '';
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Theme.of(context).colorScheme.surfaceContainerHighest,
                                        backgroundImage:
                                            avatar != null &&
                                                    avatar.startsWith('http')
                                                ? NetworkImage(avatar)
                                                : null,
                                        child:
                                            avatar == null ||
                                                    !avatar.startsWith('http')
                                                ? Icon(
                                                  Icons.person_rounded,
                                                  color: Theme.of(context).colorScheme.primary,
                                                )
                                                : null,
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text('@$handle'),
                                      onTap:
                                          handle.isEmpty
                                              ? null
                                              : () {
                                                Navigator.pop(ctx);
                                                context.push(
                                                  '/profile/$handle',
                                                );
                                              },
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    ).whenComplete(search.dispose);
  }
}

class _HighlightsRow extends StatelessWidget {
  const _HighlightsRow({
    required this.highlights,
    required this.ownProfile,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });
  final List<Map<String, dynamic>> highlights;
  final bool ownProfile;
  final VoidCallback onNew;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        if (ownProfile)
          SizedBox(
            width: 78,
            child: InkWell(
              onTap: onNew,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.add_rounded, size: 28),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text('New', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ...highlights.map((highlight) {
          final cover = highlight['coverUrl']?.toString();
          return SizedBox(
            width: 78,
            child: InkWell(
              onTap: () => onOpen(highlight),
              onLongPress: ownProfile ? () => onDelete(highlight) : null,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          cover != null && cover.startsWith('http')
                              ? NetworkImage(cover)
                              : null,
                      child:
                          cover == null || !cover.startsWith('http')
                              ? Icon(
                                Icons.auto_awesome_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              )
                              : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    highlight['title']?.toString() ?? 'Highlight',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}

class StatsRow extends StatelessWidget {
  const StatsRow({
    super.key,
    required this.posts,
    required this.followers,
    required this.following,
    required this.loading,
    required this.onFollowers,
    required this.onFollowing,
  });
  final String posts, followers, following;
  final bool loading;
  final VoidCallback onFollowers, onFollowing;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: [
      _Stat(posts, 'Posts', loading, () {}),
      _Stat(followers, 'Followers', loading, onFollowers),
      _Stat(following, 'Following', loading, onFollowing),
    ],
  );
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
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Column(
        children: [
          Text(
            loading ? '—' : value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}
