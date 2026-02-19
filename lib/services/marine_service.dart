import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'settings_service.dart';
import '../utils/unit_converter.dart';
import '../models/marine_data.dart';
import 'forecast_cache.dart';
import 'met_eireann_service.dart';


import 'dart:ui';
import 'package:flutter/material.dart'; // Grid/Widget support
import '../widgets/tide_graphic.dart'; // Import the widget

class MarineService {
  static const _swellApi = 'https://marine-api.open-meteo.com/v1/marine';
  static const _weatherApi = 'https://api.open-meteo.com/v1/forecast';
  
  final _cache = ForecastCache();
  final _metEireann = MetEireannService(); // Hybrid Service Enabled

  MarineService() {
    // Wire up Met Eireann logging to central log
    MetEireannService.onLog = (id, url, status, body, locationName) {
      _logApi(id, url, status, body, isFallback: false, locationName: locationName, requestLabel: 'Met Éireann');
    };
  }

  // --- Debug Logging ---
  static final List<ApiLog> apiLogs = [];
  static Map<String, dynamic> lastRoughnessCalculation = {};
  static Map<String, String>? lastFieldSources;
  static List<HourlyForecast>? lastForecasts; // For detailed inspection

  static void _logApi(String id, String url, int status, String body, {bool isFallback = false, String? locationName, String? requestLabel}) {
    apiLogs.insert(0, ApiLog(
      id: id,
      timestamp: DateTime.now(),
      url: url,
      status: status,
      body: body,
      isFallback: isFallback,
      isMetEireann: url.contains('met.ie'),
      locationName: locationName,
      requestLabel: requestLabel,
    ));
    if (apiLogs.length > 50) apiLogs.removeLast(); // Keep last 50
  }

  /// Region detection
  static bool isIreland(double lat, double lon) =>
      lat >= 51.3 && lat <= 55.5 && lon >= -10.7 && lon <= -5.3;
  static bool isUK(double lat, double lon) =>
      lat >= 49.8 && lat <= 60.9 && lon >= -8.2 && lon <= 1.8 && !isIreland(lat, lon);

  /// Get weather model for region
  /// ukmo_seamless is 2km resolution covering both UK and Ireland
  static String _weatherModel(double lat, double lon) {
    if (isIreland(lat, lon)) return 'ukmo_seamless';
    if (isUK(lat, lon)) return 'ukmo_seamless';
    return 'best_match';  // Open-Meteo default for rest of world
  }

  static String _dataSourceLabel(double lat, double lon) {
    if (isIreland(lat, lon)) return 'Met Éireann';
    if (isUK(lat, lon)) return 'UK Met Office';
    return 'Open-Meteo';
  }

  /// Fetch forecasts with caching
  Future<({List<HourlyForecast> forecasts, DateTime lastUpdated, Map<String, ({String sunrise, String sunset})> sunData, Location? refinedLocation})> getForecasts(
    Location location, {
    bool forceRefresh = false,
    int days = 7,
  }) async {
    final locationId = '${location.lat}-${location.lon}';

    // Check cache first (unless force refresh)
    if (!forceRefresh) {
      final cached = await _cache.get(locationId);
      if (cached != null && !cached.isStale) {
        _logApi('cache-hit', 'Cache Load', 200, 'Loaded ${cached.forecasts.length} entries. Last updated: ${cached.timestamp}', locationName: location.name);
        
        // Re-run calculation for current hour to populate debug screen
        try {
          final now = DateTime.now();
          final current = cached.forecasts.firstWhere(
            (f) => f.time.hour == now.hour && f.time.day == now.day,
            orElse: () => cached.forecasts.first
          );
          calculateSwimCondition(current.swell, current.weather);
        } catch (_) {}

        // Re-fetch sun data (lightweight) since it's not cached
        final sunData = await fetchSunData(location, days: days);
        return (forecasts: cached.forecasts, lastUpdated: cached.timestamp, sunData: sunData, refinedLocation: null);
      }
    }

    // Fetch fresh data with Offline Fallback
    try {
      final result = await fetchForecasts(location, days: days);
      
      // Save to cache
      await _cache.save(locationId, result.forecasts);

      return (forecasts: result.forecasts, lastUpdated: DateTime.now(), sunData: result.sunData, refinedLocation: result.refinedLocation);
    } catch (e) {
      // Try loading any cache (stale or not)
      print('MarineService: Fetch failed ($e). Attempting offline fallback...');
      
      final cached = await _cache.get(locationId);
      if (cached != null) {
         _logApi('cache-hit', 'Offline Fallback', 200, 'Loaded ${cached.forecasts.length} entries from cache.', isFallback: true, locationName: location.name);
         // Re-fetch sun data (might fail too, handled in fetchSunData)
         final sunData = await fetchSunData(location, days: days);
         return (forecasts: cached.forecasts, lastUpdated: cached.timestamp, sunData: sunData, refinedLocation: null);
      }
      
      rethrow;
    }
  }

