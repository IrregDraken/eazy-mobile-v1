import 'dart:io';

import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/media/media_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SellerSetupPage extends StatefulWidget {
  const SellerSetupPage({super.key});

  @override
  State<SellerSetupPage> createState() => _SellerSetupPageState();
}

class _SellerSetupPageState extends State<SellerSetupPage> {
  final api = ApiClient();
  late final media = EazyMediaService(api);
  final name = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final quantity = TextEditingController(text: '1');
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  MediaUpload? image;
  bool loadingCategories = true;
  bool uploading = false;
  bool publishing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final result = await api.get('marketplace/categories?page=1&limit=50');
      if (!mounted) return;
      setState(() {
        categories = (result['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loadingCategories = false);
    }
  }

  Future<void> _pickImage() async {
    if (uploading || publishing) return;
    setState(() { uploading = true; error = null; });
    try {
      final uploaded = await media.pickAndUpload(kind: 'product');
      if (mounted && uploaded != null) setState(() => image = uploaded);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not upload that image. Try another file.');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _publish() async {
    final title = name.text.trim();
    final amount = price.text.trim();
    final stock = int.tryParse(quantity.text.trim());
    if (title.isEmpty || amount.isEmpty || stock == null || stock < 0) {
      setState(() => error = 'Enter a product name, valid price and stock quantity.');
      return;
    }
    if (!RegExp(r'^\\d{1,18}(\\.\\d{1,2})?$').hasMatch(amount) || double.tryParse(amount) == null || double.parse(amount) <= 0) {
      setState(() => error = 'Enter a valid NGN price, for example 12500 or 12500.50.');
      return;
    }
    setState(() { publishing = true; error = null; });
    try {
      final result = await api.post(
        'marketplace/products',
        auth: true,
        body: {
          'name': title,
          'description': description.text.trim(),
          if (categoryId != null) 'categoryId': categoryId,
          'priceAmount': amount,
          'currency': 'NGN',
          'status': 'active',
          'availableQuantity': stock,
          'media': image == null ? [] : [{'storageKey': image!.path, 'position': 0}],
        },
      );
      if (!mounted) return;
      final product = result['product'];
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your product is now listed on Eazy.')),
      );
      Navigator.of(context).pop(product);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Become a Seller')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Put your first product in front of Eazy buyers.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 176,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.eazyBorder),
              ),
              child: image?.localPath != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(File(image!.localPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.check_circle_outline_rounded, size: 42)))
                  : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(uploading ? Icons.cloud_upload_outlined : Icons.add_photo_alternate_outlined, size: 36, color: context.eazyAccent),
                      const SizedBox(height: 8),
                      Text(uploading ? 'Uploading image…' : image == null ? 'Add product photo' : 'Photo uploaded', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
            ),
          ),
          const SizedBox(height: 18),
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Product name', hintText: 'What are you selling?')),
          const SizedBox(height: 12),
          TextField(controller: description, minLines: 3, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Description', hintText: 'Describe the product, condition and details')),
          const SizedBox(height: 12),
          if (loadingCategories) const LinearProgressIndicator()
          else DropdownButtonFormField<String>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: 'Category (optional)'),
            items: categories.map((item) => DropdownMenuItem<String>(
              value: item['id']?.toString(),
              child: Text(item['name']?.toString() ?? 'Category'),
            )).where((item) => item.value != null).toList(),
            onChanged: (value) => setState(() => categoryId = value),
          ),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price', prefixText: '₦ ', hintText: '12500')),
          const SizedBox(height: 12),
          TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Available quantity')),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 22),
          SizedBox(height: 54, child: FilledButton(
            onPressed: publishing || uploading ? null : _publish,
            child: publishing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Publish product'),
          )),
          const SizedBox(height: 8),
          Text('Your listing is subject to Eazy marketplace rules. You can update inventory and product details later.', textAlign: TextAlign.center, style: TextStyle(color: context.eazyMuted, fontSize: 12)),
        ],
      ),
    ),
  );
}
