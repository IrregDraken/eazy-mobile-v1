import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_detail_page.dart';

class ProductRoutePage extends StatefulWidget {
  const ProductRoutePage({super.key, required this.productId});
  final String productId;
  @override
  State<ProductRoutePage> createState() => _ProductRoutePageState();
}

class _ProductRoutePageState extends State<ProductRoutePage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  Map<String, dynamic>? product;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final result = await api.get('marketplace/products/${widget.productId}');
      if (mounted) setState(() => product = Map<String, dynamic>.from(result['product'] as Map));
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => loading ? const Scaffold(body: Center(child: CircularProgressIndicator())) : error != null ? Scaffold(appBar: AppBar(), body: Center(child: Text(error!))) : product == null ? const Scaffold(body: Center(child: Text('Product not found.'))) : ProductDetailPage(product: product!);
}