  /// Get cached forecasts (optimistic UI helper)
  Future<({List<HourlyForecast> forecasts, DateTime lastUpdated, Map<String, ({String sunrise, String sunset})> sunData, Location? refinedLocation})?> getCachedForecasts(Location location) async {
    final locationId = '${location.lat}-${location.lon}';
    final cached = await _cache.get(locationId);
    
    if (cached != null) {
      // Best effort sun data (cached not supported for sun yet, maybe todo)
      // For now, return empty sun data or try fetch. 
      // Actually, let's just return empty and let the real fetch fill it in.
      return (forecasts: cached.forecasts, lastUpdated: cached.timestamp, sunData: <String, ({String sunrise, String sunset})>{}, refinedLocation: null);
    }
    return null;
  }

  /// Update cache with enriched data (e.g. including tides)
  Future<void> updateCache(Location location, List<HourlyForecast> forecasts) async {
    final locationId = '${location.lat}-${location.lon}';
    await _cache.save(locationId, forecasts);
  }


  /// Clear cache and force refresh
  Future<void> clearCache(Location location) async {
    await _cache.clear('${location.lat}-${location.lon}');
  }

  /// Clear all caches
  Future<void> clearAllCaches() async {
    await _cache.clearAll();
  }

  /// Fetch sunrise/sunset data from Open-Meteo
  Future<Map<String, ({String sunrise, String sunset})>> fetchSunData(Location location, {int days = 7}) async {
    final uri = Uri.parse(
      '$_weatherApi?latitude=${location.lat}&longitude=${location.lon}'
      '&daily=sunrise,sunset&forecast_days=$days&past_days=1&timezone=Europe%2FDublin'
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return {};
    final data = json.decode(resp.body);
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily == null) return {};
    final dates = (daily['time'] as List).cast<String>();
    final sunrises = (daily['sunrise'] as List).cast<String>();
    final sunsets = (daily['sunset'] as List).cast<String>();
    final result = <String, ({String sunrise, String sunset})>{};
    for (int i = 0; i < dates.length; i++) {
      result[dates[i]] = (sunrise: sunrises[i], sunset: sunsets[i]);
    }
    return result;
  }

