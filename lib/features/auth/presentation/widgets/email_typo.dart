/// Suggerisce la correzione di un dominio email scritto male
/// (`gmial.com` → `gmail.com`, `hotmail.con` → `hotmail.com`).
///
/// Serve a evitare registrazioni con un indirizzo sbagliato: l'email di
/// conferma non arriverebbe mai e la persona resterebbe bloccata.
library;

const _knownDomains = [
  'gmail.com', 'googlemail.com',
  'hotmail.com', 'hotmail.it', 'outlook.com', 'outlook.it',
  'live.com', 'live.it', 'msn.com',
  'icloud.com', 'me.com', 'mac.com',
  'yahoo.com', 'yahoo.it', 'ymail.com',
  'libero.it', 'virgilio.it', 'alice.it', 'tiscali.it', 'tim.it',
  'fastwebnet.it', 'email.it', 'inwind.it', 'iol.it', 'pec.it',
  'gmx.com', 'gmx.it', 'aol.com', 'proton.me', 'protonmail.com',
];

/// Restituisce l'indirizzo corretto, oppure `null` se sembra giusto
/// (o se il dominio non somiglia a nessuno di quelli più comuni).
String? suggestEmailFix(String email) {
  final e = email.trim().toLowerCase();
  final at = e.lastIndexOf('@');
  if (at <= 0 || at == e.length - 1) return null;
  final local = e.substring(0, at);
  final domain = e.substring(at + 1);
  if (_knownDomains.contains(domain)) return null;

  String? best;
  var bestDist = 99;
  for (final d in _knownDomains) {
    final dist = _distance(domain, d);
    if (dist < bestDist) {
      bestDist = dist;
      best = d;
    }
  }
  // Domini corti: basta una lettera di differenza per essere un altro
  // dominio vero, quindi suggeriamo solo se ne manca/avanza al massimo una.
  final maxDist = domain.length <= 8 ? 1 : 2;
  if (best == null || bestDist == 0 || bestDist > maxDist) return null;
  return '$local@$best';
}

/// Distanza di Damerau-Levenshtein (lettere scambiate contano 1).
int _distance(String a, String b) {
  final d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final t = d[i - 2][j - 2] + 1;
        if (t < v) v = t;
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}
