import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/ui/eazy_assist_fab.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final api = ApiClient();
  List<Map<String, dynamic>> items = [];
  int unread = 0;
  String error = '';
  bool loading = true, pushBusy = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  @override
  void initState() {
    super.initState();
    load();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerDeviceToken(token);
    });
    _registerExistingTokenIfAuthorized();
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  Future<void> _registerExistingTokenIfAuthorized() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _registerDeviceToken(token);
    } catch (_) {
      // Push registration can retry on the next token refresh or explicit enable.
    }
  }

  Future<void> _registerDeviceToken(String token) async {
    try {
      await api.post(
        'notifications/devices',
        body: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
        auth: true,
      );
    } catch (_) {
      // A later token refresh or explicit opt-in can retry registration.
    }
  }

  Future<void> load() async {
    if (mounted) setState(() => error = '');
    try {
      final result = await api.get('notifications?page=1&limit=50', auth: true);
      if (mounted) {
        setState(() {
          items = (result['items'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((item) {
                final type = item['type']?.toString().toLowerCase();
                return type != 'payment' && type != 'order';
              })
              .toList();
          unread = items.where((item) => item['isRead'] != true).length;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> enablePush() async {
    setState(() => pushBusy = true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        throw Exception('Notification permission was denied.');
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Push token was unavailable on this device.');
      }
      final r = await api.post(
        'notifications/devices',
        body: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
        auth: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r['pushDelivery'] == 'available'
                  ? 'Push notifications enabled.'
                  : 'In-app notifications are enabled; push delivery is not configured on the server yet.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => pushBusy = false);
    }
  }

  Future<void> read(String id) async {
    try {
      await api.post('notifications/$id/read', auth: true);
      await load();
    } catch (_) {}
  }

  Future<void> readAll() async {
    try {
      await api.post('notifications/read-all', auth: true);
      await load();
    } catch (_) {}
  }

  IconData icon(String? t) => switch (t) {
    'follow' => Icons.person_add_alt_1_rounded,
    'like' => Icons.favorite_rounded,
    'comment' => Icons.mode_comment_rounded,
    _ => Icons.notifications_rounded,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: const EazyAssistFab(),
    appBar: AppBar(
      title: Text(
        unread > 0 ? 'Notifications ($unread)' : 'Notifications',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          onPressed: pushBusy ? null : enablePush,
          icon: const Icon(Icons.notifications_active_outlined),
        ),
        TextButton(
          onPressed: unread == 0 ? null : readAll,
          child: const Text('Read all'),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child:
          loading
              ? const Center(child: CircularProgressIndicator())
              : error.isNotEmpty
              ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      error,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              )
              : items.isEmpty
              ? ListView(
                children: [
                  const SizedBox(height: 180),
                  Center(
                    child: Text(
                      'You’re all caught up.',
                      style: TextStyle(color: context.eazyMuted),
                    ),
                  ),
                ],
              )
              : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final n = items[i];
                  return Card(
                    child: ListTile(
                      onTap: () => read(n['id'].toString()),
                      leading: CircleAvatar(
                        child: Icon(icon(n['type']?.toString())),
                      ),
                      title: Text(
                        n['title']?.toString() ?? 'Eazy notification',
                      ),
                      subtitle: Text(
                        n['body']?.toString() ?? 'Activity on Eazy',
                      ),
                      trailing:
                          n['isRead'] == true
                              ? null
                              : Icon(
                                Icons.circle,
                                size: 9,
                                color: context.eazyAccent,
                              ),
                    ),
                  );
                },
              ),
    ),
  );
}
