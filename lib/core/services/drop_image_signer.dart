import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Foto dei drop con link temporanei firmati.
///
/// Il bucket `memories` è privato (033_private_drop_photos.sql): una foto si
/// può aprire solo con un link firmato, e Supabase lo concede solo a chi può
/// vedere il drop che la contiene (stesse regole di cerchia, blocchi ed
/// eventi). Nel database `image_url` resta il vecchio indirizzo "pubblico":
/// serve solo come identificativo da cui ricavare il percorso del file.
///
/// I link valgono [_ttl]: chi esce dalla cerchia o viene bloccato smette di
/// ricevere link nuovi, e quelli che aveva scadono entro quel tempo.
class DropImageSigner {
  DropImageSigner._();
  static final instance = DropImageSigner._();

  static const _bucket = 'memories';
  static const _ttl = Duration(hours: 2);
  // Un link che scade a breve viene rinnovato in anticipo.
  static const _renewBefore = Duration(minutes: 10);

  final _cache = <String, ({String url, DateTime expiresAt})>{};
  // I link firmati valgono per l'utente che li ha chiesti: se cambia
  // account, la cache si svuota.
  String? _cacheOwner;

  /// Percorso del file nel bucket (`<userId>/<token>.jpg`), ricavato sia dai
  /// vecchi link pubblici sia dai link firmati. `null` se non è una foto dei
  /// drop.
  static String? pathFromUrl(String? url) {
    if (url == null) return null;
    for (final marker in const [
      '/object/public/$_bucket/',
      '/object/sign/$_bucket/',
      '/object/authenticated/$_bucket/',
    ]) {
      final i = url.indexOf(marker);
      if (i != -1) {
        final rest = url.substring(i + marker.length);
        final q = rest.indexOf('?');
        return Uri.decodeComponent(q == -1 ? rest : rest.substring(0, q));
      }
    }
    return null;
  }

  /// Chiave stabile per la cache delle immagini sul telefono: il link
  /// firmato cambia, il file no. Così una foto già scaricata non si
  /// riscarica a ogni rinnovo del link e resta visibile anche offline.
  static String cacheKey(String url) {
    final path = pathFromUrl(url);
    return path == null ? url : '$_bucket/$path';
  }

  /// Sostituisce `imageUrl` di ogni drop con un link firmato, con una sola
  /// richiesta per tutte le foto che non hanno già un link valido.
  /// - foto non accessibile → `imageUrl` diventa `null` (niente foto rotta);
  /// - rete assente → resta l'indirizzo originale: la foto si vede lo
  ///   stesso se è già nella cache del telefono (stessa [cacheKey]).
  Future<List<DropModel>> signDrops(
    SupabaseClient client,
    List<DropModel> drops,
  ) async {
    if (drops.isEmpty) return drops;
    final me = client.auth.currentUser?.id;
    if (me != _cacheOwner) {
      _cache.clear();
      _cacheOwner = me;
    }
    final now = DateTime.now();

    final missing = <String>{};
    for (final d in drops) {
      final path = pathFromUrl(d.imageUrl);
      if (path == null) continue;
      final hit = _cache[path];
      if (hit == null || hit.expiresAt.difference(now) < _renewBefore) {
        missing.add(path);
      }
    }

    final denied = <String>{};
    if (missing.isNotEmpty) {
      final paths = missing.toList();
      try {
        final signed = await client.storage
            .from(_bucket)
            .createSignedUrls(paths, _ttl.inSeconds);
        final expiresAt = now.add(_ttl);
        for (var i = 0; i < signed.length; i++) {
          // Abbiniamo per percorso quando Supabase lo restituisce; altrimenti
          // per posizione (la risposta segue l'ordine della richiesta).
          final path = signed[i].path.isNotEmpty
              ? signed[i].path
              : (i < paths.length ? paths[i] : null);
          if (path == null || !missing.contains(path)) continue;
          final url = signed[i].signedUrl;
          // Senza permesso Supabase non restituisce il link (la libreria
          // lo trasforma in ".../storage/v1null").
          if (url.endsWith('null') || !url.contains('token=')) {
            denied.add(path);
            _cache.remove(path);
          } else {
            _cache[path] = (url: url, expiresAt: expiresAt);
          }
        }
      } catch (_) {
        // Offline o errore temporaneo: si useranno cache e indirizzo originale.
      }
    }

    return [for (final d in drops) _apply(d, pathFromUrl(d.imageUrl), denied)];
  }

  Future<DropModel> signDrop(SupabaseClient client, DropModel drop) async =>
      (await signDrops(client, [drop])).first;

  DropModel _apply(DropModel d, String? path, Set<String> denied) {
    if (path == null) return d;
    if (denied.contains(path)) return d.copyWith(clearImage: true);
    final hit = _cache[path];
    return hit == null ? d : d.copyWith(imageUrl: hit.url);
  }

  /// Svuota la cache dei link (es. al logout).
  void clear() {
    _cache.clear();
    _cacheOwner = null;
  }
}
