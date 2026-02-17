import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/marine_data.dart';
import '../services/tide_service.dart';
import '../services/location_service.dart';
import '../utils/unit_converter.dart';
import 'tide_curve.dart';
import 'wave_visualization.dart';
import 'weather_trend.dart';
import 'roughness_explanation_modal.dart';
import 'tide_graphic.dart';
import 'share_modal.dart';
import '../screens/debug_log_screen.dart';

/// Hour detail bottom sheet with full data display and visualizations
class HourDetailSheet extends StatefulWidget {
  final HourlyForecast forecast;
  final TideData? tide;
  final MoonPhase moonPhase;
  final List<HourlyForecast>? allHours;
  final List<double>? tideLevels;
  final String locationName;
  final SavedLocation? savedLocation;

  const HourDetailSheet({
    super.key,
    required this.forecast,
    this.tide,
    required this.moonPhase,
    this.allHours,
    this.tideLevels,
    required this.locationName,
    this.savedLocation,
  });

  @override
  State<HourDetailSheet> createState() => _HourDetailSheetState();
}

class _HourDetailSheetState extends State<HourDetailSheet> {
  Color get _statusColor {
    switch (widget.forecast.swimCondition.status) {
      case SwimCondition.unsafe: return const Color(0xFFEF4444);
      case SwimCondition.rough: return const Color(0xFFF97316);
      case SwimCondition.medium: return const Color(0xFF3B82F6);
      case SwimCondition.calm: return const Color(0xFF22C55E);
    }
  }

  String get _statusLabel {
    switch (widget.forecast.swimCondition.status) {
      case SwimCondition.unsafe: return 'UNSAFE';
      case SwimCondition.rough: return 'ROUGH';
      case SwimCondition.medium: return 'MEDIUM';
      case SwimCondition.calm: return 'CALM';
    }
  }

  String get _weatherIcon {
    final code = widget.forecast.weather.wmoCode;
    if (code == 0) return '☀️'; // Clear
    if (code <= 3) return '⛅'; // Partly cloudy
    if (code <= 49) return '🌫️'; // Fog
    if (code <= 69) return '🌧️'; // Rain
    if (code <= 79) return '🌨️'; // Snow
    if (code <= 82) return '🌧️'; // Showers
    if (code <= 86) return '🌨️'; // Snow Showers
    return '⛈️'; // Thunderstorm
  }

  String _getWindArrow(int deg) {
    const arrows = ['↓', '↙', '←', '↖', '↑', '↗', '→', '↘'];
    return arrows[(deg / 45).round() % 8];
  }

  String _getSwellArrow(int deg) {
    const arrows = ['↓', '↙', '←', '↖', '↑', '↗', '→', '↘'];
    return arrows[(deg / 45).round() % 8];
  }