  /// Fetch forecasts from APIs (Met Éireann + Open-Meteo)
  Future<({List<HourlyForecast> forecasts, Map<String, ({String sunrise, String sunset})> sunData, Location? refinedLocation})> fetchForecasts(Location location, {int days = 7}) async {
    final model = _weatherModel(location.lat, location.lon);

    // SST Strategy: Use saved water location IF available, otherwise Jitter
    final hasSavedWaterLoc = location.waterLat != null && location.waterLon != null;
    final sLat = hasSavedWaterLoc ? location.waterLat! : location.lat;
    final sLon = hasSavedWaterLoc ? location.waterLon! : location.lon;

    // Fetch swell data — ECMWF WAM (Atlantic Gold Standard)
    final swellUri = Uri.parse(
      '$_swellApi?latitude=$sLat&longitude=$sLon'
      '&hourly=wave_height,wave_direction,wave_period,sea_surface_temperature'
      ',swell_wave_height,swell_wave_period,wind_wave_height'
      '&forecast_days=$days&past_days=1&timezone=UTC'
      '&models=ecmwf_wam025'
    );
    
    // Fetch weather — ukmo_seamless (2km UK+IE) or best_match fallback
    // Note: ukmo_seamless doesn't provide precipitation_probability, so we fetch
    // that separately from best_match and merge it in.
    final weatherUri = Uri.parse(
      '$_weatherApi?latitude=${location.lat}&longitude=${location.lon}'
      '&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code,cloud_cover,precipitation,sea_surface_temperature'
      '&forecast_days=$days&past_days=1&timezone=UTC'
      '&models=$model'
    );

    final precipUri = Uri.parse(
      '$_weatherApi?latitude=${location.lat}&longitude=${location.lon}'
      '&hourly=precipitation_probability'
      '&forecast_days=$days&past_days=1&timezone=UTC'
    );
    // Fetch weather — ukmo_seamless (2km UK+IE) or best_match fallback
    final sstUris = <Uri>[];
    final offsetsDescriptions = <String>[];

    if (hasSavedWaterLoc) {
      sstUris.add(Uri.parse(
        'https://marine-api.open-meteo.com/v1/marine?latitude=${location.waterLat}&longitude=${location.waterLon}'
        '&hourly=sea_surface_temperature,wave_height,wave_direction,wave_period,swell_wave_height,swell_wave_period,wind_wave_height'
        '&forecast_days=$days&past_days=1&timezone=UTC&models=ecmwf_wam025'
      ));
      offsetsDescriptions.add('Saved Water Location');
    } else {
       // 1. Primary point
       // 2. Wide cardinal offsets (0.2 deg ~ 20km, 0.4 deg ~ 45km) to clear land-masks
       final offsets = [
        (0.0, 0.0),   // Primary
        (0.0, 0.25),  // East
        (0.0, -0.25), // West
        (0.25, 0.0),  // North
        (-0.25, 0.0), // South
        (0.0, 0.5),   // Deep East
        (0.0, -0.5),  // Deep West
      ];
      
      for(var o in offsets) {
        sstUris.add(Uri.parse(
          'https://marine-api.open-meteo.com/v1/marine?latitude=${location.lat + o.$1}&longitude=${location.lon + o.$2}'
          '&hourly=sea_surface_temperature,wave_height,wave_direction,wave_period,swell_wave_height,swell_wave_period,wind_wave_height'
          '&forecast_days=$days&past_days=1&timezone=UTC&models=ecmwf_wam025'
        ));
        offsetsDescriptions.add(o == offsets.first ? 'Primary' : 'Jitter ${o.$1},${o.$2}');
      }
    }

    // Log initial requests
    // Generate UUIDs for logs (simple random string for now)
    String _uuid() => DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString();

    final swellLogId = _uuid();
    final weatherLogId = _uuid();
    final metLogId = _uuid();
    final sstLogIds = List.generate(sstUris.length, (_) => _uuid());

    late http.Response swellResponse;
    late http.Response weatherResponse;
    late http.Response precipResponse;
    List<http.Response> sstResponses = [];
    Map<int, MetWeatherData> metEireannData = {};

    try {
      final futures = await Future.wait([
        http.get(swellUri).timeout(const Duration(seconds: 10)),
        http.get(weatherUri).timeout(const Duration(seconds: 10)),
        http.get(precipUri).timeout(const Duration(seconds: 10)),
        if (isIreland(location.lat, location.lon)) 
          _metEireann.fetchHourlyForecast(location.lat, location.lon, logId: metLogId, locationName: location.name)
        else 
          Future.value(<int, MetWeatherData>{}),
        ...sstUris.map((u) => http.get(u).timeout(const Duration(seconds: 10)))
      ]);

      swellResponse = futures[0] as http.Response;
      weatherResponse = futures[1] as http.Response;
      precipResponse = futures[2] as http.Response;
      metEireannData = futures[3] as Map<int, MetWeatherData>;
      sstResponses = futures.sublist(4).cast<http.Response>();
      
      _logApi(swellLogId, swellUri.toString(), swellResponse.statusCode, swellResponse.body, locationName: location.name, requestLabel: 'Swell (ECMWF)');
      _logApi(weatherLogId, weatherUri.toString(), weatherResponse.statusCode, weatherResponse.body, locationName: location.name, requestLabel: 'Weather ($model)');
      
      // Removed bulk logging of all SST attempts. We will log only the winner below.

    } catch (e) {
      throw Exception('Network error: $e');
    }

    if (swellResponse.statusCode != 200) throw Exception('Swell API error (${swellResponse.statusCode})');
    if (weatherResponse.statusCode != 200) throw Exception('Weather API error (${weatherResponse.statusCode})');
    
    final swellData = json.decode(swellResponse.body);
    final weatherData = json.decode(weatherResponse.body);

    final swellHourly = swellData['hourly'] as Map<String, dynamic>;
    final weatherHourly = weatherData['hourly'] as Map<String, dynamic>;

    final times = (swellHourly['time'] as List).cast<String>();

    // Marine Jitter Logic: Find the first response that has non-null SST and/or Wave data
    List<dynamic> seaTempsSST = [];
    List<dynamic> waveHeightsJitter = [];
    List<dynamic> waveDirectionsJitter = [];
    List<dynamic> wavePeriodsJitter = [];
    List<dynamic> swellWaveHeightsJitter = [];
    List<dynamic> swellWavePeriodsJitter = [];
    List<dynamic> windWaveHeightsJitter = [];
    
    String sstSource = 'None';
    String sstLogId = '';
    Location? refinedLocation;

    for (int k = 0; k < sstResponses.length; k++) {
      var resp = sstResponses[k];
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final hourly = data['hourly'] as Map<String, dynamic>?;
        if (hourly != null) {
          final temps = (hourly['sea_surface_temperature'] as List?) ?? [];
          if (temps.any((t) => t != null)) {
            seaTempsSST = temps;
            sstLogId = sstLogIds[k];
            
            // Capture waves from Jitter too if available
            waveHeightsJitter = (hourly['wave_height'] as List?) ?? [];
            waveDirectionsJitter = (hourly['wave_direction'] as List?) ?? [];
            wavePeriodsJitter = (hourly['wave_period'] as List?) ?? [];
            swellWaveHeightsJitter = (hourly['swell_wave_height'] as List?) ?? [];
            swellWavePeriodsJitter = (hourly['swell_wave_period'] as List?) ?? [];
            windWaveHeightsJitter = (hourly['wind_wave_height'] as List?) ?? [];

            if (hasSavedWaterLoc) {
               final dist = _calculateDistance(location.lat, location.lon, location.waterLat!, location.waterLon!);
               final dir = _calculateBearing(location.lat, location.lon, location.waterLat!, location.waterLon!);
               sstSource = 'Open-Meteo (Saved Water Loc: ${dist.toStringAsFixed(1)}km $dir)';
            } else {
               final uri = sstUris[k];
               final q = uri.queryParameters;
               final wLat = double.parse(q['latitude']!);
               final wLon = double.parse(q['longitude']!);
               
               final dist = _calculateDistance(location.lat, location.lon, wLat, wLon);
               final dir = _calculateBearing(location.lat, location.lon, wLat, wLon);
               sstSource = 'Open-Meteo (${offsetsDescriptions[k]}: ${dist.toStringAsFixed(1)}km $dir)';
               
               if (dist > 1.0) {
                 refinedLocation = Location(
                   id: location.id,
                   name: location.name,
                   lat: location.lat,
                   lon: location.lon,
                   waterLat: wLat,
                   waterLon: wLon
                 );
               }
            }
            // Log only the winner SST/Wave
            final label = hasSavedWaterLoc ? 'Marine (Saved Water Loc)' : (k == 0 ? 'Marine Primary' : 'Marine Jitter #$k');
            _logApi(sstLogIds[k], sstUris[k].toString(), resp.statusCode, resp.body, locationName: location.name, requestLabel: label);
            
            break; 
          }
        }
      }
    }

