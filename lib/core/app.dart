import 'package:echo/core/router/app_router.dart';
import 'package:echo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class EchoApp extends StatelessWidget {
  const EchoApp({super.key}); 

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Mingle',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      
    );
  }
}