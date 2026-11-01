import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final api = ApiClient();
  final random = Random.secure();
  bool loading = true;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> addresses = [];
  final Map<String, Map<String, dynamic>> sellerSettings = {};
  final Map<String, String> methods = {};
  final Map<String, String?> selectedAddresses = {};
  String? orderId;
  String? paymentId;
  String? paymentError;
  String? checkoutUrl;
  String? orderIdempotencyKey;
  String? paymentIdempotencyKey;

  String newIdempotencyKey() {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        api.get('cart', auth: true),
        api.get('orders/addresses', auth: true),
      ]);
      final cart = results[0];
      final cartItems = (cart['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final savedAddresses = (results[1]['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final sellerIds = cartItems
          .map((item) => (item['seller'] as Map?)?['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final settings = <String, Map<String, dynamic>>{};
      for (final sellerId in sellerIds) {
        final response = await api.get('marketplace/sellers/$sellerId/delivery-settings');
        settings[sellerId] = Map<String, dynamic>.from(response['settings'] as Map? ?? const {});
      }
      if (!mounted) return;
      setState(() {
        items = cartItems;
        addresses = savedAddresses;
        sellerSettings
          ..clear()
          ..addAll(settings);
        methods.clear();
        selectedAddresses.clear();
        for (final sellerId in sellerIds) {
          final config = settings[sellerId] ?? {};
          final delivery = config['deliveryEnabled'] == true;
          final pickup = config['pickupEnabled'] == true;
          methods[sellerId] = pickup ? 'pickup' : (delivery ? 'delivery' : '');
          Map<String, dynamic>? defaultAddress;
          for (final address in savedAddresses) {
            if (address['isDefault'] == true) { defaultAddress = address; break; }
          }
          selectedAddresses[sellerId] = defaultAddress?['id']?.toString();
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<String> get sellerIds => items
      .map((item) => (item['seller'] as Map?)?['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  String money(Object? value) => '₦${value?.toString() ?? '0.00'}';

  Future<void> addAddress() async {
    final fields = List.generate(8, (_) => TextEditingController());
    const labels = ['Label (Home, Work)', 'Recipient full name', 'Phone number', 'State', 'City', 'Area', 'Street address', 'Landmark (optional)'];
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add delivery address'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(fields.length, (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: fields[index],
                    decoration: InputDecoration(labelText: labels[index]),
                    validator: (value) {
                      if (index == 7) return null;
                      if ((value ?? '').trim().length < (index == 0 ? 1 : 2)) return 'Enter ${labels[index].toLowerCase()}';
                      return null;
                    },
                  ),
                )),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (formKey.currentState?.validate() == true) Navigator.pop(dialogContext, true);
          }, child: const Text('Save address')),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() => busy = true);
      try {
        final result = await api.post('orders/addresses', auth: true, body: {
          'label': fields[0].text.trim(),
          'recipientName': fields[1].text.trim(),
          'phone': fields[2].text.trim(),
          'state': fields[3].text.trim(),
          'city': fields[4].text.trim(),
          'area': fields[5].text.trim(),
          'addressLine': fields[6].text.trim(),
          'landmark': fields[7].text.trim().isEmpty ? null : fields[7].text.trim(),
          'isDefault': addresses.isEmpty,
        });
        final address = Map<String, dynamic>.from(result['address'] as Map);
        setState(() {
          addresses.add(address);
          for (final sellerId in sellerIds) {
            if (methods[sellerId] == 'delivery') selectedAddresses[sellerId] = address['id'].toString();
          }
        });
      } on ApiException catch (e) {
        if (mounted) setState(() => error = e.message);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    for (final field in fields) { field.dispose(); }
  }

  Future<void> placeOrder() async {
    if (items.isEmpty && orderId == null) return;
    if (orderId == null) {
      for (final sellerId in sellerIds) {
        final method = methods[sellerId] ?? '';
        if (method != 'delivery' && method != 'pickup') {
          setState(() => error = 'Choose delivery or pickup for every seller.');
          return;
        }
        if (method == 'delivery' && (selectedAddresses[sellerId] == null || selectedAddresses[sellerId]!.isEmpty)) {
          setState(() => error = 'Add and select a delivery address for each delivery order.');
          return;
        }
      }
    }
    setState(() { busy = true; error = null; paymentError = null; });
    try {
      String currentOrderId;
      if (orderId == null) {
        orderIdempotencyKey ??= newIdempotencyKey();
        final result = await api.post(
          'orders',
          auth: true,
          headers: {'Idempotency-Key': orderIdempotencyKey!},
          body: {
            'fulfillments': sellerIds.map((sellerId) => {
              'sellerId': sellerId,
              'method': methods[sellerId],
              if (methods[sellerId] == 'delivery') 'addressId': selectedAddresses[sellerId],
            }).toList(),
          },
        );
        final order = Map<String, dynamic>.from(result['order'] as Map);
        currentOrderId = order['id'].toString();
        if (mounted) setState(() => orderId = currentOrderId);
      } else {
        currentOrderId = orderId!;
      }

      if (paymentId == null || checkoutUrl == null) {
        paymentIdempotencyKey ??= newIdempotencyKey();
        final payment = await api.post(
          'payments/initialize',
          auth: true,
          headers: {'Idempotency-Key': paymentIdempotencyKey!},
          body: {'purpose': 'order_purchase', 'orderId': currentOrderId},
        );
        final transaction = Map<String, dynamic>.from(payment['transaction'] as Map);
        final paymentDetails = Map<String, dynamic>.from(payment['payment'] as Map);
        final url = paymentDetails['authorizationUrl']?.toString() ?? '';
        if (url.isEmpty) throw const ApiException('The payment provider did not return a checkout link.');
        if (mounted) setState(() {
          paymentId = transaction['id']?.toString();
          checkoutUrl = url;
        });
      }
      await openCheckout();
    } on ApiException catch (e) {
      if (mounted) setState(() => paymentError = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openCheckout() async {
    final url = checkoutUrl;
    if (url == null || url.isEmpty) {
      setState(() => paymentError = 'Payment checkout has not been initialized yet.');
      return;
    }
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) setState(() => paymentError = 'Could not open Paystack checkout. Try opening it again.');
  }

  Future<void> verifyPayment() async {
    final id = paymentId;
    if (id == null) return;
    setState(() { busy = true; paymentError = null; });
    try {
      final result = await api.post('payments/$id/verify', auth: true);
      final transaction = Map<String, dynamic>.from(result['transaction'] as Map? ?? const {});
      if (transaction['status'] == 'succeeded') {
        if (mounted) context.go('/orders/$orderId');
      } else if (mounted) {
        setState(() => paymentError = 'Payment has not been confirmed yet. Wait a moment and check again.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => paymentError = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final sellerId = (item['seller'] as Map?)?['id']?.toString() ?? '';
      if (sellerId.isNotEmpty) groups.putIfAbsent(sellerId, () => []).add(item);
    }
    final subtotal = items.fold<double>(0, (sum, item) {
      final price = double.tryParse(item['unitPrice']?.toString() ?? '') ?? 0;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      return sum + price * quantity;
    });
    final deliveryTotal = sellerIds.fold<double>(0, (sum, sellerId) {
      if (methods[sellerId] != 'delivery') return sum;
      return sum + (double.tryParse(sellerSettings[sellerId]?['deliveryFeeAmount']?.toString() ?? '') ?? 0);
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ]),
                ))
              : orderId != null
                  ? ListView(padding: const EdgeInsets.all(20), children: [
                      const Icon(Icons.lock_clock_rounded, size: 48),
                      const SizedBox(height: 12),
                      const Text('Order created. Payment is pending.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text('Order reference: $orderId', textAlign: TextAlign.center),
                      if (paymentError != null) Text(paymentError!, textAlign: TextAlign.center),
                      if (checkoutUrl != null)
                        FilledButton(onPressed: busy ? null : openCheckout, child: const Text('Open Paystack checkout')),
                      if (paymentId == null)
                        FilledButton(onPressed: busy ? null : placeOrder, child: const Text('Retry payment setup')),
                      if (paymentId != null)
                        OutlinedButton(onPressed: busy ? null : verifyPayment, child: Text(busy ? 'Checking…' : 'I have paid. Verify payment')),
                      TextButton(onPressed: () => context.go('/orders/$orderId'), child: const Text('View order')),
                    ])
                  : items.isEmpty
                      ? const Center(child: Text('Your bag is empty.'))
                      : ListView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
                          children: [
                            const Text('Delivery method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            for (final sellerId in sellerIds) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text((groups[sellerId]?.first['seller'] as Map?)?['displayName']?.toString() ?? 'Seller', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    for (final item in groups[sellerId] ?? [])
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text('${item['name']} × ${item['quantity']}'),
                                      ),
                                    const SizedBox(height: 10),
                                    if (sellerSettings[sellerId]?['pickupEnabled'] == true)
                                      RadioListTile<String>(
                                        contentPadding: EdgeInsets.zero,
                                        value: 'pickup',
                                        groupValue: methods[sellerId],
                                        onChanged: busy ? null : (value) => setState(() => methods[sellerId] = value!),
                                        title: const Text('Pickup'),
                                      ),
                                    if (sellerSettings[sellerId]?['deliveryEnabled'] == true)
                                      RadioListTile<String>(
                                        contentPadding: EdgeInsets.zero,
                                        value: 'delivery',
                                        groupValue: methods[sellerId],
                                        onChanged: busy ? null : (value) => setState(() => methods[sellerId] = value!),
                                        title: Text('Delivery · ${money(sellerSettings[sellerId]?['deliveryFeeAmount'])}'),
                                      ),
                                    if (methods[sellerId] == 'delivery') ...[
                                      DropdownButtonFormField<String>(
                                        value: selectedAddresses[sellerId],
                                        decoration: const InputDecoration(labelText: 'Delivery address'),
                                        items: addresses.map((address) => DropdownMenuItem(
                                          value: address['id'].toString(),
                                          child: Text('${address['label']} · ${address['city']}', overflow: TextOverflow.ellipsis),
                                        )).toList(),
                                        onChanged: (value) => setState(() => selectedAddresses[sellerId] = value),
                                      ),
                                      TextButton.icon(onPressed: busy ? null : addAddress, icon: const Icon(Icons.add), label: const Text('Add address')),
                                    ],
                                  ]),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(onPressed: busy ? null : addAddress, icon: const Icon(Icons.location_on_outlined), label: const Text('Manage delivery addresses')),
                            const Divider(height: 28),
                            _total('Items subtotal', money(subtotal)),
                            _total('Delivery', money(deliveryTotal)),
                            _total('Total', money(subtotal + deliveryTotal), strong: true),
                            const SizedBox(height: 12),
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.verified_user_outlined),
                              title: Text('Protected by Eazy'),
                              subtitle: Text('Payment is held until you confirm that your order arrived.'),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: busy ? null : placeOrder,
                              child: busy ? const CircularProgressIndicator() : const Text('Continue to Paystack'),
                            ),
                          ],
                        ),
    );
  }

  Widget _total(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w500)),
      const Spacer(),
      Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: strong ? 18 : 14)),
    ]),
  );
}
