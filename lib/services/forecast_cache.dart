import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marine_data.dart';

/// Cached forecast with timestamp
class CachedForecast {
  final List<HourlyForecast> forecasts;
  final DateTime timestamp;
  final String locationId;

  CachedForecast({
    required this.forecasts,
    required this.timestamp,
    required this.locationId,
  });

  bool get isStale {
    final age = DateTime.now().difference(timestamp);
    return age.inMinutes > 15; // 15-minute cache expiry
  }

  Map<String, dynamic> toJson() => {
    'forecasts': forecasts.map((f) => f.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'locationId': locationId,
  };

  factory CachedForecast.fromJson(Map<String, dynamic> json) => CachedForecast(
    forecasts: (json['forecasts'] as List).map((f) => HourlyForecast.fromJson(f)).toList(),
    timestamp: DateTime.parse(json['timestamp']),
    locationId: json['locationId'],
  );
}

class ForecastCache {
  static const _prefix = 'forecast_cache_';

  /// Get cached forecast for a location
  Future<CachedForecast?> get(String locationId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_prefix$locationId');
    if (data == null) return null;

    try {
      return CachedForecast.fromJson(json.decode(data));
    } catch (e) {
      print('Cache parse error: $e');
      return null;
    }
  }

  /// Save forecast to cache
  Future<void> save(String locationId, List<HourlyForecast> forecasts) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = CachedForecast(
      forecasts: forecasts,
      timestamp: DateTime.now(),
      locationId: locationId,
    );
    await prefs.setString('$_prefix$locationId', json.encode(cached.toJson()));
  }

  /// Check if cache is stale
  Future<bool> isStale(String locationId) async {
    final cached = await get(locationId);
    return cached?.isStale ?? true;
  }

  /// Clear cache for a location
  Future<void> clear(String locationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$locationId');
  }

  /// Clear all cached forecasts
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Get last updated time for a location
  Future<DateTime?> getLastUpdated(String locationId) async {
    final cached = await get(locationId);
    return cached?.timestamp;
  }
}
