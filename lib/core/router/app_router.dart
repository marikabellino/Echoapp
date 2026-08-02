import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:echo/features/auth/presentation/pages/login_page.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
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

// Intercetta il deep link di conferma email (io.echoapp.echo://confirm-signup,
// vedi emailRedirectTo in AuthRepository.signUp) per mostrare un banner e
// forzare il logout: supabase_flutter crea comunque una sessione dal link,
// ma vogliamo che l'utente rientri sempre con un login esplicito invece di
// ritrovarsi già autenticato senza averlo fatto lui.
class _EmailConfirmationHandler {
  _EmailConfirmationHandler() {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _onUri(uri);
    });
    _linkSub = _appLinks.uriLinkStream.listen(_onUri);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (_awaitingSignIn && data.event == AuthChangeEvent.signedIn) {
        _awaitingSignIn = false;
        _completeConfirmation();
      }
    });
  }

  final _appLinks = AppLinks();
  late final StreamSubscription<Uri> _linkSub;
  late final StreamSubscription<AuthState> _authSub;
  bool _awaitingSignIn = false;

  void _onUri(Uri uri) {
    if (uri.scheme == 'io.echoapp.echo' && uri.host == 'confirm-signup') {
      _awaitingSignIn = true;
    }
  }

  void dispose() {
    _linkSub.cancel();
    _authSub.cancel();
  }

  Future<void> _completeConfirmation() async {
    await Supabase.instance.client.auth.signOut();
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      EchoToast.show(
        context,
        'Email confermata! Accedi per continuare.',
        type: EchoToastType.success,
      );
    }
  }
}

final _emailConfirmationHandler = _EmailConfirmationHandler();

// Chiave del Navigator radice — usata per navigare (es. dal tap su una push
// FCM in background/killed) da punti del codice senza un BuildContext locale.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    // Riferimento per forzare l'inizializzazione (i top-level `final` sono
    // lazy in Dart): senza questo, se nessuno lo tocca mai, il listener dei
    // deep link di conferma email non parte.
    _emailConfirmationHandler;
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
