import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../app/theme/theme_controller.dart';
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
  String theme = 'light';
  bool follows = true, likes = true, comments = true;
  bool loading = true;
  bool deleting = false;
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
      if (mounted) {
        setState(() {
          theme = s['theme']?.toString() == 'dark' ? 'dark' : 'light';
          follows = n['follows'] != false;
          likes = n['likes'] != false;
          comments = n['comments'] != false;
        });
      }
      await setEazyThemeMode(
        theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deleteAccount() async {
    setState(() {
      deleting = true;
      error = '';
    });
    try {
      final preflight = await api.get(
        'auth/delete-account/preflight',
        auth: true,
      );
      if (!mounted) return;
      final blockers =
          (preflight['blockers'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => item['message']?.toString() ?? '')
              .where((message) => message.isNotEmpty)
              .toList();

      if (preflight['canDelete'] != true || blockers.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Account deletion is not available yet'),
                content: Text(
                  blockers.isEmpty
                      ? 'Resolve any pending account activity, then try again. If you need help, contact privacy@eazy.name.ng.'
                      : blockers.join('\n\n'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Understood'),
                  ),
                ],
              ),
        );
        return;
      }

      final confirmation = TextEditingController();
      if (!mounted) {
        confirmation.dispose();
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (dialogContext, setDialogState) => AlertDialog(
                    title: const Text('Delete your Eazy account?'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This permanently removes your Eazy profile and personal content. Financial records that must be retained by law may remain. This action cannot be undone.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmation,
                          autofocus: true,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Type DELETE to confirm',
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(dialogContext).colorScheme.error,
                        ),
                        onPressed:
                            confirmation.text.trim() == 'DELETE'
                                ? () => Navigator.of(dialogContext).pop(true)
                                : null,
                        child: const Text('Delete account'),
                      ),
                    ],
                  ),
            ),
      );
      confirmation.dispose();
      if (confirmed != true) return;

      await api.post(
        'auth/delete-account',
        body: {'confirmation': 'DELETE'},
        auth: true,
      );
      await widget.auth.signOut();
      if (mounted) context.go('/welcome');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'We could not complete account deletion. Contact privacy@eazy.name.ng for help.';
        });
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Future<void> save(Map<String, dynamic> patch) async {
    try {
      await api.patch('settings', body: patch, auth: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900)),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              _sectionLabel(context, 'Account'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('My profile'),
                      subtitle: const Text('View your profile and posts'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go('/home?tab=profile'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('Account details'),
                      subtitle: const Text('Manage your email, phone number and password'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/account-settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Security and privacy'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Security and sign-in'),
                      subtitle: const Text('Manage account security'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/security'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.block_rounded),
                      title: const Text('Blocked accounts'),
                      subtitle: const Text('Manage people you have blocked'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/blocks'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Preferences'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: theme,
                    decoration: const InputDecoration(labelText: 'Appearance'),
                    items: const [
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => theme = value);
                      setEazyThemeMode(
                        value == 'dark' ? ThemeMode.dark : ThemeMode.light,
                      );
                      save({'theme': value});
                    },
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('App language'),
                  subtitle: const Text(
                    'English. Use Translator to translate messages and content into other supported languages.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Notifications'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notification center'),
                      subtitle: const Text('View your recent activity'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/notifications'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('New followers'),
                      value: follows,
                      onChanged: (value) {
                        setState(() => follows = value);
                        save({'notifications': {'follows': value}});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Post likes'),
                      value: likes,
                      onChanged: (value) {
                        setState(() => likes = value);
                        save({'notifications': {'likes': value}});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Comments'),
                      value: comments,
                      onChanged: (value) {
                        setState(() => comments = value);
                        save({'notifications': {'comments': value}});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Danger zone'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                  title: const Text('Delete account'),
                  subtitle: const Text('Permanently delete your account and personal content.'),
                  trailing: deleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: deleting ? null : deleteAccount,
                ),
              ),
            ],
          ),
  );

  Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}
