import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class ProductDetailPage extends StatefulWidget{const ProductDetailPage({super.key,required this.product});final Map<String,dynamic> product;@override State<ProductDetailPage> createState()=>_ProductDetailPageState();}
class _ProductDetailPageState extends State<ProductDetailPage>{
 final api=ApiClient();int quantity=1;bool busy=false;
 Future<void> add()async{setState(()=>busy=true);try{await api.post('cart/items',auth:true,body:{'productId':widget.product['id'],'quantity':quantity});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Added to cart.')));}on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context){final p=widget.product;final raw=p['priceAmount']??p['priceMinor'];final price=raw is num?raw/((p['priceMinor']!=null)?100:1):0;return Scaffold(appBar:AppBar(title:const Text('Product')),body:ListView(padding:const EdgeInsets.all(20),children:[
 Container(height:260,decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(24)),child:const Center(child:Icon(Icons.shopping_bag_outlined,size:80,color:EazyColors.green))),
 const SizedBox(height:20),Text(p['name']?.toString()??'Product',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:8),
 Text((p['currency']?.toString()??'NGN')+' '+(price is num?price.toStringAsFixed(2):price.toString()),style:const TextStyle(fontSize:22,color:EazyColors.green,fontWeight:FontWeight.w900)),const SizedBox(height:18),
 Text(p['description']?.toString()??'No description provided.',style:const TextStyle(color:EazyColors.muted,height:1.5)),const SizedBox(height:28),
 Row(children:[const Text('Quantity',style:TextStyle(fontWeight:FontWeight.w800)),const Spacer(),IconButton(onPressed:quantity>1?()=>setState(()=>quantity--):null,icon:const Icon(Icons.remove_circle_outline)),Text(quantity.toString(),style:const TextStyle(fontWeight:FontWeight.w900)),IconButton(onPressed:()=>setState(()=>quantity++),icon:const Icon(Icons.add_circle_outline))]),
 const SizedBox(height:12),SizedBox(height:56,child:FilledButton(onPressed:busy?null:add,child:busy?const CircularProgressIndicator():const Text('Add to cart')))
 ]));}
}
