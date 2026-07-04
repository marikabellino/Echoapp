import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  final SupabaseClient _client;

  AiService(this._client);

  /// Genera una didascalia poetica per un drop.
  Future<String?> generateCaption({
    required String text,
    required String mood,
    String? locationName,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'ai-echo',
        body: {
          'type': 'caption',
          'text': text,
          'mood': mood,
          'location': locationName,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['caption'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Analizza il testo e suggerisce il mood più adatto.
  Future<String?> analyzeMood(String text) async {
    try {
      final response = await _client.functions.invoke(
        'ai-echo',
        body: {'type': 'mood', 'text': text},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['mood'] as String?;
    } catch (_) {
      return null;
    }
  }
}
