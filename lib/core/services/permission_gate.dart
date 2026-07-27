// Android permette una sola richiesta di permessi alla volta per Activity:
// una seconda richiesta partita mentre la prima è ancora in sospeso viene
// scartata silenziosamente (nessun callback, Future mai risolta). Questo gate
// serializza tutte le richieste di permesso dell'app così ognuna parte solo
// dopo che la precedente si è risolta (utente ha risposto al dialog).
class PermissionGate {
  static Future<void> _chain = Future.value();

  static Future<T> run<T>(Future<T> Function() request) {
    final result = _chain.then((_) => request());
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }
}
