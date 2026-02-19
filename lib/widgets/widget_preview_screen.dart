import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as Math;
import '../models/marine_data.dart';
import 'weather_background.dart';
import 'tide_graphic.dart';

class WidgetPreviewScreen extends StatelessWidget {
  final List<HourlyForecast> forecasts;
  final String locationName;

  const WidgetPreviewScreen({
    super.key,
    required this.forecasts,
    required this.locationName,
  });

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

  Color _roughnessColor(int roughness) {
    if (roughness <= 25) return const Color(0xFF22C55E);
    if (roughness <= 50) return const Color(0xFF3B82F6);
    if (roughness <= 75) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  String _roughnessLabel(int roughness) {
    if (roughness <= 25) return 'Calm';
    if (roughness <= 50) return 'Moderate';
    if (roughness <= 75) return 'Choppy';
    return 'Intense';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Widget Preview'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Android Home Screen Widget',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '3 × 2 Grid',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            // Simulated phone home screen area
            Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF334155), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Status bar simulation
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(DateTime.now()),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.signal_cellular_4_bar, size: 12, color: Colors.white70),
                            SizedBox(width: 4),
                            Icon(Icons.wifi, size: 12, color: Colors.white70),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full, size: 12, color: Colors.white70),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // The actual widget
                  _buildWidget(),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Averages next 2 hours from now',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidget() {
    final now = DateTime.now();
    final upcoming = forecasts.where((f) =>
      f.time.year == now.year &&
      f.time.month == now.month &&
      f.time.day == now.day &&
      f.time.hour >= now.hour &&
      f.time.hour < now.hour + 2
    ).toList();

    if (upcoming.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'No data available for next 2 hours',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    final avgTemp = upcoming.map((f) => f.weather.temperature).reduce((a, b) => a + b) / upcoming.length;
    final avgWind = upcoming.map((f) => f.weather.windSpeed).reduce((a, b) => a + b) / upcoming.length;
    final avgPrecip = (upcoming.map((f) => f.weather.precipitationProbability).reduce((a, b) => a + b) / upcoming.length).round();
    final avgTide = upcoming.where((f) => f.tide != null).map((f) => f.tide!.level).fold(0.0, (a, b) => a + b);
    final tideCount = upcoming.where((f) => f.tide != null).length;
    final tideAvg = tideCount > 0 ? avgTide / tideCount : null;
    final avgRoughness = (upcoming.map((f) => f.swimCondition.roughnessIndex).reduce((a, b) => a + b) / upcoming.length).round();
    final dominantWmo = upcoming.first.weather.wmoCode;
    final tideStatus = upcoming.where((f) => f.tide != null).isNotEmpty
        ? upcoming.firstWhere((f) => f.tide != null).tide!.status
        : null;

    final tidePercentageAvg = tideCount > 0 
        ? (upcoming.where((f) => f.tide != null).map((f) => f.tide!.percentage).reduce((a, b) => a + b) / tideCount).round()
        : null;

    final roughColor = _roughnessColor(avgRoughness);
    final tideColor = tideAvg != null 
        ? (tideStatus == 'high' ? const Color(0xFF4ADE80) : tideStatus == 'low' ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))
        : const Color(0xFF4CC9F0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                   const Icon(Icons.waves, color: Color(0xFF3B82F6), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    locationName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF8FAFC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: roughColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: roughColor.withOpacity(0.4)),
                ),
                child: Text(
                  _roughnessLabel(avgRoughness).toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    color: roughColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3-column data
          Row(
            children: [
              // Weather column
              Expanded(
                child: Column(
                  children: [
                    Text(_wmoToIcon(dominantWmo), style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 2),
                    Text(
                      '${avgTemp.toStringAsFixed(0)}°C',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                    Text(
                      '${avgWind.toStringAsFixed(0)}km/h',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                    ),
                    if (avgPrecip > 0)
                      Text(
                        '💧$avgPrecip%',
                        style: const TextStyle(fontSize: 9, color: Color(0xFF38BDF8)),
                      ),
                  ],
                ),
              ),
              // Tide column
              Expanded(
                child: Column(
                  children: [
                    TideGraphic(percentage: tidePercentageAvg ?? 0, color: tideColor),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          tideAvg != null ? '${tideAvg.toStringAsFixed(1)}m' : '--',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: tideColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          tideStatus != null
                              ? '${tideStatus == "rising" || tideStatus == "high" ? "↑" : "↓"}'
                              : '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: tideColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Roughness column
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: roughColor.withOpacity(0.2),
                        border: Border.all(color: roughColor, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '$avgRoughness',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: roughColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roughnessLabel(avgRoughness),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: roughColor,
                      ),
                    ),
                    const Text(
                      'Roughness',
                      style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 10, color: Color(0xFF475569)),
              const SizedBox(width: 3),
              Text(
                'Next 2h · ${DateFormat('HH:mm').format(DateTime.now())}',
                style: const TextStyle(fontSize: 9, color: Color(0xFF475569)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
