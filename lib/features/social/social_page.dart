import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.auth});
  final AuthController auth;
  @override State<SocialPage> createState()=>_SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  final api=ApiClient();
  final composer=TextEditingController();
  late final EazyMediaService media;
  bool loading=true, posting=false;
  String? error;
  String mode='for_you';
  List<Map<String,dynamic>> posts=[];

  @override void initState(){super.initState();media=EazyMediaService(api);load();}
  @override void dispose(){composer.dispose();super.dispose();}

  Future<void> load() async {
    setState((){loading=true;error=null;});
    try {
      final result=await api.get('home/feed?page=1&limit=20&mode=$mode',auth:true);
      final raw=result['items'] as List? ?? const [];
      posts=raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    } on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> compose() async {
    composer.clear();
    MediaUpload? attachment;
    final body=await showModalBottomSheet<String>(
      context:context,isScrollControlled:true,showDragHandle:true,
      builder:(ctx)=>Padding(
        padding:EdgeInsets.fromLTRB(20,8,20,MediaQuery.of(ctx).viewInsets.bottom+20),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Create a post',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
          const SizedBox(height:14),
          TextField(controller:composer,maxLines:6,maxLength:5000,autofocus:true,decoration:const InputDecoration(hintText:'Share something with your world')),
          const SizedBox(height:8),
          StatefulBuilder(builder:(ctx,setSheetState)=>Row(children:[
            OutlinedButton.icon(onPressed:()=>media.pickAndUpload(kind:'post').then((value){attachment=value;setSheetState((){});}),icon:const Icon(Icons.photo_outlined),label:Text(attachment==null?'Add photo':'Photo attached')),
            if(attachment!=null)const Padding(padding:EdgeInsets.only(left:10),child:Icon(Icons.check_circle,color:EazyColors.green)),
          ])),
          const SizedBox(height:8),
          SizedBox(width:double.infinity,height:54,child:FilledButton(onPressed:()=>Navigator.pop(ctx,composer.text.trim()),child:const Text('Publish'))),
        ]))));
    );
    if(body==null||body.isEmpty)return;
    setState(()=>posting=true);
    try{
      await api.post('posts',auth:true,body:{'content':body,'visibility':'public','media':[
        if(attachment!=null){'storageKey':attachment!.path,'mediaType':'image','position':0}
      ]});
      await load();
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    finally{if(mounted)setState(()=>posting=false);}
  }

  @override Widget build(BuildContext context)=>SafeArea(
    child:RefreshIndicator(
      onRefresh:load,
      child:CustomScrollView(slivers:[
        SliverToBoxAdapter(child:Padding(
          padding:const EdgeInsets.fromLTRB(20,20,20,10),
          child:Row(children:[
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Home',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900,letterSpacing:-1)),
              const SizedBox(height:3),
              Text('Welcome back, ${widget.auth.profile?['firstName']??'there'}',style:const TextStyle(color:EazyColors.muted)),
            ])),
            IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded)),
            IconButton(onPressed:posting?null:compose,icon:const Icon(Icons.add_circle_rounded,color:EazyColors.green)),
          ]))),
        SliverToBoxAdapter(child:SizedBox(height:44,child:ListView(
          scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:20),
          children:['for_you','following','trending'].map((value)=>Padding(
            padding:const EdgeInsets.only(right:8),
            child:ChoiceChip(label:Text(value=='for_you'?'For you':value[0].toUpperCase()+value.substring(1)),selected:mode==value,onSelected:(_){if(mode==value)return;setState(()=>mode=value);load();}),
          )).toList(),
        ))),
        const SliverToBoxAdapter(child:SizedBox(height:10)),
        if(loading)const SliverFillRemaining(hasScrollBody:false,child:Center(child:CircularProgressIndicator())),
        if(!loading&&error!=null)SliverFillRemaining(hasScrollBody:false,child:_State(error!,load)),
        if(!loading&&error==null&&posts.isEmpty)SliverFillRemaining(hasScrollBody:false,child:_State('Nothing here yet. Follow people or publish the first post.',compose)),
        if(!loading&&posts.isNotEmpty)SliverList.builder(itemCount:posts.length,itemBuilder:(c,i)=>_Post(post:posts[i],api:api,onChanged:load)),
      ]),
    ),
  );
}

