import 'package:echo/core/services/drop_image_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'https://abc.supabase.co/storage/v1/object';
  const path = '11111111-2222-3333-4444-555555555555/0a1b2c3d.jpg';

  group('DropImageSigner.pathFromUrl', () {
    test('vecchio link pubblico', () {
      expect(
        DropImageSigner.pathFromUrl('$base/public/memories/$path'),
        path,
      );
    });

    test('link firmato con token', () {
      expect(
        DropImageSigner.pathFromUrl('$base/sign/memories/$path?token=eyJhbGci'),
        path,
      );
    });

    test('percorso con caratteri codificati', () {
      expect(
        DropImageSigner.pathFromUrl('$base/sign/memories/u/a%20b.jpg?token=x'),
        'u/a b.jpg',
      );
    });

    test('non è una foto dei drop', () {
      expect(DropImageSigner.pathFromUrl(null), isNull);
      expect(
        DropImageSigner.pathFromUrl('$base/public/avatars/u/me.jpg'),
        isNull,
      );
      expect(DropImageSigner.pathFromUrl('https://klipy.com/gif.gif'), isNull);
    });
  });

  test('cacheKey uguale per link pubblico e firmato dello stesso file', () {
    final a = DropImageSigner.cacheKey('$base/public/memories/$path');
    final b = DropImageSigner.cacheKey('$base/sign/memories/$path?token=1');
    final c = DropImageSigner.cacheKey('$base/sign/memories/$path?token=2');
    expect(a, b);
    expect(b, c);
    expect(a, 'memories/$path');
  });
}
