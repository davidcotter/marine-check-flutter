import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/js_bridge_web.dart' as js_bridge;

/// Manages Web Push subscription lifecycle for the PWA.
/// Only active on web platform.
class WebPushService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Request permission and subscribe to push notifications.
  /// Returns true if successfully subscribed.
  static Future<bool> subscribe({String? authToken}) async {
    if (!kIsWeb) return false;

    // 1. Request permission
    final permission = await js_bridge.requestPushPermission();
    if (permission != 'granted') return false;

    // 2. Fetch VAPID public key from backend
    final vapidKey = await _fetchVapidKey();
    if (vapidKey == null) return false;

    // 3. Subscribe via browser Push API
    final subJson = await js_bridge.subscribeToPush(vapidKey);
    if (subJson == null) return false;

    final sub = jsonDecode(subJson) as Map<String, dynamic>;
    if (sub.containsKey('error')) {
      debugPrint('WebPush: subscribe error: ${sub['error']}');
      return false;
    }

    // 4. Send subscription to backend
    return await _sendSubscriptionToServer(sub, authToken: authToken);
  }

  /// Unsubscribe from push notifications.
  static Future<void> unsubscribe({String? authToken}) async {
    if (!kIsWeb) return;

    final subJson = await js_bridge.getPushSubscription();
    if (subJson != null) {
      final sub = jsonDecode(subJson) as Map<String, dynamic>;
      final endpoint = sub['endpoint'] as String?;
      if (endpoint != null) {
        await _deleteSubscriptionFromServer(endpoint, authToken: authToken);
      }
    }

    await js_bridge.unsubscribeFromPush();
  }

  /// Returns true if currently subscribed and permission is granted.
  static Future<bool> isSubscribed() async {
    if (!kIsWeb) return false;
    if (js_bridge.getPushPermission() != 'granted') return false;
    final sub = await js_bridge.getPushSubscription();
    return sub != null;
  }

  static Future<String?> _fetchVapidKey() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/push/vapid-public-key');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['vapid_public_key'] as String?;
      }
    } catch (e) {
      debugPrint('WebPush: failed to fetch VAPID key: $e');
    }
    return null;
  }

  static Future<bool> _sendSubscriptionToServer(
    Map<String, dynamic> sub, {
    String? authToken,
  }) async {
    try {
      final keys = sub['keys'] as Map<String, dynamic>?;
      final body = jsonEncode({
        'endpoint': sub['endpoint'],
        'keys': {
          'p256dh': keys?['p256dh'],
          'auth': keys?['auth'],
        },
      });

      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) headers['Authorization'] = 'Bearer $authToken';

      final uri = Uri.parse('$_baseUrl/api/push/subscribe');
      final res = await http.post(uri, headers: headers, body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('WebPush: failed to send subscription: $e');
      return false;
    }
  }

  static Future<void> _deleteSubscriptionFromServer(
    String endpoint, {
    String? authToken,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) headers['Authorization'] = 'Bearer $authToken';

      final uri = Uri.parse('$_baseUrl/api/push/subscribe');
      await http.delete(uri, headers: headers, body: jsonEncode({'endpoint': endpoint}));
    } catch (e) {
      debugPrint('WebPush: failed to delete subscription: $e');
    }
  }
}
