/// Swell data from marine API
class SwellData {
  final double height;       // Total significant wave height
  final int direction;
  final int period;          // Total wave period
  final double seaTemperature;
  final double windWaveHeight;   // Wind-generated chop (NEW)
  final double swellWaveHeight;  // Ground swell height (NEW)
  final int swellWavePeriod;     // Ground swell period (NEW)

  SwellData({
    required this.height,
    required this.direction,
    required this.period,
    required this.seaTemperature,
    this.windWaveHeight = 0.0,
    this.swellWaveHeight = 0.0,
    this.swellWavePeriod = 0,
  });

  Map<String, dynamic> toJson() => {
    'height': height,
    'direction': direction,
    'period': period,
    'seaTemperature': seaTemperature,
    'windWaveHeight': windWaveHeight,
    'swellWaveHeight': swellWaveHeight,
    'swellWavePeriod': swellWavePeriod,
  };

  factory SwellData.fromJson(Map<String, dynamic> json) => SwellData(
    height: (json['height'] as num).toDouble(),
    direction: json['direction'] as int,
    period: json['period'] as int,
    seaTemperature: (json['seaTemperature'] as num).toDouble(),
    windWaveHeight: (json['windWaveHeight'] as num?)?.toDouble() ?? 0.0,
    swellWaveHeight: (json['swellWaveHeight'] as num?)?.toDouble() ?? 0.0,
    swellWavePeriod: (json['swellWavePeriod'] as num?)?.toInt() ?? 0,
  );
}

/// Weather data from forecast API
class WeatherData {
  final double temperature;
  final int windSpeed;
  final int windDirection;
  final int wmoCode;
  final int precipitationProbability;
  final int cloudCover;
  final double? precipitation;
  final double? windGust; // New: From Met Éireann
  final String? source;   // New: "Met Éireann" or "Open-Meteo"

  WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.wmoCode,
    required this.precipitationProbability,
    required this.cloudCover,
    this.precipitation,
    this.windGust,
    this.source,
  });

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'windSpeed': windSpeed,
    'windDirection': windDirection,
    'wmoCode': wmoCode,
    'precipitationProbability': precipitationProbability,
    'cloudCover': cloudCover,
    'precipitation': precipitation,
    'windGust': windGust,
    'source': source,
  };

  factory WeatherData.fromJson(Map<String, dynamic> json) => WeatherData(
    temperature: (json['temperature'] as num).toDouble(),
    windSpeed: json['windSpeed'] as int,
    windDirection: json['windDirection'] as int,
    wmoCode: json['wmoCode'] as int,
    precipitationProbability: json['precipitationProbability'] as int? ?? 0,
    cloudCover: json['cloudCover'] as int? ?? 0,
    precipitation: (json['precipitation'] as num?)?.toDouble(),
    windGust: (json['windGust'] as num?)?.toDouble(),
    source: json['source'] as String?,
  );
}

/// Swim condition status
enum SwimCondition { calm, medium, rough, unsafe }

/// Pollution / Water Quality status
enum PollutionStatus { clean, moderate, high, unknown }

/// Diagnostics for calmness calculation
class SwimDiagnostics {
  final int deltaTheta;
  final String crossSeaLevel;
  final int directionPenalty;
  final int weatherPenalty;
  final double steepness;
  final double windSpeedMs;

  SwimDiagnostics({
    required this.deltaTheta,
    required this.crossSeaLevel,
    required this.directionPenalty,
    required this.weatherPenalty,
    required this.steepness,
    required this.windSpeedMs,
  });

  Map<String, dynamic> toJson() => {
    'deltaTheta': deltaTheta,
    'crossSeaLevel': crossSeaLevel,
    'directionPenalty': directionPenalty,
    'weatherPenalty': weatherPenalty,
    'steepness': steepness,
    'windSpeedMs': windSpeedMs,
  };

  factory SwimDiagnostics.fromJson(Map<String, dynamic> json) => SwimDiagnostics(
    deltaTheta: json['deltaTheta'] as int,
    crossSeaLevel: json['crossSeaLevel'] as String,
    directionPenalty: json['directionPenalty'] as int,
    weatherPenalty: json['weatherPenalty'] as int,
    steepness: (json['steepness'] as num).toDouble(),
    windSpeedMs: (json['windSpeedMs'] as num).toDouble(),
  );
}

/// Detailed swim condition with diagnostics
class SwimConditionDetail {
  final SwimCondition status;
  final String reason;
  final int roughnessIndex;
  final SwimDiagnostics? diagnostics;
  final Map<String, dynamic>? formulaBreakdown; // Changed to dynamic for nested maps

  SwimConditionDetail({
    required this.status,
    required this.reason,
    required this.roughnessIndex,
    this.diagnostics,
    this.formulaBreakdown,
  });

  Map<String, dynamic> toJson() => {
    'status': status.index,
    'reason': reason,
    'roughnessIndex': roughnessIndex,
    'diagnostics': diagnostics?.toJson(),
    'formulaBreakdown': formulaBreakdown,
  };

