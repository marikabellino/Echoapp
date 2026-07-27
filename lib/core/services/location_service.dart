import 'package:echo/core/services/permission_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Posizione utente, condivisa e cachata da Riverpod (non viene
/// ri-richiesta da zero ogni volta che un widget la guarda o rimonta).
///
/// `null` = servizio di localizzazione disattivato o permesso negato
/// (mostra "attiva la posizione"). Un errore nello stato async invece
/// indica un problema nel rilevamento (es. timeout del GPS) — va
/// mostrato con un messaggio diverso e un modo per riprovare, non
/// confuso con il permesso mancante.
final userPositionProvider = FutureProvider<Position?>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await PermissionGate.run(() => Geolocator.requestPermission());
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  final lastKnown = await Geolocator.getLastKnownPosition();
  if (lastKnown != null) return lastKnown;

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 10),
    ),
  );
});
