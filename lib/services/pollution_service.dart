import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/marine_data.dart';
import 'marine_service.dart';

/// Sewage / Water Quality monitoring service
/// Ireland: EPA bathing water + 48h rainfall rule
/// UK: Environment Agency STP risk prediction
/// Degrades gracefully — never blocks forecast display
class PollutionService {
  // Known river/sewage outflow coordinates in Ireland (lat, lon, radius_km)
  // These are major outflows near popular swim spots
  static const _knownOutflows = [
    (52.26, -6.95, 3.0),  // Waterford (Suir estuary)
    (53.34, -6.26, 4.0),  // Dublin (Liffey/Tolka)
    (51.90, -8.47, 3.0),  // Cork (Lee estuary)
    (52.66, -8.63, 3.0),  // Limerick (Shannon)
    (54.60, -5.93, 3.0),  // Belfast (Lagan)
    (53.27, -9.05, 2.0),  // Galway (Corrib)
  ];

  /// Check pollution status for a location
  /// [recentRainfall48h] = sum of precipitation in mm over last 48 hours
  static Future<PollutionStatus> checkPollution({
    required double lat,
    required double lon,
    required double recentRainfall48h,
  }) async {
    try {
      if (MarineService.isIreland(lat, lon)) {
        return await _checkIreland(lat, lon, recentRainfall48h);
      } else if (MarineService.isUK(lat, lon)) {
        return await _checkUK(lat, lon);
      }
      return PollutionStatus.unknown;
    } catch (e) {
      print('PollutionService: Error: $e');
      return PollutionStatus.unknown;
    }
  }

  /// Ireland: Check EPA bathing water API + 48h rainfall rule
  static Future<PollutionStatus> _checkIreland(
    double lat, double lon, double rainfall48h,
  ) async {
    // 1. Try EPA API first
    try {
      final epaStatus = await _fetchEPAStatus(lat, lon);
      if (epaStatus != PollutionStatus.unknown) {
        return epaStatus;
      }
    } catch (e) {
      print('PollutionService: EPA API unavailable: $e');
    }

    // 2. Fallback: 48-hour Rainfall Proxy Rule
    // West Coast Ireland: agricultural runoff (slurry) is the main risk
    // This usually triggers after heavy rain.
    if (rainfall48h > 12.0) {
      return PollutionStatus.high;  // HIGH RISK (Agricultural Runoff/Overflow)
    } else if (rainfall48h > 7.0) {
      return PollutionStatus.moderate;  // MODERATE RISK (Caution advised)
    }

    return PollutionStatus.clean;  // LOW RISK
  }

  /// Fetch EPA bathing water status
  static Future<PollutionStatus> _fetchEPAStatus(double lat, double lon) async {
    final uri = Uri.parse(
      'https://data.epa.ie/api/v1/bathing-water-quality'
      '?lat=$lat&lon=$lon&radius=5'
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return PollutionStatus.unknown;

    final data = json.decode(response.body);
    // Parse based on EPA response structure — look for active incidents
    if (data is Map && data.containsKey('results')) {
      final results = data['results'] as List?;
      if (results != null && results.isNotEmpty) {
        for (final result in results) {
          final status = (result['status'] ?? '').toString().toLowerCase();
          if (status.contains('warning') || status.contains('poor')) {
            return PollutionStatus.high;
          }
          if (status.contains('sufficient') || status.contains('moderate')) {
            return PollutionStatus.moderate;
          }
        }
        return PollutionStatus.clean;
      }
    }
    return PollutionStatus.unknown;
  }

  /// UK: Check Environment Agency STP risk prediction
  static Future<PollutionStatus> _checkUK(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://environment.data.gov.uk/doc/bathing-water-quality'
        '/stp-risk-prediction.json?lat=$lat&long=$lon&dist=5'
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return PollutionStatus.unknown;

      final data = json.decode(response.body);
      // Parse Environment Agency response
      if (data is Map && data.containsKey('result')) {
        final items = data['result']['items'] as List?;
        if (items != null && items.isNotEmpty) {
          for (final item in items) {
            final risk = (item['riskLevel'] ?? '').toString().toLowerCase();
            if (risk.contains('increased') || risk.contains('high')) {
              return PollutionStatus.high;
            }
            if (risk.contains('normal') || risk.contains('low')) {
              return PollutionStatus.clean;
            }
          }
        }
      }
      return PollutionStatus.unknown;
    } catch (e) {
      print('PollutionService: UK API unavailable: $e');
      return PollutionStatus.unknown;
    }
  }

  /// Check if coordinates are within proximity of a known outflow
  static bool _isNearOutflow(double lat, double lon) {
    for (final outflow in _knownOutflows) {
      final dLat = lat - outflow.$1;
      final dLon = lon - outflow.$2;
      // Rough km calculation (1° lat ≈ 111km, 1° lon ≈ 65km at Irish latitudes)
      final distKm = (dLat * dLat * 111 * 111 + dLon * dLon * 65 * 65);
      if (distKm < outflow.$3 * outflow.$3 * 111 * 111) {
        return true;
      }
    }
    return false;
  }

  /// Human-readable label for pollution status
  static String label(PollutionStatus status) {
    switch (status) {
      case PollutionStatus.clean:
        return 'Water Quality: Good';
      case PollutionStatus.moderate:
        return 'Water Quality: Moderate Risk';
      case PollutionStatus.high:
        return '⚠️ Water Quality: High Risk';
      case PollutionStatus.unknown:
        return 'Water Quality: Unknown';
    }
  }
}
