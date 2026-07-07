abstract class AppConstants {
  // MapTiler — ottieni la key su https://cloud.maptiler.com → API Keys
  static const maptilerKey = 'FJ1eatkyAtdVVE4RltiQ';
  static const maptilerDarkStyle =
      'https://api.maptiler.com/maps/darkmatter/style.json?key=$maptilerKey';
  static const maptilerLightStyle =
      'https://api.maptiler.com/maps/dataviz/style.json?key=$maptilerKey';

  // ─── Supabase ────────────────────────────────────────────────────────────────
  static const supabaseUrl = 'https://zniapgolwcqekcxsmzmk.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_eGB8UK-QTb5Zt2LbhgzFYA_dtiHt47a';

  // ─── Klipy (ricerca GIF nei messaggi) ──────────────────────────────────────────
  // Tenor ha chiuso del tutto l'API il 30/06/2026 — Klipy è l'alternativa più
  // diretta (fondata da ex-Tenor). Key di test gratuita e istantanea su
  // https://partner.klipy.com (100 chiamate/ora); per la produzione va
  // richiesta separatamente dal Partner Panel una volta pronti a lanciare.
  static const klipyApiKey = 'xDO2s7GtPjZinYTa9YwwwlMgnXYbSzpQfRpfGfC0UC3P0VuDCWcsOrXtBC2aj9f2';

  // ─── Map defaults ────────────────────────────────────────────────────────────
  static const defaultLat = 41.9028; // Roma
  static const defaultLng = 12.4964;
  static const discoveryRadiusMeters = 300.0;
}
