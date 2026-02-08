import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/marine_data.dart';
import 'services/marine_service.dart';

void main() {
  runApp(const MarineCheckApp());
}

class MarineCheckApp extends StatelessWidget {
  const MarineCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marine Check',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF3B82F6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF22C55E),
          surface: Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
      home: const MarineHomePage(),
    );
  }
}

class MarineHomePage extends StatefulWidget {
  const MarineHomePage({super.key});

  @override
  State<MarineHomePage> createState() => _MarineHomePageState();
}

class _MarineHomePageState extends State<MarineHomePage> {
  final _marineService = MarineService();
  List<HourlyForecast> _forecasts = [];
  bool _loading = true;
  String? _error;
  
  // Default location: Tramore, Ireland
  final _location = Location(
    name: 'Tramore',
    lat: 52.1608,
    lon: -7.1508,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final forecasts = await _marineService.fetchForecasts(_location);
      setState(() {
        _forecasts = forecasts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.waves, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text(_location.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading marine data...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Group forecasts by day
    final byDay = <String, List<HourlyForecast>>{};
    for (final f in _forecasts) {
      final dayKey = DateFormat('yyyy-MM-dd').format(f.time);
      byDay.putIfAbsent(dayKey, () => []).add(f);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: byDay.length,
        itemBuilder: (context, index) {
          final dayKey = byDay.keys.elementAt(index);
          final dayForecasts = byDay[dayKey]!;
          final date = DateTime.parse(dayKey);
          
          String dayLabel;
          final now = DateTime.now();
          if (date.day == now.day && date.month == now.month) {
            dayLabel = 'TODAY';
          } else if (date.day == now.day + 1) {
            dayLabel = 'TOMORROW';
          } else {
            dayLabel = DateFormat('EEEE').format(date).toUpperCase();
          }

          return _DaySection(
            dayLabel: dayLabel,
            date: DateFormat('d MMM').format(date),
            forecasts: dayForecasts,
          );
        },
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final String dayLabel;
  final String date;
  final List<HourlyForecast> forecasts;

  const _DaySection({
    required this.dayLabel,
    required this.date,
    required this.forecasts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Text(
                dayLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF8FAFC),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        ...forecasts.map((f) => _HourlyForecastRow(forecast: f)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _HourlyForecastRow extends StatelessWidget {
  final HourlyForecast forecast;

  const _HourlyForecastRow({required this.forecast});

  Color get _statusColor {
    switch (forecast.swimCondition.status) {
      case SwimCondition.unsafe:
        return const Color(0xFFEF4444);
      case SwimCondition.rough:
        return const Color(0xFFF97316);
      case SwimCondition.medium:
        return const Color(0xFF3B82F6);
      case SwimCondition.calm:
        return const Color(0xFF22C55E);
    }
  }

  String get _weatherIcon {
    final code = forecast.weather.wmoCode;
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 49) return '🌫️';
    if (code <= 69) return '🌧️';
    if (code <= 79) return '🌨️';
    if (code <= 82) return '🌧️';
    if (code <= 86) return '🌨️';
    return '⛈️';
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(forecast.time);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          // Time
          SizedBox(
            width: 50,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF8FAFC),
              ),
            ),
          ),
          
          // Status indicator
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          
          // Weather
          Text(_weatherIcon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: Text(
              '${forecast.weather.temperature.round()}°',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          
          // Wind
          const Icon(Icons.air, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            child: Text(
              '${forecast.weather.windSpeed} km/h',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ),
          
          // Waves
          const SizedBox(width: 8),
          const Text('🌊', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '${forecast.swell.height.toStringAsFixed(1)}m',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          
          // Calmness index
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${forecast.swimCondition.calmnessIndex}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
