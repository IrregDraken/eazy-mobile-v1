import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, required this.auth});
  final AuthController auth;
  @override State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}
class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final first = TextEditingController(), middle = TextEditingController(), last = TextEditingController(), username = TextEditingController(), bio = TextEditingController();
  bool busy = false; String? error;
  @override void dispose(){for(final c in [first,middle,last,username,bio]) c.dispose(); super.dispose();}
  Future<void> save() async {
    if(first.text.trim().isEmpty || last.text.trim().isEmpty || username.text.trim().isEmpty){setState(()=>error='First name, last name and username are required.');return;}
    setState(()=>busy=true);
    try {
      await widget.auth.completeOnboarding({'firstName':first.text.trim(),'middleName':middle.text.trim(),'lastName':last.text.trim(),'username':username.text.trim().toLowerCase(),'bio':bio.text.trim()});
      if(mounted) context.go('/home');
    } on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Set up your profile')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('Make Eazy yours',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),
      const SizedBox(height:8), const Text('This information powers your social profile and marketplace identity.',style:TextStyle(color:EazyColors.muted,height:1.5)),
      const SizedBox(height:24), if(error!=null) Text(error!,style:const TextStyle(color:EazyColors.red)),
      TextField(controller:first,decoration:const InputDecoration(labelText:'First name')), const SizedBox(height:12),
      TextField(controller:middle,decoration:const InputDecoration(labelText:'Middle name (optional)')), const SizedBox(height:12),
      TextField(controller:last,decoration:const InputDecoration(labelText:'Last name')), const SizedBox(height:12),
      TextField(controller:username,decoration:const InputDecoration(labelText:'Username',prefixText:'@ ')), const SizedBox(height:12),
      TextField(controller:bio,maxLines:4,decoration:const InputDecoration(labelText:'Bio (optional)',hintText:'Tell people a little about you')),
      const SizedBox(height:24), SizedBox(height:56,child:FilledButton(onPressed:busy?null:save,child:busy?const CircularProgressIndicator():const Text('Finish setup')))
    ])));
}
