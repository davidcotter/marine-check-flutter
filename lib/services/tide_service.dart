import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/marine_data.dart';

/// Tide data from Marine Institute
// TidePoint renamed to TideData and moved to marine_data.dart

/// Moon phase data
class MoonPhase {
  final String phase;
  final String icon;
  final bool isSpringTide;

  MoonPhase({
    required this.phase,
    required this.icon,
    required this.isSpringTide,
  });
}

class TideService {
  static const _baseUrl = 'https://erddap.marine.ie/erddap/tabledap/imiTidePrediction.json';
  
  /// Known tide stations (matching Expo app)
  static const Map<String, Map<String, dynamic>> stations = {
    'Tramore': {'lat': 52.1500, 'lon': -6.9833, 'stationId': 'Dunmore'},
    'Dublin Port': {'lat': 53.3467, 'lon': -6.2000, 'stationId': 'Dublin_Port'},
    'Cork': {'lat': 51.8500, 'lon': -8.3000, 'stationId': 'Ringaskiddy'},
    'Galway': {'lat': 53.2700, 'lon': -9.0500, 'stationId': 'Galway'},
    'Sligo': {'lat': 54.2766, 'lon': -8.4761, 'stationId': 'Sligo'},
  };

  /// Find nearest tide station to a location
  static String findNearestStation(double lat, double lon) {
    String nearest = 'Tramore';
    double minDist = double.infinity;

    for (final entry in stations.entries) {
      final sLat = entry.value['lat'] as double;
      final sLon = entry.value['lon'] as double;
      final dist = (lat - sLat) * (lat - sLat) + (lon - sLon) * (lon - sLon);
      if (dist < minDist) {
        minDist = dist;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  /// Fetch tide data for a location
  Future<({List<TideData> tides, String stationName})> fetchTides(double lat, double lon, {int days = 7}) async {
    final stationName = findNearestStation(lat, lon);
    final stationId = stations[stationName]!['stationId'];
    
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 1)).copyWith(hour: 0, minute: 0, second: 0); // Start from yesterday sharp
    final end = now.add(Duration(days: days));

    final startStr = start.toIso8601String().replaceAll('.000', '');
    final endStr = end.toIso8601String().replaceAll('.000', '');

    final encodedStation = Uri.encodeComponent('"$stationId"');
    final rawQuery = 'time,Water_Level&stationID=$encodedStation&time>=$startStr&time<=$endStr&orderBy("time")';

    // On web, call Marine Institute directly — they send CORS: *
    final uri = Uri.parse('$_baseUrl?$rawQuery');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Tide API error: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final table = data['table'] as Map<String, dynamic>;
      final rows = table['rows'] as List;

      final tides = <TideData>[];
      double? prevLevel;
      double minLevel = double.infinity;
      double maxLevel = double.negativeInfinity;

      // First pass: find min/max
      for (final row in rows) {
        final level = (row[1] as num).toDouble();
        minLevel = min(minLevel, level);
        maxLevel = max(maxLevel, level);
      }

      // Second pass: build tide points (sharp hours only to match weather)
      for (final row in rows) {
        final timeStr = row[0] as String;
        final time = DateTime.parse(timeStr);
        
        // Match Expo logic: only take sharp hours
        if (time.minute == 0) {
          final level = (row[1] as num).toDouble();
          
          final percentage = maxLevel > minLevel
              ? ((level - minLevel) / (maxLevel - minLevel) * 100).round()
              : 50;

          bool isRising = true; // Default
          if (prevLevel != null) {
             isRising = level > prevLevel;
          }

          String status;
          if (percentage >= 75) {
             status = 'high';
          } else if (percentage <= 25) {
             status = 'low';
          } else {
             status = isRising ? 'rising' : 'falling';
          }

          tides.add(TideData(
            time: time,
            level: level,
            status: status,
            percentage: percentage,
            isRising: isRising,
          ));
          prevLevel = level;
        }
      }

      print('TideService: Parsed ${tides.length} hourly entries');
      return (tides: tides, stationName: stationName);
    } catch (e) {
      print('Error fetching tides: $e');
      return (tides: <TideData>[], stationName: stationName);
    }
  }

  /// Calculate moon phase for a date
  static MoonPhase calculateMoonPhase(DateTime date) {
    // Julian date calculation for moon phase
    final year = date.year;
    final month = date.month;
    final day = date.day;

    int a = ((14 - month) / 12).floor();
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;

    double jd = day + ((153 * m + 2) / 5).floor() + 365 * y + (y / 4).floor() - (y / 100).floor() + (y / 400).floor() - 32045;

    // Moon cycle ~29.53 days
    const lunarCycle = 29.530588;
    const knownNewMoon = 2451550.1; // Jan 6, 2000 was a new moon

    double daysSinceNew = (jd - knownNewMoon) % lunarCycle;
    double phaseRatio = daysSinceNew / lunarCycle;

    // Determine phase
    String phase;
    String icon;
    bool isSpringTide = false;

    if (phaseRatio < 0.0625) {
      phase = 'New Moon';
      icon = '🌑';
      isSpringTide = true;
    } else if (phaseRatio < 0.1875) {
      phase = 'Waxing Crescent';
      icon = '🌒';
    } else if (phaseRatio < 0.3125) {
      phase = 'First Quarter';
      icon = '🌓';
    } else if (phaseRatio < 0.4375) {
      phase = 'Waxing Gibbous';
      icon = '🌔';
    } else if (phaseRatio < 0.5625) {
      phase = 'Full Moon';
      icon = '🌕';
      isSpringTide = true;
    } else if (phaseRatio < 0.6875) {
      phase = 'Waning Gibbous';
      icon = '🌖';
    } else if (phaseRatio < 0.8125) {
      phase = 'Last Quarter';
      icon = '🌗';
    } else if (phaseRatio < 0.9375) {
      phase = 'Waning Crescent';
      icon = '🌘';
    } else {
      phase = 'New Moon';
      icon = '🌑';
      isSpringTide = true;
    }

    return MoonPhase(
      phase: phase,
      icon: icon,
      isSpringTide: isSpringTide,
    );
  }
}
