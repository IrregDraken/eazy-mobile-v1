import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_detail_page.dart';

class MarketplacePage extends StatefulWidget{const MarketplacePage({super.key});@override State<MarketplacePage> createState()=>_MarketplacePageState();}
class _MarketplacePageState extends State<MarketplacePage>{
 final api=ApiClient();final search=TextEditingController();
 bool loading=true;String? error;String? categoryId;String sort='newest';
 List<Map<String,dynamic>> products=[];List<Map<String,dynamic>> categories=[];
 @override void initState(){super.initState();load();}
 @override void dispose(){search.dispose();super.dispose();}
 Future<void> load()async{
  setState((){loading=true;error=null;});
  try{
   final params=<String,String>{'status':'active','limit':'30','page':'1','sort':sort};
   if(categoryId!=null)params['categoryId']=categoryId!;
   if(search.text.trim().length>=2)params['q']=search.text.trim();
   final qs=params.entries.map((e)=>'${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
   final r=await Future.wait([api.get('marketplace/products?$qs'),api.get('marketplace/categories?page=1&limit=50')]);
   products=(r[0]['items'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
   categories=(r[1]['items'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>loading=false);}
 }
 @override Widget build(BuildContext context)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:CustomScrollView(slivers:[
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,20,20,10),child:Row(children:[
   const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Marketplace',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),SizedBox(height:3),Text('Discover things worth having',style:TextStyle(color:EazyColors.muted))])),
   IconButton(onPressed:()=>context.push('/cart'),icon:const Icon(Icons.shopping_bag_outlined)),
  ]))),
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,4,20,12),child:TextField(controller:search,onSubmitted:(_)=>load(),decoration:InputDecoration(prefixIcon:const Icon(Icons.search_rounded),hintText:'Search products',suffixIcon:IconButton(onPressed:load,icon:const Icon(Icons.search_rounded)))))),
  if(categories.isNotEmpty)SliverToBoxAdapter(child:SizedBox(height:48,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:20),itemCount:categories.length+1,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(c,i){
   if(i==0)return ChoiceChip(label:const Text('All'),selected:categoryId==null,onSelected:(_){setState(()=>categoryId=null);load();});
   final x=categories[i-1],id=x['id']?.toString();return ChoiceChip(label:Text(x['name']?.toString()??'Category'),selected:categoryId==id,onSelected:(_){setState(()=>categoryId=id);load();});
  }))),
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,10,20,10),child(Row(children:[
   const Text('Latest',style:TextStyle(fontWeight:FontWeight.w800)),const Spacer(),
   PopupMenuButton<String>(initialValue:sort,onSelected:(v){setState(()=>sort=v);load();},itemBuilder:(_)=>const[
    PopupMenuItem(value:'newest',child:Text('Newest')),PopupMenuItem(value:'price_asc',child:Text('Price: low to high')),PopupMenuItem(value:'price_desc',child:Text('Price: high to low')),
   ]),
  ]))),
  if(loading)const SliverFillRemaining(hasScrollBody:false,child:Center(child:CircularProgressIndicator())),
  if(!loading&&error!=null)SliverFillRemaining(hasScrollBody:false,child:_State(error!,load)),
  if(!loading&&error==null&&products.isEmpty)const SliverFillRemaining(hasScrollBody:false,child:_State('No products match your search.',null)),
  if(!loading&&products.isNotEmpty)SliverPadding(padding:const EdgeInsets.fromLTRB(20,0,20,28),sliver:SliverGrid.builder(
   gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.68),
   itemCount:products.length,itemBuilder:(c,i)=>_Product(product:products[i]))),
 ])));
}
class _Product extends StatelessWidget{
 const _Product({required this.product});final Map<String,dynamic> product;
 @override Widget build(BuildContext context){
  final media=product['media'] is List?(product['media'] as List):const[];
  final first=media.isNotEmpty&&media.first is Map?Map<String,dynamic>.from(media.first as Map):const<String,dynamic>{};
  final url=first['url']?.toString();final price=product['priceAmount']?.toString()??'0.00';
  return Card(child:InkWell(onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ProductDetailPage(product:product))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Expanded(child:ClipRRect(borderRadius:const BorderRadius.vertical(top:Radius.circular(EazyRadius.lg)),child:url!=null?Image.network(url,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const _ProductPlaceholder()):const _ProductPlaceholder())),
   Padding(padding:const EdgeInsets.fromLTRB(12,10,12,12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(product['name']?.toString()??'Product',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800)),
    const SizedBox(height:5),Text('${product['currency']??'NGN'} $price',style:const TextStyle(color:EazyColors.green,fontWeight:FontWeight.w900)),
   ])),
  ])));
 }
}
class _ProductPlaceholder extends StatelessWidget{const _ProductPlaceholder();@override Widget build(BuildContext context)=>Container(color:EazyColors.surfaceRaised,child:const Center(child:Icon(Icons.shopping_bag_outlined,size:42,color:EazyColors.green)));}
class _State extends StatelessWidget{const _State(this.text,this.action);final String text;final VoidCallback? action;@override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.storefront_outlined,size:44,color:EazyColors.green),const SizedBox(height:12),Text(text,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted)),if(action!=null)...[const SizedBox(height:12),OutlinedButton(onPressed:action,child:const Text('Try again'))]])));}
