import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SellerReviewsPage extends StatefulWidget {
  const SellerReviewsPage({super.key, required this.username});
  final String username;
  @override
  State<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends State<SellerReviewsPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> reviews = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('marketplace/sellers/${Uri.encodeComponent(widget.username)}/reviews?page=1&limit=50');
      if (!mounted) return;
      setState(() { reviews = (result['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('@${widget.username} reviews')),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('Retry'))]))
      : reviews.isEmpty ? const Center(child: Text('This seller has no reviews yet.'))
      : RefreshIndicator(onRefresh: load, child: ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: reviews.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final review = reviews[i];
          return Card(child: ListTile(
            title: Text('${review['reviewerDisplayName'] ?? review['reviewerUsername'] ?? 'Buyer'} · ★ ${review['rating']}'),
            subtitle: Text('${review['productName'] ?? 'Product'}\n${review['reviewText'] ?? ''}'),
            isThreeLine: true,
          ));
        },
      )),
  );
}
