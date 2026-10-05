import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../home/home_shell.dart';

class ChatPage extends StatefulWidget{const ChatPage({super.key});@override State<ChatPage> createState()=>_ChatPageState();}
class _ChatPageState extends State<ChatPage>{
 final api=ApiClient();bool loading=true;String? error;List<Map<String,dynamic>> conversations=[];
 @override void initState(){super.initState();load();}
 Future<void> load()async{setState((){loading=true;error=null;});try{final j=await api.get('conversations',auth:true);final raw=j['conversations']??j['items']??const[];conversations=(raw as List<dynamic>).map((e)=>Map<String,dynamic>.from(e as Map)).toList();}on ApiException catch(e){error=e.message;}finally{if(mounted)setState(()=>loading=false);}}
 @override Widget build(BuildContext context){
   return SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.only(bottom:24),children:[
     EazyPageHeader(title:'Chat',subtitle:'Conversations that move with you',trailing:IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded))),
     const Padding(padding:EdgeInsets.fromLTRB(20,0,20,16),child:TextField(readOnly:true,decoration:InputDecoration(prefixIcon:Icon(Icons.search_rounded),hintText:'Search conversations'))),
     if(loading)const SizedBox(height:260,child:Center(child:CircularProgressIndicator())),
     if(!loading&&error!=null)_State(error!,load),
     if(!loading&&error==null&&conversations.isEmpty)const _State('No conversations yet',null),
     if(!loading&&conversations.isNotEmpty) ...conversations.map((c)=>ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:20,vertical:4),leading:const CircleAvatar(radius:25,child:Icon(Icons.person_rounded)),title:Text(c['title']?.toString()??'Conversation',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(c['lastMessage']?.toString()??'Start a conversation',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:EazyColors.muted)))),
   ])));
 }
}
class _State extends StatelessWidget{const _State(this.text,this.action);final String text;final VoidCallback? action;@override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.chat_bubble_outline_rounded,size:44,color:EazyColors.green),const SizedBox(height:12),Text(text,textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted)),if(action!=null)...[const SizedBox(height:12),OutlinedButton(onPressed:action,child:const Text('Try again'))]])));}