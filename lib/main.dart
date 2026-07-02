import 'dart:async';

import 'package:echo/core/app.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/fcm_service.dart';
import 'package:echo/core/services/memory_cache_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (richiesto prima di qualsiasi altro servizio Firebase)
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  // Pre-carica i font per evitare il flash con font di sistema
  await GoogleFonts.pendingFonts([
    GoogleFonts.libreBaskerville(),
    GoogleFonts.roboto(),
  ]);

  // Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // La sessione persistita localmente può sopravvivere alla disinstallazione
  // dell'app (es. backup automatico di Android) pur essendo ormai
  // scaduta/revocata o relativa a un account eliminato. Verifichiamola col
  // server prima di considerare l'utente autenticato.
  if (Supabase.instance.client.auth.currentSession != null) {
    try {
      await Supabase.instance.client.auth
          .getUser()
          .timeout(const Duration(seconds: 8));
    } on AuthRetryableFetchException {
      // Nessuna connessione: non forzare il logout, si riproverà al prossimo avvio.
    } on TimeoutException {
      // Come sopra.
    } on AuthException {
      await Supabase.instance.client.auth.signOut();
    }
  }

  // Timeago – locale italiano
  timeago.setLocaleMessages('it', timeago.ItMessages());

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const EchoApp(),
    ),
  );
}
