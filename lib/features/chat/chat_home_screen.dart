import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
      // Groups and favourites are not represented by the current production API.
      if (_filter == 'Groups' || _filter == 'Favourites') return false;
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

  void _notAvailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature is not available in the current production backend.')));
  }

  void _menu() {
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      backgroundColor: EazyColors.surface, builder: (sheet) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.group_add_outlined), title: const Text('New group'),
            onTap: () { Navigator.pop(sheet); _notAvailable('Group conversations'); }),
          ListTile(leading: const Icon(Icons.star_outline_rounded), title: const Text('Starred messages'),
            onTap: () { Navigator.pop(sheet); _notAvailable('Starred messages'); }),
          ListTile(leading: const Icon(Icons.devices_outlined), title: const Text('Linked devices'),
            onTap: () { Navigator.pop(sheet); _notAvailable('Linked devices'); }),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Settings'),
            onTap: () { Navigator.pop(sheet); _notAvailable('Settings'); }),
          const SizedBox(height: 8),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final chats = _filtered;
    final unreadTotal = _items.fold<int>(0, (sum, c) => sum + _unread(c));
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(children: [
            const Expanded(child: Text('Chats', style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900))),
            IconButton(onPressed: _newChat, tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined, color: Color(0xFF25D366))),
            IconButton(onPressed: _menu, tooltip: 'More options', icon: const Icon(Icons.more_vert_rounded, color: Colors.white)),
          ])),
        if (_connecting) Container(width: double.infinity, color: Color(0xFF17262D),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            SizedBox(width: 9), Text('Connecting…', style: TextStyle(color: Color(0xFF8696A0), fontSize: 12))])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(controller: _search, onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: 'Search', prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8696A0)),
              hintStyle: const TextStyle(color: Color(0xFF8696A0)), filled: true, fillColor: const Color(0xFF1F2C34),
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)))),
        SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          _Chip('All', _filter == 'All', () => setState(() => _filter = 'All')),
          const SizedBox(width: 8),
          _Chip(unreadTotal > 0 ? 'Unread  ${unreadTotal > 99 ? '99+' : unreadTotal}' : 'Unread', _filter == 'Unread',
            () => setState(() => _filter = _filter == 'Unread' ? 'All' : 'Unread')),
          const SizedBox(width: 8),
          _Chip('Groups', _filter == 'Groups', () => setState(() => _filter = _filter == 'Groups' ? 'All' : 'Groups')),
          const SizedBox(width: 8),
          _Chip('Favourites', _filter == 'Favourites', () { setState(() => _filter = 'Favourites'); _notAvailable('Favourite lists'); }),
          const SizedBox(width: 8),
          _Chip('+', false, () => _notAvailable('Custom lists')),
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
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    showModalBottomSheet<void>(context: context, showDragHandle: true,
                      builder: (sheet) => SafeArea(child: Wrap(children: [
                        ListTile(leading: const Icon(Icons.mark_chat_unread_outlined), title: const Text('Mark as unread'),
                          onTap: () { Navigator.pop(sheet); _notAvailable('Mark as unread'); }),
                        ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('Pin chat'),
                          onTap: () { Navigator.pop(sheet); _notAvailable('Pinned chats'); }),
                        ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Archive'),
                          onTap: () { Navigator.pop(sheet); _notAvailable('Chat archive'); }),
                      ])));
                  });
              })),
      ])),
      floatingActionButton: AnimatedSlide(duration: const Duration(milliseconds: 200),
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: _fabVisible ? 1 : 0,
          child: FloatingActionButton(onPressed: _newChat, backgroundColor: const Color(0xFF25D366),
            foregroundColor: const Color(0xFF0B141A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.chat_rounded)))),
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
  Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF0B141A),
    appBar: AppBar(title: const Text('New chat'), backgroundColor: const Color(0xFF0B141A)),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _query, autofocus: true, onChanged: _search,
        decoration: InputDecoration(hintText: 'Search name or username', prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: const Color(0xFF1F2C34),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)))),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Text(_error!, textAlign: TextAlign.center))
        : _contacts.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Text(_query.text.trim().length < 2 ? 'Search by name or Eazy username to find people.' : 'No matching Eazy users found.',
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8696A0)))))
        : ListView.builder(itemCount: _contacts.length, itemBuilder: (_, i) {
          final c = _contacts[i]; final name = (c['displayName'] ?? c['fullName'] ?? c['username'] ?? 'Eazy user').toString();
          final avatar = c['avatarUrl']?.toString();
          return ListTile(leading: _Avatar(name: name, url: avatar), title: Text(name, style: const TextStyle(color: Colors.white)),
            subtitle: Text('@${c['username'] ?? ''}', style: const TextStyle(color: Color(0xFF8696A0))),
            onTap: () => _select(c));
        })),
    ]));
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.selected, this.onTap);
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: selected ? const Color(0xFF103629) : const Color(0xFF1F2C34),
    borderRadius: BorderRadius.circular(22), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: TextStyle(color: selected ? const Color(0xFF25D366) : const Color(0xFFB8C4CA),
          fontSize: 12, fontWeight: FontWeight.w700)))));
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
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600))),
            const SizedBox(width: 8),
            Text(timestamp, style: TextStyle(color: unread > 0 ? const Color(0xFF25D366) : const Color(0xFF8696A0), fontSize: 11)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: const Color(0xFF8696A0), fontSize: 13, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400))),
            if (unread > 0) ...[
              const SizedBox(width: 7),
              Container(height: 21, constraints: const BoxConstraints(minWidth: 21), padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center, decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(color: Color(0xFF0B141A), fontSize: 10, fontWeight: FontWeight.w900))),
            ],
          ]),
        ])),
      ]))));
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url});
  final String name; final String? url;
  @override
  Widget build(BuildContext context) {
    final image = url == null || url!.isEmpty ? null : NetworkImage(url!);
    return CircleAvatar(radius: 26, backgroundColor: const Color(0xFF4B332B), backgroundImage: image,
      child: image == null ? const Icon(Icons.person_rounded, color: Color(0xFFE5D6CF), size: 28) : null);
  }
}

class _Skeletons extends StatelessWidget {
  const _Skeletons();

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 8,
    itemBuilder: (_, index) => const SizedBox(
      height: 76,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          CircleAvatar(radius: 26, backgroundColor: Color(0xFF1F2C34)),
          SizedBox(width: 13),
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 13, width: 150, child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF1F2C34),
                  borderRadius: BorderRadius.all(Radius.circular(8))))),
              SizedBox(height: 9),
              SizedBox(height: 10, width: 220, child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF17262D),
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
      Icon(icon, size: 52, color: const Color(0xFF25D366)), const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8696A0), height: 1.4)),
      const SizedBox(height: 18), FilledButton(onPressed: action, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: const Color(0xFF0B141A)), child: Text(actionText)),
    ])));
}
