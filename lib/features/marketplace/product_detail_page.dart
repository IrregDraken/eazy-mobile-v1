import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class ProductDetailPage extends StatefulWidget{const ProductDetailPage({super.key,required this.product});final Map<String,dynamic> product;@override State<ProductDetailPage> createState()=>_ProductDetailPageState();}
class _ProductDetailPageState extends State<ProductDetailPage>{
 final api=ApiClient();int quantity=1;bool busy=false;
 Future<void> add()async{
  setState(()=>busy=true);
  try{
   await api.post('cart/items',auth:true,body:{'productId':widget.product['id'],'quantity':quantity});
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Added to your bag.')));
  }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final p=widget.product;final media=p['media'] is List?(p['media'] as List):const[];
  final images=media.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((e)=>e['url']!=null).toList();
  final price=p['priceAmount']?.toString()??'0.00';
  return Scaffold(appBar:AppBar(title:const Text('Product')),body:ListView(padding:const EdgeInsets.fromLTRB(20,8,20,30),children:[
   SizedBox(height:300,child:images.isEmpty?const _Placeholder():PageView.builder(itemCount:images.length,itemBuilder:(c,i)=>ClipRRect(borderRadius:BorderRadius.circular(24),child:Image.network(images[i]['url'].toString(),fit:BoxFit.cover,errorBuilder:(_,__,___)=>const _Placeholder())))),
   const SizedBox(height:20),
   Text(p['name']?.toString()??'Product',style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900,letterSpacing:-.7)),
   const SizedBox(height:8),Text('${p['currency']??'NGN'} $price',style:const TextStyle(fontSize:22,color:EazyColors.green,fontWeight:FontWeight.w900)),
   const SizedBox(height:16),Text(p['description']?.toString()??'No description provided.',style:const TextStyle(color:EazyColors.muted,height:1.55)),
   const SizedBox(height:20),
   if(p['seller'] is Map)Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person_rounded)),title:Text((p['seller'] as Map)['displayName']?.toString()??'Seller',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('@${(p['seller'] as Map)['username']??''}',style:const TextStyle(color:EazyColors.muted)))),
   const SizedBox(height:12),
   Row(children:[const Text('Quantity',style:TextStyle(fontWeight:FontWeight.w800)),const Spacer(),IconButton(onPressed:quantity>1?()=>setState(()=>quantity--):null,icon:const Icon(Icons.remove_circle_outline)),Text('$quantity',style:const TextStyle(fontWeight:FontWeight.w900)),IconButton(onPressed:()=>setState(()=>quantity++),icon:const Icon(Icons.add_circle_outline))]),
   const SizedBox(height:12),SizedBox(height:56,child:FilledButton(onPressed:busy?null:add,child:busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):const Text('Add to bag'))),
 ]));
 }
}
class _Placeholder extends StatelessWidget{const _Placeholder();@override Widget build(BuildContext context)=>Container(decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(24)),child:const Center(child:Icon(Icons.shopping_bag_outlined,size:72,color:EazyColors.green)));}
