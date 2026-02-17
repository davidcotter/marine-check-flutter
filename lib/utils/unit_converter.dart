import '../services/settings_service.dart';

class UnitConverter {
  // Wind Speed
  static String formatWind(double kmh) {
    if (kmh < 0) return '--';
    
    switch (SettingsService.windUnit) {
      case WindUnit.kmh:
        return '${kmh.round()} km/h';
      case WindUnit.mph:
        return '${(kmh * 0.621371).round()} mph';
      case WindUnit.knots:
        return '${(kmh * 0.539957).round()} kn';
      case WindUnit.ms:
        return '${(kmh * 0.277778).toStringAsFixed(1)} m/s';
      case WindUnit.beaufort:
        return 'F${_toBeaufort(kmh)}';
    }
  }

  static int _toBeaufort(double kmh) {
    if (kmh < 1) return 0;
    if (kmh <= 5) return 1;
    if (kmh <= 11) return 2;
    if (kmh <= 19) return 3;
    if (kmh <= 28) return 4;
    if (kmh <= 38) return 5;
    if (kmh <= 49) return 6;
    if (kmh <= 61) return 7;
    if (kmh <= 74) return 8;
    if (kmh <= 88) return 9;
    if (kmh <= 102) return 10;
    if (kmh <= 117) return 11;
    return 12;
  }

  // Temperature
  static String formatTemp(double celsius) {
    switch (SettingsService.tempUnit) {
      case TempUnit.celsius:
        return '${celsius.round()}°C';
      case TempUnit.fahrenheit:
        return '${((celsius * 9 / 5) + 32).round()}°F';
    }
  }

  // Height (Tide/Wave)
  static String formatHeight(double meters) {
    switch (SettingsService.heightUnit) {
      case HeightUnit.meters:
        return '${meters.toStringAsFixed(2)}m';
      case HeightUnit.feet:
        return '${(meters * 3.28084).toStringAsFixed(1)}ft';
    }
  }

  // Roughness Safety Logic
  static ({String label, int color}) getRoughnessStatus(int roughnesIndex) {
    if (roughnesIndex <= 20) {
      return (label: 'Calm', color: 0xFF22C55E); // Green
    } else if (roughnesIndex <= 40) {
      return (label: 'Medium', color: 0xFF3B82F6); // Blue
    } else if (roughnesIndex <= 60) {
      return (label: 'Rough', color: 0xFFF97316); // Orange
    } else {
      return (label: 'Unsafe', color: 0xFFEF4444); // Red
    }
  }

  static int getTideColor(String status) {
    switch (status.toLowerCase()) {
      case 'high': return 0xFF4ADE80; // Green-400
      case 'low': return 0xFFEF4444;  // Red-500
      default: return 0xFFF59E0B;     // Amber-500
    }
  }
}
