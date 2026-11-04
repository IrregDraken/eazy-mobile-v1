import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  final deliveryFee = TextEditingController(text: '0');
  final pickupInstructions = TextEditingController();
  final storeName = TextEditingController();
  final storeSlug = TextEditingController();
  final storeDescription = TextEditingController();
  final storePhone = TextEditingController();

  bool deliveryEnabled = false;
  bool pickupEnabled = true;
  bool loadingStoreProfile = true;
  bool storeProfileReady = false;
  bool loadingAgreement = true;
  bool sellerAgreementConfigured = false;
  bool sellerAgreementAccepted = false;
  bool agreedToSellerTerms = false;
  bool acceptingAgreement = false;
  String? sellerAgreementVersion;
  String? sellerAgreementText;
  bool savingStore = false;
  bool loadingDeliverySettings = true;
  bool deliverySettingsReady = false;
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
    _loadDeliverySettings();
    _loadStoreProfile();
    _loadSellerAgreement();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    quantity.dispose();
    deliveryFee.dispose();
    pickupInstructions.dispose();
    storeName.dispose();
    storeSlug.dispose();
    storeDescription.dispose();
    storePhone.dispose();
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

  Future<void> _loadSellerAgreement() async {
    try {
      final result = await api.get('marketplace/seller/agreement', auth: true);
      if (!mounted) return;
      setState(() {
        sellerAgreementConfigured = result['configured'] == true;
        sellerAgreementAccepted = result['accepted'] == true;
        sellerAgreementVersion = result['version']?.toString();
        sellerAgreementText = result['text']?.toString();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loadingAgreement = false);
    }
  }

  Future<void> _acceptSellerAgreement() async {
    if (!agreedToSellerTerms || !sellerAgreementConfigured) return;
    setState(() => acceptingAgreement = true);
    try {
      await api.post('marketplace/seller/agreement/accept', auth: true, body: {'accepted': true});
      if (mounted) setState(() => sellerAgreementAccepted = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => acceptingAgreement = false);
    }
  }

  Future<void> _loadStoreProfile() async {
    try {
      final result = await api.get('marketplace/seller/store', auth: true);
      final value = result['store'];
      if (!mounted) return;
      if (value is Map) {
        final saved = Map<String, dynamic>.from(value);
        storeName.text = saved['storeName']?.toString() ?? '';
        storeSlug.text = saved['slug']?.toString() ?? '';
        storeDescription.text = saved['description']?.toString() ?? '';
        storePhone.text = saved['supportPhone']?.toString() ?? '';
        setState(() => storeProfileReady = true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loadingStoreProfile = false);
    }
  }

  Future<void> _saveStoreProfile() async {
    final title = storeName.text.trim();
    final slug = storeSlug.text.trim().toLowerCase();
    if (title.length < 3 || !RegExp(r'^[a-z0-9][a-z0-9-]{2,59}$').hasMatch(slug)) {
      setState(() => error = 'Enter a store name and a URL slug using lowercase letters, numbers and hyphens.');
      return;
    }
    setState(() { savingStore = true; error = null; });
    try {
      await api.put('marketplace/seller/store', auth: true, body: {
        'storeName': title,
        'slug': slug,
        'description': storeDescription.text.trim(),
        'supportPhone': storePhone.text.trim().isEmpty ? null : storePhone.text.trim(),
      });
      if (!mounted) return;
      setState(() => storeProfileReady = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller store profile saved.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => savingStore = false);
    }
  }

  Future<void> _loadDeliverySettings() async {
    try {
      final result = await api.get('marketplace/seller/delivery-settings', auth: true);
      final settings = result['settings'] is Map
          ? Map<String, dynamic>.from(result['settings'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        deliveryEnabled = settings['deliveryEnabled'] == true;
        pickupEnabled = settings['pickupEnabled'] != false;
        deliveryFee.text = settings['deliveryFeeAmount']?.toString() ?? '0';
        pickupInstructions.text = settings['pickupInstructions']?.toString() ?? '';
        loadingDeliverySettings = false;
        deliverySettingsReady = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { error = e.message; loadingDeliverySettings = false; });
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
    final details = description.text.trim();
    final amount = price.text.trim();
    final stock = int.tryParse(quantity.text.trim());
    if (title.isEmpty || details.isEmpty || amount.isEmpty || stock == null || stock < 0) {
      setState(() => error = 'Enter a product name, description, valid price and stock quantity.');
      return;
    }
    if (!RegExp(r'^\d{1,18}(\.\d{1,2})?$').hasMatch(amount) ||
        double.tryParse(amount) == null || double.parse(amount) <= 0) {
      setState(() => error = 'Enter a valid NGN price, for example 12500 or 12500.50.');
      return;
    }
    if (!sellerAgreementAccepted || loadingAgreement) {
      setState(() => error = 'Read and accept the current Eazy seller agreement before publishing.');
      return;
    }
    if (!storeProfileReady || loadingStoreProfile) {
      setState(() => error = 'Save your seller store profile before publishing products.');
      return;
    }
    if (!deliverySettingsReady || loadingDeliverySettings) {
      setState(() => error = 'Delivery settings could not be loaded. Reopen this screen and try again.');
      return;
    }
    if (!deliveryEnabled && !pickupEnabled) {
      setState(() => error = 'Enable delivery, pickup or both before publishing.');
      return;
    }
    if (deliveryEnabled &&
        (double.tryParse(deliveryFee.text.trim()) == null ||
            double.parse(deliveryFee.text.trim()) < 0)) {
      setState(() => error = 'Enter a valid delivery fee.');
      return;
    }

    setState(() { publishing = true; error = null; });
    try {
      await api.patch('marketplace/seller/delivery-settings', auth: true, body: {
        'deliveryEnabled': deliveryEnabled,
        'pickupEnabled': pickupEnabled,
        'deliveryFeeAmount': deliveryFee.text.trim(),
        'currency': 'NGN',
        'pickupInstructions': pickupInstructions.text.trim().isEmpty
            ? null
            : pickupInstructions.text.trim(),
      });
      final result = await api.post('marketplace/products', auth: true, body: {
        'name': title,
        'description': details,
        if (categoryId != null) 'categoryId': categoryId,
        'priceAmount': amount,
        'currency': 'NGN',
        'status': 'active',
        'availableQuantity': stock,
        'media': image == null ? [] : [{'storageKey': image!.path, 'position': 0}],
      });
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
    appBar: AppBar(
      title: const Text('Become a Seller'),
      actions: [
        IconButton(tooltip: 'My listings', onPressed: () => context.push('/seller/products'), icon: const Icon(Icons.inventory_2_outlined)),
        IconButton(tooltip: 'Seller orders', onPressed: () => context.push('/seller/orders'), icon: const Icon(Icons.receipt_long_rounded)),
        IconButton(tooltip: 'Seller payables', onPressed: () => context.push('/seller/payables'), icon: const Icon(Icons.account_balance_wallet_outlined)),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Put your first product in front of Eazy buyers.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your seller store', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 6),
              const Text('Set the name and public address buyers will see.'),
              const SizedBox(height: 10),
              TextField(controller: storeName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Store name')),
              const SizedBox(height: 10),
              TextField(controller: storeSlug, decoration: const InputDecoration(labelText: 'Store URL slug', prefixText: 'www.eazy.name.ng/store/')),
              const SizedBox(height: 10),
              TextField(controller: storeDescription, minLines: 2, maxLines: 4, maxLength: 1500, decoration: const InputDecoration(labelText: 'Store description')),
              const SizedBox(height: 10),
              TextField(controller: storePhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Store contact phone (optional)')),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(
                onPressed: savingStore || loadingStoreProfile ? null : _saveStoreProfile,
                child: savingStore ? const CircularProgressIndicator() : Text(storeProfileReady ? 'Update store profile' : 'Save seller store'),
              )),
              if (loadingStoreProfile) const LinearProgressIndicator(minHeight: 2),
            ]),
          )),
          const SizedBox(height: 14),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Seller agreement', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              if (loadingAgreement) const LinearProgressIndicator(minHeight: 2)
              else if (!sellerAgreementConfigured)
                const Text('The owner-approved seller agreement has not been configured. Product publishing stays disabled until Eazy provides the approved terms.')
              else ...[
                Text('Version: $sellerAgreementVersion', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(sellerAgreementText ?? ''),
                if (sellerAgreementAccepted)
                  const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_rounded), title: Text('Agreement accepted')),
                if (!sellerAgreementAccepted) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: agreedToSellerTerms,
                    onChanged: acceptingAgreement ? null : (value) => setState(() => agreedToSellerTerms = value == true),
                    title: const Text('I have read and agree to this seller agreement'),
                  ),
                  SizedBox(width: double.infinity, child: FilledButton(
                    onPressed: acceptingAgreement || !agreedToSellerTerms ? null : _acceptSellerAgreement,
                    child: Text(acceptingAgreement ? 'Saving acceptance…' : 'Accept seller agreement'),
                  )),
                ],
              ],
            ]),
          )),
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
                      Text(uploading ? 'Uploading image…' : 'Add product photo', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
            ),
          ),
          if (uploading) const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 18),
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Product name', hintText: 'What are you selling?')),
          const SizedBox(height: 12),
          TextField(controller: description, minLines: 3, maxLines: 5, maxLength: 1500, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Description', hintText: 'Describe the product, condition and details')),
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
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: Listenable.merge([name, description, price]),
            builder: (context, _) {
              final previewName = name.text.trim().isEmpty
                  ? 'Your product name'
                  : name.text.trim();
              final previewDescription = description.text.trim().isEmpty
                  ? 'Your product description will appear here.'
                  : description.text.trim();
              final previewPrice = price.text.trim().isEmpty
                  ? '₦0.00'
                  : '₦${price.text.trim()}';
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Buyer preview',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: image?.localPath != null
                                ? Image.file(
                                    File(image!.localPath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.inventory_2_outlined,
                                      color: context.eazyAccent,
                                    ),
                                  )
                                : Icon(
                                    Icons.inventory_2_outlined,
                                    color: context.eazyAccent,
                                    size: 30,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  previewName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  previewDescription,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.eazyMuted,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  previewPrice,
                                  style: TextStyle(
                                    color: context.eazyAccent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Delivery and pickup', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: deliveryEnabled,
                onChanged: publishing ? null : (value) => setState(() => deliveryEnabled = value),
                title: const Text('Offer delivery'),
                subtitle: const Text('Set the fee buyers will see at checkout.'),
              ),
              if (deliveryEnabled) TextField(
                controller: deliveryFee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Delivery fee', prefixText: '₦ '),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: pickupEnabled,
                onChanged: publishing ? null : (value) => setState(() => pickupEnabled = value),
                title: const Text('Allow pickup'),
              ),
              if (pickupEnabled) TextField(
                controller: pickupInstructions,
                maxLength: 500,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Pickup instructions (optional)'),
              ),
            ]),
          )),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 22),
          SizedBox(height: 54, child: FilledButton(
            onPressed: publishing || uploading || loadingDeliverySettings || loadingStoreProfile || loadingAgreement || !storeProfileReady || !sellerAgreementAccepted ? null : _publish,
            child: publishing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Publish product'),
          )),
          const SizedBox(height: 8),
          Text('Your listing is subject to Eazy marketplace rules. You can update inventory and product details later.', textAlign: TextAlign.center, style: TextStyle(color: context.eazyMuted, fontSize: 12)),
        ],
      ),
    ),
  );
}
