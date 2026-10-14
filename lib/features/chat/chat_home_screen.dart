import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

typedef OpenEazyConversation = Future<void> Function(Map<String, dynamic> conversation);

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key, required this.api, required this.onOpen});
  final ApiClient api;
  final OpenEazyConversation onOpen;
  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _connecting = true, _fabVisible = true;
  String _filter = 'All';
  String? _error, _myUsername, _myUserId;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProfile();
    _scroll.addListener(_scrollChanged);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.removeListener(_scrollChanged);
    _scroll.dispose();
    _subscription?.cancel();
    _socket?.close();
    super.dispose();
  }

  void _scrollChanged() {
    if (!_scroll.hasClients) return;
    final visible = _scroll.position.userScrollDirection != ScrollDirection.reverse;
    if (visible != _fabVisible && mounted) setState(() => _fabVisible = visible);
  }

  Future<void> _loadProfile() async {
    try {
      final result = await widget.api.get('profiles/me', auth: true);
      if (mounted && result['profile'] is Map) {
        setState(() { _myUsername = result['profile']['username']?.toString(); _myUserId = result['profile']['id']?.toString(); });
      }
    } catch (_) {}
    await _connectRealtime();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.get('chat/conversations?page=1&limit=100', auth: true);
      final values = (result['items'] as List? ?? const [])
          .whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
      values.sort((a, b) => _activity(b).compareTo(_activity(a)));
      if (mounted) setState(() { _items = values; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _activity(Map<String, dynamic> c) {
    final latest = c['latestMessage'];
    return DateTime.tryParse((latest is Map ? latest['createdAt'] : null)?.toString()
        ?? c['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _connectRealtime() async {
    try {
      final token = await widget.api.readToken();
      if (token == null || token.isEmpty || _myUserId == null || _myUserId!.isEmpty) return;
      final base = Uri.parse(widget.api.baseUrl);
      final uri = Uri(scheme: base.scheme == 'https' ? 'wss' : 'ws',
          host: base.host, port: base.hasPort ? base.port : null, path: '/v1/realtime');
      final socket = await WebSocket.connect(uri.toString(),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 10));
      _socket = socket;
      // Server scopes this subscription to the authenticated user's own channel.
      socket.add(jsonEncode({'type': 'subscribe', 'channel': 'user', 'id': _myUserId}));
      _subscription = socket.listen((raw) {
        try {
          final frame = jsonDecode(raw.toString());
          if (frame is Map && frame['type'] == 'event') unawaited(_load(quiet: true));
        } catch (_) {}
      }, onDone: () { if (mounted) setState(() => _connecting = true); },
         onError: (_) { if (mounted) setState(() => _connecting = true); });
      if (mounted) setState(() => _connecting = false);
    } catch (_) {
      if (mounted) setState(() => _connecting = true);
    }
  }

  Map<String, dynamic> _person(Map<String, dynamic> c) {
    final raw = c['participants'];
    final people = raw is List ? raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList() : <Map<String, dynamic>>[];
    if (_myUsername != null) {
      for (final p in people) {
        if ((p['username'] ?? '').toString().toLowerCase() != _myUsername!.toLowerCase()) return p;
      }
    }
    return people.isEmpty ? <String, dynamic>{} : people.first;
  }

  String _name(Map<String, dynamic> c) {
    final p = _person(c);
    return (p['displayName'] ?? p['display_name'] ?? p['username'] ?? 'Eazy user').toString();
  }

  String _preview(Map<String, dynamic> c) {
    final raw = c['latestMessage'];
    if (raw is! Map) return 'Start a conversation';
    if (raw['status'] == 'deleted') return '🚫 This message was deleted';
    final body = raw['body']?.toString();
    return body == null || body.isEmpty ? 'Start a conversation' : body;
  }

  int _unread(Map<String, dynamic> c) => int.tryParse((c['unreadCount'] ?? 0).toString()) ?? 0;

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _items.where((c) {
      if (query.isNotEmpty && !_name(c).toLowerCase().contains(query) && !_preview(c).toLowerCase().contains(query)) return false;
      if (_filter == 'Unread' && _unread(c) == 0) return false;
      return true;
    }).toList();
  }

  Future<void> _newChat() async {
    final conversation = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => _NewChatScreen(api: widget.api)));
    if (conversation != null && mounted) {
      await _load();
      await widget.onOpen(conversation);
      await _load(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = _filtered;
    final unreadTotal = _items.fold<int>(0, (sum, c) => sum + _unread(c));
    return Scaffold(
      backgroundColor: EazyColors.canvas,
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Eazy', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EazyColors.green, fontWeight: FontWeight.w900, letterSpacing: 2.4)), const SizedBox(height: 2), Text('Chats', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w900)), ])),
            IconButton(onPressed: _newChat, tooltip: 'New chat', style: IconButton.styleFrom(backgroundColor: EazyColors.green.withValues(alpha: .10), foregroundColor: EazyColors.green), icon: const Icon(Icons.edit_square)),
          ])),
        if (_connecting) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(children: [Container(width: 7, height: 7, decoration: const BoxDecoration(color: EazyColors.amber, shape: BoxShape.circle)), const SizedBox(width: 8), Text('Reconnecting to Eazy', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: EazyColors.muted))])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(controller: _search, onChanged: (_) => setState(() {}),
            style: const TextStyle(color: EazyColors.ink),
            decoration: InputDecoration(hintText: 'Search conversations or people', prefixIcon: const Icon(Icons.search_rounded, color: EazyColors.green),
              hintStyle: const TextStyle(color: EazyColors.muted), filled: true, fillColor: EazyColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(EazyRadius.md), borderSide: const BorderSide(color: EazyColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(EazyRadius.md), borderSide: const BorderSide(color: EazyColors.border))))),
        SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          _Chip('All', _filter == 'All', () => setState(() => _filter = 'All')),
          const SizedBox(width: 8),
          _Chip(unreadTotal > 0 ? 'Unread  ${unreadTotal > 99 ? '99+' : unreadTotal}' : 'Unread', _filter == 'Unread',
            () => setState(() => _filter = _filter == 'Unread' ? 'All' : 'Unread')),
        ])),
        const SizedBox(height: 5),
        Expanded(child: _loading ? const _Skeletons() : _error != null
          ? _Empty(icon: Icons.cloud_off_outlined, title: 'Could not load chats', detail: _error ?? 'Please try again.', action: _load, actionText: 'Try again')
          : chats.isEmpty
            ? _Empty(icon: Icons.forum_outlined,
                title: _filter == 'Groups' ? 'Groups are not available yet' : 'Start chatting with your contacts',
                detail: _filter == 'Groups' ? 'The current production API supports 1:1 conversations only.' : 'Your real Eazy conversations will appear here.',
                action: _newChat, actionText: 'New chat')
            : ListView.separated(controller: _scroll, itemCount: chats.length, padding: const EdgeInsets.only(bottom: 100),
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (_, i) {
                final c = chats[i]; final p = _person(c); final unread = _unread(c);
                return _ChatRow(name: _name(c), preview: _preview(c), unread: unread,
                  timestamp: _time(_activity(c)), avatarUrl: p['avatarUrl']?.toString(),
                  onTap: () => widget.onOpen(c),
                  onLongPress: () {});
              })),
      ])),
      floatingActionButton: AnimatedSlide(duration: const Duration(milliseconds: 200),
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: _fabVisible ? 1 : 0,
          child: FloatingActionButton(onPressed: _newChat, backgroundColor: EazyColors.green,
            foregroundColor: EazyColors.canvas, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EazyRadius.md)),
            child: const Icon(Icons.edit_rounded)))),
    );
  }

  String _time(DateTime date) {
    final local = date.toLocal(); final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
      return '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'pm' : 'am'}';
    }
    if (now.difference(DateTime(local.year, local.month, local.day)).inDays == 1) return 'Yesterday';
    if (now.difference(local).inDays < 7) return const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][local.weekday - 1];
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _NewChatScreen extends StatefulWidget {
  const _NewChatScreen({required this.api});
  final ApiClient api;
  @override State<_NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<_NewChatScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = false, _busy = false;
  String? _error;
  @override
  void dispose() { _query.dispose(); _debounce?.cancel(); super.dispose(); }

  void _search(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) { setState(() { _contacts = []; _loading = false; _error = null; }); return; }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() { _loading = true; _error = null; });
      try {
        final result = await widget.api.get('profiles/search?q=${Uri.encodeQueryComponent(value.trim())}', auth: true);
        if (mounted) setState(() => _contacts = (result['items'] as List? ?? const [])
          .whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList());
      } on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
      finally { if (mounted) setState(() => _loading = false); }
    });
  }

  Future<void> _select(Map<String, dynamic> contact) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.post('chat/conversations', auth: true,
        body: {'username': contact['username']});
      if (mounted && result['conversation'] is Map) Navigator.pop(context, Map<String, dynamic>.from(result['conversation']));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: EazyColors.canvas,
    appBar: AppBar(title: const Text('Find people on Eazy'), backgroundColor: EazyColors.canvas),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _query, autofocus: true, onChanged: _search,
        decoration: InputDecoration(hintText: 'Search name or username', prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: EazyColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(EazyRadius.md), borderSide: const BorderSide(color: EazyColors.border))))),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Text(_error!, textAlign: TextAlign.center))
        : _contacts.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Text(_query.text.trim().length < 2 ? 'Search by name or Eazy username to find people.' : 'No matching Eazy users found.',
              textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted))))
        : ListView.builder(itemCount: _contacts.length, itemBuilder: (_, i) {
          final c = _contacts[i]; final name = (c['displayName'] ?? c['fullName'] ?? c['username'] ?? 'Eazy user').toString();
          final avatar = c['avatarUrl']?.toString();
          return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5), leading: _Avatar(name: name, url: avatar), title: Text(name, style: const TextStyle(color: EazyColors.ink, fontWeight: FontWeight.w800)),
            subtitle: Text('@${c['username'] ?? ''}', style: const TextStyle(color: EazyColors.muted)),
            onTap: () => _select(c));
        })),
    ]));
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.selected, this.onTap);
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: selected ? EazyColors.green.withValues(alpha: .13) : EazyColors.surface,
    borderRadius: BorderRadius.circular(EazyRadius.sm), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(EazyRadius.sm),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(EazyRadius.sm), border: Border.all(color: selected ? EazyColors.green.withValues(alpha: .5) : EazyColors.border)),
        child: Text(label, style: TextStyle(color: selected ? EazyColors.green : EazyColors.muted,
          fontSize: 12, fontWeight: FontWeight.w800)))));
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.name, required this.preview, required this.unread, required this.timestamp,
    required this.avatarUrl, required this.onTap, required this.onLongPress});
  final String name, preview, timestamp; final int unread; final String? avatarUrl;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, onLongPress: onLongPress,
    child: SizedBox(height: 76, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        _Avatar(name: name, url: avatarUrl),
        const SizedBox(width: 13),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EazyColors.ink, fontSize: 15, letterSpacing: -.15, fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700))),
            const SizedBox(width: 8),
            Text(timestamp, style: TextStyle(color: unread > 0 ? EazyColors.green : EazyColors.muted, fontSize: 11)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EazyColors.muted, fontSize: 12.5, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400))),
            if (unread > 0) ...[
              const SizedBox(width: 7),
              Container(height: 21, constraints: const BoxConstraints(minWidth: 21), padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center, decoration: BoxDecoration(color: EazyColors.green, borderRadius: BorderRadius.circular(8)),
                child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(color: EazyColors.canvas, fontSize: 10, fontWeight: FontWeight.w900))),
            ],
          ]),
        ])),
      ]))));
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url});
  final String name; final String? url;
  String _initials(String value) { final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList(); if (parts.isEmpty) return 'E'; return parts.length == 1 ? parts.first.substring(0, 1).toUpperCase() : (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase(); }
  @override
  Widget build(BuildContext context) {
    final image = url == null || url!.isEmpty ? null : NetworkImage(url!);
    return Container(width: 52, height: 52, decoration: BoxDecoration(color: EazyColors.surfaceRaised, borderRadius: BorderRadius.circular(17), border: Border.all(color: EazyColors.border), image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover)),
      alignment: Alignment.center, child: image == null ? Text(_initials(name), style: const TextStyle(color: EazyColors.green, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -.5)) : null);
  }
}

