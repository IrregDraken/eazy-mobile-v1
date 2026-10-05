import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class CartPage extends StatefulWidget{const CartPage({super.key});@override State<CartPage> createState()=>_CartPageState();}
class _CartPageState extends State<CartPage>{
 final api=ApiClient();bool loading=true,busy=false;String? error;Map<String,dynamic> cart={};
 @override void initState(){super.initState();load();}
 Future<void> load()async{setState(()=>loading=true);try{cart=await api.get('cart',auth:true);}on ApiException catch(e){if(mounted)setState(()=>error=e.message);}finally{if(mounted)setState(()=>loading=false);}}
 Future<void> remove(String productId)async{setState(()=>busy=true);try{await api.delete('cart/items/$productId',auth:true);await load();}on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> updateQty(String productId,int quantity)async{setState(()=>busy=true);try{await api.patch('cart/items/$productId',auth:true,body:{'quantity':quantity});await load();}on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> checkout()async{
  setState(()=>busy=true);
  try{
   final order=await api.post('orders',auth:true,headers:{'Idempotency-Key':'order-${DateTime.now().microsecondsSinceEpoch}'});
   final record=order['order'] is Map?Map<String,dynamic>.from(order['order'] as Map):const<String,dynamic>{};
   final id=record['id']?.toString();
   if(id==null)throw const ApiException('We could not create your order.');
   final payment=await api.post('payments/initialize',auth:true,headers:{'Idempotency-Key':'payment-${DateTime.now().microsecondsSinceEpoch}'},body:{'purpose':'order_purchase','orderId':id});
   final checkoutUrl=payment['payment'] is Map?(payment['payment'] as Map)['authorizationUrl']?.toString():null;
   if(checkoutUrl!=null&&checkoutUrl.isNotEmpty){await launchUrl(Uri.parse(checkoutUrl),mode:LaunchMode.externalApplication);}
   else if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Order created. Payment provider is not currently available.')));
  }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final items=(cart['items'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  final subtotal=cart['subtotal']?.toString()??'0.00';final currency=cart['currency']?.toString()??'NGN';
  return Scaffold(appBar:AppBar(title:const Text('Your bag')),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(error!,textAlign:TextAlign.center))):items.isEmpty?const Center(child:Text('Your bag is empty.',style:TextStyle(color:EazyColors.muted))):Column(children:[
   Expanded(child:ListView.separated(padding:const EdgeInsets.fromLTRB(20,20,20,10),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(c,i){final x=items[i];final productName=x['name']?.toString()??'Product';final seller=x['seller'] is Map?(x['seller'] as Map)['displayName']?.toString()??'Seller':'Seller';final qty=(x['quantity'] as num?)?.toInt()??1;return Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
    Container(width:72,height:72,decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(16)),child:const Icon(Icons.shopping_bag_outlined,color:EazyColors.green)),
    const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(productName,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(seller,style:const TextStyle(color:EazyColors.muted,fontSize:12)),const SizedBox(height:7),Text('$currency ${x['unitPrice']??'0.00'}',style:const TextStyle(color:EazyColors.green,fontWeight:FontWeight.w800))])),
    Column(children:[IconButton(onPressed:busy?null:()=>remove(x['productId'].toString()),icon:const Icon(Icons.delete_outline,color:EazyColors.red)),Row(mainAxisSize:MainAxisSize.min,children:[IconButton(onPressed:busy||qty<=1?null:()=>updateQty(x['productId'].toString(),qty-1),icon:const Icon(Icons.remove_circle_outline,size:20)),Text('$qty',style:const TextStyle(fontWeight:FontWeight.w800)),IconButton(onPressed:busy?null:()=>updateQty(x['productId'].toString(),qty+1),icon:const Icon(Icons.add_circle_outline,size:20))])])
   ])));})),
   Container(padding:const EdgeInsets.fromLTRB(20,16,20,24),decoration:const BoxDecoration(border:Border(top:BorderSide(color:EazyColors.border))),child:Column(children:[
    Row(children:[const Text('Subtotal',style:TextStyle(fontWeight:FontWeight.w800)),const Spacer(),Text('$currency $subtotal',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18))]),
    const SizedBox(height:14),SizedBox(width:double.infinity,height:54,child:FilledButton(onPressed:busy?null:checkout,child:busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):const Text('Checkout'))),
   ])),
  ]);
 }
}
