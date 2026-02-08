import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/marine_data.dart';

class MarineService {
  static const _marineBaseUrl = 'https://marine-api.open-meteo.com/v1/marine';
  static const _weatherBaseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Fetch wave/swell data from Open-Meteo Marine API
  Future<Map<String, dynamic>> fetchSwellData(double lat, double lon) async {
    final uri = Uri.parse(_marineBaseUrl).replace(queryParameters: {
      'latitude': lat.toString(),
      'longitude': lon.toString(),
      'hourly': 'wave_height,wave_direction,wave_period,sea_surface_temperature',
      'forecast_days': '7',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch swell data: ${response.statusCode}');
    }
    return json.decode(response.body);
  }

  /// Fetch weather data from Open-Meteo Weather API
  Future<Map<String, dynamic>> fetchWeatherData(double lat, double lon) async {
    final uri = Uri.parse(_weatherBaseUrl).replace(queryParameters: {
      'latitude': lat.toString(),
      'longitude': lon.toString(),
      'hourly': 'temperature_2m,wind_speed_10m,wind_direction_10m,weather_code',
      'forecast_days': '7',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch weather data: ${response.statusCode}');
    }
    return json.decode(response.body);
  }

  /// Calculate swim condition based on wave and weather data
  SwimConditionDetail calculateSwimCondition({
    required double waveHeight,
    required int waveDirection,
    required int wavePeriod,
    required int windSpeed,
    required int windDirection,
    required int wmoCode,
  }) {
    // Convert wind speed from km/h to m/s
    final windSpeedMs = windSpeed / 3.6;

    // Calculate wave steepness
    final wavelength = 1.56 * wavePeriod * wavePeriod;
    final steepness = wavelength > 0 ? waveHeight / wavelength : 0.0;

    // Base calmness score (0-1)
    var base = 0.40 * max(0.0, 1 - waveHeight / 3) +
        0.25 * max(0.0, 1 - windSpeedMs / 20) +
        0.20 * max(0.0, 1 - steepness / 0.08) +
        0.15 * max(0.0, 1 - (wavePeriod - 10).abs() / 10);

    // Direction difference (0-180)
    final deltaTheta = min(
      (windDirection - waveDirection).abs(),
      360 - (windDirection - waveDirection).abs(),
    );

    // Cross-sea penalty (60-120° is danger zone)
    double directionPenalty = 0;
    String crossSeaLevel = 'aligned';
    if (deltaTheta >= 60 && deltaTheta <= 120) {
      directionPenalty = 0.4;
      crossSeaLevel = 'cross-sea';
    } else if ((deltaTheta >= 45 && deltaTheta < 60) || (deltaTheta > 120 && deltaTheta <= 135)) {
      directionPenalty = 0.2;
      crossSeaLevel = 'moderate';
    }

    // Weather penalty
    double weatherPenalty = 0;
    if (wmoCode >= 95) weatherPenalty = 0.6;
    else if (wmoCode >= 80) weatherPenalty = 0.4;
    else if (wmoCode >= 61) weatherPenalty = 0.2;
    else if (wmoCode >= 51) weatherPenalty = 0.1;

    // Final calmness index (0-100)
    var ci = (100 * base * (1 - directionPenalty) * (1 - weatherPenalty)).clamp(0.0, 100.0);

    // Hard safety overrides
    SwimCondition status;
    String reason;

    final ripTideWarning = crossSeaLevel == 'cross-sea'
        ? '⚠️ Rip Tide Risk (${deltaTheta.round()}° cross-sea)'
        : '';

    if (waveHeight >= 4 || windSpeed >= 72 || wmoCode >= 95) {
      status = SwimCondition.unsafe;
      ci = min(ci, 20);
      reason = waveHeight >= 4 ? 'Dangerous: Extreme Waves' 
          : windSpeed >= 72 ? 'Dangerous: Storm Winds' 
          : 'Dangerous: Severe Weather';
    } else if (crossSeaLevel == 'cross-sea' && ci < 60) {
      status = SwimCondition.rough;
      reason = ripTideWarning;
    } else if (ci >= 75) {
      status = SwimCondition.calm;
      reason = ripTideWarning.isNotEmpty ? ripTideWarning : 'Ideal Glassy Conditions';
    } else if (ci >= 50) {
      status = SwimCondition.medium;
      reason = ripTideWarning.isNotEmpty ? ripTideWarning : 'Standard conditions';
    } else if (ci >= 25) {
      status = SwimCondition.rough;
      reason = ripTideWarning.isNotEmpty ? ripTideWarning : 'Choppy conditions';
    } else {
      status = SwimCondition.unsafe;
      reason = ripTideWarning.isNotEmpty ? ripTideWarning : 'Poor swimming outlook';
    }

    return SwimConditionDetail(
      status: status,
      reason: reason,
      calmnessIndex: ci.round(),
    );
  }

  /// Fetch all marine data for a location
  Future<List<HourlyForecast>> fetchForecasts(Location location) async {
    final swellData = await fetchSwellData(location.lat, location.lon);
    final weatherData = await fetchWeatherData(location.lat, location.lon);

    final swellTimes = (swellData['hourly']['time'] as List).cast<String>();
    final forecasts = <HourlyForecast>[];

    for (var i = 0; i < swellTimes.length && i < 168; i++) { // Max 7 days
      final time = DateTime.parse(swellTimes[i]);
      final swell = SwellData.fromJson(swellData, i);
      final weather = WeatherData.fromJson(weatherData, i);
      
      final condition = calculateSwimCondition(
        waveHeight: swell.height,
        waveDirection: swell.direction,
        wavePeriod: swell.period,
        windSpeed: weather.windSpeed,
        windDirection: weather.windDirection,
        wmoCode: weather.wmoCode,
      );

      forecasts.add(HourlyForecast(
        time: time,
        swell: swell,
        weather: weather,
        swimCondition: condition,
      ));
    }

    return forecasts;
  }
}
