import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, required this.auth});
  final AuthController auth;

  @override State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final first=TextEditingController(), middle=TextEditingController(), last=TextEditingController();
  final username=TextEditingController(), bio=TextEditingController();
  DateTime? dob;
  bool busy=false, checking=false;
  bool? available;
  String? error;

  @override void initState(){
    super.initState();
    final p=widget.auth.profile;
    first.text=p?['firstName']?.toString()??'';
    middle.text=p?['middleName']?.toString()??'';
    last.text=p?['lastName']?.toString()??'';
    username.text=p?['username']?.toString().replaceFirst(RegExp(r'^user_'), '')??'';
    bio.text=p?['bio']?.toString()??'';
    final raw=p?['dateOfBirth']?.toString();
    if(raw!=null&&raw.length>=10) dob=DateTime.tryParse(raw.substring(0,10));
  }

  @override void dispose(){for(final c in [first,middle,last,username,bio]){c.dispose();}super.dispose();}

  Future<void> pickDob() async {
    final now=DateTime.now();
    final value=await showDatePicker(
      context:context,
      initialDate:dob??DateTime(now.year-18,now.month,now.day),
      firstDate:DateTime(1900),lastDate:now,helpText:'Select your date of birth');
    if(value!=null) setState(()=>dob=value);
  }

  Future<void> checkUsername() async {
    final value=username.text.trim().toLowerCase();
    if(!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value)){setState(()=>available=null);return;}
    setState(()=>checking=true);
    try{
      final result=await ApiClient().get('profiles/username/$value/availability');
      if(mounted)setState(()=>available=result['available']==true);
    }on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
    finally{if(mounted)setState(()=>checking=false);}
  }

  Future<void> save() async {
    final f=first.text.trim(), u=username.text.trim().toLowerCase();
    if(f.isEmpty||u.isEmpty||dob==null){setState(()=>error='First name, username and date of birth are required.');return;}
    if(!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(u)){setState(()=>error='Username must be 3-32 lowercase letters, numbers or underscores.');return;}
    if(available==false){setState(()=>error='That username is already taken.');return;}
    setState((){busy=true;error=null;});
    try{
      await widget.auth.completeOnboarding({
        'firstName':f,
        'middleName':middle.text.trim(),
        'lastName':last.text.trim(),
        'username':u,
        'bio':bio.text.trim(),
        'dateOfBirth':'${dob!.year.toString().padLeft(4,'0')}-${dob!.month.toString().padLeft(2,'0')}-${dob!.day.toString().padLeft(2,'0')}',
      });
      if(mounted)context.go('/home');
    }on ApiException catch(e){if(mounted)setState(()=>error=e.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Set up your profile')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(24,12,24,40),children:[
      Text('Make Eazy yours',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      const Text('A few details unlock your social identity, wallet and marketplace experience.',style:TextStyle(color:EazyColors.muted,height:1.5)),
      const SizedBox(height:24),
      if(error!=null)Container(padding:const EdgeInsets.all(14),margin:const EdgeInsets.only(bottom:14),decoration:BoxDecoration(color:EazyColors.red.withValues(alpha:.1),borderRadius:BorderRadius.circular(14)),child:Text(error!,style:const TextStyle(color:EazyColors.red))),
      TextField(controller:first,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'First name')),
      const SizedBox(height:12),
      TextField(controller:middle,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Middle name (optional)')),
      const SizedBox(height:12),
      TextField(controller:last,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Last name (optional)')),
      const SizedBox(height:12),
      TextField(controller:username,autocorrect:false,onChanged:(_)=>setState(()=>available=null),onEditingComplete:checkUsername,decoration:InputDecoration(
        labelText:'Username',prefixText:'@ ',suffixIcon:checking?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))):available==true?const Icon(Icons.check_circle,color:EazyColors.green):available==false?const Icon(Icons.cancel,color:EazyColors.red):null)),
      const SizedBox(height:12),
      ListTile(
        contentPadding:const EdgeInsets.symmetric(horizontal:18),tileColor:EazyColors.surface,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(EazyRadius.md),side:const BorderSide(color:EazyColors.border)),
        leading:const Icon(Icons.cake_outlined,color:EazyColors.green),
        title:Text(dob==null?'Date of birth':'${dob!.day}/${dob!.month}/${dob!.year}'),
        subtitle:const Text('Required to complete your Eazy profile'),
        trailing:const Icon(Icons.chevron_right_rounded),onTap:busy?null:pickDob),
      const SizedBox(height:12),
      TextField(controller:bio,maxLines:4,maxLength:500,decoration:const InputDecoration(labelText:'Bio',hintText:'Tell people a little about you')),
      const SizedBox(height:20),
      SizedBox(height:56,child:FilledButton(onPressed:busy?null:save,child:busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):const Text('Finish setup'))),
    ])));
}
