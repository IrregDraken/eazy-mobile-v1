import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class BlocksPage extends StatefulWidget {
  const BlocksPage({super.key});
  @override State<BlocksPage> createState() => _BlocksPageState();
}

class _BlocksPageState extends State<BlocksPage> {
  final api = ApiClient();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String error = '';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final result = await api.get('blocks?page=1&limit=50', auth: true);
      final raw = result['items'] as List? ?? [];
      if (mounted) setState(() => items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> unblock(String id) async {
    if (id.isEmpty) return;
    try {
      await api.delete('blocks/$id', auth: true);
      await load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts', style: TextStyle(fontWeight: FontWeight.w900))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error.isNotEmpty) Text(error, style: const TextStyle(color: EazyColors.red)),
                  if (items.isEmpty)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No blocked accounts.', style: TextStyle(color: EazyColors.muted)))),
                  for (final user in items)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text((user['username']?.toString() ?? '?').substring(0, 1).toUpperCase())),
                        title: Text(user['displayName']?.toString() ?? user['username']?.toString() ?? 'Account'),
                        subtitle: Text('@' + (user['username']?.toString() ?? '')),
                        trailing: TextButton(
                          onPressed: () => unblock(user['userId']?.toString() ?? user['id']?.toString() ?? ''),
                          child: const Text('Unblock'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