    final seaTempsSwell = (swellHourly['sea_surface_temperature'] as List?) ?? [];
    final seaTempsWeather = (weatherHourly['sea_surface_temperature'] as List?) ?? [];
    
    // Seasonal Fallback for Ireland (Monthly Averages)
    final now = DateTime.now();
    final seasonalSSTIndex = now.month - 1;
    final seasonalSST = [9.0, 8.5, 9.0, 10.5, 12.0, 14.0, 15.5, 16.5, 15.5, 14.0, 12.0, 10.0][seasonalSSTIndex];

    // --- Wave Fallback Strategy ---
    // If the primary Swell fetch returned all nulls (land mask), use jittered data
    final primaryWaveHeights = (swellHourly['wave_height'] as List?) ?? [];
    final useJitterSwell = primaryWaveHeights.every((h) => h == null) && waveHeightsJitter.isNotEmpty;

    final swellWaveHeights = useJitterSwell ? swellWaveHeightsJitter : (swellHourly['swell_wave_height'] as List?) ?? [];
    final swellWavePeriods = useJitterSwell ? swellWavePeriodsJitter : (swellHourly['swell_wave_period'] as List?) ?? [];
    final windWaveHeights = useJitterSwell ? windWaveHeightsJitter : (swellHourly['wind_wave_height'] as List?) ?? [];
    
    final waveHeights = useJitterSwell ? waveHeightsJitter : primaryWaveHeights;
    final waveDirections = useJitterSwell ? waveDirectionsJitter : (swellHourly['wave_direction'] as List?) ?? [];
    final wavePeriods = useJitterSwell ? wavePeriodsJitter : (swellHourly['wave_period'] as List?) ?? [];

    final temps = (weatherHourly['temperature_2m'] as List?) ?? [];
    final windSpeeds = (weatherHourly['wind_speed_10m'] as List?) ?? [];
    final windDirs = (weatherHourly['wind_direction_10m'] as List?) ?? [];
    final weatherCodes = (weatherHourly['weather_code'] as List?) ?? [];

    // precipitation_probability from best_match (ukmo_seamless doesn't provide it)
    List<dynamic> precipProbs = [];
    if (precipResponse.statusCode == 200) {
      final precipData = json.decode(precipResponse.body);
      precipProbs = (precipData['hourly']?['precipitation_probability'] as List?) ?? [];
    }
    
    final forecasts = <HourlyForecast>[];

    String _snippet(List list, int index) {
      if (index < 0 || index >= list.length) return 'out of bounds (index $index, len ${list.length})';
      final val = list[index];
      if (val == null) {
        // Find nearest non-null for context
        int? nearestIdx;
        for (int d = 1; d < list.length; d++) {
          if (index - d >= 0 && list[index - d] != null) { nearestIdx = index - d; break; }
          if (index + d < list.length && list[index + d] != null) { nearestIdx = index + d; break; }
        }
        final hint = nearestIdx != null ? ' (nearest non-null: [${nearestIdx}]=${list[nearestIdx]})' : ' (all null)';
        return 'null at index $index$hint';
      }
      return '$val (index $index)';
    }

