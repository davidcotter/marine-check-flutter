import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

bool isPWAInstallable() {
  try {
    return js.context.callMethod('isPWAInstallable') == true;
  } catch (e) {
    return false;
  }
}

/// Returns 'granted', 'denied', 'default', or 'unsupported'
String getPushPermission() {
  try {
    return js.context.callMethod('getPushPermission') as String? ?? 'unsupported';
  } catch (e) {
    return 'unsupported';
  }
}

/// Prompts the user for notification permission.
/// Returns 'granted', 'denied', 'default', or 'unsupported'
Future<String> requestPushPermission() async {
  try {
    final promise = js.context.callMethod('requestPushPermission');
    return await js_util.promiseToFuture<String>(promise);
  } catch (e) {
    return 'unsupported';
  }
}

/// Subscribes to push and returns the subscription JSON string, or null on failure.
Future<String?> subscribeToPush(String vapidPublicKey) async {
  try {
    final promise = js.context.callMethod('subscribeToPush', [vapidPublicKey]);
    return await js_util.promiseToFuture<String?>(promise);
  } catch (e) {
    return null;
  }
}

/// Unsubscribes from push notifications.
Future<void> unsubscribeFromPush() async {
  try {
    final promise = js.context.callMethod('unsubscribeFromPush');
    await js_util.promiseToFuture(promise);
  } catch (e) {
    // ignore
  }
}

/// Returns the current push subscription JSON string, or null if not subscribed.
Future<String?> getPushSubscription() async {
  try {
    final promise = js.context.callMethod('getPushSubscription');
    return await js_util.promiseToFuture<String?>(promise);
  } catch (e) {
    return null;
  }
}

Future<String> installPWA() async {
  try {
    final promise = js.context.callMethod('installPWA');
    return await js_util.promiseToFuture(promise);
  } catch (e) {
    return 'error';
  }
}

void onPWAInstallable(VoidCallback callback) {
  js.context['onPWAInstallable'] = js.allowInterop(() {
    callback();
  });
}

void onPWAInstalled(VoidCallback callback) {
  js.context['onPWAInstalled'] = js.allowInterop(() {
    callback();
  });
}
