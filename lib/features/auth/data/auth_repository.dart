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

  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) throw const EchoAuthException('Accesso fallito');
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
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': username.trim().toLowerCase(),
          'display_name': displayName?.trim() ?? username.trim(),
        },
      );
      if (response.user == null) throw const EchoAuthException('Registrazione fallita');
      return response.user!;
    } on AuthException catch (e) {
      throw EchoAuthException(_mapAuthError(e.message));
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  String _mapAuthError(String raw) {
    if (raw.contains('Invalid login credentials')) return 'Email o password errata.';
    if (raw.contains('Email not confirmed')) return 'Conferma la tua email prima di accedere.';
    if (raw.contains('User already registered')) return 'Email già registrata.';
    if (raw.contains('Password should be')) return 'La password deve avere almeno 6 caratteri.';
    if (raw.contains('Unable to validate')) return 'Credenziali non valide.';
    return raw;
  }
}
