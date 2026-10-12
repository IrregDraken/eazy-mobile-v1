import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  final api = ApiClient();
  final composer = TextEditingController();
  late final EazyMediaService media;
  bool loading = true, posting = false;
  String? error;
  String mode = 'for_you';
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> suggestions = [];
  final dismissedSuggestions = <String>{};
  final followedSuggestions = <String>{};

  @override
  void initState() {
    super.initState();
    media = EazyMediaService(api);
    load();
  }

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api.get(
        'home/feed?page=1&limit=50&mode=$mode',
        auth: true,
      );
      final raw = result['items'] as List? ?? const [];
      posts = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      try {
        final people = await api.get('discover?type=people&page=1&limit=8', auth: true);
        suggestions = (people['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        suggestions = [];
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> followSuggestion(Map<String, dynamic> person) async {
    final username = person['username']?.toString().replaceFirst('@', '').toLowerCase() ?? '';
    if (username.isEmpty || followedSuggestions.contains(username)) return;
    try {
      await api.post('social/follow/$username', auth: true);
      if (mounted) setState(() => followedSuggestions.add(username));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> compose() async {
    composer.clear();
    MediaUpload? attachment;
    final body = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create a post',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: composer,
                  maxLines: 6,
                  maxLength: 5000,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Share something with your world',
                  ),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder:
                      (ctx, setSheetState) => Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                () => media.pickAndUpload(kind: 'post').then((
                                  value,
                                ) {
                                  attachment = value;
                                  setSheetState(() {});
                                }),
                            icon: const Icon(Icons.photo_outlined),
                            label: Text(
                              attachment == null
                                  ? 'Add photo'
                                  : 'Photo attached',
                            ),
                          ),
                          if (attachment != null)
                            const Padding(
                              padding: EdgeInsets.only(left: 10),
                              child: Icon(
                                Icons.check_circle,
                                color: EazyColors.green,
                              ),
                            ),
                        ],
                      ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, composer.text.trim()),
                    child: const Text('Publish'),
                  ),
                ),
              ],
            ),
          ),
    );
    if (body == null || body.isEmpty) return;
    setState(() => posting = true);
    try {
      await api.post(
        'posts',
        auth: true,
        body: {
          'content': body,
          'visibility': 'public',
          'media': [
            if (attachment != null)
              {
                'storageKey': attachment!.path,
                'mediaType': 'image',
                'position': 0,
              },
          ],
        },
      );
      await load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [EazyColors.green, EazyColors.greenDeep],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text('E', style: TextStyle(color: EazyColors.canvas, fontSize: 23, fontWeight: FontWeight.w900, height: 1)),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Eazy',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: EazyColors.muted, size: 19),
                        ]),
                        const SizedBox(height: 3),
                        const Text(
                          'Your world, made easier',
                          style: TextStyle(color: EazyColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: posting ? null : compose,
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: EazyColors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children:
                    ['for_you', 'following', 'trending']
                        .map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                value == 'for_you'
                                    ? 'For you'
                                    : value[0].toUpperCase() +
                                        value.substring(1),
                              ),
                              selected: mode == value,
                              onSelected: (_) {
                                if (mode == value) return;
                                setState(() => mode = value);
                                load();
                              },
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!loading && error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _State(error!, load),
            ),
          if (!loading && error == null && posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _State(
                'Nothing here yet. Follow people or publish the first post.',
                compose,
              ),
            ),
          if (!loading && posts.isNotEmpty)
            SliverList.builder(
              itemCount: posts.length + (suggestions.isNotEmpty ? posts.length ~/ 10 : 0),
              itemBuilder: (c, i) {
                if ((i + 1) % 11 == 0 && suggestions.isNotEmpty) {
                  return _SuggestedAccounts(
                    people: suggestions.where((person) {
                      final username = person['username']?.toString().toLowerCase() ?? '';
                      final id = person['id']?.toString() ?? username;
                      return !dismissedSuggestions.contains(id);
                    }).toList(),
                    followed: followedSuggestions,
                    onFollow: followSuggestion,
                    onDismiss: (person) => setState(() {
                      dismissedSuggestions.add(person['id']?.toString() ?? person['username']?.toString() ?? '');
                    }),
                  );
                }
                final postIndex = i - ((i + 1) ~/ 11);
                if (postIndex < 0 || postIndex >= posts.length) return const SizedBox.shrink();
                return _Post(post: posts[postIndex], api: api, onChanged: load);
              },
            ),
        ],
      ),
    ),
  );
}

