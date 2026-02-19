import 'package:flutter/material.dart';
import '../models/marine_data.dart';
import '../utils/unit_converter.dart';
import 'tide_graphic.dart';
import 'animated_wave_widget.dart';

class ForecastSummaryCard extends StatelessWidget {
  final String title;
  final List<HourlyForecast> forecasts;
  final bool isMetEireann;
  final String? message;

  const ForecastSummaryCard({
    super.key,
    required this.title,
    required this.forecasts,
    this.isMetEireann = true,
    this.message,
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

  @override
  Widget build(BuildContext context) {
    if (forecasts.isEmpty) return const SizedBox.shrink();

    // Compute averages/dominant values
    final avgTemp = forecasts.map((f) => f.weather.temperature).reduce((a, b) => a + b) / forecasts.length;
    final avgWind = forecasts.map((f) => f.weather.windSpeed).reduce((a, b) => a + b) / forecasts.length;
    final avgPrecip = (forecasts.map((f) => f.weather.precipitationProbability).reduce((a, b) => a + b) / forecasts.length).round();
    final avgTide = forecasts.where((f) => f.tide != null).map((f) => f.tide!.level).fold(0.0, (a, b) => a + b);
    final tideCount = forecasts.where((f) => f.tide != null).length;
    final tideAvg = tideCount > 0 ? avgTide / tideCount : null;
    final avgRoughness = (forecasts.map((f) => f.swimCondition.roughnessIndex).reduce((a, b) => a + b) / forecasts.length).round();
    final dominantWmo = forecasts.first.weather.wmoCode;
    final tideStatus = forecasts.where((f) => f.tide != null).isNotEmpty 
        ? forecasts.firstWhere((f) => f.tide != null).tide!.status 
        : null;
    final avgPercentage = tideCount > 0 
          ? (forecasts.where((f) => f.tide != null).map((f) => f.tide!.percentage).reduce((a, b) => a + b) / tideCount).round()
          : 50;

    final roughnessStatus = UnitConverter.getRoughnessStatus(avgRoughness);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              if (!isMetEireann)
                const Text(
                  'FALLBACK*',
                  style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              // Weather
              Expanded(
                child: Column(
                  children: [
                    Text(_wmoToIcon(dominantWmo), style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 2),
                    Text(
                      UnitConverter.formatTemp(avgTemp),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    Text(
                      UnitConverter.formatWind(avgWind),
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      'Rain $avgPrecip%', 
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
                    ),
                  ],
                ),
              ),
              // Tide
              Expanded(
                child: Column(
                  children: [
                    TideGraphic(
                      percentage: avgPercentage,
                      color: Color(UnitConverter.getTideColor(tideStatus ?? 'neutral')),
                      width: 40,
                      height: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tideAvg != null ? UnitConverter.formatHeight(tideAvg) : '--',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                    ),
                    Text(
                      tideStatus ?? '--',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // Sea State (wave widget, same as hourly rows)
              Expanded(
                child: Column(
                  children: [
                    AnimatedWaveWidget(
                      count: avgRoughness <= 20 ? 1 : avgRoughness <= 40 ? 2 : 3,
                      color: Color(roughnessStatus.color),
                      size: 22,
                      speed: avgRoughness <= 20 ? 0.5 : avgRoughness <= 40 ? 1.0 : avgRoughness <= 60 ? 1.8 : 2.5,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roughnessStatus.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(roughnessStatus.color)),
                    ),
                    Text(
                      'Sea State',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
