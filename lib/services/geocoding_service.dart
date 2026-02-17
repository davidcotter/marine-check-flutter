import 'dart:convert';
import 'package:http/http.dart' as http;

/// Geocoding result from Open-Meteo
class GeocodingResult {
  final String name;
  final double lat;
  final double lon;
  final String? admin1; // State/region
  final String country;
  final String? countryCode;

  GeocodingResult({
    required this.name,
    required this.lat,
    required this.lon,
    this.admin1,
    required this.country,
    this.countryCode,
  });

  factory GeocodingResult.fromJson(Map<String, dynamic> json) => GeocodingResult(
    name: json['name'] ?? 'Unknown',
    lat: (json['latitude'] as num).toDouble(),
    lon: (json['longitude'] as num).toDouble(),
    admin1: json['admin1'],
    country: json['country'] ?? '',
    countryCode: json['country_code'],
  );

  String get displayName {
    final parts = <String>[name];
    if (admin1 != null && admin1!.isNotEmpty) parts.add(admin1!);
    parts.add(country);
    return parts.join(', ');
  }
}

class GeocodingService {
  static const _baseUrl = 'https://geocoding-api.open-meteo.com/v1/search';

  /// Search for locations by name
  Future<List<GeocodingResult>> searchLocations(String query) async {
    if (query.length < 2) return [];

    final uri = Uri.parse('$_baseUrl?name=$query&count=10&language=en&format=json');
    
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Geocoding API error: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final results = data['results'] as List? ?? [];
      
      return results.map((r) => GeocodingResult.fromJson(r)).toList();
    } catch (e) {
      print('Geocoding error: $e');
      return [];
    }
  }
}
