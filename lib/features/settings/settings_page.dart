import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../app/theme/theme_controller.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final api = ApiClient();
  String language = 'en', theme = 'system';
  bool follows = true, likes = true, comments = true;
  bool loading = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await api.get('settings', auth: true);
      final s = Map<String, dynamic>.from((r['settings'] as Map?) ?? r),
          n = Map<String, dynamic>.from((s['notifications'] as Map?) ?? {});
      if (mounted)
        setState(() {
          language = s['languageCode']?.toString() ?? 'en';
          theme = s['theme']?.toString() ?? 'system';
          follows = n['follows'] != false;
          likes = n['likes'] != false;
          comments = n['comments'] != false;
        });
      eazyThemeMode.value = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save(Map<String, dynamic> patch) async {
    try {
      await api.patch('settings', body: patch, auth: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> deleteAccount() async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your Eazy account and associated personal data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EazyColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmation != true || !mounted) return;
    try {
      await widget.auth.deleteAccount();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Settings',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body:
        loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: EazyColors.red)),
                const Text(
                  'Appearance',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Card(
                  child: DropdownButtonFormField<String>(
                    value: theme,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('System')),
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => theme = v);
                      eazyThemeMode.value = switch (v) {
                        'light' => ThemeMode.light,
                        'dark' => ThemeMode.dark,
                        _ => ThemeMode.system,
                      };
                      save({'theme': v});
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Language',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Card(
                  child: DropdownButtonFormField<String>(
                    value: language,
                    decoration: const InputDecoration(
                      labelText: 'App language',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'fr', child: Text('Français')),
                      DropdownMenuItem(value: 'es', child: Text('Español')),
                      DropdownMenuItem(value: 'yo', child: Text('Yorùbá')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => language = v);
                      save({'languageCode': v});
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Activity notifications',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('New followers'),
                        value: follows,
                        onChanged: (v) {
                          setState(() => follows = v);
                          save({
                            'notifications': {'follows': v},
                          });
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Post likes'),
                        value: likes,
                        onChanged: (v) {
                          setState(() => likes = v);
                          save({
                            'notifications': {'likes': v},
                          });
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Comments'),
                        value: comments,
                        onChanged: (v) {
                          setState(() => comments = v);
                          save({
                            'notifications': {'comments': v},
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Help',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.support_agent_outlined, color: EazyColors.green),
                    title: const Text('Help & support'),
                    subtitle: const Text('FAQs, safe automated answers and escalation channels.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/support'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account',
                  style: TextStyle(
                    color: EazyColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.delete_forever_outlined,
                      color: EazyColors.red,
                    ),
                    title: const Text('Delete account'),
                    subtitle: const Text(
                      'Permanently remove your account and personal data.',
                    ),
                    onTap: deleteAccount,
                  ),
                ),
              ],
            ),
  );
}