class _Post extends StatefulWidget{
  const _Post({required this.post,required this.api,required this.onChanged});
  final Map<String,dynamic> post;final ApiClient api;final Future<void> Function() onChanged;
  @override State<_Post> createState()=>_PostState();
}
class _PostState extends State<_Post>{
  bool busy=false;
  Future<void> mutate(String action,String path,{Map<String,dynamic>? body}) async{
    if(busy)return;setState(()=>busy=true);
    try{
      if(action=='post'){await widget.api.post(path,auth:true,body:body);}
      else{await widget.api.delete(path,auth:true);}
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    finally{if(mounted){setState(()=>busy=false);await widget.onChanged();}}
  }
  Future<void> comment() async{
    final c=TextEditingController();
    final text=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Comment'),content:TextField(controller:c,maxLines:4,maxLength:2000,decoration:const InputDecoration(hintText:'Write a comment')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Comment'))]));
    c.dispose();
    if(text==null||text.isEmpty)return;
    await mutate('post','engagement/posts/${widget.post['id']}/comments',body:{'content':text});
  }
  @override Widget build(BuildContext context){
    final author=widget.post['author'] is Map?Map<String,dynamic>.from(widget.post['author'] as Map):const<String,dynamic>{};
    final liked=widget.post['likedByViewer']==true;
    final saved=widget.post['savedByViewer']==true;
    final id=widget.post['id']?.toString()??'';
    final media=widget.post['media'] is List?widget.post['media'] as List:const[];
    return Padding(padding:const EdgeInsets.fromLTRB(20,0,20,12),child:Card(
      child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          CircleAvatar(backgroundImage:(author['avatarUrl']?.toString().startsWith('http')==true)?NetworkImage(author['avatarUrl']):null,child:const Icon(Icons.person_rounded)),
          const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(author['displayName']?.toString()??'Eazy user',style:const TextStyle(fontWeight:FontWeight.w800)),
            Text(author['username']?.toString().isNotEmpty==true?'@${author['username']}':'Eazy',style:const TextStyle(color:EazyColors.muted,fontSize:12)),
          ])),const Icon(Icons.more_horiz_rounded,color:EazyColors.muted),
        ]),
        const SizedBox(height:14),
        Text(widget.post['content']?.toString()??'',style:const TextStyle(height:1.45,fontSize:15)),
        if(media.isNotEmpty) ...[const SizedBox(height:14),SizedBox(height:220,child:PageView.builder(itemCount:media.length,itemBuilder:(c,i){final m=media[i] is Map?Map<String,dynamic>.from(media[i] as Map):{};final url=m['url']?.toString();return ClipRRect(borderRadius:BorderRadius.circular(18),child:url!=null?Image.network(url,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:EazyColors.surfaceRaised,child:Center(child:Icon(Icons.broken_image_outlined)))):const ColoredBox(color:EazyColors.surfaceRaised,child:Center(child:Icon(Icons.image_outlined))));}))],
        const SizedBox(height:8),
        Row(children:[
          TextButton.icon(onPressed:busy?null:()=>mutate(liked?'delete':'post','engagement/posts/$id/like'),icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:liked?EazyColors.red:null),label:Text('${widget.post['likeCount']??0}')),
          TextButton.icon(onPressed:busy?null:comment,icon:const Icon(Icons.chat_bubble_outline_rounded),label:Text('${widget.post['commentCount']??0}')),
          const Spacer(),IconButton(onPressed:busy?null:()=>mutate(saved?'delete':'post','engagement/posts/$id/save'),icon:Icon(saved?Icons.bookmark:Icons.bookmark_border)),
        ]),
      ]))));
  }
}

class _State extends StatelessWidget{
  const _State(this.text,this.action);final String text;final VoidCallback? action;
  @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.dynamic_feed_outlined,size:44,color:EazyColors.green),const SizedBox(height:14),
    Text(text,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted,height:1.4)),
    if(action!=null)...[const SizedBox(height:16),OutlinedButton(onPressed:action,child:const Text('Try again'))],
  ])));
}
