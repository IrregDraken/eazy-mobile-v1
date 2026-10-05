import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../home/home_shell.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final profile = auth.profile ?? const <String, dynamic>{};
    final name = profile['displayName']?.toString() ?? 'Eazy user';
    final username = profile['username']?.toString() ?? '';
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
      EazyPageHeader(title: 'You', trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined))),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const CircleAvatar(radius: 44, child: Icon(Icons.person_rounded, size: 38)),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        if (username.isNotEmpty) Text('@' + username, style: const TextStyle(color: EazyColors.muted)),
        const SizedBox(height: 18),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_Stat('0', 'Posts'), _Stat('0', 'Followers'), _Stat('0', 'Following')]),
      ]))),
      const SizedBox(height: 12),
      _Menu(Icons.person_outline_rounded, 'Edit profile'),
      _Menu(Icons.notifications_none_rounded, 'Notifications'),
      _Menu(Icons.translate_rounded, 'Language & translation'),
      _Menu(Icons.location_on_outlined, 'Location sharing'),
      _Menu(Icons.help_outline_rounded, 'Help & support'),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () async { await auth.signOut(); if (context.mounted) context.go('/welcome'); }, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
    ]));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 2), Text(label, style: const TextStyle(color: EazyColors.muted, fontSize: 12))]);
}

class _Menu extends StatelessWidget {
  const _Menu(this.icon, this.title);
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(onTap: () {}, leading: Icon(icon, color: EazyColors.green), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.chevron_right_rounded, color: EazyColors.muted)));
}
