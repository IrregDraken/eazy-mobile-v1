import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../home/home_shell.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> posts = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final json = await api.get('feed?limit=20', auth: true);
      posts = (json['posts'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: EazyPageHeader(title: 'Good day', subtitle: widget.auth.profile?['displayName']?.toString() ?? 'Welcome to Eazy', trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person_rounded)), title: const Text('Share something'), subtitle: const Text('Start a conversation with your world', style: TextStyle(color: EazyColors.muted)), trailing: const Icon(Icons.add_circle_outline_rounded, color: EazyColors.green), onTap: _compose)))),
        if (loading) const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
        if (!loading && error != null) SliverFillRemaining(hasScrollBody: false, child: _State(message: error!, action: load)),
        if (!loading && error == null && posts.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: _State(message: 'Your feed is quiet. Follow people and share something to get the conversation moving.')),
        if (!loading && posts.isNotEmpty) SliverList.builder(itemCount: posts.length, itemBuilder: (context, index) => _Post(post: posts[index])),
      ]),
    ),
  );

  Future<void> _compose() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Share something'),
      content: TextField(controller: controller, autofocus: true, maxLines: 5, decoration: const InputDecoration(hintText: 'What’s on your mind?')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post'))],
    ));
    if (text == null || text.isEmpty) return;
    try {
      await api.post('feed', auth: true, body: {'body': text, 'visibility': 'PUBLIC'});
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _Post extends StatelessWidget {
  const _Post({required this.post});
  final Map<String, dynamic> post;
  @override
  Widget build(BuildContext context) {
    final author = post['author'] is Map ? Map<String, dynamic>.from(post['author'] as Map) : const <String, dynamic>{};
    final name = author['displayName']?.toString() ?? 'Eazy user';
    final username = author['username']?.toString() ?? '';
    return Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const CircleAvatar(radius: 22, child: Icon(Icons.person_rounded)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), Text(username.isEmpty ? 'Eazy' : '@' + username, style: const TextStyle(color: EazyColors.muted, fontSize: 12))])), const Icon(Icons.more_horiz_rounded, color: EazyColors.muted)]),
      const SizedBox(height: 14),
      Text(post['body']?.toString() ?? '', style: const TextStyle(fontSize: 15, height: 1.45)),
      const SizedBox(height: 12),
      Row(children: [TextButton.icon(onPressed: () {}, icon: const Icon(Icons.favorite_border_rounded), label: Text((post['likeCount'] ?? 0).toString())), TextButton.icon(onPressed: () {}, icon: const Icon(Icons.chat_bubble_outline_rounded), label: Text((post['commentCount'] ?? 0).toString())), const Spacer(), IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark_border_rounded))]),
    ]))));
  }
}

class _State extends StatelessWidget {
  const _State({required this.message, this.action});
  final String message;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.forum_outlined, size: 42, color: EazyColors.green),
    const SizedBox(height: 14),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: EazyColors.muted, height: 1.45)),
    if (action != null) ...[const SizedBox(height: 16), OutlinedButton(onPressed: action, child: const Text('Try again'))],
  ]));
}
