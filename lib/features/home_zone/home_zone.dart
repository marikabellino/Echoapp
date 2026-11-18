import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La "zona casa" dell'utente.
///
/// Resta SOLO su questo telefono (SharedPreferences): non viene mai mandata
/// al server. Quando un drop viene lasciato dentro la zona, l'app lo segna
/// come "a casa" e il database (035_home_zone.sql) ne nasconde il punto
/// esatto e impedisce che sia pubblico.
class HomeZone {
  const HomeZone({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.label,
  });

  final double lat;
  final double lng;
  final double radiusMeters;

  /// Etichetta scelta dall'utente (es. via cercata). Solo per mostrarla a lui.
  final String? label;

  /// Raggi tra cui scegliere: un appartamento in un palazzo e il GPS che
  /// "balla" di qualche decina di metri chiedono un po' di margine.
  static const radii = [100.0, 200.0, 400.0];
  static const defaultRadius = 200.0;

  bool contains(double latitude, double longitude) =>
      Geolocator.distanceBetween(lat, lng, latitude, longitude) <= radiusMeters;

  HomeZone copyWith({double? radiusMeters}) => HomeZone(
    lat: lat,
    lng: lng,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    label: label,
  );
}

class HomeZoneState {
  const HomeZoneState({this.zone, this.prompted = false});

  /// `null` = zona non impostata.
  final HomeZone? zone;

  /// Il pannello di primo avvio è già stato mostrato (impostata o rimandata).
  final bool prompted;
}

class HomeZoneNotifier extends AsyncNotifier<HomeZoneState> {
  static const _kLat = 'home_zone_lat';
  static const _kLng = 'home_zone_lng';
  static const _kRadius = 'home_zone_radius';
  static const _kLabel = 'home_zone_label';
  static const _kPrompted = 'home_zone_prompted_v1';

  @override
  Future<HomeZoneState> build() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble(_kLat);
    final lng = p.getDouble(_kLng);
    return HomeZoneState(
      zone: lat == null || lng == null
          ? null
          : HomeZone(
              lat: lat,
              lng: lng,
              radiusMeters: p.getDouble(_kRadius) ?? HomeZone.defaultRadius,
              label: p.getString(_kLabel),
            ),
      prompted: p.getBool(_kPrompted) ?? false,
    );
  }

  Future<void> save(HomeZone zone) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLat, zone.lat);
    await p.setDouble(_kLng, zone.lng);
    await p.setDouble(_kRadius, zone.radiusMeters);
    if (zone.label != null) {
      await p.setString(_kLabel, zone.label!);
    } else {
      await p.remove(_kLabel);
    }
    await p.setBool(_kPrompted, true);
    state = AsyncData(HomeZoneState(zone: zone, prompted: true));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [_kLat, _kLng, _kRadius, _kLabel]) {
      await p.remove(k);
    }
    state = const AsyncData(HomeZoneState(prompted: true));
  }

  /// "Più tardi" al primo avvio: non lo richiediamo più in automatico.
  Future<void> markPrompted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPrompted, true);
    state = AsyncData(
      HomeZoneState(zone: state.asData?.value.zone, prompted: true),
    );
  }
}

final homeZoneProvider = AsyncNotifierProvider<HomeZoneNotifier, HomeZoneState>(
  HomeZoneNotifier.new,
);