    for (int i = 0; i < times.length; i++) {
      final time = DateTime.parse(times[i] + 'Z');
      final provenance = <String, FieldProvenance>{};
      
      double sst = 0.0;
      if (i < seaTempsSST.length && seaTempsSST[i] != null) {
        sst = _toDouble(seaTempsSST, i);
        provenance['Sea Temperature'] = FieldProvenance(
          sourceName: sstSource, logId: sstLogId, snippet: _snippet(seaTempsSST, i), keyPath: 'hourly.sea_surface_temperature[$i]');
      }
      if (sst == 0.0 && i < seaTempsSwell.length && seaTempsSwell[i] != null) {
        sst = _toDouble(seaTempsSwell, i);
        provenance['Sea Temperature'] = FieldProvenance(
          sourceName: 'Open-Meteo Swell (ECMWF)', logId: swellLogId, snippet: _snippet(seaTempsSwell, i), keyPath: 'hourly.sea_surface_temperature[$i]');
      }
      if (sst == 0.0 && i < seaTempsWeather.length && seaTempsWeather[i] != null) {
        sst = _toDouble(seaTempsWeather, i);
         provenance['Sea Temperature'] = FieldProvenance(
          sourceName: 'Open-Meteo Weather ($model)', logId: weatherLogId, snippet: _snippet(seaTempsWeather, i), keyPath: 'hourly.sea_surface_temperature[$i]');
      }
      
      // ABSOLUTE LAST RESORT: Seasonal Regional Background
      if (sst == 0.0) {
        sst = seasonalSST;
        provenance['Sea Temperature'] = FieldProvenance(
          sourceName: 'Seasonal Average', logId: 'seasonal', snippet: 'Month ${now.month}: $seasonalSST', keyPath: 'N/A');
      }

      final swell = SwellData(
        height: _toDouble(waveHeights, i),
        direction: _toDouble(waveDirections, i).round(),
        period: _toDouble(wavePeriods, i).round(),
        seaTemperature: sst,
        windWaveHeight: _toDouble(windWaveHeights, i),
        swellWaveHeight: _toDouble(swellWaveHeights, i),
        swellWavePeriod: _toDouble(swellWavePeriods, i).round(),
      );
      
      final swellSourceName = useJitterSwell ? 'Marine Jitter (ECMWF)' : (hasSavedWaterLoc ? 'Swell (ECMWF @ Water)' : 'Swell (ECMWF)');
      final usedWaveLogId = useJitterSwell ? sstLogId : swellLogId;

      provenance['Wave Height'] = FieldProvenance(sourceName: swellSourceName, logId: usedWaveLogId, snippet: _snippet(swellWaveHeights, i), keyPath: 'hourly.swell_wave_height[$i]');
      provenance['Wave Period'] = FieldProvenance(sourceName: swellSourceName, logId: usedWaveLogId, snippet: _snippet(swellWavePeriods, i), keyPath: 'hourly.swell_wave_period[$i]');
      provenance['Wave Direction'] = FieldProvenance(sourceName: swellSourceName, logId: usedWaveLogId, snippet: _snippet(waveDirections, i), keyPath: 'hourly.wave_direction[$i]');

      final timeMs = time.millisecondsSinceEpoch;
      final metEntry = metEireannData[timeMs];
      final timeKey = time.toIso8601String(); // Used as keyPath for Met Éireann XML entries

      if (metEntry != null) {
        provenance['Temperature'] = FieldProvenance(
          sourceName: 'Met Éireann', logId: metLogId,
          snippet: 'temp: ${metEntry.temperature.toStringAsFixed(1)}°C',
          keyPath: 'time[$timeKey].temperature');
        provenance['Wind Speed'] = FieldProvenance(
          sourceName: 'Met Éireann', logId: metLogId,
          snippet: 'windSpeed: ${metEntry.windSpeed} km/h',
          keyPath: 'time[$timeKey].windSpeed');
        provenance['Wind Direction'] = FieldProvenance(
          sourceName: 'Met Éireann', logId: metLogId,
          snippet: 'windDir: ${metEntry.windDirection}° (${metEntry.windDirectionStr})',
          keyPath: 'time[$timeKey].windDirection');
        provenance['Weather Condition'] = FieldProvenance(
          sourceName: 'Met Éireann', logId: metLogId,
          snippet: 'symbol: ${metEntry.symbol} (wmo: ${metEntry.wmoCode})',
          keyPath: 'time[$timeKey].symbol');
        final precipVal = metEntry.precipitationProbability;
        provenance['Precipitation Prob'] = FieldProvenance(
          sourceName: 'Met Éireann', logId: metLogId,
          snippet: precipVal != null ? 'precipitation probability: $precipVal%' : 'precipitation probability: null (fallback to Open-Meteo)',
          keyPath: 'time[$timeKey].precipitation[probability]');
        if (metEntry.windGust != null) {
          provenance['Wind Gust'] = FieldProvenance(
            sourceName: 'Met Éireann', logId: metLogId,
            snippet: 'windGust: ${metEntry.windGust!.toStringAsFixed(1)} km/h',
            keyPath: 'time[$timeKey].windGust');
        }
      } else {
        provenance['Temperature'] = FieldProvenance(sourceName: 'Open-Meteo ($model)', logId: weatherLogId, snippet: _snippet(temps, i), keyPath: 'hourly.temperature_2m[$i]');
        provenance['Wind Speed'] = FieldProvenance(sourceName: 'Open-Meteo ($model)', logId: weatherLogId, snippet: _snippet(windSpeeds, i), keyPath: 'hourly.wind_speed_10m[$i]');
        provenance['Wind Direction'] = FieldProvenance(sourceName: 'Open-Meteo ($model)', logId: weatherLogId, snippet: _snippet(windDirs, i), keyPath: 'hourly.wind_direction_10m[$i]');
        provenance['Weather Condition'] = FieldProvenance(sourceName: 'Open-Meteo ($model)', logId: weatherLogId, snippet: _snippet(weatherCodes, i), keyPath: 'hourly.weather_code[$i]');
        provenance['Precipitation Prob'] = FieldProvenance(sourceName: 'Open-Meteo (best_match)', logId: weatherLogId, snippet: _snippet(precipProbs, i), keyPath: 'hourly.precipitation_probability[$i]');
      }

      // Resolve actual values — prefer Met Éireann when available
      final temperature = metEntry != null ? metEntry.temperature : _toDouble(temps, i);
      final windSpeed = metEntry != null ? metEntry.windSpeed : _toDouble(windSpeeds, i).round();
      final windDirection = metEntry != null ? metEntry.windDirection : _toDouble(windDirs, i).round();
      final wmoCode = metEntry != null ? metEntry.wmoCode : _toInt(weatherCodes, i);
      final precipProb = (metEntry?.precipitationProbability != null && metEntry!.precipitationProbability! > 0)
          ? metEntry.precipitationProbability!
          : _toInt(precipProbs, i);

      final weather = WeatherData(
        temperature: temperature,
        windSpeed: windSpeed,
        windDirection: windDirection,
        wmoCode: wmoCode,
        precipitationProbability: precipProb,
        cloudCover: 0,
        windGust: metEntry?.windGust,
        source: metEntry != null ? 'Met Éireann' : 'Open-Meteo',
      );

      forecasts.add(HourlyForecast(
        time: time,
        swell: swell,
        weather: weather,
        swimCondition: calculateSwimCondition(swell, weather),
        isMetEireann: metEntry != null,
        dataSource: metEntry != null ? 'Met Éireann' : 'Open-Meteo ($model)',
        provenance: provenance,
      ));
    }

