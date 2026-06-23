import 'dart:async';

import 'package:echo/features/auth/presentation/pages/login_page.dart';
import 'package:echo/shared/widgets/navigation/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Notifies GoRouter whenever auth state changes so redirects re-evaluate.
// Also tracks passwordRecovery events to redirect to the reset screen.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _isPasswordRecovery = true;
      } else if (data.event == AuthChangeEvent.userUpdated ||
          data.event == AuthChangeEvent.signedOut) {
        _isPasswordRecovery = false;
      }
      notifyListeners();
    });
  }

  bool _isPasswordRecovery = false;
  bool get isPasswordRecovery => _isPasswordRecovery;

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthChangeNotifier();

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final isAuthenticated =
        Supabase.instance.client.auth.currentUser != null;
    final loc = state.matchedLocation;

    if (_authNotifier.isPasswordRecovery && loc != '/reset-password') {
      return '/reset-password';
    }

    final isAuthPage = loc == '/login' ||
        loc == '/register' ||
        loc == '/forgot-password' ||
        loc == '/reset-password';

    if (!isAuthenticated && !isAuthPage) return '/login';
    if (isAuthenticated && isAuthPage && !_authNotifier.isPasswordRecovery) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LoginPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/forgot-password',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const ForgotPasswordPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: '/reset-password',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const ResetPasswordPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const MainShell(),
    ),
  ],
);
