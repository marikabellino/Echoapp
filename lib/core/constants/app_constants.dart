abstract class AppConstants {
  // Mapbox
  static const mapboxToken =
      'pk.eyJ1IjoibWFyaWthYjAxIiwiYSI6ImNtcDE2cG50aDAxd3EydHM5cXZwNGF0N3EifQ.1B_m-AT0I68QKeTajfOA0g';

  // ─── Supabase ────────────────────────────────────────────────────────────────
  // Ottieni questi valori da: https://app.supabase.com → Project Settings → API
  static const supabaseUrl = 'https://zniapgolwcqekcxsmzmk.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_eGB8UK-QTb5Zt2LbhgzFYA_dtiHt47a';

  // ─── Map defaults ────────────────────────────────────────────────────────────
  static const defaultLat = 41.9028; // Roma
  static const defaultLng = 12.4964;
  static const discoveryRadiusMeters = 300.0;
}
