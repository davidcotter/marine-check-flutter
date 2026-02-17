import 'dart:typed_data';

/// Web-only image picker fallback.
///
/// On non-web platforms this is not available.
Future<({Uint8List bytes, String name})?> pickWebImage({required bool preferCamera}) async {
  throw UnsupportedError('pickWebImage is only supported on web');
}

