import 'package:flutter/material.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class AssistPage extends StatefulWidget {
  const AssistPage({super.key});

  @override
  State<AssistPage> createState() => _AssistPageState();
}

class _AssistPageState extends State<AssistPage> {
  final api = ApiClient();
  final composer = TextEditingController();
  final scroll = ScrollController();
  final messages = <Map<String, dynamic>>[];
  String? sessionId;
  String? error;
  bool loading = true;
  bool sending = false;
  bool providerAvailable = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final capabilities = await api.get('assist/capabilities', auth: true);
      providerAvailable = capabilities['providerAvailable'] == true;
      final sessions = await api.get(
        'assist/sessions?page=1&limit=1',
        auth: true,
      );
      final items = sessions['items'] as List? ?? const [];
      if (items.isNotEmpty && items.first is Map) {
        sessionId = (items.first as Map)['id']?.toString();
      } else {
        final created = await api.post('assist/sessions', auth: true);
        sessionId = (created['session'] as Map?)?['id']?.toString();
      }
      if (sessionId != null) await _loadMessages();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadMessages() async {
    final id = sessionId;
    if (id == null) return;
    final result = await api.get(
      'assist/sessions/$id/messages?page=1&limit=50',
      auth: true,
    );
    final items = result['items'] as List? ?? const [];
    messages
      ..clear()
      ..addAll(
        items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
  }

  Future<void> _send() async {
    final content = composer.text.trim();
    final id = sessionId;
    if (content.isEmpty || id == null || sending) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final result = await api.post(
        'assist/sessions/$id/messages',
        auth: true,
        body: {'content': content},
      );
      final user = result['userMessage'];
      final assistant = result['assistantMessage'];
      if (user is Map) messages.add(Map<String, dynamic>.from(user));
      if (assistant is Map) messages.add(Map<String, dynamic>.from(assistant));
      composer.clear();
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eazy Assist', style: TextStyle(fontWeight: FontWeight.w900)),
            Text(
              'Useful help, grounded in your Eazy context',
              style: TextStyle(fontSize: 11, color: EazyColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : _bootstrap,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  if (!providerAvailable)
                    const _StatusBanner(
                      icon: Icons.cloud_off_rounded,
                      message:
                          'Assist is not enabled on the server yet. Configure the AI provider to send a message.',
                    ),
                  if (error != null)
                    _StatusBanner(
                      icon: Icons.error_outline_rounded,
                      message: error!,
                      isError: true,
                    ),
                  Expanded(
                    child:
                        messages.isEmpty
                            ? const _EmptyAssist()
                            : ListView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                18,
                                18,
                                12,
                              ),
                              itemCount: messages.length,
                              itemBuilder:
                                  (context, index) =>
                                      _MessageBubble(message: messages[index]),
                            ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: composer,
                              minLines: 1,
                              maxLines: 5,
                              enabled: providerAvailable && !sending,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText: 'Ask Eazy something useful...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: FilledButton(
                              onPressed:
                                  providerAvailable && !sending ? _send : null,
                              child:
                                  sending
                                      ? const SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.arrow_upward_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final role =
        message['role']?.toString() ??
        message['sender']?.toString() ??
        'assistant';
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? EazyColors.green : EazyColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUser ? EazyColors.green : EazyColors.border,
          ),
        ),
        child: Text(
          message['content']?.toString() ?? message['body']?.toString() ?? '',
          style: TextStyle(
            color: isUser ? EazyColors.canvas : EazyColors.ink,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _EmptyAssist extends StatelessWidget {
  const _EmptyAssist();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: EazyColors.green.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 34,
              color: EazyColors.green,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ask Eazy',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get help with your Eazy experience when the AI provider is available.',
            textAlign: TextAlign.center,
            style: TextStyle(color: EazyColors.muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.message,
    this.isError = false,
  });
  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: (isError ? EazyColors.red : EazyColors.amber).withValues(
        alpha: .10,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (isError ? EazyColors.red : EazyColors.amber).withValues(
          alpha: .30,
        ),
      ),
    ),
    child: Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: isError ? EazyColors.red : EazyColors.amber,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: EazyColors.muted, height: 1.35),
          ),
        ),
      ],
    ),
  );
}
