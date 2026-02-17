import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marine_data.dart';

/// Saved location with caching
class SavedLocation {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final bool isCurrentLocation;
  final DateTime? addedAt;
  final double? waterLat;
  final double? waterLon;

  SavedLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.isCurrentLocation = false,
    this.addedAt,
    this.waterLat,
    this.waterLon,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lon': lon,
    'isCurrentLocation': isCurrentLocation,
    'addedAt': addedAt?.toIso8601String(),
    'waterLat': waterLat,
    'waterLon': waterLon,
  };

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'],
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    isCurrentLocation: json['isCurrentLocation'] ?? false,
    addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : null,
    waterLat: (json['waterLat'] as num?)?.toDouble(),
    waterLon: (json['waterLon'] as num?)?.toDouble(),
  );
}

/// Default Irish coastal locations
final List<SavedLocation> defaultLocations = [
  SavedLocation(
    id: 'tramore',
    name: 'Tramore',
    lat: 52.1608,
    lon: -7.1508,
  ),
  SavedLocation(
    id: 'dunmore-east',
    name: 'Dunmore East',
    lat: 52.1500,
    lon: -6.9833,
  ),
  SavedLocation(
    id: 'ardmore',
    name: 'Ardmore',
    lat: 51.9489,
    lon: -7.7261,
  ),
  SavedLocation(
    id: 'buncrana',
    name: 'Buncrana',
    lat: 55.1336,
    lon: -7.4536,
  ),
  SavedLocation(
    id: 'sandycove',
    name: 'Sandycove',
    lat: 53.2881,
    lon: -6.1139,
  ),
  SavedLocation(
    id: 'lahinch',
    name: 'Lahinch',
    lat: 52.9331,
    lon: -9.3481,
  ),
];

class LocationService {
  static const _storageKey = 'saved_locations';
  static const _selectedKey = 'selected_location';

  /// Load saved locations from storage
  Future<List<SavedLocation>> getSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    if (data == null) {
      // Return defaults on first run
      // Return defaults on first run AND save them so native side can see them
      await saveLocations(defaultLocations);
      return defaultLocations;
    }
    
    try {
      final list = json.decode(data) as List;
      return list.map((e) => SavedLocation.fromJson(e)).toList();
    } catch (e) {
      return defaultLocations;
    }
  }

  /// Save locations to storage
  Future<void> saveLocations(List<SavedLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(locations.map((l) => l.toJson()).toList()));
  }

  /// Add a new location
  Future<void> addLocation(SavedLocation location) async {
    final locations = await getSavedLocations();
    locations.add(location);
    await saveLocations(locations);
  }

  /// Remove a location
  Future<void> removeLocation(String id) async {
    final locations = await getSavedLocations();
    locations.removeWhere((l) => l.id == id);
    await saveLocations(locations);
  }

  /// Get selected location
  Future<SavedLocation> getSelectedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString(_selectedKey);
    final locations = await getSavedLocations();
    
    if (selectedId != null) {
      final found = locations.where((l) => l.id == selectedId);
      if (found.isNotEmpty) return found.first;
    }
    
    return locations.isNotEmpty ? locations.first : defaultLocations.first;
  }

  /// Set selected location
  Future<void> setSelectedLocation(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedKey, id);
  }

  /// Update an existing location (e.g. adding water coordinates)
  Future<void> updateLocation(SavedLocation updated) async {
    final locations = await getSavedLocations();
    final index = locations.indexWhere((l) => l.id == updated.id);
    if (index != -1) {
      locations[index] = updated;
      await saveLocations(locations);
    }
  }
}
