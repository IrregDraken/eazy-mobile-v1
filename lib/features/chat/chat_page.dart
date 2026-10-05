import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

const _reactions = <String>['👍','❤️','😂','😮','😢','🙏','👏','🔥'];

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final api = ApiClient();
  final search = TextEditingController();
  final username = TextEditingController();
  bool loading = true, busy = false;
  String? error;
  List<Map<String,dynamic>> conversations = [];

  @override void initState() { super.initState(); load(); }
  @override void dispose() { search.dispose(); username.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await api.get('chat/conversations?page=1&limit=50', auth:true);
      conversations = (r['items'] as List? ?? const []).whereType<Map>()
        .map((e) => Map<String,dynamic>.from(e)).toList();
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> startChat() async {
    final value = username.text.trim().replaceFirst('@','').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid Eazy username.')));
      return;
    }
    setState(() => busy = true);
    try {
      final r = await api.post('chat/conversations', auth:true, body:{'username':value});
      username.clear();
      await load();
      final c = r['conversation'];
      if (c is Map && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConversationPage(api:api, conversation:Map<String,dynamic>.from(c))));
        await load();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final filtered = conversations.where((c) {
      if (q.isEmpty) return true;
      final name = (c['displayName'] ?? c['display_name'] ?? c['username'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();

    return SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(
      padding:const EdgeInsets.fromLTRB(20,18,20,110),children:[
        Row(children:[
          const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Chat',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,letterSpacing:-1)),
            SizedBox(height:3),Text('Conversations that move with you',style:TextStyle(color:EazyColors.muted))
          ])),
          IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded))
        ]),
        const SizedBox(height:16),
        Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Start a conversation',style:TextStyle(fontWeight:FontWeight.w900)),
          const SizedBox(height:10),
          Row(children:[
            Expanded(child:TextField(controller:username,autocorrect:false,decoration:const InputDecoration(
              hintText:'@username',prefixIcon:Icon(Icons.person_search_outlined)))),
            const SizedBox(width:9),
            SizedBox(width:54,height:54,child:FilledButton(
              onPressed:busy?null:startChat,
              child:busy?const SizedBox(width:19,height:19,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.arrow_forward_rounded)))
          ])
        ]))),
        const SizedBox(height:15),
        TextField(controller:search,onChanged:(_) => setState((){}),decoration:const InputDecoration(
          prefixIcon:Icon(Icons.search_rounded),hintText:'Search conversations')),
        const SizedBox(height:18),
        const Text('Messages',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
        const SizedBox(height:9),
        if (loading) const Padding(padding:EdgeInsets.only(top:100),child:Center(child:CircularProgressIndicator()))
        else if (error != null) _ChatState(error!,load)
        else if (filtered.isEmpty) const _ChatState('No conversations yet. Start one above.')
        else ...filtered.map((c) => _ConversationTile(c,onTap:() async {
          await Navigator.of(context).push(MaterialPageRoute(builder:(_) => ConversationPage(api:api,conversation:c)));
          await load();
        }))
      ])));
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile(this.c,{required this.onTap});
  final Map<String,dynamic> c;
  final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final participants = c['participants'] is List ? c['participants'] as List : const[];
    final p = participants.isNotEmpty && participants.first is Map ? Map<String,dynamic>.from(participants.first as Map) : <String,dynamic>{};
    final name = (c['displayName'] ?? c['display_name'] ?? p['displayName'] ?? c['username'] ?? 'Eazy user').toString();
    final latest = c['latestMessage'] is Map ? Map<String,dynamic>.from(c['latestMessage'] as Map) : <String,dynamic>{};
    final unread = int.tryParse((c['unreadCount'] ?? c['unread_count'] ?? 0).toString()) ?? 0;
    return Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:InkWell(onTap:onTap,
      borderRadius:BorderRadius.circular(EazyRadius.lg),child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[
        CircleAvatar(radius:25,child:Text(name.characters.first.toUpperCase())),
        const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(name,style:const TextStyle(fontWeight:FontWeight.w900)),
          const SizedBox(height:4),Text(latest['body']?.toString() ?? 'Start a conversation',
            maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted,fontSize:12))
        ])),
        if(unread>0)Container(minWidth:25,height:25,alignment:Alignment.center,
          padding:const EdgeInsets.symmetric(horizontal:7),decoration:const BoxDecoration(color:EazyColors.green,shape:BoxShape.circle),
          child:Text(unread.toString(),style:const TextStyle(color:EazyColors.canvas,fontSize:10,fontWeight:FontWeight.w900))),
        const SizedBox(width:4),const Icon(Icons.chevron_right_rounded,color:EazyColors.muted)
      ])))));
  }
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key,required this.api,required this.conversation});
  final ApiClient api;
  final Map<String,dynamic> conversation;
  @override State<ConversationPage> createState()=>_ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final draft=TextEditingController();
  final scroll=ScrollController();
  List<Map<String,dynamic>> messages=[];
  Map<String,dynamic>? replying,editing;
  bool loading=true,sending=false;
  String? error;
  WebSocket? socket;
  StreamSubscription? subscription;

  String get id=>widget.conversation['id']?.toString() ?? '';

  @override void initState(){super.initState();loadMessages();connectRealtime();}
  @override void dispose(){subscription?.cancel();socket?.close();draft.dispose();scroll.dispose();super.dispose();}

  Future<void> loadMessages() async {
    try {
      setState(()=>loading=true);
      final r=await widget.api.get('chat/conversations/' + id + '/messages?page=1&limit=50',auth:true);
      messages=(r['items'] as List? ?? const[]).whereType<Map>()
        .map((e)=>Map<String,dynamic>.from(e)).toList().reversed.toList();
      await markRead();
      if(mounted)setState(()=>error=null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(scroll.hasClients)scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    } on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> markRead() async {
    if(messages.isEmpty)return;
    try{await widget.api.post('chat/conversations/' + id + '/read',auth:true,body:{'lastReadMessageId':messages.last['id']});}catch(_){}
  }

  Future<void> connectRealtime() async {
    try {
      final token=await widget.api.readToken();
      if(token==null||token.isEmpty)return;
      final base=Uri.parse(widget.api.baseUrl);
      final scheme=base.scheme=='https'?'wss':'ws';
      final wsUri=Uri(scheme:scheme,host:base.host,port:base.hasPort?base.port:null,path:'/v1/realtime');
      final ws=await WebSocket.connect(wsUri.toString(),headers:{'Authorization':'Bearer ' + token});
      socket=ws;
      ws.add(jsonEncode({'type':'subscribe','channel':'conversation','id':id}));
      subscription=ws.listen((raw){
        try{
          final frame=jsonDecode(raw.toString());
          if(frame is! Map || frame['type']!='event')return;
          if(frame['event']=='message.created' && frame['data'] is Map && frame['data']['message'] is Map){
            final m=Map<String,dynamic>.from(frame['data']['message'] as Map);
            if(m['conversationId']?.toString()==id && !messages.any((x)=>x['id']==m['id'])){
              if(mounted)setState(()=>messages.add(m));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:220),curve:Curves.easeOut);
              });
              unawaited(markRead());
            }
          } else if(frame['event']=='message.reaction.created'||frame['event']=='message.reaction.deleted'){
            unawaited(loadMessages());
          }
        }catch(_){}
      },onError:(_){});
    }catch(_){}
  }

  Future<void> send() async {
    final body=draft.text.trim();
    if(body.isEmpty||sending)return;
    setState(()=>sending=true);
    try{
      if(editing!=null){
        final r=await widget.api.patch('chat/messages/' + editing!['id'].toString(),auth:true,body:{'body':body});
        final m=r['message'];
        if(m is Map)setState(()=>messages=messages.map((x)=>x['id']==m['id']?Map<String,dynamic>.from(m):x).toList());
        editing=null;
      }else{
        final r=await widget.api.post('chat/conversations/' + id + '/messages',auth:true,body:{
          'body':body,if(replying!=null)'replyToMessageId':replying!['id']
        });
        final m=r['message'];
        if(m is Map && !messages.any((x)=>x['id']==m['id']))messages.add(Map<String,dynamic>.from(m));
        replying=null;
      }
      draft.clear();setState((){});await markRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:220),curve:Curves.easeOut);
      });
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    finally{if(mounted)setState(()=>sending=false);}
  }

  Future<void> reactTo(Map<String,dynamic> m,String reaction) async {
    try{
      final list=(m['reactions'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      final found=list.where((x)=>x['reaction']==reaction).firstOrNull;
      if(found?['reactedByMe']==true){
        await widget.api.delete('chat/messages/' + m['id'].toString() + '/reactions/' + Uri.encodeComponent(reaction),auth:true);
      }else{
        await widget.api.post('chat/messages/' + m['id'].toString() + '/reactions',auth:true,body:{'reaction':reaction});
      }
      await loadMessages();
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  }

  Future<void> translate(Map<String,dynamic> m) async {
    final body=m['body']?.toString() ?? '';if(body.isEmpty)return;
    try{
      final r=await widget.api.post('translation/translate',auth:true,body:{'text':body,'targetLanguage':'en'});
      final value=r['translatedText']?.toString() ?? r['text']?.toString();
      if(value!=null&&mounted)setState(()=>m['_translation']=value);
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  }

  Future<void> deleteMessage(Map<String,dynamic> m) async {
    try{await widget.api.delete('chat/messages/' + m['id'].toString(),auth:true);await loadMessages();}
    on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  }

  Future<void> report(Map<String,dynamic> m,String reason) async {
    try{
      await widget.api.post('chat/messages/' + m['id'].toString() + '/report',auth:true,body:{'reason':reason});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Report submitted.')));
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  }

  void actions(Map<String,dynamic> m) {
    final sender=m['sender'] is Map?Map<String,dynamic>.from(m['sender'] as Map):<String,dynamic>{};
    final status=m['status']?.toString() ?? 'sent';
    showModalBottomSheet(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Wrap(children:[
      ListTile(leading:const Icon(Icons.reply_rounded),title:const Text('Reply'),onTap:(){Navigator.pop(ctx);setState(()=>replying=m);}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.translate_rounded),title:const Text('Translate to English'),onTap:(){Navigator.pop(ctx);translate(m);}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.flag_outlined),title:const Text('Report'),onTap:(){Navigator.pop(ctx);report(m,'Other inappropriate content');}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('Edit'),onTap:(){Navigator.pop(ctx);setState(()=>{editing=m;draft.text=m['body']?.toString() ?? '';});}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.delete_outline_rounded),title:const Text('Delete'),onTap:(){Navigator.pop(ctx);deleteMessage(m);}),
      const SizedBox(height:8)
    ])));
  }

  @override Widget build(BuildContext context){
    final title=(widget.conversation['displayName'] ?? widget.conversation['display_name'] ?? widget.conversation['username'] ?? 'Conversation').toString();
    return Scaffold(
      appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900)),
        Text('Eazy chat',style:const TextStyle(fontSize:10,color:EazyColors.muted))
      ]),actions:[IconButton(onPressed:loadMessages,icon:const Icon(Icons.refresh_rounded))]),
      body:Column(children:[
        if(replying!=null)_ContextBar(label:'REPLYING',value:replying!['body']?.toString() ?? '',onClose:()=>setState(()=>replying=null)),
        if(editing!=null)_ContextBar(label:'EDITING',value:editing!['body']?.toString() ?? '',onClose:()=>setState(()=>{editing=null;draft.clear();})),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):error!=null?_ChatState(error!,loadMessages):messages.isEmpty
          ?const _ChatState('No messages yet. Start the conversation.')
          :ListView.builder(controller:scroll,padding:const EdgeInsets.fromLTRB(16,12,16,16),itemCount:messages.length,itemBuilder:(_,i){
            return _MessageBubble(message:messages[i],onLongPress:()=>actions(messages[i]),onReaction:(r)=>reactTo(messages[i],r),onTranslate:()=>translate(messages[i]));
          })),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(12,6,12,10),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Expanded(child:TextField(controller:draft,maxLines:5,minLines:1,decoration:InputDecoration(
            hintText:editing!=null?'Edit message…':replying!=null?'Write a reply…':'Write a message…',
            prefixIcon:Icon(editing!=null?Icons.edit_outlined:replying!=null?Icons.reply_rounded:Icons.chat_bubble_outline_rounded)))),
          const SizedBox(width:8),SizedBox(width:54,height:54,child:FilledButton(onPressed:sending?null:send,child:sending?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):Icon(editing!=null?Icons.check_rounded:Icons.send_rounded)))
        ])))
      ])
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message,required this.onLongPress,required this.onReaction,required this.onTranslate});
  final Map<String,dynamic> message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReaction;
  final VoidCallback onTranslate;
  @override Widget build(BuildContext context){
    final sender=message['sender'] is Map?Map<String,dynamic>.from(message['sender'] as Map):<String,dynamic>{};
    final deleted=message['status']=='deleted';
    final reactions=(message['reactions'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return GestureDetector(onLongPress:onLongPress,child:Container(
      margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.fromLTRB(13,10,10,9),
      decoration:BoxDecoration(color:deleted?EazyColors.surfaceRaised:EazyColors.surface,borderRadius:BorderRadius.circular(19),border:Border.all(color:EazyColors.border)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(sender['displayName']!=null&&!deleted)Text(sender['displayName'].toString(),style:const TextStyle(color:EazyColors.muted,fontSize:10,fontWeight:FontWeight.w800)),
        Text(deleted?'Message deleted':(message['body']?.toString() ?? ''),style:TextStyle(color:deleted?EazyColors.muted:EazyColors.ink,fontSize:14,height:1.35,fontStyle:deleted?FontStyle.italic:FontStyle.normal)),
        if(message['replyTo'] is Map)Padding(padding:const EdgeInsets.only(top:8),child:Text('↳ ' + ((message['replyTo']['body'] ?? 'Deleted message').toString()),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted,fontSize:11))),
        if(message['_translation']!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(message['_translation'].toString(),style:const TextStyle(color:EazyColors.mint,fontSize:12,height:1.35))),
        if(reactions.isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:Wrap(spacing:4,children:reactions.map((r)=>InkWell(
          onTap:()=>onReaction(r['reaction'].toString()),borderRadius:BorderRadius.circular(20),child:Container(
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:EazyColors.green.withValues(alpha:.08),borderRadius:BorderRadius.circular(20),border:Border.all(color:EazyColors.border)),
            child:Text(r['reaction'].toString() + ' ' + (r['count'] ?? 0).toString(),style:const TextStyle(fontSize:11)))).toList())),
        if(!deleted)SizedBox(height:28,child:ListView(scrollDirection:Axis.horizontal,children:_reactions.map((r)=>IconButton(
          padding:EdgeInsets.zero,constraints:const BoxConstraints(minWidth:30),onPressed:()=>onReaction(r),icon:Text(r,style:const TextStyle(fontSize:16)))).toList())),
        Row(children:[
          Expanded(child:Text(_time(message['createdAt'] ?? message['created_at']),style:const TextStyle(color:EazyColors.muted,fontSize:9))),
          if(!deleted)TextButton(onPressed:onTranslate,child:const Text('Translate',style:TextStyle(fontSize:10)))
        ])
      ])
    ));
  }
  String _time(dynamic value){
    final d=DateTime.tryParse(value?.toString() ?? '');if(d==null)return '';
    final local=d.toLocal();final h=local.hour%12==0?12:local.hour%12;final m=local.minute.toString().padLeft(2,'0');
    return h.toString() + ':' + m + (local.hour>=12?' PM':' AM');
  }
}

class _ContextBar extends StatelessWidget{
  const _ContextBar({required this.label,required this.value,required this.onClose});
  final String label,value;final VoidCallback onClose;
  @override Widget build(BuildContext context)=>Container(margin:const EdgeInsets.fromLTRB(12,6,12,0),padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),
    decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(15),border:Border.all(color:EazyColors.border)),child:Row(children:[
      Container(width:3,height:31,decoration:BoxDecoration(color:EazyColors.green,borderRadius:BorderRadius.circular(4))),const SizedBox(width:9),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:const TextStyle(color:EazyColors.green,fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1)),
        Text(value,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted,fontSize:11))
      ])),IconButton(onPressed:onClose,icon:const Icon(Icons.close_rounded,size:18))
    ]));
}

class _ChatState extends StatelessWidget{
  const _ChatState(this.message,[this.action]);final String message;final Future<void> Function()? action;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:70,horizontal:24),child:Column(children:[
    const Icon(Icons.forum_outlined,size:44,color:EazyColors.green),const SizedBox(height:12),
    Text(message,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted,height:1.4)),
    if(action!=null)...[const SizedBox(height:14),OutlinedButton(onPressed:action,child:const Text('Try again'))]
  ]));
}
