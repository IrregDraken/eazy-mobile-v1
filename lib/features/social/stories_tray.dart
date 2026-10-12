import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/media/media_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'video_media.dart';

class StoriesTray extends StatefulWidget {
  const StoriesTray({super.key, required this.api, required this.media});
  final ApiClient api;
  final EazyMediaService media;

  @override
  State<StoriesTray> createState() => _StoriesTrayState();
}

class _StoriesTrayState extends State<StoriesTray> {
  bool loading = true, uploading = false;
  String? error;
  List<Map<String, dynamic>> stories = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final result = await widget.api.get('stories/feed', auth: true);
      final items = (result['items'] as List? ?? const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) setState(() { stories = items; error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> createStory() async {
    if (uploading) return;
    setState(() => uploading = true);
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Photo story'), onTap: () => Navigator.pop(ctx, 'image')),
          ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('Video story'), onTap: () => Navigator.pop(ctx, 'video')),
          const SizedBox(height: 8),
        ])),
      );
      if (choice == null) return;
      final upload = choice == 'video'
          ? await widget.media.pickAndUploadVideo(kind: 'post')
          : await widget.media.pickAndUpload(kind: 'post');
      if (upload == null) return;
      await widget.api.post('stories', auth: true, body: {
        'storageKey': upload.path,
        'mediaType': upload.contentType.startsWith('video/') ? 'video' : 'image',
        'caption': '',
      });
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your story is live for 24 hours.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally { if (mounted) setState(() => uploading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final story in stories) {
      final key = story['authorId']?.toString() ?? story['username']?.toString() ?? 'unknown';
      grouped.putIfAbsent(key, () => []).add(story);
    }
    final groups = grouped.values.toList();
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        children: [
          _StoryAvatar(
            title: 'Your story',
            imageUrl: null,
            seen: true,
            isOwn: true,
            busy: uploading,
            onTap: createStory,
          ),
          if (loading && stories.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 32, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))),
          ...groups.map((group) {
            final first = group.first;
            final username = first['username']?.toString() ?? 'Eazy user';
            final avatar = first['avatarUrl']?.toString();
            final seen = group.every((item) => item['seenByMe'] == true);
            return _StoryAvatar(
              title: username,
              imageUrl: avatar,
              seen: seen,
              isOwn: first['isMine'] == true,
              busy: false,
              onTap: () async {
                await showGeneralDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: 'Close stories',
                  barrierColor: Colors.black,
                  transitionDuration: const Duration(milliseconds: 180),
                  pageBuilder: (ctx, _, __) => StoryViewer(
                    stories: group,
                    api: widget.api,
                    onChanged: load,
                  ),
                  transitionBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
                );
                if (mounted) load();
              },
            );
          }),
          if (error != null && stories.isEmpty)
            InkWell(onTap: load, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.refresh_rounded, color: EazyColors.muted))),
        ],
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({required this.title, required this.imageUrl, required this.seen, required this.isOwn, required this.busy, required this.onTap});
  final String title;
  final String? imageUrl;
  final bool seen, isOwn, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: seen ? EazyColors.border : EazyColors.green, width: seen ? 1.4 : 2.4),
            ),
            child: Stack(children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: EazyColors.surfaceRaised,
                backgroundImage: imageUrl != null && imageUrl!.startsWith('http') ? NetworkImage(imageUrl!) : null,
                child: imageUrl == null || !imageUrl!.startsWith('http') ? const Icon(Icons.person_rounded, color: EazyColors.green, size: 28) : null,
              ),
              if (isOwn) Positioned(
                right: -1, bottom: -1,
                child: Container(
                  decoration: BoxDecoration(color: EazyColors.green, shape: BoxShape.circle, border: Border.all(color: EazyColors.canvas, width: 2)),
                  child: const Icon(Icons.add_rounded, color: EazyColors.canvas, size: 17),
                ),
              ),
              if (busy) const Positioned.fill(child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          const SizedBox(height: 5),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    ),
  );
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.stories, required this.api, required this.onChanged, this.allowDelete = true, this.markSeen = true});
  final List<Map<String, dynamic>> stories;
  final ApiClient api;
  final Future<void> Function() onChanged;
  final bool allowDelete;
  final bool markSeen;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  int index = 0;
  Timer? timer;
  bool paused = false;
  String? failure;

  Map<String, dynamic> get current => widget.stories[index];

  @override
  void initState() { super.initState(); _markSeen(); _startTimer(); }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _markSeen() async {
    if (!widget.markSeen) return;
    try { await widget.api.post('stories/${current['id']}/view', auth: true); }
    on ApiException catch (e) { if (mounted) setState(() => failure = e.message); }
  }

  void _startTimer() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 6), _next);
  }
  void _next() {
    if (!mounted) return;
    if (index >= widget.stories.length - 1) { Navigator.of(context).pop(); return; }
    setState(() { index++; failure = null; });
    _markSeen();
    _startTimer();
  }
  void _previous() {
    if (index == 0) return;
    setState(() { index--; failure = null; });
    _markSeen();
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final url = current['mediaUrl']?.toString();
    final mine = current['isMine'] == true;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 350) Navigator.of(context).pop();
          },
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -200) _next();
            if ((details.primaryVelocity ?? 0) > 200) _previous();
          },
          onLongPressStart: (_) { paused = true; timer?.cancel(); setState(() {}); },
          onLongPressEnd: (_) { paused = false; _startTimer(); setState(() {}); },
          child: Stack(fit: StackFit.expand, children: [
            if (url != null && url.startsWith('http'))
              if (current['mediaType']?.toString() == 'video')
                EazyVideoMedia(url: url, fit: BoxFit.contain, showControls: false)
              else
                Center(child: Image.network(url, fit: BoxFit.contain, width: double.infinity, height: double.infinity,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white, size: 48)))
            else
              const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white, size: 48)),
            Row(children: [
              Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _previous)),
              Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _next)),
            ]),
            Positioned(top: 10, left: 12, right: 12, child: Row(children: [
              for (var i = 0; i < widget.stories.length; i++)
                Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: i <= index ? Colors.white : Colors.white30, borderRadius: BorderRadius.circular(5)))),
            ])),
            Positioned(top: 24, left: 12, right: 8, child: Row(children: [
              const CircleAvatar(radius: 17, child: Icon(Icons.person_rounded, size: 19)),
              const SizedBox(width: 9),
              Expanded(child: Text(current['username']?.toString() ?? 'Eazy user', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              if (mine && widget.allowDelete) IconButton(onPressed: () async {
                try {
                  await widget.api.delete('stories/${current['id']}', auth: true);
                  if (widget.stories.length == 1) { if (context.mounted) Navigator.of(context).pop(); }
                  else { setState(() { widget.stories.removeAt(index); index = index.clamp(0, widget.stories.length - 1); }); _startTimer(); }
                  await widget.onChanged();
                } on ApiException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
              }, icon: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ])),
            if (current['caption']?.toString().isNotEmpty == true)
              Positioned(left: 24, right: 24, bottom: 64, child: Text(current['caption'].toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            if (paused) const Positioned(bottom: 24, left: 0, right: 0, child: Center(child: Icon(Icons.pause_circle_outline_rounded, color: Colors.white, size: 36))),
            if (failure != null) Positioned(bottom: 16, left: 16, right: 16, child: Text(failure!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
  }
}