  void _showGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RoughnessExplanationModal(forecast: widget.forecast),
    );
  }

  void _shareForecast() {
    // Close the detail sheet and signal the parent to open the share modal
    Navigator.pop(context, 'share');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final timeStr = '${widget.forecast.time.hour.toString().padLeft(2, '0')}:00';
    final selectedHourIndex = widget.allHours?.indexWhere((h) => 
        h.time.hour == widget.forecast.time.hour) ?? -1;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Time header with Share button
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    icon: Icon(Icons.ios_share, color: colorScheme.primary),
                    onPressed: _shareForecast,
                    tooltip: 'Share Dip Report',
                  ),
                ),
              ],
            ),
            if (widget.tide != null) ...[
              const SizedBox(height: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TideGraphic(
                    percentage: widget.tide!.percentage,
                    color: Color(UnitConverter.getTideColor(widget.tide!.status)),
                    width: 42,
                    height: 24,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                    UnitConverter.formatHeight(widget.tide!.level),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(UnitConverter.getTideColor(widget.tide!.status)),
                    ),
                  ),
                      const SizedBox(width: 4),
                      Text(
                        widget.tide!.isRising ? '↑' : '↓',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(UnitConverter.getTideColor(widget.tide!.status)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            
            // Status header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.forecast.swimCondition.reason,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Roughness Analytics Section
            _SectionTitle(
              title: 'Roughness Analytics',
              trailing: GestureDetector(
                onTap: _showGuide,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'GUIDE ℹ️',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant, 
                      fontSize: 10, 
                      fontWeight: FontWeight.w600
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Score card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: _statusColor, width: 4)),
                boxShadow: theme.brightness == Brightness.light ? [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ] : null,
              ),
              child: Row(
                children: [
                  Text(
                    '${widget.forecast.swimCondition.roughnessIndex}',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                  Text(
                    ' / 100',
                    style: TextStyle(fontSize: 20, color: colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _statusLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Roughness Gauge (Green to Red)
            _RoughnessGauge(score: widget.forecast.swimCondition.roughnessIndex),
            
            const SizedBox(height: 16),
            
            // Temperature Gauge
            if (widget.forecast.swell.seaTemperature > 0)
              _TemperatureGauge(temperature: widget.forecast.swell.seaTemperature),
            
            const SizedBox(height: 16),
            
            // Diagnostics Grid
            if (widget.forecast.swimCondition.diagnostics != null) ...[
              const _SectionTitle(title: 'Diagnostics'),
              const SizedBox(height: 8),
              _DiagnosticsGrid(diagnostics: widget.forecast.swimCondition.diagnostics!, forecast: widget.forecast),
            ],
            
            const SizedBox(height: 24),

            // Weather Section
            const _SectionTitle(title: 'Weather'),
            const SizedBox(height: 8),
            Row(
              children: [
                _DataTile(
                  icon: _weatherIcon,
                  label: 'Temp',
                  value: '${widget.forecast.weather.temperature.round()}°C',
                ),
                _DataTile(
                  icon: '💨',
                  label: widget.forecast.weather.windGust != null ? 'Wind / Gust' : 'Wind',
                  value: widget.forecast.weather.windGust != null 
                      ? '${widget.forecast.weather.windSpeed}/${widget.forecast.weather.windGust!.round()}'
                      : '${widget.forecast.weather.windSpeed} km/h',
                  sublabel: _getWindArrow(widget.forecast.weather.windDirection),
                ),
                _DataTile(
                  icon: '🧭',
                  label: 'Direction',
                  value: '${widget.forecast.weather.windDirection}°',
                ),
                _DataTile(
                  icon: '💧',
                  label: 'Rain',
                  value: '${widget.forecast.weather.precipitationProbability}%',
                  valueColor: widget.forecast.weather.precipitationProbability > 50 
                      ? const Color(0xFF38BDF8) : null,
                ),
              ],
            ),
            
            // Weather trend
            if (widget.allHours != null && widget.allHours!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _SectionTitle(title: 'Weather Trend'),
              const SizedBox(height: 8),
              WeatherTrend(
                hours: widget.allHours!,
                selectedHourIndex: selectedHourIndex >= 0 ? selectedHourIndex : 0,
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Tide Section with curve
            if (widget.tide != null) ...[
              _SectionTitle(
                title: 'Tide',
                trailing: Row(
                  children: [
                    Text(widget.moonPhase.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Text(
                      widget.moonPhase.phase,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    if (widget.moonPhase.isSpringTide) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF3B82F6)),
                        ),
                        child: const Text(
                          'SPRING',
                          style: TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              
              // Tide curve visualization
              if (widget.tideLevels != null && widget.tideLevels!.isNotEmpty)
                TideCurve(
                  hours: widget.allHours ?? [],
                  selectedHour: widget.forecast.time.hour,
                  levels: widget.tideLevels!,
                ),
              
              const SizedBox(height: 8),
            ],
            
            const SizedBox(height: 24),
            
            // Wave Conditions Section with visualization
            const _SectionTitle(title: 'Wave Conditions'),
            const SizedBox(height: 8),
            
            // Wave visualization
            WaveVisualization(waveHeight: widget.forecast.swell.height),
              // Main conditions row with UnitConverter
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                   _DataTile(
                    icon: _weatherIcon,
                    label: 'Weather',
                    value: UnitConverter.formatTemp(widget.forecast.weather.temperature),
                  ),
                   _DataTile(
                    icon: '💨',
                    label: 'Wind',
                    value: UnitConverter.formatWind(widget.forecast.weather.windSpeed.toDouble()),
                  ),
                   _DataTile(
                    icon: '🌊',
                    label: 'Roughness',
                    value: UnitConverter.getRoughnessStatus(widget.forecast.swimCondition.roughnessIndex).label,
                    valueColor: Color(UnitConverter.getRoughnessStatus(widget.forecast.swimCondition.roughnessIndex).color),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DataTile(
                  icon: '🌊',
                  label: 'Height',
                  value: '${widget.forecast.swell.height.toStringAsFixed(1)}m',
                ),
                _DataTile(
                  icon: '⏱️',
                  label: 'Period',
                  value: '${widget.forecast.swell.period}s',
                ),
                _DataTile(
                  icon: '🧭',
                  label: 'Direction',
                  value: '${widget.forecast.swell.direction}° ${_getSwellArrow(widget.forecast.swell.direction)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Disaggregated swell vs wind-wave breakdown
            if (widget.forecast.swell.swellWaveHeight > 0 || widget.forecast.swell.windWaveHeight > 0)
              Row(
                children: [
                  _DataTile(
                    icon: '🏊',
                    label: 'Swell',
                    value: '${widget.forecast.swell.swellWaveHeight.toStringAsFixed(1)}m / ${widget.forecast.swell.swellWavePeriod}s',
                    valueColor: const Color(0xFF38BDF8),
                  ),
                  _DataTile(
                    icon: '💨',
                    label: 'Wind Chop',
                    value: '${widget.forecast.swell.windWaveHeight.toStringAsFixed(1)}m',
                    valueColor: const Color(0xFFF97316),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DataTile(
                  icon: '🌡️',
                  label: 'Water Temp',
                  value: '${widget.forecast.swell.seaTemperature.toStringAsFixed(1)}°C',
                  valueColor: const Color(0xFF4CC9F0),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 32),
            
            // Data Sources & Parameters - Tap to view debug logs!
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DebugLogScreen(),
                  ),
                );
              },
              child: const _SectionTitle(title: 'Data Sources & Parameters (Tap for Debug)'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Weather Source', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                        Text(
                          widget.forecast.weather.source ?? widget.forecast.dataSource,
                          style: TextStyle(
                            color: (widget.forecast.weather.source == 'Met Éireann') ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tide Station', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                      Text(
                        widget.forecast.tideStation ?? 'Nearest',
                        style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Divider(color: theme.dividerColor, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GPS Coordinates', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                      Text(
                        '${widget.forecast.lat?.toStringAsFixed(4)}, ${widget.forecast.lon?.toStringAsFixed(4)}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.8), // Using primary color for headers
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _RoughnessGauge extends StatelessWidget {
  final int score;

  const _RoughnessGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    final clampedScore = score.clamp(0, 100);
    final percentage = clampedScore / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 20, child: Container(color: const Color(0xFF22C55E))), // Calm (Green)
                      Expanded(flex: 20, child: Container(color: const Color(0xFF3B82F6))), // Medium (Blue)
                      Expanded(flex: 20, child: Container(color: const Color(0xFFF97316))), // Rough (Orange)
                      Expanded(flex: 40, child: Container(color: const Color(0xFFEF4444))), // Unsafe (Red)
                    ],
                  ),
                  Positioned(
                    left: (percentage * constraints.maxWidth).clamp(0, constraints.maxWidth - 4),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Calm', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
            Text('Medium', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
            Text('Rough', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
            Text('Unsafe', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _TemperatureGauge extends StatelessWidget {
  final double temperature;
  
  static const double minTemp = 7.0;
  static const double maxTemp = 14.0;

  const _TemperatureGauge({required this.temperature});

  @override
  Widget build(BuildContext context) {
    final isBelow = temperature < minTemp;
    final isAbove = temperature > maxTemp;
    final clamped = temperature.clamp(minTemp, maxTemp);
    final percentage = (clamped - minTemp) / (maxTemp - minTemp);

    final highlightColor = isBelow 
        ? const Color(0xFF3B82F6) // Deep blue for extreme cold
        : isAbove 
            ? const Color(0xFFEF4444) // Red for extreme heat
            : const Color(0xFF4CC9F0); // Cyan for normal range

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Water Temperature',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            if (isBelow)
              const Text('⚠️ EXTREME COLD', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.bold)),
            if (isAbove)
              const Text('⚠️ UNUSUALLY WARM', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 33, child: Container(color: const Color(0xFF3B82F6))),
                      Expanded(flex: 34, child: Container(color: const Color(0xFF06B6D4))),
                      Expanded(flex: 33, child: Container(color: const Color(0xFFF97316))),
                    ],
                  ),
                  Positioned(
                    left: (percentage * constraints.maxWidth).clamp(0, constraints.maxWidth - 4),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${minTemp.round()}°C', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
            Text(
              '${temperature.toStringAsFixed(1)}°C',
              style: TextStyle(color: highlightColor, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text('${maxTemp.round()}°C', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _DiagnosticsGrid extends StatelessWidget {
  final SwimDiagnostics diagnostics;
  final HourlyForecast forecast;

  const _DiagnosticsGrid({required this.diagnostics, required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Column(
        children: diagnostics.toJson().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  e.key,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                Text(
                  e.value is double ? (e.value as double).toStringAsFixed(1) : e.value.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final String? sublabel;
  final Color? valueColor;

  const _DataTile({
    required this.icon,
    required this.label,
    required this.value,
    this.sublabel,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.normal)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}
