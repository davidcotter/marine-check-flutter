import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io'; 

import '../models/marine_data.dart';
import '../models/notification_schedule.dart'; // Added
import '../services/marine_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../utils/unit_converter.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Platform.isAndroid) {
        // Initialize simple services if needed
      }

      final prefs = await SharedPreferences.getInstance();
      
      // 1. Check if notifications are enabled
      final enabled = prefs.getBool('notifications_enabled') ?? false; // Hardcoded key from SettingsService
      if (!enabled) {
        return Future.value(true);
      }

      // 2. Check Time Window
      // 2. Check Time Windows & Schedules
      List<String> scheduleJsonList = prefs.getStringList('notification_schedules') ?? [];
      List<NotificationSchedule> schedules = [];
      
      if (scheduleJsonList.isEmpty) {
         // Fallback/Migration handled in SettingsService, but here we might just have empty if nothing set.
      } else {
         schedules = scheduleJsonList.map((e) => NotificationSchedule.fromJson(e)).toList();
      }

      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month}-${now.day}';
      final sentSlotsKey = 'sent_slots_$todayStr'; 
      final sentSlots = prefs.getStringList(sentSlotsKey) ?? [];
      
      NotificationSchedule? targetSchedule;
      String? targetTimeSlot; // "HH:mm" identifier
      
      for (final schedule in schedules) {
         final timeStr = schedule.timeString;
         if (sentSlots.contains(timeStr)) continue;
         
         // Check Day of Week (1=Mon ... 7=Sun)
         if (!schedule.days.contains(now.weekday)) continue;

         final targetHour = schedule.time.hour;
         
         // Logic: Send if now >= targetHour AND within 3 hours
         if (now.hour >= targetHour && now.hour < targetHour + 3) {
            targetSchedule = schedule;
            targetTimeSlot = timeStr;
            break; 
         }
      }

      if (targetSchedule == null || targetTimeSlot == null) {
         // No pending notifications for now
         return Future.value(true);
      }
      
      // We have a target time (targetTimeSlot). Use its hour for data fetching?
      // Actually we should fetch data relevant to the "surf check".
      // Usually "now" is fine, or the specific target hour.
      // Let's us "now" as it's a "live" check.
      // But we need to save *which* slot we sent.

      // 3. Fetch Data & Calculate Averages (Next 2 Hours)
      final locationService = LocationService();
      final savedLocation = await locationService.getSelectedLocation();
      
      final location = Location(
        id: savedLocation.id,
        name: savedLocation.name,
        lat: savedLocation.lat,
        lon: savedLocation.lon,
        waterLat: savedLocation.waterLat,
        waterLon: savedLocation.waterLon,
      );

      final marineService = MarineService();
      final result = await marineService.getForecasts(location, forceRefresh: true);
      
      // Update refined water location if found
      if (result.refinedLocation != null) {
        final updated = SavedLocation(
          id: savedLocation.id,
          name: savedLocation.name,
          lat: savedLocation.lat,
          lon: savedLocation.lon,
          isCurrentLocation: savedLocation.isCurrentLocation,
          addedAt: savedLocation.addedAt,
          waterLat: result.refinedLocation!.waterLat,
          waterLon: result.refinedLocation!.waterLon,
        );
        await locationService.updateLocation(updated);
      }
      // The user wants the notification NOW, but the data for (Now + Offset)
      final offsetHours = targetSchedule.forecastOffset;
      final targetForecastTime = now.add(Duration(hours: offsetHours));
      
      // Get forecasts for the next 2 hours average STARTING at the offset time
      List<HourlyForecast> upcoming = result.forecasts.where((f) => 
        f.time.hour >= targetForecastTime.hour && f.time.hour < targetForecastTime.hour + 2
      ).toList();

      if (upcoming.isEmpty) {
         // Fallback to closest available if we go beyond today's data (e.g. +8h into tomorrow)
         // Our API usually fetches 7 days so this should be fine unless it's way later.
         try {
           upcoming = [result.forecasts.firstWhere((f) => f.time.isAfter(targetForecastTime.subtract(const Duration(minutes: 30))))];
         } catch (_) {
           if (result.forecasts.isNotEmpty) upcoming = [result.forecasts.last];
         }
      }

      if (upcoming.isEmpty) return Future.value(true);
      
      // Calculate Averages
      // Roughness: Average index -> then back to status
      final avgRoughness = (upcoming.map((f) => f.swimCondition.roughnessIndex).reduce((a, b) => a + b) / upcoming.length).round();
      final avgStatus = UnitConverter.getRoughnessStatus(avgRoughness); // This gives us strict/calm/etc
      // Map back to SwimCondition status enum best we can? 
      // Actually UnitConverter `roughnessIndex` 0=Calm, 1=Medium, 2=Rough, 3=Unsafe.
      // So avgStatus.label or color is useful.
      // Let's assume index 0=Calm, 1=Medium etc for logic.
      
      bool isGoodConditions = avgRoughness <= 1; // 0 or 1 is Calm or Medium

      // Tide: Check if HIGH tide is present in the window OR average percentage > 75%
      // Let's use average percentage logic
      final tideCount = upcoming.where((f) => f.tide != null).length;
      bool isHighTide = false;
      String tideString = '--';
      
      if (tideCount > 0) {
         final avgPct = upcoming.where((f) => f.tide != null)
                                .map((f) => f.tide!.percentage)
                                .reduce((a, b) => a + b) / tideCount;
         isHighTide = avgPct >= 75;
         tideString = upcoming.first.tide!.isRising ? "Rising" : "Falling"; // Just take first for direction
      }

      // Rain: Average precipitation probability
      final avgPrecip = upcoming.map((f) => f.weather.precipitationProbability).reduce((a, b) => a + b) / upcoming.length;
      final isLowRain = avgPrecip < 10;


      // 4. Apply Filters
      final goodOnly = targetSchedule.goodConditionsOnly;
      final highTideOnly = targetSchedule.highTideOnly;
      final lowRainOnly = targetSchedule.lowRainOnly;

      // Filter: Good Conditions
      if (goodOnly && !isGoodConditions) {
        if (targetTimeSlot != null) {
          sentSlots.add(targetTimeSlot);
          await prefs.setStringList(sentSlotsKey, sentSlots);
        }
        return Future.value(true);
      }

      // Filter: High Tide
      if (highTideOnly && !isHighTide) {
         if (targetTimeSlot != null) {
            sentSlots.add(targetTimeSlot);
            await prefs.setStringList(sentSlotsKey, sentSlots);
         }
         return Future.value(true);
      }

      // Filter: Low Rain
      if (lowRainOnly && !isLowRain) {
         if (targetTimeSlot != null) {
            sentSlots.add(targetTimeSlot);
            await prefs.setStringList(sentSlotsKey, sentSlots);
         }
         return Future.value(true);
      }

      // 5. Build Notification
      final emojis = {
        0: '🟢', // Calm
        1: '🔵', // Medium
        2: '🟠', // Rough
        3: '🔴', // Unsafe
      };
      
      final emoji = emojis[avgRoughness] ?? '🌊';
      final statusLabel = avgStatus.label;
      
      // Determine time label for notification
      String timeLabel = "Now";
      if (offsetHours > 0) {
        timeLabel = '${targetForecastTime.hour.toString().padLeft(2, '0')}:00';
      }
      
      // Build body
      String body = '$emoji Status: $statusLabel (For $timeLabel)\n';
      // Average swell?
      final avgSwell = upcoming.map((f) => f.swell.height).reduce((a, b) => a + b) / upcoming.length;
      body += '🌊 Swell: ${avgSwell.toStringAsFixed(1)}m';
      
      if (tideCount > 0) {
         body += ' | Tide: $tideString';
      }
      body += ' | Rain: ${avgPrecip.toStringAsFixed(0)}%';
      
      await NotificationService().init();
      await NotificationService().showNotification(
        id: 1, 
        title: 'Marine Check: ${location.name}',
        body: body,
      );

      // Mark as sent
      if (targetTimeSlot != null) {
        sentSlots.add(targetTimeSlot);
        await prefs.setStringList(sentSlotsKey, sentSlots);
      }

      return Future.value(true);
      
    } catch (e) {
      debugPrint('Background Task Error: $e');
      return Future.value(false);
    }
  });
}

class BackgroundService {
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true for testing
      );
    } catch (e) {
      debugPrint('BackgroundService init failed: $e');
    }
  }

  static Future<void> registerPeriodicTask() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerPeriodicTask(
        "marine_check_daily_check",
        "dailyWeatherCheck",
        frequency: const Duration(hours: 1), // Check every hour
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('Register task failed: $e');
    }
  }
  
  static Future<void> cancelTasks() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      debugPrint('Cancel tasks failed: $e');
    }
  }
}
