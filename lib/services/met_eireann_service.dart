import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Met Éireann weather data (Irish meteorological service)
class MetWeatherData {
  final double temperature;
  final int windSpeed;
  final int windDirection;
  final String windDirectionStr;
  final String symbol;
  final int wmoCode;
  final double? windGust;
  final int? precipitationProbability;

  MetWeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.windDirectionStr,
    required this.symbol,
    required this.wmoCode,
    this.windGust,
    this.precipitationProbability,
  });
}

class MetEireannService {
  static const _apiUrl = 'http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast';
  
  // DEBUG DATA
  static List<String> debugOutput = [];
  static String? lastXmlBody;
  static Map<int, Map<String, dynamic>>? lastStructuredData;

  // Callback for external logging (avoid circular dependency)
  static Function(String id, String url, int status, String body, String locationName)? onLog;

  // Helper to allow mocking or overriding
  bool get _isWeb => kIsWeb;

  /// Fetch hourly forecast from Met Éireann (XML)
  Future<Map<int, MetWeatherData>> fetchHourlyForecast(double lat, double lon, {String? logId, String locationName = 'Unknown'}) async {
    debugOutput.clear();
    lastXmlBody = null;
    
    // Build standard URI
    final uri = Uri.http('openaccess.pf.api.met.ie', '/metno-wdb2ts/locationforecast', {
      'lat': lat.toStringAsFixed(4),
      'long': lon.toStringAsFixed(4),
    });
    
    final url = uri.toString();
    // Use direct URL for mobile, Proxy for Web
    // import 'package:flutter/foundation.dart'; needs to be added if not present, 
    // but we can just use a try-catch pattern or pass a flag. 
    // Ideally we check kIsWeb.
    
    try {
      // Logic: Try direct first (works on Mobile), fallback to proxy (needed for Web)
      // Actually, better to just implement kIsWeb check if we can import it.
      // Let's stick to the direct URL for Android.
      
      // On web, proxy through our own Phoenix backend to avoid CORS
      final targetUri = _isWeb
          ? Uri.parse('/api/proxy/met-eireann?lat=${lat.toStringAsFixed(4)}&long=${lon.toStringAsFixed(4)}')
          : uri;
      
      print('MetEireann: Fetching $url...');
      final response = await http.get(targetUri).timeout(const Duration(seconds: 10));
      print('MetEireann: HTTP ${response.statusCode}');
      
      // Log to centralized logger if ID provided
      if (logId != null && onLog != null) {
        onLog!(logId, targetUri.toString(), response.statusCode, response.body, locationName);
      }
      
      if (response.statusCode != 200) {
        print('MetEireann: API Error: ${response.statusCode}');
        debugOutput.add('Error: HTTP ${response.statusCode}');
        return {};
      }

      final body = response.body;
      lastXmlBody = body; // Capture raw XML
      if (body.isEmpty) {
        debugOutput.add('Error: Empty Body');
        return {};
      }

      final document = XmlDocument.parse(body);
      final times = document.findAllElements('time');

      final mergedData = <int, Map<String, dynamic>>{};
      lastStructuredData = mergedData;

      for (final t in times) {
        final fromStr = t.getAttribute('from');
        final toStr = t.getAttribute('to');
        if (fromStr == null || toStr == null) continue;

        final from = DateTime.parse(fromStr).toUtc();
        final to = DateTime.parse(toStr).toUtc();
        final location = t.getElement('location');
        if (location == null) continue;

        if (fromStr == toStr) {
          // Point data
          final msKey = DateTime.utc(from.year, from.month, from.day, from.hour).millisecondsSinceEpoch;
          final entry = mergedData.putIfAbsent(msKey, () => {'ms': msKey, 'time': from});
          
          final temp = location.getElement('temperature')?.getAttribute('value');
          final windSpeed = location.getElement('windSpeed')?.getAttribute('mps');
          final windDir = location.getElement('windDirection')?.getAttribute('deg');
          final windGust = location.getElement('windGust')?.getAttribute('mps'); // Parse Gusts

          if (temp != null) entry['temp'] = double.parse(temp);
          if (windSpeed != null) entry['windSpeed'] = double.parse(windSpeed);
          if (windDir != null) entry['windDir'] = double.parse(windDir);
          if (windGust != null) entry['windGust'] = double.parse(windGust); // Store raw mps
        } else {
          // Interval data (symbols, precip) - propagate across all hours in interval
          // Met Eireann intervals are usually 1h or 6h.
          // We need to find all hourly slots covered by this interval and update them.
          
          final symbol = location.getElement('symbol')?.getAttribute('id') ?? location.getElement('symbol')?.getAttribute('number');
          final precipProb = location.getElement('precipitation')?.getAttribute('probability');
          final precip = precipProb ?? location.getElement('precipitation')?.getAttribute('value');

          // Duration in hours
          final duration = to.difference(from).inHours;
          
          for (int i = 0; i < duration; i++) {
             final targetTime = from.add(Duration(hours: i));
             final msKey = DateTime.utc(targetTime.year, targetTime.month, targetTime.day, targetTime.hour).millisecondsSinceEpoch;
             
             if (mergedData.containsKey(msKey)) {
                final entry = mergedData[msKey]!;
                // Parse symbol to int
                if (symbol != null && !entry.containsKey('symbol')) {
                   entry['symbol'] = int.tryParse(symbol); 
                }
                if (precip != null) {
                   // Handle "0.0" or "0"
                   entry['precip'] = double.tryParse(precip)?.round();
                }
             }
          }
        }
      }

      // Generate Debug Output from merged data (sorted)
      final sortedKeys = mergedData.keys.toList()..sort();
      
      // Header for debug output
      debugOutput.add('Time (UTC)       | Temp | Wind | Dir | Gust | Rain% | Symbol');
      debugOutput.add('-------------------------------------------------------------');

      for (final key in sortedKeys) {
         final entry = mergedData[key]!;
         final time = entry['time'] as DateTime;
         final timeStr = '${time.year}-${time.month.toString().padLeft(2,'0')}-${time.day.toString().padLeft(2,'0')} ${time.hour.toString().padLeft(2,'0')}:00';
         
         final temp = entry['temp']?.toStringAsFixed(1) ?? '-';
         final wind = entry['windSpeed']?.toStringAsFixed(1) ?? '-';
         final dir = entry['windDir']?.toStringAsFixed(0) ?? '-';
         final gust = entry['windGust']?.toStringAsFixed(1) ?? '-';
         final rain = entry['precip']?.toString() ?? '-';
         final sym = entry['symbol']?.toString() ?? '-';
         
         debugOutput.add('$timeStr | $temp | $wind | $dir | $gust | $rain | $sym');
      }
      
      // Second pass: Fill points (temp, wind) if they are sparse
      
      // 1. Forward fill
      Map<String, dynamic>? lastPoint;
      for (final ms in sortedKeys) {
        final entry = mergedData[ms]!;
        if (entry['temp'] != null) {
          lastPoint = entry;
        } else if (lastPoint != null) {
          final diffHours = (ms - (lastPoint['ms'] as int)) / (1000 * 60 * 60);
          if (diffHours <= 14) {
            entry['temp'] ??= lastPoint['temp'];
            entry['windSpeed'] ??= lastPoint['windSpeed'];
            entry['windDir'] ??= lastPoint['windDir'];
          }
        }
      }

      // 2. Backward fill (to catch the start of intervals before the first point)
      Map<String, dynamic>? nextPoint;
      for (final ms in sortedKeys.reversed) {
        final entry = mergedData[ms]!;
        if (entry['temp'] != null) {
          nextPoint = entry;
        } else if (nextPoint != null) {
          final diffHours = ((nextPoint['ms'] as int) - ms) / (1000 * 60 * 60);
          if (diffHours <= 14) {
            entry['temp'] ??= nextPoint['temp'];
            entry['windSpeed'] ??= nextPoint['windSpeed'];
            entry['windDir'] ??= nextPoint['windDir'];
          }
        }
      }

      final result = <int, MetWeatherData>{};

      mergedData.forEach((ms, entry) {
        // Only include if we have at least temperature (either original or filled)
        if (entry['temp'] != null) {
          final symbol = entry['symbol'] as int? ?? 3;
          final windDirDeg = (entry['windDir'] as double? ?? 0.0).round();

          result[ms] = MetWeatherData(
            temperature: entry['temp'] as double,
            windSpeed: ((entry['windSpeed'] as double? ?? 0.0) * 3.6).round(),
            windDirection: windDirDeg,
            windDirectionStr: _getCardinalDirection(windDirDeg),
            symbol: _mapSymbolToInternal(symbol),
            wmoCode: _mapSymbolToWmo(symbol),
            windGust: entry['windGust'] != null ? ((entry['windGust'] as double) * 3.6) : null, // Convert mps to km/h
            precipitationProbability: entry['precip'] as int?,
          );
        }
      });

      if (result.isNotEmpty) {
        final sortedResultKeys = result.keys.toList()..sort();
        final first = DateTime.fromMillisecondsSinceEpoch(sortedResultKeys.first, isUtc: true);
        final last = DateTime.fromMillisecondsSinceEpoch(sortedResultKeys.last, isUtc: true);
        print('MetEireann: Mapped ${result.length} hours from $first to $last');
      }

      return result;
    } catch (e) {
      print('MetEireann: Critical failure: $e');
      return {};
    }
  }

  static String _getCardinalDirection(int angle) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return directions[((angle + 22.5) / 45).floor() % 8];
  }

  static String _mapSymbolToInternal(int? symbol) {
    if (symbol == null) return 'Cloud';
    if (symbol == 1) return 'Sun';
    if (symbol <= 3) return 'PartlyCloudy';
    if (symbol == 15) return 'Fog';
    if (symbol <= 10 || (symbol >= 40 && symbol <= 45)) return 'Rain';
    if (symbol == 13 || symbol == 14) return 'Snow';
    if (symbol == 11) return 'Thunder';
    return 'Cloud';
  }

  static int _mapSymbolToWmo(int? symbol) {
    if (symbol == null) return 3;
    if (symbol == 1) return 0;
    if (symbol == 2 || symbol == 3) return 2;
    if (symbol == 4) return 3;
    if (symbol >= 5 && symbol <= 8) return 61;
    if (symbol == 9) return 63;
    if (symbol == 10) return 65;
    if (symbol == 11) return 95;
    if (symbol == 12) return 68;
    if (symbol == 13) return 71;
    if (symbol == 15) return 45;
    return 3;
  }
}
