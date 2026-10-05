import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class CartPage extends StatefulWidget{const CartPage({super.key});@override State<CartPage> createState()=>_CartPageState();}
class _CartPageState extends State<CartPage>{final api=ApiClient();bool loading=true,busy=false;String? error;List<Map<String,dynamic>> items=[];num total=0;
 @override void initState(){super.initState();load();}
 Future<void> load()async{setState(()=>loading=true);try{final j=await api.get('cart',auth:true);final raw=j['items']??j['cart']??const[];items=(raw as List<dynamic>).map((e)=>Map<String,dynamic>.from(e as Map)).toList();total=(j['total']??j['subtotal']??0) as num;error=null;}on ApiException catch(e){error=e.message;}finally{if(mounted)setState(()=>loading=false);}}
 Future<void> remove(String id)async{setState(()=>busy=true);try{await api.delete('cart/items/'+id,auth:true);await load();}on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Your cart')),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!,style:const TextStyle(color:EazyColors.muted))):items.isEmpty?const Center(child:Text('Your cart is empty.',style:TextStyle(color:EazyColors.muted))):Column(children:[
 Expanded(child:ListView.separated(padding:const EdgeInsets.all(20),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(c,i){final x=items[i];return Card(child:ListTile(title:Text(x['product'] is Map?(x['product']['name']?.toString()??'Product'):'Product',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Quantity: '+(x['quantity']??1).toString(),style:const TextStyle(color:EazyColors.muted)),trailing:IconButton(onPressed:busy?null:()=>remove(x['productId']?.toString()??x['id'].toString()),icon:const Icon(Icons.delete_outline,color:EazyColors.red)));})),
 Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(border:Border(top:BorderSide(color:EazyColors.border))),child:Row(children:[const Text('Subtotal',style:TextStyle(fontWeight:FontWeight.w800)),const Spacer(),Text('₦'+total.toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18))]))
 ]);}
