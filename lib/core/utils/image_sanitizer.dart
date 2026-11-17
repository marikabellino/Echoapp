import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> stripImageMetadata(Uint8List bytes) =>
    compute(_reencode, bytes);

Uint8List _reencode(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Immagine non valida');
  }
  final oriented = img.bakeOrientation(decoded);
  oriented.exif = img.ExifData();
  return img.encodeJpg(oriented, quality: 85);
}
