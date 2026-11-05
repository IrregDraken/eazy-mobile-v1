import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/media/media_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SellerProductsPage extends StatefulWidget {
  const SellerProductsPage({super.key});
  @override
  State<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends State<SellerProductsPage> {
  final api = ApiClient();
  late final media = EazyMediaService(api);
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await api.get('marketplace/seller/products?page=1&limit=50', auth: true);
      if (!mounted) return;
      setState(() { products = (result['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> edit(Map<String, dynamic> product) async {
    final name = TextEditingController(text: product['name']?.toString() ?? '');
    final description = TextEditingController(text: product['description']?.toString() ?? '');
    final price = TextEditingController(text: product['priceAmount']?.toString() ?? '');
    final stock = TextEditingController(text: (product['availability'] as Map?)?['availableQuantity']?.toString() ?? '0');
    String status = product['status']?.toString() ?? 'active';
    MediaUpload? replacement;
    bool saving = false;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
      title: const Text('Edit product'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')),
        TextField(controller: description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price', prefixText: '₦ ')),
        TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Available stock')),
        DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'Listing status'), items: const [DropdownMenuItem(value: 'active', child: Text('Active')), DropdownMenuItem(value: 'draft', child: Text('Draft')), DropdownMenuItem(value: 'archived', child: Text('Archived')), DropdownMenuItem(value: 'sold_out', child: Text('Sold out'))], onChanged: (value) { if (value != null) update(() => status = value); }),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: saving ? null : () async { final value = await media.pickAndUpload(kind: 'product'); if (value != null) update(() => replacement = value); }, icon: const Icon(Icons.photo_outlined), label: Text(replacement == null ? 'Replace product photo' : 'Replacement photo uploaded')),
        if (replacement?.localPath != null) Image.file(File(replacement!.localPath!), height: 90, fit: BoxFit.cover),
      ]))),
      actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: saving ? null : () async {
        final quantity = int.tryParse(stock.text.trim());
        final amount = double.tryParse(price.text.trim());
        if (name.text.trim().isEmpty || quantity == null || quantity < 0 || amount == null || amount <= 0) return;
        update(() => saving = true);
        try {
          await api.patch('marketplace/products/${product['id']}', auth: true, body: {
            'name': name.text.trim(), 'description': description.text.trim(),
            'priceAmount': price.text.trim(), 'status': status,
            if (replacement != null) 'media': [{'storageKey': replacement!.path, 'position': 0}],
          });
          await api.patch('marketplace/products/${product['id']}/inventory', auth: true, body: {'availableQuantity': quantity});
          if (dialogContext.mounted) Navigator.pop(dialogContext, true);
        } on ApiException catch (e) {
          update(() => saving = false);
          if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }, child: Text(saving ? 'Saving…' : 'Save changes'))],
    )));
    name.dispose(); description.dispose(); price.dispose(); stock.dispose();
    if (saved == true && mounted) load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My listings'), actions: [IconButton(tooltip: 'Add product', onPressed: () => context.push('/seller'), icon: const Icon(Icons.add_rounded))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('Retry'))])) : products.isEmpty ? const Center(child: Text('You have not listed any products yet.')) : RefreshIndicator(onRefresh: load, child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: products.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, i) {
      final product = products[i];
      final mediaList = product['media'] as List? ?? const [];
      final first = mediaList.isNotEmpty && mediaList.first is Map ? Map<String, dynamic>.from(mediaList.first as Map) : <String, dynamic>{};
      final url = first['url']?.toString();
      return Card(child: ListTile(leading: url != null ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 54, height: 54, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))) : const Icon(Icons.inventory_2_outlined), title: Text(product['name']?.toString() ?? 'Product'), subtitle: Text('₦${product['priceAmount'] ?? '0.00'} · ${product['status']} · Stock ${(product['availability'] as Map?)?['availableQuantity'] ?? '—'}'), trailing: const Icon(Icons.edit_outlined), onTap: () => edit(product)));
    })),
  );
}
