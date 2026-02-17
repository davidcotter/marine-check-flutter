import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_schedule.dart';

class SettingsService {
  static const String _keyShowNext2Hours = 'show_next_2_hours';
  static const String _keyWindUnit = 'unit_wind';
  static const String _keyTempUnit = 'unit_temp';
  static const String _keyHeightUnit = 'unit_height';
  static const String _keyThemeMode = 'pref_theme_mode';
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyNotificationSchedules = 'notification_schedules';
  static const String _keyNotifyGoodOnly = 'notify_good_only'; // kept for migration

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
    
    // Migration: Check for old single notification time
    if (_prefs!.containsKey('notification_time')) {
      final oldTime = _prefs!.getString('notification_time');
      if (oldTime != null) {
        // Create schedule from old time
        final goodOnly = _prefs!.getBool(_keyNotifyGoodOnly) ?? true;
        final parts = oldTime.split(':');
        final schedule = NotificationSchedule(
          time: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
          goodConditionsOnly: goodOnly,
        );
        await setNotificationSchedules([schedule]);
      }
      await _prefs!.remove('notification_time');
    }
    
    // Migration: Check for notification_times list (intermediate step)
    if (_prefs!.containsKey('notification_times')) {
       final oldTimes = _prefs!.getStringList('notification_times') ?? [];
       final goodOnly = _prefs!.getBool(_keyNotifyGoodOnly) ?? true;
       final schedules = oldTimes.map((t) {
          final parts = t.split(':');
          return NotificationSchedule(
            time: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
            goodConditionsOnly: goodOnly,
          );
       }).toList();
       if (schedules.isNotEmpty) {
         await setNotificationSchedules(schedules);
       }
       await _prefs!.remove('notification_times');
    }
    } catch (e) {
      // If SharedPreferences fails, _prefs stays null.
      // All getters use ?. and ?? so they'll return safe defaults.
      _prefs = null;
    }
  }

  static bool get showNext2Hours => _prefs?.getBool(_keyShowNext2Hours) ?? true;
  static Future<void> setShowNext2Hours(bool value) async => await _prefs?.setBool(_keyShowNext2Hours, value);

  // Wind Unit
  static WindUnit get windUnit {
    final index = _prefs?.getInt(_keyWindUnit) ?? WindUnit.kmh.index;
    return WindUnit.values[index];
  }
  static Future<void> setWindUnit(WindUnit value) async => await _prefs?.setInt(_keyWindUnit, value.index);

  // Temp Unit
  static TempUnit get tempUnit {
    final index = _prefs?.getInt(_keyTempUnit) ?? TempUnit.celsius.index;
    return TempUnit.values[index];
  }
  static Future<void> setTempUnit(TempUnit value) async => await _prefs?.setInt(_keyTempUnit, value.index);

  // Height Unit
  static HeightUnit get heightUnit {
    final index = _prefs?.getInt(_keyHeightUnit) ?? HeightUnit.meters.index;
    return HeightUnit.values[index];
  }
  static Future<void> setHeightUnit(HeightUnit value) async => await _prefs?.setInt(_keyHeightUnit, value.index);

  // Theme Mode
  static AppThemeMode get themeMode {
    final index = _prefs?.getInt(_keyThemeMode) ?? AppThemeMode.system.index;
    return AppThemeMode.values[index];
  }
  static Future<void> setThemeMode(AppThemeMode value) async => await _prefs?.setInt(_keyThemeMode, value.index);

  // Notifications
  static bool get notificationsEnabled => _prefs?.getBool(_keyNotificationsEnabled) ?? false;
  static Future<void> setNotificationsEnabled(bool value) async => await _prefs?.setBool(_keyNotificationsEnabled, value);

  static List<NotificationSchedule> get notificationSchedules {
    final list = _prefs?.getStringList(_keyNotificationSchedules);
    if (list == null) {
       return [NotificationSchedule(time: const TimeOfDay(hour: 9, minute: 0))];
    }
    return list.map((e) => NotificationSchedule.fromJson(e)).toList();
  }
  
  static Future<void> setNotificationSchedules(List<NotificationSchedule> values) async {
     await _prefs?.setStringList(_keyNotificationSchedules, values.map((e) => e.toJson()).toList());
  }
}

enum WindUnit { kmh, knots, mph, ms, beaufort }
enum TempUnit { celsius, fahrenheit }
enum HeightUnit { meters, feet }
enum AppThemeMode { system, light, dark }
