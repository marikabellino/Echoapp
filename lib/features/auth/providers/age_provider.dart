import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'utente ha meno di 18 anni? Per lui: niente drop pubblici, chat solo con
/// la cerchia, niente drop sugli eventi 18+. Le stesse regole le impone il
/// database (migrazione 036): qui servono solo a spiegarle nell'interfaccia.
final isMinorProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  try {
    final result = await ref
        .watch(supabaseClientProvider)
        .rpc('is_minor', params: {'p_user': user.id});
    return result == true;
  } catch (_) {
    return false;
  }
});