    if (forecasts.isNotEmpty) {
      lastFieldSources = forecasts.first.provenance?.map((k, v) => MapEntry(k, v.sourceName)); // Legacy support
      lastForecasts = forecasts;
    }

    final sunData = await fetchSunData(location, days: days);
    return (forecasts: forecasts, sunData: sunData, refinedLocation: refinedLocation);
  }

  double _toDouble(List list, int i) {
    if (i >= list.length || list[i] == null) return 0.0;
    return (list[i] as num).toDouble();
  }

  int _toInt(List list, int i) {
    if (i >= list.length || list[i] == null) return 0;
    return (list[i] as num).toInt();
  }

  /// Calculate swim condition with diagnostics
  /// Spec formula: wind*0.5 + wave_wind*60 + wave_swell*20*powerMultiplier
  SwimConditionDetail calculateSwimCondition(SwellData swell, WeatherData weather) {
    final waveHeight = swell.height;
    final wavePeriod = swell.period;
    final waveDir = swell.direction;
    final windSpeed = weather.windSpeed;
    final windDir = weather.windDirection;
    final wmoCode = weather.wmoCode;

    // Use disaggregated data if available, fall back to totals
    final windWaveH = swell.windWaveHeight > 0 ? swell.windWaveHeight : waveHeight * 0.4;
    final swellH = swell.swellWaveHeight > 0 ? swell.swellWaveHeight : waveHeight * 0.6;
    final swellP = swell.swellWavePeriod > 0 ? swell.swellWavePeriod : wavePeriod;

    // === ROUGHNESS FORMULA (West Coast Spec) ===
    double roughness = 0;

    // 1. The "Misery" Factor (Wind Chop)
    roughness += windSpeed * 0.5;
    roughness += windWaveH * 60;  // 0.5m chop = very annoying

    // 2. The "Danger" Factor (West Coast Power)
    // On the Atlantic, 1m @ 14s is MUCH stronger than 1m @ 8s
    double powerMultiplier = 1.0;
    if (swellP > 13) {
      powerMultiplier = 1.8;  // Long period = deceptive power & rip currents
    } else if (swellP > 10) {
      powerMultiplier = 1.4;
    }
    roughness += (swellH * 20) * powerMultiplier;

    // Safety clamp at 100
    roughness = roughness.clamp(0, 100).toDouble();

    // === Supplementary diagnostics ===
    final wavelength = 1.56 * wavePeriod * wavePeriod;
    final steepness = wavelength > 0 ? waveHeight / wavelength : 0.0;

    final deltaTheta = ((waveDir - windDir).abs() % 360).toDouble();
    final normalizedDelta = deltaTheta > 180 ? 360 - deltaTheta : deltaTheta;

    String crossSeaLevel = 'aligned';
    if (normalizedDelta >= 60 && normalizedDelta <= 120) {
      crossSeaLevel = 'cross-sea';
    } else if (normalizedDelta >= 45 && normalizedDelta <= 135) {
      crossSeaLevel = 'partial';
    }

    // === Score Key (from spec) ===
    // 0-20: Perfect / Glassy
    // 21-40: Standard West Coast (Choppy but swimmable)
    // 41-60: Advanced Only (Rough)
    // 60+: Dangerous / Unswimmable
    SwimCondition status;
    String reason;

    final crossSeaWarning = crossSeaLevel == 'cross-sea'
        ? 'Cross-swell (${normalizedDelta.round()}°)'
        : '';

    // Hard overrides first
    if (waveHeight >= 4 || windSpeed >= 72 || wmoCode >= 95) {
      status = SwimCondition.unsafe;
      reason = waveHeight >= 4
          ? 'Very Large Waves (${waveHeight.toStringAsFixed(1)}m)'
          : windSpeed >= 72
              ? 'Storm Force Winds (${windSpeed}km/h)'
              : 'Severe Weather';
    } else if (crossSeaLevel == 'cross-sea' && roughness > 40) {
      status = SwimCondition.rough;
      reason = crossSeaWarning;
    } else if (roughness <= 20) {
      status = SwimCondition.calm;
      reason = crossSeaWarning.isNotEmpty ? crossSeaWarning : 'Flat / Glassy';
    } else if (roughness <= 40) {
      status = SwimCondition.medium;
      reason = crossSeaWarning.isNotEmpty ? crossSeaWarning : 'Standard West Coast';
    } else if (roughness <= 60) {
      status = SwimCondition.rough;
      reason = crossSeaWarning.isNotEmpty ? crossSeaWarning : 'Experienced Swimmers';
    } else {
      status = SwimCondition.unsafe;
      reason = 'High Sea State';
    }

    // Capture precise calculation data for Debug Screen logic reuse
    final debugData = {
      'inputs': {
        'windSpeed': windSpeed.toStringAsFixed(1),
        'windWaveHeight': windWaveH.toStringAsFixed(2),
        'swellHeight': swellH.toStringAsFixed(2),
        'swellPeriod': swellP.toStringAsFixed(1),
      },
      'formula': {
        'misery (wind*0.5)': (windSpeed * 0.5).toStringAsFixed(1),
        'chop (wave*60)': (windWaveH * 60).toStringAsFixed(1),
        'power_mult': powerMultiplier.toStringAsFixed(1),
        'danger (swell*20*power)': ((swellH * 20) * powerMultiplier).toStringAsFixed(1),
      },
      'result': {
        'roughness': roughness.toStringAsFixed(1),
        'status': status.toString(),
        'crossSea': crossSeaLevel,
        'deltaTheta': normalizedDelta.toStringAsFixed(0),
      }
    };

    // Update global debug variable (overwritten every hour)
    lastRoughnessCalculation = debugData;

    return SwimConditionDetail(
      status: status,
      reason: reason,
      roughnessIndex: roughness.round(),
      formulaBreakdown: debugData,
      diagnostics: SwimDiagnostics(
        deltaTheta: normalizedDelta.round(),
        crossSeaLevel: crossSeaLevel,
        directionPenalty: 0, // No longer used in primary formula
        weatherPenalty: 0,   // No longer used in primary formula
        steepness: steepness,
        windSpeedMs: (windSpeed / 3.6),
      ),
    );
  }

  Future<void> updateHomeWidget(Location location, List<HourlyForecast> allForecasts) async {
    print('MarineService: updateHomeWidget called for ${location.name}');
    try {
      final now = DateTime.now();
      // Get forecasts for the next 2 hours — must match TODAY's date
      final upcoming = allForecasts.where((f) =>
        f.time.year == now.year && f.time.month == now.month && f.time.day == now.day &&
        f.time.hour >= now.hour && f.time.hour < now.hour + 2
      ).toList();

      if (upcoming.isEmpty) return;
      
      final suffix = '_${location.id}';

      // Compute averages
      final avgTemp = upcoming.map((f) => f.weather.temperature).reduce((a, b) => a + b) / upcoming.length;
      final avgWind = upcoming.map((f) => f.weather.windSpeed).reduce((a, b) => a + b) / upcoming.length;
      final avgTide = upcoming.where((f) => f.tide != null).map((f) => f.tide!.level).fold(0.0, (a, b) => a + b);
      final tideCount = upcoming.where((f) => f.tide != null).length;
      final tideAvg = tideCount > 0 ? avgTide / tideCount : null;
      // Calculate average percentage for the graphic
      final avgPercentage = tideCount > 0 
          ? (upcoming.where((f) => f.tide != null).map((f) => f.tide!.percentage).reduce((a, b) => a + b) / tideCount).round()
          : 50;
          
      // Determine status from first available or default
      final tideStatus = upcoming.where((f) => f.tide != null).isNotEmpty 
          ? upcoming.where((f) => f.tide != null).first.tide!.status 
          : 'neutral';
          
      final avgRoughness = (upcoming.map((f) => f.swimCondition.roughnessIndex).reduce((a, b) => a + b) / upcoming.length).round();
      final avgPrecip = (upcoming.map((f) => f.weather.precipitationProbability).reduce((a, b) => a + b) / upcoming.length).round();
      final dominantWmo = upcoming.first.weather.wmoCode;
      
      // Render Tide Graphic
      final tideColor = Color(UnitConverter.getTideColor(tideStatus));
      final tideImagePath = await HomeWidget.renderFlutterWidget(
        TideGraphic(
          percentage: avgPercentage,
          color: tideColor,
          width: 60, // Render slightly larger for density
          height: 36,
        ),
        key: 'tide_graphic', 
        logicalSize: const Size(60, 36),
      );
      print('MarineService: Generated TideGraphic at $tideImagePath with color $tideColor');
      
      // Save Main Data
      await HomeWidget.saveWidgetData<String>('location_name', location.name);
      await HomeWidget.saveWidgetData<String>('temp_display', UnitConverter.formatTemp(avgTemp));
      await HomeWidget.saveWidgetData<String>('wind_display', UnitConverter.formatWind(avgWind));
      await HomeWidget.saveWidgetData<String>('precip_display', '$avgPrecip%');
      await HomeWidget.saveWidgetData<String>('tide_display', tideAvg != null ? UnitConverter.formatHeight(tideAvg) : '--');
      
      final roughnessStatus = UnitConverter.getRoughnessStatus(avgRoughness);
      await HomeWidget.saveWidgetData<String>('roughness_label', roughnessStatus.label);
      await HomeWidget.saveWidgetData<int>('roughness_color', roughnessStatus.color);
      await HomeWidget.saveWidgetData<String>('roughness_index', '$avgRoughness'); // New: Send index for display
      
      // Icons & Symbols
      await HomeWidget.saveWidgetData<String>('weather_icon', _wmoToIcon(dominantWmo));
      await HomeWidget.saveWidgetData<String>('tide_image', tideImagePath); // Save image path

      // Location-specific overrides (Suffixed)
      await HomeWidget.saveWidgetData<String>('location_name$suffix', location.name);
      await HomeWidget.saveWidgetData<String>('temp_display$suffix', UnitConverter.formatTemp(avgTemp));
      await HomeWidget.saveWidgetData<String>('wind_display$suffix', UnitConverter.formatWind(avgWind));
      await HomeWidget.saveWidgetData<String>('precip_display$suffix', '$avgPrecip%');
      await HomeWidget.saveWidgetData<String>('tide_display$suffix', tideAvg != null ? UnitConverter.formatHeight(tideAvg) : '--');
      await HomeWidget.saveWidgetData<String>('roughness_label$suffix', roughnessStatus.label);
      await HomeWidget.saveWidgetData<int>('roughness_color$suffix', roughnessStatus.color);
      await HomeWidget.saveWidgetData<String>('roughness_index$suffix', '$avgRoughness');
      await HomeWidget.saveWidgetData<String>('weather_icon$suffix', _wmoToIcon(dominantWmo));
      await HomeWidget.saveWidgetData<String>('tide_image$suffix', tideImagePath);

      // Full Date Format: "Mon 12 Oct 14:30"
      final dateStr = DateFormat('EEE d MMM HH:mm').format(DateTime.now());
      await HomeWidget.saveWidgetData<String>('last_updated', 'Updated: $dateStr');
      await HomeWidget.saveWidgetData<String>('last_updated$suffix', 'Updated: $dateStr');

      // Save Theme Mode
      await HomeWidget.saveWidgetData<int>('theme_mode', SettingsService.themeMode.index);
      
      await HomeWidget.updateWidget(
        name: 'MarineWidgetProvider',
        androidName: 'MarineWidgetProvider',
      );

      // Save with location-specific suffix
      if (location.id != null) {
        final suffix = '_${location.id}';
        await HomeWidget.saveWidgetData<String>('location_name$suffix', location.name);
        await HomeWidget.saveWidgetData<String>('temp_display$suffix', UnitConverter.formatTemp(avgTemp));
        await HomeWidget.saveWidgetData<String>('wind_display$suffix', UnitConverter.formatWind(avgWind));
        await HomeWidget.saveWidgetData<String>('tide_display$suffix', tideAvg != null ? UnitConverter.formatHeight(tideAvg) : '--');
        
        final rs = UnitConverter.getRoughnessStatus(avgRoughness);
        await HomeWidget.saveWidgetData<String>('roughness_label$suffix', rs.label);
        await HomeWidget.saveWidgetData<int>('roughness_color$suffix', rs.color);
        await HomeWidget.saveWidgetData<String>('roughness_index$suffix', '$avgRoughness');
        
        await HomeWidget.saveWidgetData<String>('weather_icon$suffix', _wmoToIcon(dominantWmo));
        // await HomeWidget.saveWidgetData<String>('tide_icon$suffix', '🌊');
        await HomeWidget.saveWidgetData<String>('tide_image$suffix', tideImagePath);

        await HomeWidget.saveWidgetData<String>('last_updated$suffix', 'Updated: $dateStr');
        
        await HomeWidget.saveWidgetData<String>('location_id$suffix', location.id!); // Verify ID persistence

        await HomeWidget.updateWidget(
          name: 'MarineWidgetProvider',
          androidName: 'MarineWidgetProvider',
        );
      }
    } catch (e) {
      print('Widget Update Error: $e');
    }
  }


  String _wmoToIcon(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '🌨️';
    if (code <= 82) return '🌧️';
    if (code <= 86) return '🌨️';
    return '⛈️';
  }

  // --- Geoutil Helpers ---
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p)/2 + 
              cos(lat1 * p) * cos(lat2 * p) * 
              (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a));
  }

  String _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180;
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;
    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    final brng = (atan2(y, x) * 180 / pi + 360) % 360;
    
    if (brng >= 337.5 || brng < 22.5) return 'N';
    if (brng >= 22.5 && brng < 67.5) return 'NE';
    if (brng >= 67.5 && brng < 112.5) return 'E';
    if (brng >= 112.5 && brng < 157.5) return 'SE';
    if (brng >= 157.5 && brng < 202.5) return 'S';
    if (brng >= 202.5 && brng < 247.5) return 'SW';
    if (brng >= 247.5 && brng < 292.5) return 'W';
    return 'NW';
  }
}
