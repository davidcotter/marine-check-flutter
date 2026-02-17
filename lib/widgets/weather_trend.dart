import 'package:flutter/material.dart';
import '../models/marine_data.dart';

/// Weather trend display showing ±3 hours around selected time
class WeatherTrend extends StatelessWidget {
  final List<HourlyForecast> hours;
  final int selectedHourIndex;

  const WeatherTrend({
    super.key,
    required this.hours,
    required this.selectedHourIndex,
  });

  String _getWeatherIcon(int wmoCode) {
    if (wmoCode == 0) return '☀️';
    if (wmoCode <= 3) return '⛅';
    if (wmoCode <= 49) return '🌫️';
    if (wmoCode <= 69) return '🌧️';
    if (wmoCode <= 79) return '🌨️';
    if (wmoCode <= 82) return '🌧️';
    if (wmoCode <= 86) return '🌨️';
    return '⛈️';
  }

  @override
  Widget build(BuildContext context) {
    // Get ±3 hours around selected
    final startIdx = (selectedHourIndex - 3).clamp(0, hours.length - 1);
    final endIdx = (selectedHourIndex + 4).clamp(0, hours.length);
    final trendHours = hours.sublist(startIdx, endIdx);

    if (trendHours.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: trendHours.asMap().entries.map((entry) {
          final i = entry.key;
          final h = entry.value;
          final isSelected = startIdx + i == selectedHourIndex;

          return Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                  : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                  : null,
            ),
            child: Column(
              children: [
                Text(
                  '${h.time.hour.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getWeatherIcon(h.weather.wmoCode),
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  '${h.weather.temperature.round()}°',
                  style: const TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${h.weather.windSpeed}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
