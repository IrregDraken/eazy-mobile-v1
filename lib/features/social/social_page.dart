import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';
import 'stories_tray.dart';
import 'video_media.dart';

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
  final ScrollController scrollController = ScrollController();
  int page = 1;
  bool hasMore = true, loadingMore = false, newPostsAvailable = false;
  final dismissedSuggestions = <String>{};
  final followedSuggestions = <String>{};

  @override
  void initState() {
    super.initState();
    media = EazyMediaService(api);
    scrollController.addListener(_onScroll);
    load();
  }

  @override
  void dispose() {
    composer.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients || loading || loadingMore || !hasMore) {
      return;
    }
    if (scrollController.position.maxScrollExtent -
            scrollController.position.pixels <
        500) {
      loadMore();
    }
  }

  Future<void> load() async {
    final previousFirst =
        posts.isNotEmpty ? posts.first['id']?.toString() : null;
    final wasScrolled =
        scrollController.hasClients && scrollController.offset > 180;
    if (mounted) {
      setState(() {
        if (posts.isEmpty) loading = true;
        error = null;
        page = 1;
        hasMore = true;
      });
    }
    try {
      // The current people-discovery endpoint requires a search query, so
      // requesting an empty recommendation feed only adds a failed round trip.
      // Keep the feed as the critical home-screen request.
      final result = await api.get(
        'home/feed?page=1&limit=20&mode=$mode',
        auth: true,
      );
      suggestions = [];
      final raw = result['items'] as List? ?? const [];
      final loaded = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final total = result['meta'] is Map
          ? int.tryParse((result['meta'] as Map)['total']?.toString() ?? '')
          : null;
      if (mounted) {
        setState(() {
          if (wasScrolled &&
              previousFirst != null &&
              loaded.isNotEmpty &&
              loaded.first['id']?.toString() != previousFirst) {
            newPostsAvailable = true;
          }
          posts = loaded;
          hasMore = total == null ? loaded.length == 20 : loaded.length < total;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final nextPage = page + 1;
      final result = await api.get(
        'home/feed?page=$nextPage&limit=20&mode=$mode',
        auth: true,
      );
      final raw = result['items'] as List? ?? const [];
      final loaded =
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
          page = nextPage;
          posts.addAll(loaded);
          hasMore = total == null ? loaded.length == 20 : posts.length < total;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> followSuggestion(Map<String, dynamic> person) async {
    final username =
        person['username']?.toString().replaceFirst('@', '').toLowerCase() ??
        '';
    if (username.isEmpty || followedSuggestions.contains(username)) return;
    try {
      await api.post('social/follow/$username', auth: true);
      if (mounted) setState(() => followedSuggestions.add(username));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> compose() async {
    composer.clear();
    MediaUpload? attachment;
    Future<void> chooseMedia(bool video, StateSetter setSheetState) async {
      try {
        final value =
            video
                ? await media.pickAndUploadVideo(kind: 'post')
                : await media.pickAndUpload(kind: 'post');
        if (value != null) {
          attachment = value;
          setSheetState(() {});
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

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
                      (ctx, setSheetState) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => chooseMedia(false, setSheetState),
                            icon: Icon(Icons.photo_outlined),
                            label: Text(
                              attachment != null &&
                                      !attachment!.contentType.startsWith(
                                        'video/',
                                      )
                                  ? 'Photo attached'
                                  : 'Add photo',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => chooseMedia(true, setSheetState),
                            icon: Icon(Icons.video_library_outlined),
                            label: Text(
                              attachment != null &&
                                      attachment!.contentType.startsWith(
                                        'video/',
                                      )
                                  ? 'Video attached'
                                  : 'Add video',
                            ),
                          ),
                          if (attachment != null)
                            Icon(
                              Icons.check_circle,
                              color: context.eazyAccent,
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
    if (body == null || (body.isEmpty && attachment == null)) return;
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
                'mediaType':
                    attachment!.contentType.startsWith('video/')
                        ? 'video'
                        : 'image',
                'position': 0,
              },
          ],
        },
      );
      await load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Home',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                    icon: Icon(Icons.notifications_none_rounded),
                  ),
                  IconButton(
                    onPressed: posting ? null : compose,
                    icon: Icon(
                      Icons.add_circle_rounded,
                      color: context.eazyAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (newPostsAvailable)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      setState(() => newPostsAvailable = false);
                      if (scrollController.hasClients) {
                        await scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    icon: Icon(Icons.arrow_upward_rounded, size: 16),
                    label: const Text('New posts'),
                  ),
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
          SliverToBoxAdapter(child: StoriesTray(api: api, media: media)),
          SliverToBoxAdapter(
            child: Divider(height: 1, color: context.eazyBorder),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 10)),
          if (loading && posts.isEmpty)
            SliverToBoxAdapter(child: _FeedLoadingSkeleton()),
          if (!loading && error != null && posts.isEmpty)
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
          if (loading && posts.isNotEmpty)
            SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (!loading && error != null && posts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  'Could not refresh feed: $error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (posts.isNotEmpty && loadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          if (!loading && !hasMore && posts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 100),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: context.eazyAccent,
                          size: 30,
                        ),
                        SizedBox(height: 8),
                        Text(
                          "You're all caught up",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'You have seen the latest from your Eazy circle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.eazyMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SliverList.builder(
            itemCount:
                posts.length +
                (suggestions.isNotEmpty ? posts.length ~/ 10 : 0),
            itemBuilder: (c, i) {
              if ((i + 1) % 11 == 0 && suggestions.isNotEmpty) {
                return _SuggestedAccounts(
                  people:
                      suggestions.where((person) {
                        final username =
                            person['username']?.toString().toLowerCase() ?? '';
                        final id = person['id']?.toString() ?? username;
                        return !dismissedSuggestions.contains(id);
                      }).toList(),
                  followed: followedSuggestions,
                  onFollow: followSuggestion,
                  onDismiss:
                      (person) => setState(() {
                        dismissedSuggestions.add(
                          person['id']?.toString() ??
                              person['username']?.toString() ??
                              '',
                        );
                      }),
                );
              }
              final postIndex = i - ((i + 1) ~/ 11);
              if (postIndex < 0 || postIndex >= posts.length) {
                return const SizedBox.shrink();
              }
              return _Post(
                post: posts[postIndex],
                api: api,
                onChanged: load,
                currentUsername:
                    widget.auth.profile?['username']?.toString() ?? '',
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _Post extends StatefulWidget {
  const _Post({
    required this.post,
    required this.api,
    required this.onChanged,
    required this.currentUsername,
  });
  final Map<String, dynamic> post;
  final ApiClient api;
  final Future<void> Function() onChanged;
  final String currentUsername;
  @override
  State<_Post> createState() => _PostState();
}

class _PostState extends State<_Post> {
  bool busy = false, showHeart = false;
  Timer? heartTimer;

  @override
  void dispose() {
    heartTimer?.cancel();
    super.dispose();
  }

  Future<void> doubleLike() async {
    HapticFeedback.lightImpact();
    heartTimer?.cancel();
    setState(() => showHeart = true);
    if (widget.post['likedByViewer'] != true) {
      await mutate('post', 'posts/${widget.post['id']}/like');
    }
    heartTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => showHeart = false);
    });
  }

  Future<void> mutate(
    String action,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (busy) return;
    final previous = <String, dynamic>{};
    final wasLike = widget.post['likedByViewer'] == true;
    final wasSave = widget.post['savedByViewer'] == true;
    final wasPinned = widget.post['isPinned'] == true;
    if (path.endsWith('/like')) {
      previous['likedByViewer'] = wasLike;
      previous['likeCount'] = widget.post['likeCount'] ?? 0;
      widget.post['likedByViewer'] = action == 'post';
      widget.post['likeCount'] =
          (int.tryParse(widget.post['likeCount']?.toString() ?? '') ?? 0) +
          (action == 'post' ? 1 : -1);
    } else if (path.endsWith('/save')) {
      previous['savedByViewer'] = wasSave;
      widget.post['savedByViewer'] = action == 'post';
    } else if (path.endsWith('/pin')) {
      previous['isPinned'] = wasPinned;
      widget.post['isPinned'] = action == 'post';
    }
    setState(() => busy = true);
    try {
      if (action == 'post') {
        await widget.api.post(path, auth: true, body: body);
      } else {
        await widget.api.delete(path, auth: true);
      }
    } on ApiException catch (e) {
      widget.post.addAll(previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
    String? replyToId;
    String? replyToName;

    Future<void> refreshComments(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      try {
        final result = await widget.api.get(
          'posts/$id/comments?page=1&limit=50',
          auth: true,
        );
        comments =
            (result['items'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        commentError = null;
      } on ApiException catch (e) {
        commentError = e.message;
      } finally {
        commentsLoading = false;
        if (sheetContext.mounted) setSheetState(() {});
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .82,
      ),
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (ctx, setSheetState) {
              if (commentsLoading) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (commentsLoading) refreshComments(ctx, setSheetState);
                });
              }
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * .68,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 14),
                        child: Text(
                          'Comments',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child:
                            commentsLoading
                                ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                                : commentError != null && comments.isEmpty
                                ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 34,
                                          color: context.eazyMuted,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          commentError!,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: context.eazyMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        OutlinedButton(
                                          onPressed: () {
                                            commentsLoading = true;
                                            refreshComments(ctx, setSheetState);
                                          },
                                          child: const Text('Try again'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                : comments.isEmpty
                                ? Center(
                                  child: Text(
                                    'Start the conversation.',
                                    style: TextStyle(color: context.eazyMuted),
                                  ),
                                )
                                : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    16,
                                  ),
                                  itemCount: comments.length,
                                  separatorBuilder:
                                      (_, _) => const SizedBox(height: 16),
                                  itemBuilder:
                                      (_, index) => _CommentTile(
                                        comment: comments[index],
                                        api: widget.api,
                                        currentUsername: widget.currentUsername,
                                        onChanged: () async {
                                          if (ctx.mounted) {
                                            commentsLoading = true;
                                            await refreshComments(
                                              ctx,
                                              setSheetState,
                                            );
                                          }
                                        },
                                        onReply: (comment) {
                                          setSheetState(() {
                                            replyToId =
                                                comment['id']?.toString();
                                            final author =
                                                comment['author'] is Map
                                                    ? Map<String, dynamic>.from(
                                                      comment['author'] as Map,
                                                    )
                                                    : <String, dynamic>{};
                                            replyToName =
                                                author['username']
                                                    ?.toString() ??
                                                author['displayName']
                                                    ?.toString() ??
                                                'user';
                                          });
                                        },
                                      ),
                                ),
                      ),
                      const Divider(height: 1),
                      if (replyToId != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Replying to @$replyToName',
                                  style: TextStyle(
                                    color: context.eazyMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed:
                                    () => setSheetState(() {
                                      replyToId = null;
                                      replyToName = null;
                                    }),
                                icon: Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                        ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 2000,
                                  decoration: const InputDecoration(
                                    hintText: 'Add a comment…',
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Post comment',
                                onPressed:
                                    sendingComment
                                        ? null
                                        : () async {
                                          final text = controller.text.trim();
                                          if (text.isEmpty) return;
                                          setSheetState(
                                            () => sendingComment = true,
                                          );
                                          try {
                                            await widget.api.post(
                                              'posts/$id/comments',
                                              auth: true,
                                              body: {
                                                'content': text,
                                                if (replyToId != null)
                                                  'parentId': replyToId,
                                              },
                                            );
                                            if (!ctx.mounted) {
                                              if (mounted) {
                                                await widget.onChanged();
                                              }
                                              return;
                                            }
                                            controller.clear();
                                            replyToId = null;
                                            replyToName = null;
                                            await refreshComments(
                                              ctx,
                                              setSheetState,
                                            );
                                            await widget.onChanged();
                                          } on ApiException catch (e) {
                                            if (mounted && ctx.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(e.message),
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (ctx.mounted) {
                                              setSheetState(
                                                () => sendingComment = false,
                                              );
                                            }
                                          }
                                        },
                                icon:
                                    sendingComment
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : Icon(
                                          Icons.send_rounded,
                                          color: context.eazyAccent,
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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
                    child: Icon(Icons.person_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        final username = author['username']?.toString() ?? '';
                        if (username.isNotEmpty) {
                          context.push('/profile/$username');
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author['displayName']?.toString() ?? 'Eazy user',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            author['username']?.toString().isNotEmpty == true
                                ? '@${author['username']}'
                                : 'Eazy',
                            style: TextStyle(
                              color: context.eazyMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Post options',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: context.eazyMuted,
                    ),
                    onSelected: (value) async {
                      if (value == 'save') {
                        await mutate(
                          saved ? 'delete' : 'post',
                          'posts/$id/save',
                        );
                      } else if (value == 'report') {
                        final controller = TextEditingController();
                        final reason = await showDialog<String>(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('Report post'),
                              content: TextField(
                                controller: controller,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Tell us what is wrong with this post',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed:
                                      () => Navigator.pop(
                                        ctx,
                                        controller.text.trim(),
                                      ),
                                  child: const Text('Submit'),
                                ),
                              ],
                            );
                          },
                        );
                        controller.dispose();
                        if (reason != null && reason.length >= 3) {
                          await mutate(
                            'post',
                            'posts/$id/report',
                            body: {'reason': reason},
                          );
                        }
                      } else if (value == 'copy') {
                        await Clipboard.setData(
                          ClipboardData(text: 'https://eazy.app/p/$id'),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Post link copied')),
                          );
                        }
                      } else if (value == 'pin') {
                        await mutate('post', 'posts/$id/pin');
                      } else if (value == 'unpin') {
                        await mutate('delete', 'posts/$id/pin');
                      } else if (value == 'tag') {
                        final controller = TextEditingController();
                        final raw = await showDialog<String>(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('Tag people'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  hintText: 'username1, username2',
                                ),
                                maxLines: 2,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed:
                                      () => Navigator.pop(ctx, controller.text),
                                  child: const Text('Tag'),
                                ),
                              ],
                            );
                          },
                        );
                        controller.dispose();
                        if (raw != null) {
                          final names =
                              raw
                                  .split(',')
                                  .map(
                                    (name) => name.trim().replaceFirst(
                                      RegExp(r'^@'),
                                      '',
                                    ),
                                  )
                                  .where((name) => name.isNotEmpty)
                                  .toList();
                          if (names.isNotEmpty) {
                            await mutate(
                              'post',
                              'posts/$id/tags',
                              body: {'usernames': names},
                            );
                          }
                        }
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: 'save',
                            child: Text(
                              saved ? 'Remove from saved' : 'Save post',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: Text('Copy link'),
                          ),
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('Report post'),
                          ),
                          if ((author['username']?.toString().toLowerCase() ??
                                  '') ==
                              widget.currentUsername.toLowerCase()) ...[
                            const PopupMenuItem(
                              value: 'tag',
                              child: Text('Tag people'),
                            ),
                            PopupMenuItem(
                              value:
                                  widget.post['isPinned'] == true
                                      ? 'unpin'
                                      : 'pin',
                              child: Text(
                                widget.post['isPinned'] == true
                                    ? 'Unpin from profile'
                                    : 'Pin to profile',
                              ),
                            ),
                          ],
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.post['content']?.toString() ?? '',
                style: TextStyle(height: 1.45, fontSize: 15),
              ),
              if (widget.post['taggedUsers'] is List &&
                  (widget.post['taggedUsers'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children:
                        (widget.post['taggedUsers'] as List)
                            .whereType<Map>()
                            .map(
                              (person) => Text(
                                '@${person['username']}',
                                style: TextStyle(
                                  color: context.eazyAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              if (media.isNotEmpty) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onDoubleTap: doubleLike,
                  child: SizedBox(
                    height: 220,
                    child: Stack(
                      children: [
                        PageView.builder(
                          itemCount: media.length,
                          itemBuilder: (c, i) {
                            final m =
                                media[i] is Map
                                    ? Map<String, dynamic>.from(media[i] as Map)
                                    : <String, dynamic>{};
                            final url = m['url']?.toString();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child:
                                  url != null
                                      ? (m['mediaType']?.toString() == 'video'
                                          ? EazyVideoMedia(
                                            url: url,
                                            fit: BoxFit.cover,
                                          )
                                          : Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  imageContext,
                                                  _,
                                                  _,
                                                ) => ColoredBox(
                                                  color:
                                                      Theme.of(imageContext)
                                                          .colorScheme
                                                          .surfaceContainerHighest,
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                                  ),
                                                ),
                                          ))
                                      : ColoredBox(
                                        color:
                                            Theme.of(c)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        child: const Center(
                                          child: Icon(Icons.image_outlined),
                                        ),
                                      ),
                            );
                          },
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: AnimatedScale(
                                scale: showHeart ? 1 : .35,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.elasticOut,
                                child: AnimatedOpacity(
                                  opacity: showHeart ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Icon(
                                    Icons.favorite_rounded,
                                    color: Colors.white,
                                    size: 86,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black38,
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                      color: liked ? Theme.of(context).colorScheme.error : null,
                    ),
                    label: Text('${widget.post['likeCount'] ?? 0}'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : comment,
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    label: Text('${widget.post['commentCount'] ?? 0}'),
                  ),
                  IconButton(
                    tooltip: 'Copy post link',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: 'https://eazy.app/p/$id'),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Post link copied')),
                        );
                      }
                    },
                    icon: Icon(Icons.send_outlined),
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

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.comment,
    required this.api,
    required this.currentUsername,
    required this.onChanged,
    required this.onReply,
  });
  final Map<String, dynamic> comment;
  final ApiClient api;
  final String currentUsername;
  final Future<void> Function() onChanged;
  final ValueChanged<Map<String, dynamic>> onReply;
  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  late bool liked;
  late int likes;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    liked = widget.comment['likedByViewer'] == true;
    likes = int.tryParse(widget.comment['likeCount']?.toString() ?? '') ?? 0;
  }

  Future<void> toggleLike() async {
    if (busy) return;
    final wasLiked = liked;
    setState(() {
      liked = !wasLiked;
      likes += wasLiked ? -1 : 1;
      busy = true;
    });
    try {
      if (wasLiked) {
        await widget.api.delete(
          'comments/${widget.comment['id']}/like',
          auth: true,
        );
      } else {
        await widget.api.post(
          'comments/${widget.comment['id']}/like',
          auth: true,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          liked = wasLiked;
          likes += wasLiked ? 1 : -1;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showOptions() async {
    if (busy) return;
    final author =
        widget.comment['author'] is Map
            ? Map<String, dynamic>.from(widget.comment['author'] as Map)
            : <String, dynamic>{};
    final isMine =
        author['username']?.toString().toLowerCase() ==
        widget.currentUsername.toLowerCase();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMine)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Delete comment'),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                ListTile(
                  leading: Icon(Icons.flag_outlined),
                  title: const Text('Report comment'),
                  onTap: () => Navigator.pop(ctx, 'report'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') {
        await widget.api.delete('comments/${widget.comment['id']}', auth: true);
      } else {
        final controller = TextEditingController();
        final reason = await showDialog<String>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Report comment'),
              content: TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Tell us what happened',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
        controller.dispose();
        if (reason == null || reason.length < 3) return;
        await widget.api.post(
          'comments/${widget.comment['id']}/report',
          auth: true,
          body: {'reason': reason},
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'delete' ? 'Comment deleted' : 'Report sent to Eazy',
            ),
          ),
        );
      }
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final author =
        widget.comment['author'] is Map
            ? Map<String, dynamic>.from(widget.comment['author'] as Map)
            : <String, dynamic>{};
    final name =
        author['displayName']?.toString() ??
        author['username']?.toString() ??
        'Eazy user';
    final username = author['username']?.toString();
    final avatar = author['avatarUrl']?.toString();
    final created = widget.comment['createdAt']?.toString() ?? '';
    final isReply = widget.comment['parentId'] != null;
    return GestureDetector(
      onLongPress: showOptions,
      child: Padding(
        padding: EdgeInsets.only(left: isReply ? 28 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  avatar != null && avatar.startsWith('http')
                      ? NetworkImage(avatar)
                      : null,
              child:
                  avatar == null || !avatar.startsWith('http')
                      ? Text(
                        name.isEmpty
                            ? 'E'
                            : name.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: context.eazyAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username == null || username.isEmpty ? name : '@$username',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.comment['content']?.toString() ?? '',
                    style: TextStyle(height: 1.4),
                  ),
                  Row(
                    children: [
                      if (created.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            created.length >= 10
                                ? created.substring(0, 10)
                                : created,
                            style: TextStyle(
                              color: context.eazyMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => widget.onReply(widget.comment),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 28),
                        ),
                        child: const Text(
                          'Reply',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : toggleLike,
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: liked ? Theme.of(context).colorScheme.error : context.eazyMuted,
                    size: 18,
                  ),
                ),
                if (likes > 0)
                  Text(
                    '$likes',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.eazyMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedAccounts extends StatelessWidget {
  const _SuggestedAccounts({
    required this.people,
    required this.followed,
    required this.onFollow,
    required this.onDismiss,
  });
  final List<Map<String, dynamic>> people;
  final Set<String> followed;
  final Future<void> Function(Map<String, dynamic>) onFollow;
  final ValueChanged<Map<String, dynamic>> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20, bottom: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'People to know on Eazy',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Icon(
                  Icons.auto_awesome_rounded,
                  color: context.eazyAccent,
                  size: 18,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 166,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final person = people[index];
                final username = person['username']?.toString() ?? '';
                final name =
                    person['displayName']?.toString() ??
                    person['display_name']?.toString() ??
                    username;
                final avatar =
                    person['avatarUrl']?.toString() ??
                    person['avatar_url']?.toString();
                final isFollowed = followed.contains(username.toLowerCase());
                return Container(
                  width: 142,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(EazyRadius.md),
                    border: Border.all(color: context.eazyBorder),
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        heightFactor: .5,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.eazyMuted,
                          ),
                          onPressed: () => onDismiss(person),
                        ),
                      ),
                      CircleAvatar(
                        radius: 27,
                        backgroundColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                        backgroundImage:
                            avatar != null && avatar.startsWith('http')
                                ? NetworkImage(avatar)
                                : null,
                        child:
                            avatar == null || !avatar.startsWith('http')
                                ? Text(
                                  name.isEmpty
                                      ? 'E'
                                      : name.characters.first.toUpperCase(),
                                  style: TextStyle(
                                    color: context.eazyAccent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                                : null,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        name.isEmpty ? 'Eazy member' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        username.isEmpty ? 'On Eazy' : '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.eazyMuted,
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: FilledButton(
                          onPressed: isFollowed ? null : () => onFollow(person),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 30),
                          ),
                          child: Text(
                            isFollowed ? 'Following' : 'Follow',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedLoadingSkeleton extends StatelessWidget {
  const _FeedLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        children: List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.eazyBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: surface, radius: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 112, height: 10, decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 7),
                          Container(width: 76, height: 8, decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(8))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 12, decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: .68,
                  child: Container(height: 12, decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(8))),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          Icon(
            Icons.dynamic_feed_outlined,
            size: 44,
            color: context.eazyAccent,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eazyMuted, height: 1.4),
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