class _Post extends StatefulWidget {
  const _Post({required this.post, required this.api, required this.onChanged});
  final Map<String, dynamic> post;
  final ApiClient api;
  final Future<void> Function() onChanged;
  @override
  State<_Post> createState() => _PostState();
}

class _PostState extends State<_Post> {
  bool busy = false;
  Future<void> mutate(
    String action,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (action == 'post') {
        await widget.api.post(path, auth: true, body: body);
      } else {
        await widget.api.delete(path, auth: true);
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await widget.onChanged();
      }
    }
  }

  Future<void> comment() async {
    final id = widget.post['id']?.toString() ?? '';
    final controller = TextEditingController();
    List<Map<String, dynamic>> comments = [];
    bool commentsLoading = true;
    bool sendingComment = false;
    String? commentError;

    Future<void> refreshComments(StateSetter setSheetState) async {
      try {
        final result = await widget.api.get('posts/$id/comments?page=1&limit=50', auth: true);
        comments = (result['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        commentError = null;
      } on ApiException catch (e) {
        commentError = e.message;
      } finally {
        commentsLoading = false;
        setSheetState(() {});
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: EazyColors.surface,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .82),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (commentsLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (commentsLoading) refreshComments(setSheetState);
            });
          }
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * .68,
              child: Column(children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                const Divider(height: 1),
                Expanded(child: commentsLoading
                    ? const Center(child: CircularProgressIndicator())
                    : commentError != null && comments.isEmpty
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 34, color: EazyColors.muted),
                              const SizedBox(height: 10),
                              Text(commentError!, textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted)),
                              const SizedBox(height: 10),
                              OutlinedButton(onPressed: () { commentsLoading = true; refreshComments(setSheetState); }, child: const Text('Try again')),
                            ],
                          )))
                        : comments.isEmpty
                            ? const Center(child: Text('Start the conversation.', style: TextStyle(color: EazyColors.muted)))
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                itemCount: comments.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (_, index) => _CommentTile(comment: comments[index]),
                              )),
                const Divider(height: 1),
                SafeArea(top: false, child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(hintText: 'Add a comment…', counterText: ''),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Post comment',
                      onPressed: sendingComment ? null : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        setSheetState(() => sendingComment = true);
                        try {
                          await widget.api.post('posts/$id/comments', auth: true, body: {'content': text});
                          controller.clear();
                          await refreshComments(setSheetState);
                          await widget.onChanged();
                        } on ApiException catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        } finally {
                          setSheetState(() => sendingComment = false);
                        }
                      },
                      icon: sendingComment
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: EazyColors.green),
                    ),
                  ]),
                )),
              ]),
            ),
          );
        },
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final author =
        widget.post['author'] is Map
            ? Map<String, dynamic>.from(widget.post['author'] as Map)
            : const <String, dynamic>{};
    final liked = widget.post['likedByViewer'] == true;
    final saved = widget.post['savedByViewer'] == true;
    final id = widget.post['id']?.toString() ?? '';
    final media =
        widget.post['media'] is List ? widget.post['media'] as List : const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage:
                        (author['avatarUrl']?.toString().startsWith('http') ==
                                true)
                            ? NetworkImage(author['avatarUrl'])
                            : null,
                    child: const Icon(Icons.person_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author['displayName']?.toString() ?? 'Eazy user',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          author['username']?.toString().isNotEmpty == true
                              ? '@${author['username']}'
                              : 'Eazy',
                          style: const TextStyle(
                            color: EazyColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Post options',
                    icon: const Icon(Icons.more_horiz_rounded, color: EazyColors.muted),
                    onSelected: (value) async {
                      if (value == 'save') {
                        await mutate(saved ? 'delete' : 'post', 'posts/$id/save');
                      } else if (value == 'report') {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report options will be available with Eazy moderation controls.')));
                      } else if (value == 'copy') {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A shareable post link is not available for this post yet.')));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'save', child: Text(saved ? 'Remove from saved' : 'Save post')),
                      const PopupMenuItem(value: 'copy', child: Text('Copy link')),
                      const PopupMenuItem(value: 'report', child: Text('Report post')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.post['content']?.toString() ?? '',
                style: const TextStyle(height: 1.45, fontSize: 15),
              ),
              if (media.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 220,
                  child: PageView.builder(
                    itemCount: media.length,
                    itemBuilder: (c, i) {
                      final m =
                          media[i] is Map
                              ? Map<String, dynamic>.from(media[i] as Map)
                              : {};
                      final url = m['url']?.toString();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child:
                            url != null
                                ? Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => const ColoredBox(
                                        color: EazyColors.surfaceRaised,
                                        child: Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                      ),
                                )
                                : const ColoredBox(
                                  color: EazyColors.surfaceRaised,
                                  child: Center(
                                    child: Icon(Icons.image_outlined),
                                  ),
                                ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed:
                        busy
                            ? null
                            : () => mutate(
                              liked ? 'delete' : 'post',
                              'posts/$id/like',
                            ),
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? EazyColors.red : null,
                    ),
                    label: Text('${widget.post['likeCount'] ?? 0}'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : comment,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text('${widget.post['commentCount'] ?? 0}'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed:
                        busy
                            ? null
                            : () => mutate(
                              saved ? 'delete' : 'post',
                              'posts/$id/save',
                            ),
                    icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Map<String, dynamic> comment;
  @override
  Widget build(BuildContext context) {
    final author = comment['author'] is Map ? Map<String, dynamic>.from(comment['author'] as Map) : <String, dynamic>{};
    final name = author['displayName']?.toString() ?? author['username']?.toString() ?? 'Eazy user';
    final username = author['username']?.toString();
    final avatar = author['avatarUrl']?.toString();
    final created = comment['createdAt']?.toString() ?? '';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(
        radius: 17,
        backgroundColor: EazyColors.surfaceRaised,
        backgroundImage: avatar != null && avatar.startsWith('http') ? NetworkImage(avatar) : null,
        child: avatar == null || !avatar.startsWith('http') ? Text(name.isEmpty ? 'E' : name.characters.first.toUpperCase(), style: const TextStyle(color: EazyColors.green, fontSize: 12, fontWeight: FontWeight.w900)) : null,
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(username == null || username.isEmpty ? name : '@$username', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        const SizedBox(height: 3),
        Text(comment['content']?.toString() ?? '', style: const TextStyle(height: 1.4)),
        if (created.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(created.length >= 10 ? created.substring(0, 10) : created, style: const TextStyle(color: EazyColors.muted, fontSize: 10))),
      ])),
    ]);
  }
}

class _SuggestedAccounts extends StatelessWidget {
  const _SuggestedAccounts({required this.people, required this.followed, required this.onFollow, required this.onDismiss});
  final List<Map<String, dynamic>> people;
  final Set<String> followed;
  final Future<void> Function(Map<String, dynamic>) onFollow;
  final ValueChanged<Map<String, dynamic>> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 0, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(right: 20, bottom: 10),
          child: Row(children: [
            const Expanded(child: Text('People to know on Eazy', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            const Icon(Icons.auto_awesome_rounded, color: EazyColors.green, size: 18),
          ]),
        ),
        SizedBox(
          height: 166,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final person = people[index];
              final username = person['username']?.toString() ?? '';
              final id = person['id']?.toString() ?? username;
              final name = person['displayName']?.toString() ?? person['display_name']?.toString() ?? username;
              final avatar = person['avatarUrl']?.toString() ?? person['avatar_url']?.toString();
              final isFollowed = followed.contains(username.toLowerCase());
              return Container(
                width: 142,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EazyColors.surface,
                  borderRadius: BorderRadius.circular(EazyRadius.md),
                  border: Border.all(color: EazyColors.border),
                ),
                child: Column(children: [
                  Align(alignment: Alignment.topRight, heightFactor: .5, child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    icon: const Icon(Icons.close_rounded, size: 16, color: EazyColors.muted),
                    onPressed: () => onDismiss(person),
                  )),
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: EazyColors.surfaceRaised,
                    backgroundImage: avatar != null && avatar.startsWith('http') ? NetworkImage(avatar) : null,
                    child: avatar == null || !avatar.startsWith('http') ? Text(name.isEmpty ? 'E' : name.characters.first.toUpperCase(), style: const TextStyle(color: EazyColors.green, fontWeight: FontWeight.w900)) : null,
                  ),
                  const SizedBox(height: 7),
                  Text(name.isEmpty ? 'Eazy member' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  Text(username.isEmpty ? 'On Eazy' : '@$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: EazyColors.muted, fontSize: 10)),
                  const Spacer(),
                  SizedBox(width: double.infinity, height: 30, child: FilledButton(
                    onPressed: isFollowed ? null : () => onFollow(person),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                    child: Text(isFollowed ? 'Following' : 'Follow', style: const TextStyle(fontSize: 11)),
                  )),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
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
          const Icon(
            Icons.dynamic_feed_outlined,
            size: 44,
            color: EazyColors.green,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EazyColors.muted, height: 1.4),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: action, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
