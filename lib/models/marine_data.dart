// Marine data models for MarineCheck Flutter app

class SwellData {
  final double height;
  final int direction;
  final int period;
  final double seaTemperature;

  SwellData({
    required this.height,
    required this.direction,
    required this.period,
    required this.seaTemperature,
  });

  factory SwellData.fromJson(Map<String, dynamic> json, int hourIndex) {
    final hourly = json['hourly'] as Map<String, dynamic>;
    return SwellData(
      height: (hourly['wave_height']?[hourIndex] ?? 0).toDouble(),
      direction: (hourly['wave_direction']?[hourIndex] ?? 0).toInt(),
      period: (hourly['wave_period']?[hourIndex] ?? 0).toInt(),
      seaTemperature: (hourly['sea_surface_temperature']?[hourIndex] ?? 0).toDouble(),
    );
  }
}

class WeatherData {
  final double temperature;
  final int windSpeed;
  final int windDirection;
  final int wmoCode;

  WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.wmoCode,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json, int hourIndex) {
    final hourly = json['hourly'] as Map<String, dynamic>;
    return WeatherData(
      temperature: (hourly['temperature_2m']?[hourIndex] ?? 0).toDouble(),
      windSpeed: (hourly['wind_speed_10m']?[hourIndex] ?? 0).round(),
      windDirection: (hourly['wind_direction_10m']?[hourIndex] ?? 0).round(),
      wmoCode: (hourly['weather_code']?[hourIndex] ?? 0).toInt(),
    );
  }
}

enum SwimCondition { unsafe, rough, medium, calm }

class SwimConditionDetail {
  final SwimCondition status;
  final String reason;
  final int calmnessIndex;

  SwimConditionDetail({
    required this.status,
    required this.reason,
    required this.calmnessIndex,
  });

  String get icon {
    switch (status) {
      case SwimCondition.unsafe:
        return '🛑';
      case SwimCondition.rough:
        return '⚠️';
      case SwimCondition.medium:
        return '🆗';
      case SwimCondition.calm:
        return '✅';
    }
  }
}

class HourlyForecast {
  final DateTime time;
  final SwellData swell;
  final WeatherData weather;
  final SwimConditionDetail swimCondition;

  HourlyForecast({
    required this.time,
    required this.swell,
    required this.weather,
    required this.swimCondition,
  });
}

class Location {
  final String name;
  final double lat;
  final double lon;
  final bool isCoastal;

  Location({
    required this.name,
    required this.lat,
    required this.lon,
    this.isCoastal = true,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lon': lon,
    'isCoastal': isCoastal,
  };

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    name: json['name'],
    lat: json['lat'],
    lon: json['lon'],
    isCoastal: json['isCoastal'] ?? true,
  );
}
