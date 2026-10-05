import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../home/home_shell.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.auth});
  final AuthController auth;
  @override State<SocialPage> createState()=>_SocialPageState();
}
class _SocialPageState extends State<SocialPage>{
  final api=ApiClient(); bool loading=true; String? error; List<Map<String,dynamic>> posts=[];
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{final j=await api.get('feed?limit=20&mode=for_you',auth:true);final raw=j['items']??j['posts']??const[];posts=(raw as List<dynamic>).map((e)=>Map<String,dynamic>.from(e as Map)).toList();}
    on ApiException catch(e){error=e.message;}finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> compose()async{
    final c=TextEditingController();
    final body=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Create a post'),content:TextField(controller:c,autofocus:true,maxLines:6,maxLength:5000,decoration:const InputDecoration(hintText:'What do you want to share?')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Post'))]));
    if(body==null||body.isEmpty)return;
    try{await api.post('posts',auth:true,body:{'body':body,'visibility':'PUBLIC'});await load();}on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}}
  @override Widget build(BuildContext context)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:CustomScrollView(slivers:[
    SliverToBoxAdapter(child:EazyPageHeader(title:'Home',subtitle:widget.auth.profile?['displayName']?.toString()??'Welcome to Eazy',trailing:IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded)))),
    SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,4,20,14),child:Card(child:ListTile(onTap:compose,leading:const CircleAvatar(child:Icon(Icons.person_rounded)),title:const Text('What’s happening?'),subtitle:const Text('Share something with your world',style:TextStyle(color:EazyColors.muted)),trailing:const Icon(Icons.add_circle_outline,color:EazyColors.green))))),
    if(loading)const SliverFillRemaining(hasScrollBody:false,child:Center(child:CircularProgressIndicator())),
    if(!loading&&error!=null)SliverFillRemaining(hasScrollBody:false,child:_State(message:error!,action:load)),
    if(!loading&&error==null&&posts.isEmpty)const SliverFillRemaining(hasScrollBody:false,child:_State(message:'Your feed is quiet. Follow people and share something to get the conversation moving.')),
    if(!loading&&posts.isNotEmpty)SliverList.builder(itemCount:posts.length,itemBuilder:(c,i)=>_Post(post:posts[i],api:api,onChanged:load))
  ])));
}
class _Post extends StatefulWidget{
  const _Post({required this.post,required this.api,required this.onChanged});
  final Map<String,dynamic> post; final ApiClient api; final Future<void> Function() onChanged;
  @override State<_Post> createState()=>_PostState();
}
class _PostState extends State<_Post>{
  bool busy=false;
  Future<void> call(String method,String path,{Map<String,dynamic>? body})async{
    if(busy)return;setState(()=>busy=true);
    try{if(method=='POST'){await widget.api.post(path,auth:true,body:body);}else{await widget.api.delete(path,auth:true);}}
    on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    finally{if(mounted){setState(()=>busy=false);await widget.onChanged();}}
  }
  @override Widget build(BuildContext context){
    final a=widget.post['author'] is Map?Map<String,dynamic>.from(widget.post['author'] as Map):const<String,dynamic>{};
    final liked=widget.post['liked']==true||widget.post['isLiked']==true;
    final saved=widget.post['saved']==true||widget.post['isSaved']==true;
    final id=widget.post['id']?.toString()??'';
    return Padding(padding:const EdgeInsets.fromLTRB(20,0,20,12),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const CircleAvatar(child:Icon(Icons.person_rounded)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a['displayName']?.toString()??'Eazy user',style:const TextStyle(fontWeight:FontWeight.w800)),Text(a['username']?.toString().isNotEmpty==true?'@'+a['username'].toString():'Eazy',style:const TextStyle(color:EazyColors.muted,fontSize:12))])),const Icon(Icons.more_horiz_rounded,color:EazyColors.muted)]),
      const SizedBox(height:14),Text(widget.post['body']?.toString()??'',style:const TextStyle(fontSize:15,height:1.45)),const SizedBox(height:8),
      Row(children:[
        TextButton.icon(onPressed:busy?null:()=>call(liked?'DELETE':'POST','engagement/posts/$id/like'),icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:liked?EazyColors.red:null),label:Text((widget.post['likeCount']??0).toString())),
        TextButton.icon(onPressed:()=>_comment(context),icon:const Icon(Icons.chat_bubble_outline_rounded),label:Text((widget.post['commentCount']??0).toString())),
        const Spacer(),IconButton(onPressed:busy?null:()=>call(saved?'DELETE':'POST','engagement/posts/$id/save'),icon:Icon(saved?Icons.bookmark:Icons.bookmark_border))
      ])
    ]))));
  }
  Future<void> _comment(BuildContext context)async{
    final c=TextEditingController();
    final text=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Comment'),content:TextField(controller:c,maxLines:4,decoration:const InputDecoration(hintText:'Write a comment')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Comment'))]));
    if(text!=null&&text.isNotEmpty)await call('POST','engagement/posts/'+widget.post['id'].toString()+'/comments',body:{'content':text});
  }
}
class _State extends StatelessWidget{
  const _State({required this.message,this.action}); final String message; final VoidCallback? action;
  @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.dynamic_feed_outlined,size:44,color:EazyColors.green),const SizedBox(height:14),Text(message,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted,height:1.45)),if(action!=null)...[const SizedBox(height:16),OutlinedButton(onPressed:action,child:const Text('Try again'))]])));
}
