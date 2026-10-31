import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/ui/eazy_skeleton.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';
import 'chat_home_screen.dart';

const _reactions = <String>['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final api = ApiClient();

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(api: api, conversation: conversation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ChatHomeScreen(api: api, onOpen: _openConversation);
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.api,
    required this.conversation,
  });
  final ApiClient api;
  final Map<String, dynamic> conversation;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final draft = TextEditingController();
  final draftStorage = const FlutterSecureStorage();
  Timer? draftSaveTimer;
  final scroll = ScrollController();
  late final EazyMediaService media;
  final List<MediaUpload> pendingAttachments = [];
  List<Map<String, dynamic>> messages = [];
  Map<String, dynamic>? replying, editing;
  bool loading = true, sending = false;
  String? error;
  String? currentUsername;
  WebSocket? socket;
  StreamSubscription? subscription;
  Timer? realtimeReconnectTimer;
  bool connectingRealtime = false;
  int realtimeReconnectAttempts = 0;
  List<String> _chatWallpaperChoices = [];
  String? _selectedChatWallpaper;
  bool? _wallpaperDarkMode;

  String get _wallpaperPreferenceKey =>
      'eazy.chat.wallpaper.${_wallpaperDarkMode == true ? 'dark' : 'light'}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_wallpaperDarkMode != dark) {
      _wallpaperDarkMode = dark;
      unawaited(_loadChatWallpapers(dark));
    }
  }

  Future<void> _loadChatWallpapers(bool dark) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final all = manifest.listAssets().where((asset) {
        final path = asset.toLowerCase();
        final isImage = path.endsWith('.png') ||
            path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.webp');
        return path.startsWith('assets/images/chat/') && isImage;
      }).toList()..sort();
      final modeName = dark ? 'dark' : 'light';
      final preferred = all
          .where((asset) => asset.toLowerCase().contains(modeName))
          .toList();
      final neutral = all.where((asset) {
        final path = asset.toLowerCase();
        return !path.contains('light') && !path.contains('dark');
      }).toList();
      final choices = [...preferred, ...neutral];
      final key = 'eazy.chat.wallpaper.' + modeName;
      final saved = await draftStorage.read(key: key);
      final selected = choices.contains(saved)
          ? saved
          : (preferred.isNotEmpty
              ? preferred.first
              : (neutral.isNotEmpty ? neutral.first : null));
      if (!mounted || _wallpaperDarkMode != dark) return;
      setState(() {
        _chatWallpaperChoices = choices;
        _selectedChatWallpaper = selected;
      });
    } catch (_) {
      if (!mounted || _wallpaperDarkMode != dark) return;
      setState(() {
        _chatWallpaperChoices = [];
        _selectedChatWallpaper = null;
      });
    }
  }

  Future<void> _chooseChatWallpaper() async {
    if (_chatWallpaperChoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat wallpaper images have not been added to assets/images/chat yet.',
          ),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chat wallpaper',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 320,
                child: GridView.builder(
                  itemCount: _chatWallpaperChoices.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (_, index) {
                    final asset = _chatWallpaperChoices[index];
                    final selectedAsset = asset == _selectedChatWallpaper;
                    return InkWell(
                      onTap: () => Navigator.pop(sheetContext, asset),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selectedAsset
                                ? Theme.of(context).colorScheme.primary
                                : context.eazyBorder,
                            width: selectedAsset ? 2.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(asset, fit: BoxFit.cover),
                            if (selectedAsset)
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircleAvatar(
                                    radius: 13,
                                    child: Icon(Icons.check, size: 16),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedChatWallpaper = selected);
    try {
      await draftStorage.write(
        key: 'eazy.chat.wallpaper.' +
            (_wallpaperDarkMode == true ? 'dark' : 'light'),
        value: selected,
      );
    } catch (_) {
      // Keep the selected wallpaper for this conversation session.
    }
  }

  Widget _chatWallpaperBackground(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fallback = CustomPaint(
      painter: _ChatWallpaperPainter(
        color: Theme.of(context).colorScheme.primary.withValues(
          alpha: dark ? .055 : .045,
        ),
      ),
    );
    final asset = _selectedChatWallpaper;
    if (asset == null) return fallback;
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  String get id => widget.conversation['id']?.toString() ?? '';
  String get _draftStorageKey => 'eazy.chat.draft.$id';

  Future<void> _restoreDraft() async {
    try {
      final saved = await draftStorage.read(key: _draftStorageKey);
      if (mounted && draft.text.isEmpty && saved != null && saved.isNotEmpty) {
        draft.value = TextEditingValue(
          text: saved,
          selection: TextSelection.collapsed(offset: saved.length),
        );
      }
    } catch (_) {
      // Draft restoration is best-effort; it must not block opening a chat.
    }
  }

  void _scheduleDraftSave() {
    draftSaveTimer?.cancel();
    draftSaveTimer = Timer(
      const Duration(milliseconds: 350),
      _persistDraft,
    );
  }

  Future<void> _persistDraft() async {
    final value = draft.text;
    try {
      if (value.isEmpty) {
        await draftStorage.delete(key: _draftStorageKey);
      } else {
        await draftStorage.write(key: _draftStorageKey, value: value);
      }
    } catch (_) {
      // A local draft is convenience data, never a prerequisite for sending.
    }
  }

  Map<String, dynamic> get _otherParticipant {
    final participants = widget.conversation['participants'];
    if (participants is List) {
      final people =
          participants
              .whereType<Map>()
              .map((person) => Map<String, dynamic>.from(person))
              .toList();
      if (people.isNotEmpty) {
        return people.firstWhere(
          (person) =>
              (person['username'] ?? '').toString().toLowerCase() !=
              (currentUsername ?? '').toLowerCase(),
          orElse: () => people.first,
        );
      }
    }
    return <String, dynamic>{
      'username': widget.conversation['username'],
      'displayName':
          widget.conversation['displayName'] ??
          widget.conversation['display_name'],
    };
  }

  String get _conversationUsername {
    final username = _otherParticipant['username']?.toString();
    return username == null || username.isEmpty
        ? 'Private conversation'
        : '@$username';
  }

  String get _conversationTitle {
    final person = _otherParticipant;
    final name =
        (person['displayName'] ??
                person['display_name'] ??
                person['name'] ??
                person['username'])
            ?.toString()
            .trim();
    return name == null || name.isEmpty ? 'Chat' : name;
  }

  @override
  void initState() {
    super.initState();
    media = EazyMediaService(widget.api);
    draft.addListener(_scheduleDraftSave);
    unawaited(_restoreDraft());
    loadMessages();
    connectRealtime();
    loadMyProfile();
  }

  Future<void> loadMyProfile() async {
    try {
      final result = await widget.api.get('profiles/me', auth: true);
      final profile = result['profile'];
      if (mounted && profile is Map) {
        setState(() => currentUsername = profile['username']?.toString());
      }
    } catch (_) {}
  }

  bool _isMine(Map<String, dynamic> message) {
    final sender =
        message['sender'] is Map
            ? Map<String, dynamic>.from(message['sender'] as Map)
            : <String, dynamic>{};
    final value =
        (sender['username'] ??
                message['senderUsername'] ??
                message['sender_username'])
            ?.toString()
            .toLowerCase();
    return currentUsername != null && value == currentUsername!.toLowerCase();
  }

  @override
  void dispose() {
    draftSaveTimer?.cancel();
    draft.removeListener(_scheduleDraftSave);
    unawaited(_persistDraft());
    realtimeReconnectTimer?.cancel();
    subscription?.cancel();
    socket?.close();
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> loadMessages() async {
    try {
      if (messages.isEmpty && mounted) setState(() => loading = true);
      final r = await widget.api.get(
        'chat/conversations/$id/messages?page=1&limit=50',
        auth: true,
      );
      messages =
          (r['items'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
              .reversed
              .toList();
      unawaited(markRead());
      if (mounted) setState(() => error = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markRead() async {
    if (messages.isEmpty) return;
    try {
      await widget.api.post(
        'chat/conversations/$id/read',
        auth: true,
        body: {'lastReadMessageId': messages.last['id']},
      );
    } catch (_) {}
  }

  Future<void> connectRealtime() async {
    if (!mounted || connectingRealtime || socket != null) return;
    connectingRealtime = true;
    try {
      final token = await widget.api.readToken();
      if (token == null || token.isEmpty) {
        _scheduleRealtimeReconnect();
        return;
      }
      final base = Uri.parse(widget.api.baseUrl);
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri(
        scheme: scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/v1/realtime',
      );
      final ws = await WebSocket.connect(
        wsUri.toString(),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) {
        await ws.close();
        return;
      }
      final recoveringConnection = realtimeReconnectAttempts > 0;
      socket = ws;
      realtimeReconnectTimer?.cancel();
      realtimeReconnectTimer = null;
      realtimeReconnectAttempts = 0;
      ws.add(
        jsonEncode({'type': 'subscribe', 'channel': 'conversation', 'id': id}),
      );
      if (recoveringConnection) unawaited(loadMessages());
      subscription = ws.listen(
        (raw) {
          try {
            final frame = jsonDecode(raw.toString());
            if (frame is! Map || frame['type'] != 'event') return;
            if (frame['event'] == 'message.created' &&
                frame['data'] is Map &&
                frame['data']['message'] is Map) {
              final m = Map<String, dynamic>.from(
                frame['data']['message'] as Map,
              );
              if (m['conversationId']?.toString() == id &&
                  !messages.any((x) => x['id'] == m['id'])) {
                if (mounted) setState(() => messages.add(m));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scroll.hasClients) {
                    scroll.animateTo(
                      scroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  }
                });
                unawaited(markRead());
              }
            } else if (frame['event'] == 'message.reaction.created' ||
                frame['event'] == 'message.reaction.deleted') {
              unawaited(loadMessages());
            }
          } catch (_) {}
        },
        onDone: () => _handleRealtimeDisconnect(ws),
        onError: (_) => _handleRealtimeDisconnect(ws),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRealtimeReconnect();
    } finally {
      connectingRealtime = false;
    }
  }

  void _handleRealtimeDisconnect(WebSocket disconnectedSocket) {
    if (!identical(socket, disconnectedSocket)) return;
    socket = null;
    subscription = null;
    _scheduleRealtimeReconnect();
  }

  void _scheduleRealtimeReconnect() {
    if (!mounted || realtimeReconnectTimer != null) return;
    final delaySeconds = switch (realtimeReconnectAttempts) {
      0 => 1,
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      _ => 30,
    };
    if (realtimeReconnectAttempts < 5) realtimeReconnectAttempts++;
    realtimeReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      realtimeReconnectTimer = null;
      unawaited(connectRealtime());
    });
  }

  Future<void> send() async {
    final body = draft.text.trim();
    if ((body.isEmpty && pendingAttachments.isEmpty) || sending) return;
    final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final isEditing = editing != null;
    if (!isEditing && body.isNotEmpty) {
      setState(() {
        sending = true;
        messages.add({
          'id': pendingId,
          'body': body,
          'sender': {'username': currentUsername},
          'createdAt': DateTime.now().toIso8601String(),
          'status': 'sending',
        });
        draft.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() => sending = true);
    }
    try {
      if (isEditing) {
        final r = await widget.api.patch(
          'chat/messages/${editing!['id']}',
          auth: true,
          body: {'body': body},
        );
        final m = r['message'];
        if (m is Map) {
          setState(
            () =>
                messages =
                    messages
                        .map(
                          (x) =>
                              x['id'] == m['id']
                                  ? Map<String, dynamic>.from(m)
                                  : x,
                        )
                        .toList(),
          );
        }
        editing = null;
      } else {
        final r = await widget.api.post(
          'chat/conversations/$id/messages',
          auth: true,
          body: {
            if (body.isNotEmpty) 'body': body,
            if (replying != null) 'replyToMessageId': replying!['id'],
            if (pendingAttachments.isNotEmpty)
              'attachments':
                  pendingAttachments
                      .map(
                        (a) => {
                          'storageKey': a.path,
                          'contentType': a.contentType,
                          'byteSize': a.byteSize,
                        },
                      )
                      .toList(),
          },
        );
        final m = r['message'];
        messages.removeWhere((message) => message['id'] == pendingId);
        if (m is Map && !messages.any((x) => x['id'] == m['id'])) {
          messages.add(Map<String, dynamic>.from(m));
        }
        replying = null;
        pendingAttachments.clear();
      }
      draft.clear();
      setState(() {});
      await markRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } on ApiException catch (e) {
      messages.removeWhere((message) => message['id'] == pendingId);
      if (mounted) {
        setState(() {
          if (draft.text.trim().isEmpty) draft.text = body;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reactTo(Map<String, dynamic> m, String reaction) async {
    try {
      final list =
          (m['reactions'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      final found = list.where((x) => x['reaction'] == reaction).firstOrNull;
      if (found?['reactedByMe'] == true) {
        await widget.api.delete(
          'chat/messages/${m['id']}/reactions/${Uri.encodeComponent(reaction)}',
          auth: true,
        );
      } else {
        await widget.api.post(
          'chat/messages/${m['id']}/reactions',
          auth: true,
          body: {'reaction': reaction},
        );
      }
      await loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> translate(Map<String, dynamic> m) async {
    final body = m['body']?.toString() ?? '';
    if (body.isEmpty) return;
    try {
      final r = await widget.api.post(
        'translation',
        auth: true,
        body: {'text': body, 'targetLanguage': 'en'},
      );
      final value = r['translatedText']?.toString() ?? r['text']?.toString();
      if (value != null && mounted) setState(() => m['_translation'] = value);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _pickCamera() async {
    if (sending) return;
    try {
      final upload = await media.pickAndUpload(
        kind: 'message',
        source: ImageSource.camera,
      );
      if (upload != null && mounted) {
        setState(() => pendingAttachments.add(upload));
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
          const SnackBar(content: Text('Could not capture a photo. Please try again.')),
        );
      }
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheet) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: context.eazyAccent,
                  ),
                  title: Text('Photo'),
                  subtitle: Text('Choose an image'),
                  onTap: () => Navigator.pop(sheet, 'photo'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.video_library_outlined,
                    color: context.eazyAccent,
                  ),
                  title: Text('Video'),
                  subtitle: Text('Choose a video'),
                  onTap: () => Navigator.pop(sheet, 'video'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.attach_file_rounded,
                    color: context.eazyAccent,
                  ),
                  title: const Text('File or document'),
                  subtitle: const Text('PDF, Word, TXT or CSV, up to 25 MB'),
                  onTap: () => Navigator.pop(sheet, 'file'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (choice == null || !mounted) return;
    try {
      final upload = switch (choice) {
        'photo' => await media.pickAndUpload(kind: 'message'),
        'video' => await media.pickAndUploadVideo(kind: 'message'),
        _ => await media.pickAndUploadDocument(kind: 'message'),
      };
      if (upload != null && mounted) {
        setState(() => pendingAttachments.add(upload));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not attach that file. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final path = attachment['storageKey']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final result = await widget.api.post(
        'media/signed-message-attachment-url',
        auth: true,
        body: {'path': path},
      );
      final url = result['signedUrl']?.toString();
      if (url == null || url.isEmpty) {
        throw const ApiException('The attachment could not be opened.');
      }
      final type = attachment['contentType']?.toString() ?? '';
      if (type.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => Dialog(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('This image could not be loaded.'),
                        ),
                  ),
                ),
              ),
        );
      } else {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No app could open this attachment.')),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this attachment. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _translateDraft() async {
    final text = draft.text.trim();
    if (text.isEmpty) {
      if (mounted) context.push('/translation');
      return;
    }
    try {
      final result = await widget.api.post(
        'translation',
        auth: true,
        body: {'text': text, 'targetLanguage': 'en'},
      );
      final translated =
          (result['translatedText'] ?? result['text'])?.toString();
      if (translated == null || translated.trim().isEmpty) {
        throw const ApiException('No translated text was returned.');
      }
      if (mounted) {
        setState(() {
          draft.text = translated;
          draft.selection = TextSelection.collapsed(offset: translated.length);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> deleteMessage(Map<String, dynamic> m) async {
    try {
      await widget.api.delete('chat/messages/${m['id']}', auth: true);
      await loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> report(Map<String, dynamic> m, String reason) async {
    try {
      await widget.api.post(
        'chat/messages/${m['id']}/report',
        auth: true,
        body: {'reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void actions(Map<String, dynamic> m) {
    final status = m['status']?.toString() ?? 'sent';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => replying = m);
                  },
                ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: const Text('React'),
                    onTap: () {
                      Navigator.pop(ctx);
                      chooseReaction(m);
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('Translate to English'),
                    onTap: () {
                      Navigator.pop(ctx);
                      translate(m);
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report'),
                    onTap: () {
                      Navigator.pop(ctx);
                      report(m, 'Other inappropriate content');
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        editing = m;
                        draft.text = m['body']?.toString() ?? '';
                      });
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Delete'),
                    onTap: () {
                      Navigator.pop(ctx);
                      deleteMessage(m);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void chooseReaction(Map<String, dynamic> message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 8,
                runSpacing: 8,
                children:
                    _reactions
                        .map(
                          (reaction) => IconButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              reactTo(message, reaction);
                            },
                            icon: Text(
                              reaction,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
  }

  Future<void> _handleRecipientAction(String action) async {
    final username = _otherParticipant['username']?.toString().trim() ?? '';
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient details are unavailable.')),
      );
      return;
    }
    if (action == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Block this account?'),
              content: Text(
                'You will no longer receive messages from @$username.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Block'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await widget.api.post('social/block/$username', auth: true);
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Account blocked.')),
        );
      } on ApiException catch (e) {
        if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (action == 'report') {
      final reasonController = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Report account'),
              content: TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'What should Eazy review?',
                  hintText: 'Describe the issue',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = reasonController.text.trim();
                    if (value.length >= 3) Navigator.pop(dialogContext, value);
                  },
                  child: const Text('Submit report'),
                ),
              ],
            ),
      );
      reasonController.dispose();
      if (reason == null) return;
      try {
        await widget.api.post(
          'social/report/$username',
          body: {'reason': reason},
          auth: true,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted for review.')),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _conversationTitle;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              _conversationUsername,
              style: TextStyle(
                fontSize: 11,
                color: context.eazyMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat wallpaper',
            onPressed: _chooseChatWallpaper,
            icon: const Icon(Icons.wallpaper_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: _handleRecipientAction,
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded),
                        SizedBox(width: 10),
                        Text('Block account'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined),
                        SizedBox(width: 10),
                        Text('Report account'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _chatWallpaperBackground(context),
          ),
          Column(
          children: [
            if (replying != null)
              _ContextBar(
                label: 'REPLYING',
                value: replying!['body']?.toString() ?? '',
                onClose: () => setState(() => replying = null),
              ),
            if (editing != null)
              _ContextBar(
                label: 'EDITING',
                value: editing!['body']?.toString() ?? '',
                onClose:
                    () => setState(() {
                      editing = null;
                      draft.clear();
                    }),
              ),
            Expanded(
              child:
                  loading
                      ? const _ConversationSkeleton()
                      : error != null
                      ? _ChatState(error!, loadMessages)
                      : messages.isEmpty
                      ? const _ChatState(
                        'No messages yet. Start the conversation.',
                      )
                      : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          return _MessageBubble(
                            message: messages[i],
                            isMine: _isMine(messages[i]),
                            onLongPress: () => actions(messages[i]),
                            onReaction: (r) => reactTo(messages[i], r),
                            onTranslate: () => translate(messages[i]),
                            onOpenAttachment: _openAttachment,
                          );
                        },
                      ),
            ),
            if (pendingAttachments.isNotEmpty)
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  itemCount: pendingAttachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = pendingAttachments[index];
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.contentType.startsWith('image/')
                                ? Icons.image_outlined
                                : item.contentType.startsWith('video/')
                                ? Icons.video_file_outlined
                                : Icons.description_outlined,
                            color: context.eazyAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 17,
                            onPressed:
                                () => setState(
                                  () => pendingAttachments.removeAt(index),
                                ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? .96
                          : .98,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .055),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Attach photo, video or document',
                        onPressed: sending ? null : _pickAttachment,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 25),
                      ),
                      IconButton(
                        tooltip: 'Take a photo',
                        onPressed: sending ? null : _pickCamera,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.camera_alt_outlined, size: 21),
                      ),
                      Expanded(
                        child: TextField(
                          controller: draft,
                          maxLines: 5,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => send(),
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            hintText: editing != null
                                ? 'Edit message…'
                                : replying != null
                                    ? 'Write a reply…'
                                    : 'Message on Eazy…',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Translate draft to English',
                        onPressed: _translateDraft,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.translate_rounded, size: 21),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: FilledButton(
                          onPressed: sending ? null : send,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          child: Icon(
                            editing != null
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          ),
        ],
      ),
    );
  }
}


class _ConversationSkeleton extends StatelessWidget {
  const _ConversationSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    children: const [
      Align(
        alignment: Alignment.centerLeft,
        child: _SkeletonMessage(width: 224, lines: 2),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: _SkeletonMessage(width: 184, lines: 1),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: _SkeletonMessage(width: 252, lines: 3),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: _SkeletonMessage(width: 210, lines: 2),
      ),
    ],
  );
}

class _SkeletonMessage extends StatelessWidget {
  const _SkeletonMessage({required this.width, required this.lines});
  final double width;
  final int lines;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.eazyBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++) ...[
          EazySkeletonBox(
            width: i == lines - 1 ? width * .58 : width - 28,
            height: 10,
            radius: 6,
          ),
          if (i != lines - 1) const SizedBox(height: 8),
        ],
      ],
    ),
  );
}

class _ChatWallpaperPainter extends CustomPainter {
  const _ChatWallpaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    const spacing = 76.0;
    for (var row = -1; row < (size.height / spacing).ceil() + 1; row++) {
      for (var column = -1; column < (size.width / spacing).ceil() + 1; column++) {
        final x = column * spacing + (row.isOdd ? spacing / 2 : 0);
        final y = row * spacing;
        final rect = Rect.fromCenter(
          center: Offset(x + 22, y + 22),
          width: 30,
          height: 30,
        );
        canvas.drawArc(rect, .35, 1.65, false, paint);
        canvas.drawCircle(Offset(x + 52, y + 49), 2.2, paint);
        canvas.drawLine(
          Offset(x + 7, y + 57),
          Offset(x + 17, y + 47),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onLongPress,
    required this.onReaction,
    required this.onTranslate,
    required this.onOpenAttachment,
  });
  final Map<String, dynamic> message;
  final bool isMine;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReaction;
  final VoidCallback onTranslate;
  final ValueChanged<Map<String, dynamic>> onOpenAttachment;
  @override
  Widget build(BuildContext context) {
    final sender =
        message['sender'] is Map
            ? Map<String, dynamic>.from(message['sender'] as Map)
            : <String, dynamic>{};
    final deleted = message['status'] == 'deleted';
    final reactions =
        (message['reactions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .80,
        ),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 9),
            decoration: BoxDecoration(
              color:
                  deleted
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : (isMine
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMine ? 20 : 7),
                bottomRight: Radius.circular(isMine ? 7 : 20),
              ),
              border: Border.all(
                color:
                    isMine
                        ? context.eazyAccent.withValues(alpha: .24)
                        : context.eazyBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine && sender['displayName'] != null && !deleted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      sender['displayName'].toString(),
                      style: TextStyle(
                        color: context.eazyAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                Text(
                  deleted
                      ? 'Message deleted'
                      : (message['body']?.toString() ?? ''),
                  style: TextStyle(
                    color:
                        deleted
                            ? context.eazyMuted
                            : (isMine
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface),
                    fontSize: 14,
                    height: 1.45,
                    fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (message['replyTo'] is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '↳ ${message['replyTo']['body'] ?? 'Deleted message'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.eazyMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (message['attachments'] is List &&
                    (message['attachments'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          (message['attachments'] as List).whereType<Map>().map<
                            Widget
                          >((raw) {
                            final attachment = Map<String, dynamic>.from(raw);
                            final type =
                                attachment['contentType']?.toString() ?? '';
                            final bytes =
                                int.tryParse(
                                  attachment['byteSize']?.toString() ?? '',
                                ) ??
                                0;
                            final label =
                                type.startsWith('image/')
                                    ? 'Photo'
                                    : type.startsWith('video/')
                                    ? 'Video'
                                    : type.startsWith('audio/')
                                    ? 'Audio'
                                    : 'Document';
                            final size =
                                bytes >= 1024 * 1024
                                    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                                    : '${(bytes / 1024).round()} KB';
                            return InkWell(
                              onTap: () => onOpenAttachment(attachment),
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      type.startsWith('image/')
                                          ? Icons.image_outlined
                                          : type.startsWith('video/')
                                          ? Icons.video_file_outlined
                                          : Icons.description_outlined,
                                      color: context.eazyAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      '$label attachment',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      size,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: context.eazyMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                if (message['_translation'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      message['_translation'].toString(),
                      style: const TextStyle(
                        color: EazyColors.mint,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Wrap(
                      spacing: 4,
                      children:
                          reactions
                              .map<Widget>(
                                (r) => InkWell(
                                  onTap:
                                      () =>
                                          onReaction(r['reaction'].toString()),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .22),
                                      ),
                                    ),
                                    child: Text(
                                      '${r['reaction']} ${r['count'] ?? 0}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _time(message['createdAt'] ?? message['created_at']),
                        style: TextStyle(
                          color: context.eazyMuted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (!deleted)
                      TextButton.icon(
                        onPressed: onTranslate,
                        icon: Icon(Icons.translate_rounded, size: 13),
                        label: Text(
                          'Translate',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _time(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    if (d == null) return '';
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m${local.hour >= 12 ? ' PM' : ' AM'}';
  }
}

class _ContextBar extends StatelessWidget {
  const _ContextBar({
    required this.label,
    required this.value,
    required this.onClose,
  });
  final String label, value;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(EazyRadius.md),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 31,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.eazyAccent, EazyColors.mint],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.eazyAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.eazyMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _ChatState extends StatelessWidget {
  const _ChatState(this.message, [this.action]);
  final String message;
  final Future<void> Function()? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
    child: Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: context.eazyAccent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.eazyBorder),
          ),
          child: Icon(
            Icons.forum_outlined,
            size: 32,
            color: context.eazyAccent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.eazyMuted, height: 1.4),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: action, child: const Text('Try again')),
        ],
      ],
    ),
  );
}
).hasMatch(path);
      }).toList()..sort();
      final modeName = dark ? 'dark' : 'light';
      final preferred = all.where((asset) =>
          asset.toLowerCase().contains(modeName)).toList();
      final neutral = all.where((asset) {
        final path = asset.toLowerCase();
        return !path.contains('light') && !path.contains('dark');
      }).toList();
      final choices = [...preferred, ...neutral];
      final key = 'eazy.chat.wallpaper.$modeName';
      final saved = await draftStorage.read(key: key);
      final selected = choices.contains(saved)
          ? saved
          : (preferred.isNotEmpty
              ? preferred.first
              : (neutral.isNotEmpty ? neutral.first : null));
      if (!mounted || _wallpaperDarkMode != dark) return;
      setState(() {
        _chatWallpaperChoices = choices;
        _selectedChatWallpaper = selected;
      });
    } catch (_) {
      if (!mounted || _wallpaperDarkMode != dark) return;
      setState(() {
        _chatWallpaperChoices = [];
        _selectedChatWallpaper = null;
      });
    }
  }

  Future<void> _chooseChatWallpaper() async {
    if (_chatWallpaperChoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat wallpaper images have not been added to assets/images/chat yet.'),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chat wallpaper',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 320,
                child: GridView.builder(
                  itemCount: _chatWallpaperChoices.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (_, index) {
                    final asset = _chatWallpaperChoices[index];
                    final selected = asset == _selectedChatWallpaper;
                    return InkWell(
                      onTap: () => Navigator.pop(sheetContext, asset),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : context.eazyBorder,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(asset, fit: BoxFit.cover),
                            if (selected)
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircleAvatar(
                                    radius: 13,
                                    child: Icon(Icons.check, size: 16),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedChatWallpaper = selected);
    try {
      await draftStorage.write(
        key: _wallpaperPreferenceKey,
        value: selected,
      );
    } catch (_) {
      // Keep the selected wallpaper for this conversation session.
    }
  }

  Widget _chatWallpaperBackground(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fallback = CustomPaint(
      painter: _ChatWallpaperPainter(
        color: Theme.of(context).colorScheme.primary.withValues(
          alpha: dark ? .055 : .045,
        ),
      ),
    );
    final asset = _selectedChatWallpaper;
    if (asset == null) return fallback;
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }


  String get id => widget.conversation['id']?.toString() ?? '';
  String get _draftStorageKey => 'eazy.chat.draft.$id';

  Future<void> _restoreDraft() async {
    try {
      final saved = await draftStorage.read(key: _draftStorageKey);
      if (mounted && draft.text.isEmpty && saved != null && saved.isNotEmpty) {
        draft.value = TextEditingValue(
          text: saved,
          selection: TextSelection.collapsed(offset: saved.length),
        );
      }
    } catch (_) {
      // Draft restoration is best-effort; it must not block opening a chat.
    }
  }

  void _scheduleDraftSave() {
    draftSaveTimer?.cancel();
    draftSaveTimer = Timer(
      const Duration(milliseconds: 350),
      _persistDraft,
    );
  }

  Future<void> _persistDraft() async {
    final value = draft.text;
    try {
      if (value.isEmpty) {
        await draftStorage.delete(key: _draftStorageKey);
      } else {
        await draftStorage.write(key: _draftStorageKey, value: value);
      }
    } catch (_) {
      // A local draft is convenience data, never a prerequisite for sending.
    }
  }

  Map<String, dynamic> get _otherParticipant {
    final participants = widget.conversation['participants'];
    if (participants is List) {
      final people =
          participants
              .whereType<Map>()
              .map((person) => Map<String, dynamic>.from(person))
              .toList();
      if (people.isNotEmpty) {
        return people.firstWhere(
          (person) =>
              (person['username'] ?? '').toString().toLowerCase() !=
              (currentUsername ?? '').toLowerCase(),
          orElse: () => people.first,
        );
      }
    }
    return <String, dynamic>{
      'username': widget.conversation['username'],
      'displayName':
          widget.conversation['displayName'] ??
          widget.conversation['display_name'],
    };
  }

  String get _conversationUsername {
    final username = _otherParticipant['username']?.toString();
    return username == null || username.isEmpty
        ? 'Private conversation'
        : '@$username';
  }

  String get _conversationTitle {
    final person = _otherParticipant;
    final name =
        (person['displayName'] ??
                person['display_name'] ??
                person['name'] ??
                person['username'])
            ?.toString()
            .trim();
    return name == null || name.isEmpty ? 'Chat' : name;
  }

  @override
  void initState() {
    super.initState();
    media = EazyMediaService(widget.api);
    draft.addListener(_scheduleDraftSave);
    unawaited(_restoreDraft());
    loadMessages();
    connectRealtime();
    loadMyProfile();
  }

  Future<void> loadMyProfile() async {
    try {
      final result = await widget.api.get('profiles/me', auth: true);
      final profile = result['profile'];
      if (mounted && profile is Map) {
        setState(() => currentUsername = profile['username']?.toString());
      }
    } catch (_) {}
  }

  bool _isMine(Map<String, dynamic> message) {
    final sender =
        message['sender'] is Map
            ? Map<String, dynamic>.from(message['sender'] as Map)
            : <String, dynamic>{};
    final value =
        (sender['username'] ??
                message['senderUsername'] ??
                message['sender_username'])
            ?.toString()
            .toLowerCase();
    return currentUsername != null && value == currentUsername!.toLowerCase();
  }

  @override
  void dispose() {
    draftSaveTimer?.cancel();
    draft.removeListener(_scheduleDraftSave);
    unawaited(_persistDraft());
    realtimeReconnectTimer?.cancel();
    subscription?.cancel();
    socket?.close();
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> loadMessages() async {
    try {
      if (messages.isEmpty && mounted) setState(() => loading = true);
      final r = await widget.api.get(
        'chat/conversations/$id/messages?page=1&limit=50',
        auth: true,
      );
      messages =
          (r['items'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
              .reversed
              .toList();
      unawaited(markRead());
      if (mounted) setState(() => error = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markRead() async {
    if (messages.isEmpty) return;
    try {
      await widget.api.post(
        'chat/conversations/$id/read',
        auth: true,
        body: {'lastReadMessageId': messages.last['id']},
      );
    } catch (_) {}
  }

  Future<void> connectRealtime() async {
    if (!mounted || connectingRealtime || socket != null) return;
    connectingRealtime = true;
    try {
      final token = await widget.api.readToken();
      if (token == null || token.isEmpty) {
        _scheduleRealtimeReconnect();
        return;
      }
      final base = Uri.parse(widget.api.baseUrl);
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri(
        scheme: scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/v1/realtime',
      );
      final ws = await WebSocket.connect(
        wsUri.toString(),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) {
        await ws.close();
        return;
      }
      final recoveringConnection = realtimeReconnectAttempts > 0;
      socket = ws;
      realtimeReconnectTimer?.cancel();
      realtimeReconnectTimer = null;
      realtimeReconnectAttempts = 0;
      ws.add(
        jsonEncode({'type': 'subscribe', 'channel': 'conversation', 'id': id}),
      );
      if (recoveringConnection) unawaited(loadMessages());
      subscription = ws.listen(
        (raw) {
          try {
            final frame = jsonDecode(raw.toString());
            if (frame is! Map || frame['type'] != 'event') return;
            if (frame['event'] == 'message.created' &&
                frame['data'] is Map &&
                frame['data']['message'] is Map) {
              final m = Map<String, dynamic>.from(
                frame['data']['message'] as Map,
              );
              if (m['conversationId']?.toString() == id &&
                  !messages.any((x) => x['id'] == m['id'])) {
                if (mounted) setState(() => messages.add(m));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scroll.hasClients) {
                    scroll.animateTo(
                      scroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  }
                });
                unawaited(markRead());
              }
            } else if (frame['event'] == 'message.reaction.created' ||
                frame['event'] == 'message.reaction.deleted') {
              unawaited(loadMessages());
            }
          } catch (_) {}
        },
        onDone: () => _handleRealtimeDisconnect(ws),
        onError: (_) => _handleRealtimeDisconnect(ws),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRealtimeReconnect();
    } finally {
      connectingRealtime = false;
    }
  }

  void _handleRealtimeDisconnect(WebSocket disconnectedSocket) {
    if (!identical(socket, disconnectedSocket)) return;
    socket = null;
    subscription = null;
    _scheduleRealtimeReconnect();
  }

  void _scheduleRealtimeReconnect() {
    if (!mounted || realtimeReconnectTimer != null) return;
    final delaySeconds = switch (realtimeReconnectAttempts) {
      0 => 1,
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      _ => 30,
    };
    if (realtimeReconnectAttempts < 5) realtimeReconnectAttempts++;
    realtimeReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      realtimeReconnectTimer = null;
      unawaited(connectRealtime());
    });
  }

  Future<void> send() async {
    final body = draft.text.trim();
    if ((body.isEmpty && pendingAttachments.isEmpty) || sending) return;
    final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final isEditing = editing != null;
    if (!isEditing && body.isNotEmpty) {
      setState(() {
        sending = true;
        messages.add({
          'id': pendingId,
          'body': body,
          'sender': {'username': currentUsername},
          'createdAt': DateTime.now().toIso8601String(),
          'status': 'sending',
        });
        draft.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() => sending = true);
    }
    try {
      if (isEditing) {
        final r = await widget.api.patch(
          'chat/messages/${editing!['id']}',
          auth: true,
          body: {'body': body},
        );
        final m = r['message'];
        if (m is Map) {
          setState(
            () =>
                messages =
                    messages
                        .map(
                          (x) =>
                              x['id'] == m['id']
                                  ? Map<String, dynamic>.from(m)
                                  : x,
                        )
                        .toList(),
          );
        }
        editing = null;
      } else {
        final r = await widget.api.post(
          'chat/conversations/$id/messages',
          auth: true,
          body: {
            if (body.isNotEmpty) 'body': body,
            if (replying != null) 'replyToMessageId': replying!['id'],
            if (pendingAttachments.isNotEmpty)
              'attachments':
                  pendingAttachments
                      .map(
                        (a) => {
                          'storageKey': a.path,
                          'contentType': a.contentType,
                          'byteSize': a.byteSize,
                        },
                      )
                      .toList(),
          },
        );
        final m = r['message'];
        messages.removeWhere((message) => message['id'] == pendingId);
        if (m is Map && !messages.any((x) => x['id'] == m['id'])) {
          messages.add(Map<String, dynamic>.from(m));
        }
        replying = null;
        pendingAttachments.clear();
      }
      draft.clear();
      setState(() {});
      await markRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } on ApiException catch (e) {
      messages.removeWhere((message) => message['id'] == pendingId);
      if (mounted) {
        setState(() {
          if (draft.text.trim().isEmpty) draft.text = body;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reactTo(Map<String, dynamic> m, String reaction) async {
    try {
      final list =
          (m['reactions'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      final found = list.where((x) => x['reaction'] == reaction).firstOrNull;
      if (found?['reactedByMe'] == true) {
        await widget.api.delete(
          'chat/messages/${m['id']}/reactions/${Uri.encodeComponent(reaction)}',
          auth: true,
        );
      } else {
        await widget.api.post(
          'chat/messages/${m['id']}/reactions',
          auth: true,
          body: {'reaction': reaction},
        );
      }
      await loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> translate(Map<String, dynamic> m) async {
    final body = m['body']?.toString() ?? '';
    if (body.isEmpty) return;
    try {
      final r = await widget.api.post(
        'translation',
        auth: true,
        body: {'text': body, 'targetLanguage': 'en'},
      );
      final value = r['translatedText']?.toString() ?? r['text']?.toString();
      if (value != null && mounted) setState(() => m['_translation'] = value);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _pickCamera() async {
    if (sending) return;
    try {
      final upload = await media.pickAndUpload(
        kind: 'message',
        source: ImageSource.camera,
      );
      if (upload != null && mounted) {
        setState(() => pendingAttachments.add(upload));
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
          const SnackBar(content: Text('Could not capture a photo. Please try again.')),
        );
      }
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheet) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: context.eazyAccent,
                  ),
                  title: Text('Photo'),
                  subtitle: Text('Choose an image'),
                  onTap: () => Navigator.pop(sheet, 'photo'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.video_library_outlined,
                    color: context.eazyAccent,
                  ),
                  title: Text('Video'),
                  subtitle: Text('Choose a video'),
                  onTap: () => Navigator.pop(sheet, 'video'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.attach_file_rounded,
                    color: context.eazyAccent,
                  ),
                  title: const Text('File or document'),
                  subtitle: const Text('PDF, Word, TXT or CSV, up to 25 MB'),
                  onTap: () => Navigator.pop(sheet, 'file'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (choice == null || !mounted) return;
    try {
      final upload = switch (choice) {
        'photo' => await media.pickAndUpload(kind: 'message'),
        'video' => await media.pickAndUploadVideo(kind: 'message'),
        _ => await media.pickAndUploadDocument(kind: 'message'),
      };
      if (upload != null && mounted) {
        setState(() => pendingAttachments.add(upload));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not attach that file. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final path = attachment['storageKey']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final result = await widget.api.post(
        'media/signed-message-attachment-url',
        auth: true,
        body: {'path': path},
      );
      final url = result['signedUrl']?.toString();
      if (url == null || url.isEmpty) {
        throw const ApiException('The attachment could not be opened.');
      }
      final type = attachment['contentType']?.toString() ?? '';
      if (type.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => Dialog(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('This image could not be loaded.'),
                        ),
                  ),
                ),
              ),
        );
      } else {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No app could open this attachment.')),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this attachment. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _translateDraft() async {
    final text = draft.text.trim();
    if (text.isEmpty) {
      if (mounted) context.push('/translation');
      return;
    }
    try {
      final result = await widget.api.post(
        'translation',
        auth: true,
        body: {'text': text, 'targetLanguage': 'en'},
      );
      final translated =
          (result['translatedText'] ?? result['text'])?.toString();
      if (translated == null || translated.trim().isEmpty) {
        throw const ApiException('No translated text was returned.');
      }
      if (mounted) {
        setState(() {
          draft.text = translated;
          draft.selection = TextSelection.collapsed(offset: translated.length);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> deleteMessage(Map<String, dynamic> m) async {
    try {
      await widget.api.delete('chat/messages/${m['id']}', auth: true);
      await loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> report(Map<String, dynamic> m, String reason) async {
    try {
      await widget.api.post(
        'chat/messages/${m['id']}/report',
        auth: true,
        body: {'reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void actions(Map<String, dynamic> m) {
    final status = m['status']?.toString() ?? 'sent';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => replying = m);
                  },
                ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: const Text('React'),
                    onTap: () {
                      Navigator.pop(ctx);
                      chooseReaction(m);
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('Translate to English'),
                    onTap: () {
                      Navigator.pop(ctx);
                      translate(m);
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report'),
                    onTap: () {
                      Navigator.pop(ctx);
                      report(m, 'Other inappropriate content');
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        editing = m;
                        draft.text = m['body']?.toString() ?? '';
                      });
                    },
                  ),
                if (status != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Delete'),
                    onTap: () {
                      Navigator.pop(ctx);
                      deleteMessage(m);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void chooseReaction(Map<String, dynamic> message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 8,
                runSpacing: 8,
                children:
                    _reactions
                        .map(
                          (reaction) => IconButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              reactTo(message, reaction);
                            },
                            icon: Text(
                              reaction,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
  }

  Future<void> _handleRecipientAction(String action) async {
    final username = _otherParticipant['username']?.toString().trim() ?? '';
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient details are unavailable.')),
      );
      return;
    }
    if (action == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Block this account?'),
              content: Text(
                'You will no longer receive messages from @$username.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Block'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await widget.api.post('social/block/$username', auth: true);
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Account blocked.')),
        );
      } on ApiException catch (e) {
        if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (action == 'report') {
      final reasonController = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Report account'),
              content: TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'What should Eazy review?',
                  hintText: 'Describe the issue',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = reasonController.text.trim();
                    if (value.length >= 3) Navigator.pop(dialogContext, value);
                  },
                  child: const Text('Submit report'),
                ),
              ],
            ),
      );
      reasonController.dispose();
      if (reason == null) return;
      try {
        await widget.api.post(
          'social/report/$username',
          body: {'reason': reason},
          auth: true,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted for review.')),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _conversationTitle;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              _conversationUsername,
              style: TextStyle(
                fontSize: 11,
                color: context.eazyMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: _handleRecipientAction,
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded),
                        SizedBox(width: 10),
                        Text('Block account'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined),
                        SizedBox(width: 10),
                        Text('Report account'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ChatWallpaperPainter(
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? .055
                      : .045,
                ),
              ),
            ),
          ),
          Column(
          children: [
            if (replying != null)
              _ContextBar(
                label: 'REPLYING',
                value: replying!['body']?.toString() ?? '',
                onClose: () => setState(() => replying = null),
              ),
            if (editing != null)
              _ContextBar(
                label: 'EDITING',
                value: editing!['body']?.toString() ?? '',
                onClose:
                    () => setState(() {
                      editing = null;
                      draft.clear();
                    }),
              ),
            Expanded(
              child:
                  loading
                      ? const _ConversationSkeleton()
                      : error != null
                      ? _ChatState(error!, loadMessages)
                      : messages.isEmpty
                      ? const _ChatState(
                        'No messages yet. Start the conversation.',
                      )
                      : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          return _MessageBubble(
                            message: messages[i],
                            isMine: _isMine(messages[i]),
                            onLongPress: () => actions(messages[i]),
                            onReaction: (r) => reactTo(messages[i], r),
                            onTranslate: () => translate(messages[i]),
                            onOpenAttachment: _openAttachment,
                          );
                        },
                      ),
            ),
            if (pendingAttachments.isNotEmpty)
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  itemCount: pendingAttachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = pendingAttachments[index];
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.contentType.startsWith('image/')
                                ? Icons.image_outlined
                                : item.contentType.startsWith('video/')
                                ? Icons.video_file_outlined
                                : Icons.description_outlined,
                            color: context.eazyAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 17,
                            onPressed:
                                () => setState(
                                  () => pendingAttachments.removeAt(index),
                                ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? .96
                          : .98,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .055),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Attach photo, video or document',
                        onPressed: sending ? null : _pickAttachment,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 25),
                      ),
                      IconButton(
                        tooltip: 'Take a photo',
                        onPressed: sending ? null : _pickCamera,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.camera_alt_outlined, size: 21),
                      ),
                      Expanded(
                        child: TextField(
                          controller: draft,
                          maxLines: 5,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => send(),
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            hintText: editing != null
                                ? 'Edit message…'
                                : replying != null
                                    ? 'Write a reply…'
                                    : 'Message on Eazy…',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Translate draft to English',
                        onPressed: _translateDraft,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                        ),
                        icon: const Icon(Icons.translate_rounded, size: 21),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: FilledButton(
                          onPressed: sending ? null : send,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          child: Icon(
                            editing != null
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          ),
        ],
      ),
    );
  }
}


class _ConversationSkeleton extends StatelessWidget {
  const _ConversationSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    children: const [
      Align(
        alignment: Alignment.centerLeft,
        child: _SkeletonMessage(width: 224, lines: 2),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: _SkeletonMessage(width: 184, lines: 1),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: _SkeletonMessage(width: 252, lines: 3),
      ),
      SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: _SkeletonMessage(width: 210, lines: 2),
      ),
    ],
  );
}

class _SkeletonMessage extends StatelessWidget {
  const _SkeletonMessage({required this.width, required this.lines});
  final double width;
  final int lines;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.eazyBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++) ...[
          EazySkeletonBox(
            width: i == lines - 1 ? width * .58 : width - 28,
            height: 10,
            radius: 6,
          ),
          if (i != lines - 1) const SizedBox(height: 8),
        ],
      ],
    ),
  );
}

class _ChatWallpaperPainter extends CustomPainter {
  const _ChatWallpaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    const spacing = 76.0;
    for (var row = -1; row < (size.height / spacing).ceil() + 1; row++) {
      for (var column = -1; column < (size.width / spacing).ceil() + 1; column++) {
        final x = column * spacing + (row.isOdd ? spacing / 2 : 0);
        final y = row * spacing;
        final rect = Rect.fromCenter(
          center: Offset(x + 22, y + 22),
          width: 30,
          height: 30,
        );
        canvas.drawArc(rect, .35, 1.65, false, paint);
        canvas.drawCircle(Offset(x + 52, y + 49), 2.2, paint);
        canvas.drawLine(
          Offset(x + 7, y + 57),
          Offset(x + 17, y + 47),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onLongPress,
    required this.onReaction,
    required this.onTranslate,
    required this.onOpenAttachment,
  });
  final Map<String, dynamic> message;
  final bool isMine;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReaction;
  final VoidCallback onTranslate;
  final ValueChanged<Map<String, dynamic>> onOpenAttachment;
  @override
  Widget build(BuildContext context) {
    final sender =
        message['sender'] is Map
            ? Map<String, dynamic>.from(message['sender'] as Map)
            : <String, dynamic>{};
    final deleted = message['status'] == 'deleted';
    final reactions =
        (message['reactions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .80,
        ),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 9),
            decoration: BoxDecoration(
              color:
                  deleted
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : (isMine
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMine ? 20 : 7),
                bottomRight: Radius.circular(isMine ? 7 : 20),
              ),
              border: Border.all(
                color:
                    isMine
                        ? context.eazyAccent.withValues(alpha: .24)
                        : context.eazyBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine && sender['displayName'] != null && !deleted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      sender['displayName'].toString(),
                      style: TextStyle(
                        color: context.eazyAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                Text(
                  deleted
                      ? 'Message deleted'
                      : (message['body']?.toString() ?? ''),
                  style: TextStyle(
                    color:
                        deleted
                            ? context.eazyMuted
                            : (isMine
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface),
                    fontSize: 14,
                    height: 1.45,
                    fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (message['replyTo'] is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '↳ ${message['replyTo']['body'] ?? 'Deleted message'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.eazyMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (message['attachments'] is List &&
                    (message['attachments'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          (message['attachments'] as List).whereType<Map>().map<
                            Widget
                          >((raw) {
                            final attachment = Map<String, dynamic>.from(raw);
                            final type =
                                attachment['contentType']?.toString() ?? '';
                            final bytes =
                                int.tryParse(
                                  attachment['byteSize']?.toString() ?? '',
                                ) ??
                                0;
                            final label =
                                type.startsWith('image/')
                                    ? 'Photo'
                                    : type.startsWith('video/')
                                    ? 'Video'
                                    : type.startsWith('audio/')
                                    ? 'Audio'
                                    : 'Document';
                            final size =
                                bytes >= 1024 * 1024
                                    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                                    : '${(bytes / 1024).round()} KB';
                            return InkWell(
                              onTap: () => onOpenAttachment(attachment),
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      type.startsWith('image/')
                                          ? Icons.image_outlined
                                          : type.startsWith('video/')
                                          ? Icons.video_file_outlined
                                          : Icons.description_outlined,
                                      color: context.eazyAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      '$label attachment',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      size,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: context.eazyMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                if (message['_translation'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      message['_translation'].toString(),
                      style: const TextStyle(
                        color: EazyColors.mint,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Wrap(
                      spacing: 4,
                      children:
                          reactions
                              .map<Widget>(
                                (r) => InkWell(
                                  onTap:
                                      () =>
                                          onReaction(r['reaction'].toString()),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .22),
                                      ),
                                    ),
                                    child: Text(
                                      '${r['reaction']} ${r['count'] ?? 0}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _time(message['createdAt'] ?? message['created_at']),
                        style: TextStyle(
                          color: context.eazyMuted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (!deleted)
                      TextButton.icon(
                        onPressed: onTranslate,
                        icon: Icon(Icons.translate_rounded, size: 13),
                        label: Text(
                          'Translate',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: context.eazyAccent,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _time(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    if (d == null) return '';
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m${local.hour >= 12 ? ' PM' : ' AM'}';
  }
}

class _ContextBar extends StatelessWidget {
  const _ContextBar({
    required this.label,
    required this.value,
    required this.onClose,
  });
  final String label, value;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(EazyRadius.md),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 31,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.eazyAccent, EazyColors.mint],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.eazyAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.eazyMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _ChatState extends StatelessWidget {
  const _ChatState(this.message, [this.action]);
  final String message;
  final Future<void> Function()? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
    child: Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: context.eazyAccent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.eazyBorder),
          ),
          child: Icon(
            Icons.forum_outlined,
            size: 32,
            color: context.eazyAccent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.eazyMuted, height: 1.4),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: action, child: const Text('Try again')),
        ],
      ],
    ),
  );
}
