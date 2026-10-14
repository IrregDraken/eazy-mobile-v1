import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';
import 'chat_home_screen.dart';

const _reactions = <String>['👍','❤️','😂','😮','😢','🙏','👏','🔥'];

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final api = ApiClient();

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationPage(api: api, conversation: conversation),
    ));
  }

  @override
  Widget build(BuildContext context) => ChatHomeScreen(
    api: api,
    onOpen: _openConversation,
  );
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
  late final EazyMediaService media;
  final List<MediaUpload> pendingAttachments=[];
  List<Map<String,dynamic>> messages=[];
  Map<String,dynamic>? replying,editing;
  bool loading=true,sending=false;
  String? error;
  String? currentUsername;
  WebSocket? socket;
  StreamSubscription? subscription;

  String get id=>widget.conversation['id']?.toString() ?? '';
  Map<String, dynamic> get _otherParticipant {
    final participants = widget.conversation['participants'];
    if (participants is List) {
      final people = participants.whereType<Map>().map((person) => Map<String, dynamic>.from(person)).toList();
      if (people.isNotEmpty) {
        return people.firstWhere(
          (person) => (person['username'] ?? '').toString().toLowerCase() != (currentUsername ?? '').toLowerCase(),
          orElse: () => people.first,
        );
      }
    }
    return <String, dynamic>{
      'username': widget.conversation['username'],
      'displayName': widget.conversation['displayName'] ?? widget.conversation['display_name'],
    };
  }

  String get _conversationUsername {
    final username = _otherParticipant['username']?.toString();
    return username == null || username.isEmpty ? 'Private conversation' : '@$username';
  }

  String get _conversationTitle {
    final person = _otherParticipant;
    final name = (person['displayName'] ?? person['display_name'] ?? person['name'] ?? person['username'])?.toString().trim();
    return name == null || name.isEmpty ? 'Eazy Chat' : name;
  }

  @override void initState(){super.initState();media=EazyMediaService(widget.api);loadMessages();connectRealtime();loadMyProfile();}
  Future<void> loadMyProfile() async {
    try {
      final result = await widget.api.get('profiles/me', auth:true);
      final profile = result['profile'];
      if (mounted && profile is Map) setState(() => currentUsername = profile['username']?.toString());
    } catch (_) {}
  }
  bool _isMine(Map<String,dynamic> message) {
    final sender = message['sender'] is Map ? Map<String,dynamic>.from(message['sender'] as Map) : <String,dynamic>{};
    final value = (sender['username'] ?? message['senderUsername'] ?? message['sender_username'])?.toString().toLowerCase();
    return currentUsername != null && value == currentUsername!.toLowerCase();
  }
  @override void dispose(){subscription?.cancel();socket?.close();draft.dispose();scroll.dispose();super.dispose();}

  Future<void> loadMessages() async {
    try {
      if (messages.isEmpty && mounted) setState(()=>loading=true);
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
    if((body.isEmpty && pendingAttachments.isEmpty)||sending)return;
    setState(()=>sending=true);
    try{
      if(editing!=null){
        final r=await widget.api.patch('chat/messages/' + editing!['id'].toString(),auth:true,body:{'body':body});
        final m=r['message'];
        if(m is Map)setState(()=>messages=messages.map((x)=>x['id']==m['id']?Map<String,dynamic>.from(m):x).toList());
        editing=null;
      }else{
        final r=await widget.api.post('chat/conversations/' + id + '/messages',auth:true,body:{
          if(body.isNotEmpty)'body':body,if(replying!=null)'replyToMessageId':replying!['id'],if(pendingAttachments.isNotEmpty)'attachments':pendingAttachments.map((a)=>{'storageKey':a.path,'contentType':a.contentType,'byteSize':a.byteSize}).toList()
        });
        final m=r['message'];
        if(m is Map && !messages.any((x)=>x['id']==m['id']))messages.add(Map<String,dynamic>.from(m));
        replying=null;
        pendingAttachments.clear();
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
      final r=await widget.api.post('translation',auth:true,body:{'text':body,'targetLanguage':'en'});
      final value=r['translatedText']?.toString() ?? r['text']?.toString();
      if(value!=null&&mounted)setState(()=>m['_translation']=value);
    }on ApiException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined, color: EazyColors.green), title: const Text('Photo'), subtitle: const Text('Choose an image'), onTap: () => Navigator.pop(sheet, 'photo')),
        ListTile(leading: const Icon(Icons.video_library_outlined, color: EazyColors.green), title: const Text('Video'), subtitle: const Text('Choose a video'), onTap: () => Navigator.pop(sheet, 'video')),
        ListTile(leading: const Icon(Icons.attach_file_rounded, color: EazyColors.green), title: const Text('File or document'), subtitle: const Text('PDF, Word, TXT or CSV, up to 25 MB'), onTap: () => Navigator.pop(sheet, 'file')),
        const SizedBox(height: 8),
      ])),
    );
    if (choice == null || !mounted) return;
    try {
      final upload = switch (choice) {
        'photo' => await media.pickAndUpload(kind: 'message'),
        'video' => await media.pickAndUploadVideo(kind: 'message'),
        _ => await media.pickAndUploadDocument(kind: 'message'),
      };
      if (upload != null && mounted) setState(() => pendingAttachments.add(upload));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not attach that file. Please try again.')));
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final path = attachment['storageKey']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final result = await widget.api.post('media/signed-message-attachment-url', auth: true, body: {'path': path});
      final url = result['signedUrl']?.toString();
      if (url == null || url.isEmpty) throw const ApiException('The attachment could not be opened.');
      final type = attachment['contentType']?.toString() ?? '';
      if (type.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: EazyColors.canvas,
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('This image could not be loaded.'),
                ),
              ),
            ),
          ),
        );
      } else {
        final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app could open this attachment.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this attachment. Please try again.')));
    }
  }

  Future<void> _translateDraft() async {
    final text = draft.text.trim();
    if (text.isEmpty) {
      if (mounted) context.push('/translation');
      return;
    }
    try {
      final result = await widget.api.post('translation', auth: true, body: {'text': text, 'targetLanguage': 'en'});
      final translated = (result['translatedText'] ?? result['text'])?.toString();
      if (translated == null || translated.trim().isEmpty) throw const ApiException('No translated text was returned.');
      if (mounted) setState(() { draft.text = translated; draft.selection = TextSelection.collapsed(offset: translated.length); });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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
    final status=m['status']?.toString() ?? 'sent';
    showModalBottomSheet(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Wrap(children:[
      ListTile(leading:const Icon(Icons.reply_rounded),title:const Text('Reply'),onTap:(){Navigator.pop(ctx);setState(()=>replying=m);}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.add_reaction_outlined),title:const Text('React'),onTap:(){Navigator.pop(ctx);chooseReaction(m);}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.translate_rounded),title:const Text('Translate to English'),onTap:(){Navigator.pop(ctx);translate(m);}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.flag_outlined),title:const Text('Report'),onTap:(){Navigator.pop(ctx);report(m,'Other inappropriate content');}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('Edit'),onTap:(){Navigator.pop(ctx);setState(() { editing=m; draft.text=m['body']?.toString() ?? ''; });}),
      if(status!='deleted')ListTile(leading:const Icon(Icons.delete_outline_rounded),title:const Text('Delete'),onTap:(){Navigator.pop(ctx);deleteMessage(m);}),
      const SizedBox(height:8)
    ])));
  }

  void chooseReaction(Map<String,dynamic> message) {
    showModalBottomSheet<void>(
      context:context,
      showDragHandle:true,
      builder:(ctx)=>SafeArea(
        child:Padding(
          padding:const EdgeInsets.all(18),
          child:Wrap(
            alignment:WrapAlignment.spaceEvenly,
            spacing:8,
            runSpacing:8,
            children:_reactions.map((reaction)=>IconButton(
              onPressed:(){Navigator.pop(ctx);reactTo(message,reaction);},
              icon:Text(reaction,style:const TextStyle(fontSize:26)),
            )).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRecipientAction(String action) async {
    final username = _otherParticipant['username']?.toString().trim() ?? '';
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recipient details are unavailable.')));
      return;
    }
    if (action == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Block this account?'),
          content: Text('You will no longer receive messages from @$username.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Block')),
          ],
        ),
      );
      if (confirmed != true) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await widget.api.post('social/block/$username', auth: true);
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Account blocked.')));
      } on ApiException catch (e) {
        if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (action == 'report') {
      final reasonController = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Report account'),
          content: TextField(
            controller: reasonController,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'What should Eazy review?', hintText: 'Describe the issue'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final value = reasonController.text.trim();
              if (value.length >= 3) Navigator.pop(dialogContext, value);
            }, child: const Text('Submit report')),
          ],
        ),
      );
      reasonController.dispose();
      if (reason == null) return;
      try {
        await widget.api.post('social/report/$username', body: {'reason': reason}, auth: true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted for review.')));
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
  @override Widget build(BuildContext context){
    final title = _conversationTitle;
    return Scaffold(
      backgroundColor: EazyColors.canvas,
      appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontSize:17,fontWeight:FontWeight.w900)),
        Text(_conversationUsername,style:const TextStyle(fontSize:11,color:EazyColors.muted,fontWeight:FontWeight.w600))
      ]),actions:[
        PopupMenuButton<String>(
          tooltip: 'Conversation options',
          onSelected: _handleRecipientAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block_rounded), SizedBox(width: 10), Text('Block account')])),
            PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined), SizedBox(width: 10), Text('Report account')])),
          ],
        ),
      ]),
      body:Column(children:[
        if(replying!=null)_ContextBar(label:'REPLYING',value:replying!['body']?.toString() ?? '',onClose:()=>setState(()=>replying=null)),
        if(editing!=null)_ContextBar(label:'EDITING',value:editing!['body']?.toString() ?? '',onClose:()=>setState(() { editing=null; draft.clear(); })),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):error!=null?_ChatState(error!,loadMessages):messages.isEmpty
          ?const _ChatState('No messages yet. Start the conversation.')
          :ListView.builder(controller:scroll,padding:const EdgeInsets.fromLTRB(16,12,16,16),itemCount:messages.length,itemBuilder:(_,i){
            return _MessageBubble(message:messages[i],isMine:_isMine(messages[i]),onLongPress:()=>actions(messages[i]),onReaction:(r)=>reactTo(messages[i],r),onTranslate:()=>translate(messages[i]),onOpenAttachment:_openAttachment);
          })),
        if(pendingAttachments.isNotEmpty)
          SizedBox(height:54,child:ListView.separated(
            scrollDirection:Axis.horizontal,
            padding:const EdgeInsets.fromLTRB(14,4,14,4),
            itemCount:pendingAttachments.length,
            separatorBuilder:(_,__)=>const SizedBox(width:8),
            itemBuilder:(context,index){
              final item=pendingAttachments[index];
              return Container(
                constraints:const BoxConstraints(maxWidth:220),
                padding:const EdgeInsets.only(left:10,right:4),
                decoration:BoxDecoration(color:EazyColors.surface,borderRadius:BorderRadius.circular(14),border:Border.all(color:EazyColors.border)),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  Icon(item.contentType.startsWith('image/')?Icons.image_outlined:item.contentType.startsWith('video/')?Icons.video_file_outlined:Icons.description_outlined,color:EazyColors.green,size:18),
                  const SizedBox(width:6),
                  Flexible(child:Text(item.fileName,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11))),
                  IconButton(visualDensity:VisualDensity.compact,iconSize:17,onPressed:()=>setState(()=>pendingAttachments.removeAt(index)),icon:const Icon(Icons.close_rounded)),
                ]),
              );
            },
          )),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(8,6,8,10),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          IconButton(tooltip:'Attach photo, video or document',onPressed:sending?null:_pickAttachment,style:IconButton.styleFrom(foregroundColor:EazyColors.green),icon:const Icon(Icons.add_circle_outline_rounded,size:29)),
          Expanded(child:TextField(controller:draft,maxLines:5,minLines:1,decoration:InputDecoration(
            hintText:editing!=null?'Edit message…':replying!=null?'Write a reply…':'Message on Eazy…'))),
          IconButton(tooltip:'Open Eazy Assist',onPressed:()=>context.push('/assist'),style:IconButton.styleFrom(foregroundColor:EazyColors.green),icon:Image.asset('assets/images/eazy_logo_mark.png',width:23,height:23,errorBuilder:(_,__,___)=>const Icon(Icons.auto_awesome_rounded))),
          IconButton(tooltip:'Translate draft to English',onPressed:_translateDraft,style:IconButton.styleFrom(foregroundColor:EazyColors.green),icon:const Icon(Icons.translate_rounded)),
          SizedBox(width:48,height:52,child:FilledButton(onPressed:sending?null:send,style:FilledButton.styleFrom(padding:EdgeInsets.zero),child:Icon(editing!=null?Icons.check_rounded:Icons.send_rounded)))
        ])))
      ])
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message,required this.isMine,required this.onLongPress,required this.onReaction,required this.onTranslate,required this.onOpenAttachment});
  final Map<String,dynamic> message;
  final bool isMine;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReaction;
  final VoidCallback onTranslate;
  final ValueChanged<Map<String,dynamic>> onOpenAttachment;
  @override Widget build(BuildContext context){
    final sender=message['sender'] is Map?Map<String,dynamic>.from(message['sender'] as Map):<String,dynamic>{};
    final deleted=message['status']=='deleted';
    final reactions=(message['reactions'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return Align(
      alignment:isMine?Alignment.centerRight:Alignment.centerLeft,
      child:ConstrainedBox(
        constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(context).width*.80),
        child:GestureDetector(onLongPress:onLongPress,child:Container(
      margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.fromLTRB(13,10,10,9),
      decoration:BoxDecoration(
        color:deleted?EazyColors.surfaceRaised:(isMine?const Color(0xFF173D2B):EazyColors.surface),
        borderRadius:BorderRadius.only(
          topLeft:const Radius.circular(20),
          topRight:const Radius.circular(20),
          bottomLeft:Radius.circular(isMine?20:7),
          bottomRight:Radius.circular(isMine?7:20),
        ),
        border:Border.all(color:isMine?EazyColors.green.withValues(alpha:.24):EazyColors.border),
      ),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(!isMine&&sender['displayName']!=null&&!deleted)Padding(padding:const EdgeInsets.only(bottom:4),child:Text(sender['displayName'].toString(),style:const TextStyle(color:EazyColors.green,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:.2))),
        Text(deleted?'Message deleted':(message['body']?.toString() ?? ''),style:TextStyle(color:deleted?EazyColors.muted:EazyColors.ink,fontSize:14,height:1.45,fontStyle:deleted?FontStyle.italic:FontStyle.normal)),
        if(message['replyTo'] is Map)Padding(padding:const EdgeInsets.only(top:8),child:Text('↳ ' + ((message['replyTo']['body'] ?? 'Deleted message').toString()),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted,fontSize:11))),
        if(message['attachments'] is List && (message['attachments'] as List).isNotEmpty)
          Padding(
            padding:const EdgeInsets.only(top:8),
            child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:(message['attachments'] as List).whereType<Map>().map<Widget>((raw){
                final attachment=Map<String,dynamic>.from(raw);
                final type=attachment['contentType']?.toString() ?? '';
                final bytes=int.tryParse(attachment['byteSize']?.toString() ?? '') ?? 0;
                final label=type.startsWith('image/')?'Photo':type.startsWith('video/')?'Video':type.startsWith('audio/')?'Audio':'Document';
                final size=bytes>=1024*1024?'${(bytes/(1024*1024)).toStringAsFixed(1)} MB':'${(bytes/1024).round()} KB';
                return InkWell(
                  onTap:()=>onOpenAttachment(attachment),
                  borderRadius:BorderRadius.circular(11),
                  child:Container(
                  margin:const EdgeInsets.only(bottom:5),
                  padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
                  decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(11),border:Border.all(color:EazyColors.border)),
                  child:Row(mainAxisSize:MainAxisSize.min,children:[
                    Icon(type.startsWith('image/')?Icons.image_outlined:type.startsWith('video/')?Icons.video_file_outlined:Icons.description_outlined,color:EazyColors.green,size:18),
                    const SizedBox(width:7),
                    Text('${label} attachment',style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800)),
                    const SizedBox(width:7),
                    Text(size,style:const TextStyle(fontSize:10,color:EazyColors.muted)),
                  ]),
                  ),
                );
              }).toList(),
            ),
          ),
        if(message['_translation']!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(message['_translation'].toString(),style:const TextStyle(color:EazyColors.mint,fontSize:12,height:1.35))),
        if(reactions.isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:Wrap(
          spacing:4,
          children:reactions.map<Widget>((r) => InkWell(
            onTap:()=>onReaction(r['reaction'].toString()),
            borderRadius:BorderRadius.circular(20),
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
              decoration:BoxDecoration(color:EazyColors.surfaceRaised,borderRadius:BorderRadius.circular(10),border:Border.all(color:EazyColors.green.withValues(alpha:.22))),
              child:Text(r['reaction'].toString() + ' ' + (r['count'] ?? 0).toString(),style:const TextStyle(fontSize:11)),
            ),
          )).toList(),
        )),
         Row(children:[
          Expanded(child:Text(_time(message['createdAt'] ?? message['created_at']),style:const TextStyle(color:EazyColors.muted,fontSize:9))),
          if(!deleted)TextButton.icon(onPressed:onTranslate, icon:const Icon(Icons.translate_rounded,size:13), label:const Text('Translate',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800)), style:TextButton.styleFrom(foregroundColor:EazyColors.green,visualDensity:VisualDensity.compact,padding:const EdgeInsets.symmetric(horizontal:6)))
        ])
      ])
        ))));
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
    decoration:BoxDecoration(color:EazyColors.surface,borderRadius:BorderRadius.circular(EazyRadius.md),border:Border.all(color:EazyColors.border)),child:Row(children:[
      Container(width:3,height:31,decoration:BoxDecoration(gradient:const LinearGradient(colors:[EazyColors.green,EazyColors.mint],begin:Alignment.topCenter,end:Alignment.bottomCenter),borderRadius:BorderRadius.circular(4))),const SizedBox(width:9),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:const TextStyle(color:EazyColors.green,fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1)),
        Text(value,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted,fontSize:11))
      ])),IconButton(onPressed:onClose,icon:const Icon(Icons.close_rounded,size:18))
    ]));
}

class _ChatState extends StatelessWidget{
  const _ChatState(this.message,[this.action]);final String message;final Future<void> Function()? action;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:70,horizontal:24),child:Column(children:[
    Container(width:68,height:68,decoration:BoxDecoration(color:EazyColors.green.withValues(alpha:.08),borderRadius:BorderRadius.circular(22),border:Border.all(color:EazyColors.border)),child:const Icon(Icons.forum_outlined,size:32,color:EazyColors.green)),const SizedBox(height:12),
    Text(message,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted,height:1.4)),
    if(action!=null)...[const SizedBox(height:14),OutlinedButton(onPressed:action,child:const Text('Try again'))]
  ]));
}
