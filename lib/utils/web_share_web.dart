import 'dart:js_util' as js_util;
import 'dart:html' as html;
import 'dart:typed_data';

/// Returns true if the Web Share API was invoked successfully.
Future<bool> shareText(String text) async {
  final nav = html.window.navigator;
  if (!js_util.hasProperty(nav, 'share')) return false;
  try {
    final shareData = js_util.jsify({'text': text});
    await js_util.promiseToFuture<void>(
      js_util.callMethod(nav, 'share', [shareData]),
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Share an image file via the Web Share API.
/// Returns true if shared successfully.
Future<bool> shareImage(Uint8List pngBytes, String filename, String text) async {
  final nav = html.window.navigator;
  if (!js_util.hasProperty(nav, 'share')) return false;
  // Check canShare with files
  try {
    final file = html.File([pngBytes], filename, {'type': 'image/png'});
    final filesArray = js_util.jsify([file]);
    final canShareData = js_util.jsify({'files': filesArray});
    final canShare = js_util.callMethod(nav, 'canShare', [canShareData]);
    if (canShare != true) return false;

    final shareData = js_util.jsify({
      'files': [file],
      'text': text,
    });
    await js_util.promiseToFuture<void>(
      js_util.callMethod(nav, 'share', [shareData]),
    );
    return true;
  } catch (_) {
    return false;
  }
}
