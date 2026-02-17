import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _fcmToken;
  
  // Local notifications
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Legacy API support for background_service.dart
  Future<void> init() async => initialize();

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();

      // Request FCM permissions
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted notification permission');
        _fcmToken = await _messaging.getToken();
        print('FCM Token: $_fcmToken');
        
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('Loaded foreground message: ${message.notification?.title}');
          // Optionally show a local notification here when in foreground
          if (message.notification != null) {
            NotificationService().showNotification(
              id: message.hashCode,
              title: message.notification!.title ?? '',
              body: message.notification!.body ?? '',
            );
          }
        });
      }

      // Initialize local notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
          
      const InitializationSettings initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );

      if (kIsWeb) return;

      await _localNotifications.initialize(
        settings: initializationSettings,
      );
    } catch (e) {
      print('Notification Service initialization error: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'marine_check_alerts',
      'Marine Check Alerts',
      channelDescription: 'Weather and tide alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }

  static String? get fcmToken => _fcmToken;

  static Future<void> uploadTokenToServer() async {
    if (_fcmToken == null) return;
    // TODO: Implement server sync
  }
}
