import 'package:echo/core/app.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/fcm_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
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

  // Mapbox
  MapboxOptions.setAccessToken(AppConstants.mapboxToken);

  // Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Timeago – locale italiano
  timeago.setLocaleMessages('it', timeago.ItMessages());

  runApp(
    const ProviderScope(child: EchoApp()),
  );
}