class _Skeletons extends StatelessWidget {
  const _Skeletons();

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 8,
    itemBuilder: (_, index) => SizedBox(
      height: 76,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: EazyColors.surfaceRaised, borderRadius: BorderRadius.all(Radius.circular(17)), border: Border.all(color: EazyColors.border))),
          SizedBox(width: 13),
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 13, width: 150, child: DecoratedBox(
                decoration: BoxDecoration(color: EazyColors.surfaceRaised,
                  borderRadius: BorderRadius.all(Radius.circular(8))))),
              SizedBox(height: 9),
              SizedBox(height: 10, width: 220, child: DecoratedBox(
                decoration: BoxDecoration(color: EazyColors.border,
                  borderRadius: BorderRadius.all(Radius.circular(8))))),
            ],
          )),
        ]),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.detail, required this.action, required this.actionText});
  final IconData icon; final String title, detail, actionText; final Future<void> Function() action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 76, height: 76, decoration: BoxDecoration(color: EazyColors.green.withValues(alpha: .09), borderRadius: BorderRadius.circular(25), border: Border.all(color: EazyColors.green.withValues(alpha: .25))), child: Icon(icon, size: 34, color: EazyColors.green)), const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted, height: 1.5)),
      const SizedBox(height: 18), FilledButton(onPressed: action, child: Text(actionText)),
    ])));
}
