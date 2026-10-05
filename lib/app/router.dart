import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_controller.dart';
import '../features/auth/auth_page.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/profile_setup_page.dart';
import '../features/onboarding/welcome_page.dart';

GoRouter buildRouter(AuthController auth) => GoRouter(
  initialLocation: '/welcome',
  refreshListenable: auth,
  redirect: (context,state) {
    final path=state.uri.path;
    final public=path=='/welcome'||path=='/auth';
    if(auth.isSignedIn && public) return '/home';
    if(!auth.isSignedIn && path.startsWith('/home')) return '/auth';
    return null;
  },
  routes:[
    GoRoute(path:'/welcome',builder:(_,__)=>const WelcomePage()),
    GoRoute(path:'/auth',builder:(_,__)=>AuthPage(auth:auth)),
    GoRoute(path:'/onboarding',builder:(_,__)=>ProfileSetupPage(auth:auth)),
    GoRoute(path:'/home',builder:(_,__)=>HomeShell(auth:auth)),
  ],
  errorBuilder:(context,state)=>Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('This view is temporarily unavailable.\n'+state.error.toString())))),
);
