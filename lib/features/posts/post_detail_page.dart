import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.postId});
  final String postId;
  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  Map<String, dynamic>? post;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final result = await api.get('posts/${widget.postId}', auth: true);
      if (mounted) setState(() => post = Map<String, dynamic>.from(result['post'] as Map));
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final data = post ?? const <String, dynamic>{};
    final author = data['author'] is Map ? Map<String, dynamic>.from(data['author'] as Map) : <String, dynamic>{};
    final media = (data['media'] as List? ?? const []).whereType<Map>().toList();
    return Scaffold(appBar: AppBar(title: const Text('Post')), body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Text(error!)) : ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(author['displayName']?.toString() ?? 'Eazy user'), subtitle: Text('@${author['username'] ?? ''}')),
      if ((data['content']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(data['content'].toString(), style: const TextStyle(fontSize: 16))),
      for (final item in media) if (item['mediaType'] == 'image' && item['url'] != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(item['url'].toString(), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined)))),
      if (media.any((item) => item['mediaType'] == 'video')) const Text('This post contains video media. Open the post in the Eazy feed to view the video.'),
    ]));
  }
}
