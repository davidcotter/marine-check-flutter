import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<({Uint8List bytes, String name})?> pickWebImage({required bool preferCamera}) async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.style.display = 'none';

  // Hint to mobile browsers to open camera capture UI.
  if (preferCamera) {
    input.setAttribute('capture', 'environment');
  }

  html.document.body?.append(input);

  try {
    // Must be invoked from a user gesture.
    input.click();

    // Wait for selection.
    await input.onChange.first;

    final files = input.files;
    if (files == null || files.isEmpty) return null;

    final file = files.first;
    final reader = html.FileReader();

    // Use onLoadEnd (more reliable across browsers than onLoad).
    final loadFuture = reader.onLoadEnd.first;
    final errorFuture =
        reader.onError.first.then((_) => throw StateError('Failed to read selected file'));

    reader.readAsArrayBuffer(file);

    // Race load vs error, with a timeout so we never hang silently.
    await Future.any([loadFuture, errorFuture]).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('Timed out reading selected file'),
    );

    final result = reader.result;
    Uint8List raw;
    if (result is ByteBuffer) {
      raw = Uint8List.view(result);
    } else if (result is Uint8List) {
      raw = result;
    } else {
      throw StateError('Unexpected file read result: ${result.runtimeType}');
    }

    final processed = await _compressForShare(raw);
    return (bytes: processed, name: _jpegName(file.name));
  } finally {
    input.remove();
  }
}

Future<Uint8List> _compressForShare(Uint8List bytes) async {
  try {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final img = html.ImageElement(src: url);
    await img.onLoad.first.timeout(const Duration(seconds: 10));

    final maxDim = 1400;
    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      html.Url.revokeObjectUrl(url);
      return bytes;
    }

    final scale = (w > h ? maxDim / w : maxDim / h);
    final targetW = scale < 1 ? (w * scale).round() : w;
    final targetH = scale < 1 ? (h * scale).round() : h;

    final canvas = html.CanvasElement(width: targetW, height: targetH);
    final ctx = canvas.context2D;
    ctx.drawImageScaled(img, 0, 0, targetW.toDouble(), targetH.toDouble());

    final outBlob = await canvas.toBlob('image/jpeg', 0.82);
    html.Url.revokeObjectUrl(url);
    if (outBlob == null) return bytes;

    final outReader = html.FileReader();
    final done = Completer<Uint8List>();
    outReader.onLoadEnd.listen((_) {
      final r = outReader.result;
      if (r is ByteBuffer) {
        done.complete(Uint8List.view(r));
      } else if (r is Uint8List) {
        done.complete(r);
      } else {
        done.complete(bytes);
      }
    });
    outReader.onError.listen((_) => done.complete(bytes));
    outReader.readAsArrayBuffer(outBlob);
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () => bytes);
  } catch (_) {
    return bytes;
  }
}

String _jpegName(String original) {
  final dot = original.lastIndexOf('.');
  if (dot <= 0) return '$original.jpg';
  return '${original.substring(0, dot)}.jpg';
}