  factory SwimConditionDetail.fromJson(Map<String, dynamic> json) => SwimConditionDetail(
    status: SwimCondition.values[json['status'] as int],
    reason: json['reason'] as String,
    roughnessIndex: json['roughnessIndex'] as int,
    diagnostics: json['diagnostics'] != null 
        ? SwimDiagnostics.fromJson(json['diagnostics']) 
        : null,
    formulaBreakdown: json['formulaBreakdown'] != null
        ? Map<String, dynamic>.from(json['formulaBreakdown'])
        : null,
  );
}

/// Tide data from Marine Institute
class TideData {
  final DateTime time;
  final double level;
  final String status; // 'rising', 'falling', 'high', 'low'
  final int percentage;
  final bool isRising;

  TideData({
    required this.time,
    required this.level,
    required this.status,
    required this.percentage,
    required this.isRising,
  });

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'level': level,
    'status': status,
    'percentage': percentage,
    'isRising': isRising,
  };

  factory TideData.fromJson(Map<String, dynamic> json) => TideData(
    time: DateTime.parse(json['time'] as String),
    level: (json['level'] as num).toDouble(),
    status: json['status'] as String,
    percentage: json['percentage'] as int,
    isRising: json['isRising'] as bool? ?? (json['status'] == 'rising' || json['status'] == 'high'), // Fallback
  );
}

typedef TideResult = ({List<TideData> tides, String stationName});

/// Hourly forecast entry
class HourlyForecast {
  final DateTime time;
  final SwellData swell;
  final WeatherData weather;
  final SwimConditionDetail swimCondition;
  final bool isMetEireann;
  final String? tideStation;
  final double? lat;
  final double? lon;
  final TideData? tide;
  final String dataSource;           // e.g. "Met Éireann", "Open-Meteo"
  final Map<String, FieldProvenance>? provenance; // Interactive Provenance
  final PollutionStatus? pollutionWarning;

  HourlyForecast({
    required this.time,
    required this.swell,
    required this.weather,
    required this.swimCondition,
    this.isMetEireann = false,
    this.tideStation,
    this.lat,
    this.lon,
    this.tide,
    this.dataSource = 'Open-Meteo',
    this.provenance,
    this.pollutionWarning,
  });

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'swell': swell.toJson(),
    'weather': weather.toJson(),
    'swimCondition': swimCondition.toJson(),
    'isMetEireann': isMetEireann,
    'tideStation': tideStation,
    'lat': lat,
    'lon': lon,
    'tide': tide?.toJson(),
    'dataSource': dataSource,
    'provenance': provenance?.map((k, v) => MapEntry(k, v.toJson())),
    'pollutionWarning': pollutionWarning?.index,
  };

  factory HourlyForecast.fromJson(Map<String, dynamic> json) => HourlyForecast(
    time: DateTime.parse(json['time'] as String),
    swell: SwellData.fromJson(json['swell']),
    weather: WeatherData.fromJson(json['weather']),
    swimCondition: SwimConditionDetail.fromJson(json['swimCondition']),
    isMetEireann: json['isMetEireann'] as bool? ?? false,
    tideStation: json['tideStation'] as String?,
    lat: json['lat'] as double?,
    lon: json['lon'] as double?,
    tide: json['tide'] != null ? TideData.fromJson(json['tide']) : null,
    dataSource: json['dataSource'] as String? ?? 'Open-Meteo',
    provenance: json['provenance'] != null 
        ? (json['provenance'] as Map<String, dynamic>).map((k, v) => MapEntry(k, FieldProvenance.fromJson(v)))
        : null,
    pollutionWarning: json['pollutionWarning'] != null
        ? PollutionStatus.values[json['pollutionWarning'] as int]
        : null,
  );
}

/// Provenance for a specific data field
class FieldProvenance {
  final String sourceName; // e.g. "Met Éireann", "Open-Meteo Marine"
  final String logId;      // UUID binding to ApiLog used
  final String snippet;    // Small JSON/XML chunk showing the value
  final String keyPath;    // e.g. "hourly.temperature_2m[4]"

  FieldProvenance({
    required this.sourceName,
    required this.logId,
    required this.snippet,
    required this.keyPath,
  });

  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'logId': logId,
    'snippet': snippet,
    'keyPath': keyPath,
  };

  factory FieldProvenance.fromJson(Map<String, dynamic> json) => FieldProvenance(
    sourceName: json['sourceName'] as String,
    logId: json['logId'] as String,
    snippet: json['snippet'] as String,
    keyPath: json['keyPath'] as String,
  );
}

class ApiLog {
  final String id;
  final DateTime timestamp;
  final String url;
  final int status;
  final String body;
  final bool isMetEireann;
  final bool isFallback;
  final String? locationName;
  final String? requestLabel;

  ApiLog({
    required this.id,
    required this.timestamp,
    required this.url,
    required this.status,
    required this.body,
    this.isMetEireann = false,
    this.isFallback = false,
    this.locationName,
    this.requestLabel,
  });
}

/// Location
class Location {
  final String? id;
  final String name;
  final double lat;
  final double lon;
  final double? waterLat;
  final double? waterLon;

  Location({
    this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.waterLat,
    this.waterLon,
  });
}
