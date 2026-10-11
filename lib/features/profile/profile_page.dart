import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class ProfilePage extends StatefulWidget{
  const ProfilePage({super.key,required this.auth});final AuthController auth;
  @override State<ProfilePage> createState()=>_ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage>{
  final api=ApiClient();bool loading=true;Map<String,dynamic> stats={};String? error;
  @override void initState(){super.initState();load();}
  Future<void> load()async{try{final r=await api.get('profiles/me/stats',auth:true);if(mounted)setState(()=>stats=Map<String,dynamic>.from(r['stats'] as Map? ?? {}));}on ApiException catch(e){if(mounted)setState(()=>error=e.message);}finally{if(mounted)setState(()=>loading=false);}}
  @override Widget build(BuildContext context){
    final p=widget.auth.profile??const<String,dynamic>{};
    final name=p['displayName']?.toString().trim().isNotEmpty==true?p['displayName'].toString():'Eazy user';
    final username=p['username']?.toString()??'';final avatar=p['avatarUrl']?.toString();
    return SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.fromLTRB(20,20,20,110),children:[
      Row(children:[const Expanded(child:Text('You',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900))),IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded))]),
      const SizedBox(height:14),
      Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
        CircleAvatar(radius:46,backgroundImage:avatar!=null&&avatar.startsWith('http')?NetworkImage(avatar):null,child:const Icon(Icons.person_rounded,size:40)),
        const SizedBox(height:12),Text(name,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),
        if(username.isNotEmpty)Text('@'+username,style:const TextStyle(color:EazyColors.muted)),
        if(p['bio']?.toString().isNotEmpty==true)...[const SizedBox(height:10),Text(p['bio'].toString(),textAlign:TextAlign.center,style:const TextStyle(color:EazyColors.muted,height:1.4))],
        const SizedBox(height:18),Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
          _Stat(loading?'—':(stats['posts']??0).toString(),'Posts'),
          _Stat(loading?'—':(stats['followers']??0).toString(),'Followers'),
          _Stat(loading?'—':(stats['following']??0).toString(),'Following'),
        ]),
      ]))),
      const SizedBox(height:12),
      _Menu(Icons.auto_awesome_rounded,'Eazy Assist',onTap:()=>context.push('/assist')),
      _Menu(Icons.translate_rounded,'Translation',onTap:()=>context.push('/translation')),
      _Menu(Icons.location_on_outlined,'Location tools',onTap:()=>context.push('/location')),
      _Menu(Icons.edit_outlined,'Edit profile',onTap:()async{await context.push('/profile/edit');if(mounted)setState((){});}),
      _Menu(Icons.notifications_none_rounded,'Notifications',onTap:()=>context.push('/notifications')),
      _Menu(Icons.settings_outlined,'Settings',onTap:()=>context.push('/settings')),
      _Menu(Icons.shield_outlined,'Security & sessions',onTap:()=>context.push('/security')),
      _Menu(Icons.block_outlined,'Blocked accounts',onTap:()=>context.push('/blocks')),
      const SizedBox(height:8),
      OutlinedButton.icon(onPressed:()async{await widget.auth.signOut();if(context.mounted)context.go('/welcome');},icon:const Icon(Icons.logout_rounded),label:const Text('Sign out')),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:EazyColors.red))),
    ])));
  }
}
class _Stat extends StatelessWidget{const _Stat(this.value,this.label);final String value,label;@override Widget build(BuildContext context)=>Column(children:[Text(value,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),const SizedBox(height:2),Text(label,style:const TextStyle(color:EazyColors.muted,fontSize:12))]);}
class _Menu extends StatelessWidget{const _Menu(this.icon,this.title,{required this.onTap});final IconData icon;final String title;final VoidCallback onTap;@override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(onTap:onTap,leading:Icon(icon,color:EazyColors.green),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),trailing:const Icon(Icons.chevron_right_rounded,color:EazyColors.muted)));}
