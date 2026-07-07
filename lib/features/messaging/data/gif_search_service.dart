import 'dart:convert';

import 'package:echo/core/constants/app_constants.dart';
import 'package:http/http.dart' as http;

class GifResult {
  final String id;
  final String previewUrl;
  final String fullUrl;

  const GifResult({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
  });
}

// Ricerca GIF via Klipy API (https://klipy.com/developers) — Tenor ha
// chiuso completamente l'API il 30/06/2026.
class GifSearchService {
  static String get _base =>
      'https://api.klipy.com/api/v1/${AppConstants.klipyApiKey}/gifs';

  Future<List<GifResult>> trending({int limit = 24}) =>
      _fetch(Uri.parse('$_base/trending?per_page=$limit'));

  Future<List<GifResult>> search(String query, {int limit = 24}) => _fetch(
    Uri.parse(
      '$_base/search?q=${Uri.encodeComponent(query)}&per_page=$limit',
    ),
  );

  Future<List<GifResult>> _fetch(Uri uri) async {
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'];
      final items = (data is Map<String, dynamic> ? data['data'] : data)
          as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((r) {
            final item = r as Map<String, dynamic>;
            final file = item['file'] as Map<String, dynamic>?;
            if (file == null) return null;

            final xs = file['xs'] as Map<String, dynamic>?;
            final hd = file['hd'] as Map<String, dynamic>?;
            final previewUrl =
                (xs?['jpg'] as Map<String, dynamic>?)?['url'] as String?;
            final fullUrl =
                ((hd?['gif'] as Map<String, dynamic>?)?['url'] as String?) ??
                (file['gif'] as Map<String, dynamic>?)?['url'] as String? ??
                previewUrl;
            if (fullUrl == null) return null;

            return GifResult(
              id: '${item['id']}',
              previewUrl: previewUrl ?? fullUrl,
              fullUrl: fullUrl,
            );
          })
          .whereType<GifResult>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
