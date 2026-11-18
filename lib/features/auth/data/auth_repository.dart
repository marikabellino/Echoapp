import 'package:echo/core/constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EchoAuthException implements Exception {
  final String message;
  const EchoAuthException(this.message);

  @override
  String toString() => message;
}

class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null)
        throw const EchoAuthException('Accesso fallito');
      return response.user!;
    } on AuthException catch (e) {
      throw EchoAuthException(_mapAuthError(e.message));
    }
  }

  Future<User> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
    Map<String, Object?> consent = const {},
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': username.trim().toLowerCase(),
          'display_name': displayName?.trim() ?? username.trim(),
          ...consent,
        },
        emailRedirectTo: '${AppConstants.authLandingUrl}?flow=signup',
      );
      if (response.user == null)
        throw const EchoAuthException('Registrazione fallita');
      return response.user!;
    } on AuthException catch (e) {
      throw EchoAuthException(_mapAuthError(e.message));
    }
  }

  /// True se nessun profilo usa già [username] (confronto case-insensitive,
  /// come lo salva signUp). `_` è un jolly in ILIKE: va escapato.
  Future<bool> isUsernameAvailable(String username) async {
    final normalized = username.trim().toLowerCase();
    final pattern = normalized.replaceAll('_', r'\_');
    final rows = await _client
        .from('profiles')
        .select('id')
        .ilike('username', pattern)
        .limit(1);
    return (rows as List).isEmpty;
  }

  /// Sganciare il token FCM da questo profilo prima del signOut: altrimenti
  /// il device resta agganciato all'account uscito e continua a ricevere le
  /// sue push finché un altro utente non fa login sullo stesso device (o
  /// finché questo stesso utente non rientra e lo sovrascrive).
  Future<void> signOut() async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await _client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', userId);
      } catch (e) {
        debugPrint(
          'AuthRepository: impossibile azzerare fcm_token per $userId — $e',
        );
      }
    }
    await _client.auth.signOut();
  }

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: '${AppConstants.authLandingUrl}?flow=reset',
      );

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw EchoAuthException(_mapAuthError(e.message));
    }
  }

  /// Elimina l'account dell'utente corrente tramite la funzione PostgreSQL
  /// `delete_account()` (SECURITY DEFINER) che rimuove la riga da auth.users
  /// e a cascata tutti i dati collegati.
  Future<void> deleteAccount() async {
    try {
      await _deleteOwnFiles();
      await _client.rpc('delete_account');
      await _client.auth.signOut();
    } catch (_) {
      throw const EchoAuthException(
        'Impossibile eliminare l\'account. Riprova più tardi.',
      );
    }
  }

  Future<void> _deleteOwnFiles() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    for (final bucket in const ['memories', 'avatars']) {
      while (true) {
        final files = await _client.storage
            .from(bucket)
            .list(path: userId, searchOptions: const SearchOptions(limit: 100));
        if (files.isEmpty) break;
        await _client.storage.from(bucket).remove([
          for (final f in files) '$userId/${f.name}',
        ]);
        if (files.length < 100) break;
      }
    }
  }

  String _mapAuthError(String raw) {
    if (raw.contains('Invalid login credentials'))
      return 'Email o password errata.';
    if (raw.contains('Email not confirmed'))
      return 'Conferma la tua email prima di accedere.';
    if (raw.contains('User already registered')) return 'Email già registrata.';
    // Il trigger handle_new_user fallisce sul vincolo unique di
    // profiles.username (es. due persone che lo scelgono nello stesso istante).
    if (raw.contains('Database error saving new user'))
      return 'Questo username è già in uso. Scegline un altro.';
    if (raw.contains('Password should be'))
      return 'La password deve avere almeno 6 caratteri.';
    if (raw.contains('Unable to validate')) return 'Credenziali non valide.';
    return raw;
  }
}
