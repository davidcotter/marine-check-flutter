import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/marine_data.dart';
import 'services/marine_service.dart';
import 'services/location_service.dart';
import 'services/tide_service.dart';
import 'widgets/hour_detail_sheet.dart';
import 'widgets/animated_wave_widget.dart';
import 'widgets/add_location_modal.dart';
import 'screens/webcam_screen.dart';
import 'widgets/tide_graphic.dart';
import 'services/settings_service.dart';
import 'screens/settings_screen.dart';
import 'utils/unit_converter.dart';
import 'services/background_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'widgets/forecast_summary_card.dart';
import 'widgets/share_modal.dart';
import 'services/notification_service.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

@pragma('vm:entry-point')
Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Something went wrong.\n${details.exception}',
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    await SettingsService.init();
    await BackgroundService.init();
    await NotificationService.initialize();

    runApp(const MarineCheckApp());
  } catch (e, stack) {
    debugPrint('CRITICAL STARTUP ERROR: $e');
    debugPrint(stack.toString());
    runApp(const MarineCheckApp());
  }
}

class MarineCheckApp extends StatefulWidget {
  const MarineCheckApp({super.key});

  static _MarineCheckAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MarineCheckAppState>();

  @override
  State<MarineCheckApp> createState() => _MarineCheckAppState();
}

class _MarineCheckAppState extends State<MarineCheckApp> {
  ThemeMode _themeMode = ThemeMode.system;

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initDeepLinks();
  }

  void _initDeepLinks() async {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    final uri = await _appLinks.getInitialLink();
    if (uri != null) {
      _handleDeepLink(uri);
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('MarineCheck: Deep link received: $uri');
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _loadTheme() {
    final mode = SettingsService.themeMode;
    setState(() {
      _themeMode = ThemeMode.values[mode.index];
    });
  }

  void updateTheme() {
    _loadTheme();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marine Check',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      home: const SelectionArea(
        child: MarineHomePage(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        primaryColor: const Color(0xFF2563EB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF10B981),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          onSurfaceVariant: Color(0xFF64748B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8FAFC),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF3B82F6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF22C55E),
          surface: Color(0xFF1E293B),
          onSurface: Color(0xFFF8FAFC),
          onSurfaceVariant: Color(0xFF94A3B8),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class MarineHomePage extends StatefulWidget {
  const MarineHomePage({super.key});

  @override
  State<MarineHomePage> createState() => _MarineHomePageState();
}

class _MarineHomePageState extends State<MarineHomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _marineService = MarineService();
  final _locationService = LocationService();
  final _tideService = TideService();
  
  late AnimationController _refreshController;

  List<HourlyForecast> _forecasts = [];
  List<TideData> _tides = [];
  List<SavedLocation> _locations = [];
  SavedLocation? _selectedLocation;
  bool _loading = true;
  bool _refreshing = false; // New state for non-intrusive loading
  String? _error;
  DateTime? _lastUpdated;
  
  // Day navigation
  int _selectedDayIndex = 1; // 0 = yesterday, 1 = today
  List<_DayData> _days = [];
  Map<String, ({String sunrise, String sunset})> _sunData = {};
  bool _showNext2Hours = true;
  final ScrollController _scrollController = ScrollController();

  // Deep link state
  String? _deepLinkTime;
  String? _deepLinkMessage;
  HourlyForecast? _sharedForecast;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _showNext2Hours = SettingsService.showNext2Hours;
    _handleDeepLink();
    _loadLocations();
  }

  void _handleDeepLink() {
    if (!kIsWeb) return;
    
    final uri = Uri.base;
    final params = uri.queryParameters;

    if (params.containsKey('v')) {
      try {
        final parts = params['v']!.split(',');
        if (parts.length >= 2) {
          final lat = double.parse(parts[0]);
          final lon = double.parse(parts[1]);
          final name = parts.length >= 3 ? Uri.decodeComponent(parts[2]) : 'Shared Location';
          
          if (parts.length >= 4) {
            final ts = int.parse(parts[3]);
            _deepLinkTime = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toIso8601String();
          }
          if (parts.length >= 5) {
            _deepLinkMessage = Uri.decodeComponent(parts[4]);
          }

          _selectedLocation = SavedLocation(
            id: 'deeplink_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            lat: lat,
            lon: lon,
          );
          print('MarineCheck: Compact deep link detected - $name ($lat, $lon)');
          return;
        }
      } catch (e) {
        print('MarineCheck: Compact deep link parse error: $e');
      }
    }

    if (params.containsKey('lat') && params.containsKey('lon')) {
      try {
        final lat = double.parse(params['lat']!);
        final lon = double.parse(params['lon']!);
        final name = params['loc'] ?? 'Shared Location';
        _deepLinkTime = params['time'];
        
        _selectedLocation = SavedLocation(
          id: 'deeplink_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          lat: lat,
          lon: lon,
        );
        print('MarineCheck: Deep link detected - $name ($lat, $lon) @ $_deepLinkTime');
      } catch (e) {
        print('MarineCheck: Deep link parse error: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ... (Lifecycle methods removed for brevity - keep if needed, but Mixin conflict handling)
  
  // ignore: unused_element
  void _startRefreshAnimation() {
    _refreshController.repeat();
  }

  void _stopRefreshAnimation() {
    _refreshController.stop();
    _refreshController.reset();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && _selectedLocation != null) {
          try {
            _loadData(forceRefresh: true);
          } catch (e) {
            debugPrint('Resume refresh error: $e');
          }
        }
      });
    }
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await _locationService.getSavedLocations();
      final selected = await _locationService.getSelectedLocation();
      if (!mounted) return;
      setState(() {
        _locations = locations;
        if (_selectedLocation == null) {
          _selectedLocation = selected;
        }
      });
      // If link wants to open the posts view, do it after first frame — removed (no posts)
      // Optimistic: try to show cached data instantly, then refresh in background
      await _loadCachedThenRefresh();
    } catch (e) {
      debugPrint('Error loading locations: $e');
      if (!mounted) return;
      setState(() {
        _locations = defaultLocations;
        _selectedLocation = defaultLocations.first;
      });
      _loadData(forceRefresh: true);
    }
  }

  Future<void> _loadCachedThenRefresh() async {
    if (_selectedLocation == null) return;

    final location = Location(
      id: _selectedLocation!.id,
      name: _selectedLocation!.name,
      lat: _selectedLocation!.lat,
      lon: _selectedLocation!.lon,
      waterLat: _selectedLocation!.waterLat,
      waterLon: _selectedLocation!.waterLon,
    );

    // Try cache first for instant UI
    final cached = await _marineService.getCachedForecasts(location);
    if (cached != null && cached.forecasts.isNotEmpty && mounted) {
      final processed = _processForecastData(cached.forecasts, cached.sunData, null);
      setState(() {
        _forecasts = processed.forecasts;
        _days = processed.days;
        _sunData = cached.sunData;
        _selectedDayIndex = processed.todayIndex;
        _lastUpdated = cached.lastUpdated;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToRelevantTime();
      });
    }

    // Now do the full refresh in the background
    _loadData(forceRefresh: _forecasts.isNotEmpty);
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (_selectedLocation == null) return;
    
    // Only show loading spinner if we have NO existing data
    final hasExistingData = _forecasts.isNotEmpty;
    
    if (forceRefresh) {
      _startRefreshAnimation();
      if (mounted) setState(() => _refreshing = true); // UI indication for background refresh
    }
    
    if (!hasExistingData && !forceRefresh) {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final location = Location(
        id: _selectedLocation!.id,
        name: _selectedLocation!.name,
        lat: _selectedLocation!.lat,
        lon: _selectedLocation!.lon,
        waterLat: _selectedLocation!.waterLat,
        waterLon: _selectedLocation!.waterLon,
      );
      
      final result = await _marineService.getForecasts(location, forceRefresh: forceRefresh);
      
      // Fetch tides (always fresh if we are refreshing, but maybe cacheable too? 
      // For now, lets fetch. It's usually fast.)
      // Actually, if we are offline, fetchTides might fail?
      // TideService doesn't have offline fallback?
      // If offline, we rely on duplicate data in `result.forecasts` if it came from cache.
      // But `getForecasts` returns `HourlyForecast` list.
      // If came from cache, `result.forecasts` has tides.
      // If came from network, `result.forecasts` has NO tides.
      
      
      // So:
      TideResult? tideResult;
      try {
        tideResult = await _tideService.fetchTides(location.lat, location.lon);
      } catch (e) {
        print('Tide fetch failed: $e');
      }

      // Check for refined water location (SST Optimization)
      if (result.refinedLocation != null) {
        print('MarineCheck: Found refined water location for ${location.name} at ${result.refinedLocation!.waterLat},${result.refinedLocation!.waterLon}');
        final updated = SavedLocation(
          id: _selectedLocation!.id,
          name: _selectedLocation!.name,
          lat: _selectedLocation!.lat,
          lon: _selectedLocation!.lon,
          isCurrentLocation: _selectedLocation!.isCurrentLocation,
          addedAt: _selectedLocation!.addedAt,
          waterLat: result.refinedLocation!.waterLat,
          waterLon: result.refinedLocation!.waterLon,
        );
        await _locationService.updateLocation(updated);
        
        // Update local state without rebuild if possible, or just let next reload pick it up
        if (mounted) {
           setState(() {
             _selectedLocation = updated;
             // Update the specific item in _locations too so UI stays consistent
             final index = _locations.indexWhere((l) => l.id == updated.id);
             if (index != -1) _locations[index] = updated;
           });
        }
      }
      
      final processed = _processForecastData(result.forecasts, result.sunData, tideResult);

      // Update Cache with enriched data (tides merged)
      if (tideResult != null) {
         await _marineService.updateCache(location, processed.forecasts);
      }

      // Update Home Screen Widget
      try {
        if (processed.forecasts.isNotEmpty) {
          await _marineService.updateHomeWidget(location, processed.forecasts);
        }
      } catch (e) {
        print('Widget update trigger failed: $e');
      }
      
      if (!mounted) return;
      setState(() {
        _forecasts = processed.forecasts;
        _tides = tideResult?.tides ?? [];
        _days = processed.days;
        _sunData = result.sunData;
        _selectedDayIndex = processed.todayIndex;
        _lastUpdated = result.lastUpdated;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      _stopRefreshAnimation();

      // If this was a deep link, we might need to select a different day
      if (_deepLinkTime != null) {
        try {
          final target = DateTime.parse(_deepLinkTime!);
          final index = _days.indexWhere((d) => 
            d.date.year == target.year && 
            d.date.month == target.month && 
            d.date.day == target.day
          );
          if (index != -1 && index != _selectedDayIndex) {
            setState(() => _selectedDayIndex = index);
          }
          
          // Identify the specific shared forecast object for high-visibility display
          if (index != -1) {
             final target = DateTime.parse(_deepLinkTime!);
             _sharedForecast = _days[index].forecasts.firstWhere(
               (f) => f.time.hour == target.hour,
               orElse: () => _days[index].forecasts.first,
             );
          }
        } catch (e) {
          print('Deep link date select error: $e');
        }
      }

      // Auto-scroll after build
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToRelevantTime();
        });
      }
    } catch (e) {
      _stopRefreshAnimation();
      if (!mounted) return;
      
      setState(() => _refreshing = false);

      if (hasExistingData) {
        // Silent fail — keep showing old data, just log it
        print('MarineService: Background refresh failed (keeping old data): $e');
        setState(() {
          _loading = false;
        });
        
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Offline: Using cached data ($e)'),
             backgroundColor: Colors.orange,
             duration: const Duration(seconds: 2),
           ),
         );
      } else {
        // No existing data — show the error
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }


  // Helper to process forecasts (merge tides, group by day)
  ({List<HourlyForecast> forecasts, List<_DayData> days, int todayIndex}) _processForecastData(
      List<HourlyForecast> rawForecasts, 
      Map<String, ({String sunrise, String sunset})> sunData,
      TideResult? tideResult
  ) {
      // Map tide station and join tide data to forecasts if available
      final processedForecasts = rawForecasts.map((f) {
        // If forecast already has tide (from cache), keep it unless we have fresh tide result
        TideData? matchingTide = f.tide;
        
        if (tideResult != null) {
          try {
            // Look for matching hour on the same day
            matchingTide = tideResult.tides.firstWhere(
              (t) => t.time.year == f.time.year && 
                     t.time.month == f.time.month && 
                     t.time.day == f.time.day && 
                     t.time.hour == f.time.hour
            );
          } catch (_) {}
        }

        return HourlyForecast(
          time: f.time,
          swell: f.swell,
          weather: f.weather,
          swimCondition: f.swimCondition,
          isMetEireann: f.isMetEireann,
          tideStation: tideResult?.stationName ?? f.tideStation,
          lat: _selectedLocation!.lat,
          lon: _selectedLocation!.lon,
          tide: matchingTide,
          dataSource: f.dataSource,
        );
      }).toList();

      // Group forecasts by day
      final days = _groupByDay(processedForecasts, sunData);
      
      // Find today's index (safely clamped)
      final today = DateTime.now();
      int todayIndex = days.indexWhere((d) => 
          d.date.day == today.day && d.date.month == today.month);
      if (todayIndex == -1) todayIndex = days.length > 1 ? 1 : 0;
      
      return (forecasts: processedForecasts, days: days, todayIndex: todayIndex);
  }

  // ... (helper methods like _wmoToIcon, _roughnessColor, _roughnessLabel, _buildSummaryCard, etc. - ensure they are preserved or not overwritten if outside range)
  // Wait, I need to make sure I don't overwrite them. The range is big.
  // Actually, I'll just check where the Refresh button is and replace THAT part specifically in build() 
  // and add the controller variables at the top. 
  // This large block replacement is risky if I miss something.
  // I'll split it into smaller tasks.

  // TASK 1: Add variables and initState/dispose
  // TASK 2: Wrap the refresh button.

  // Let me CANCEL this big replace and do smaller ones.


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
    return Color(UnitConverter.getRoughnessStatus(roughness).color);
  }

  String _roughnessLabel(int roughness) {
    return UnitConverter.getRoughnessStatus(roughness).label;
  }

  Widget _buildSummaryCard(_DayData day) {
    final now = DateTime.now();
    final upcoming = day.forecasts.where((f) =>
      f.time.hour >= now.hour && f.time.hour < now.hour + 2
    ).toList();

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return ForecastSummaryCard(
      title: 'Next 2 Hours${upcoming.any((f) => !f.isMetEireann) ? "*" : ""}',
      forecasts: upcoming,
      isMetEireann: !upcoming.any((f) => !f.isMetEireann),
    );
  }

  List<_DayData> _groupByDay(List<HourlyForecast> forecasts, Map<String, ({String sunrise, String sunset})> sunData) {
    final Map<String, List<HourlyForecast>> grouped = {};
    
    for (final f in forecasts) {
      final key = DateFormat('yyyy-MM-dd').format(f.time);
      grouped.putIfAbsent(key, () => []).add(f);
    }

    final now = DateTime.now();
    return grouped.entries.map((e) {
      final date = DateTime.parse(e.key);
      String label;
      
      if (date.day == now.day - 1 && date.month == now.month) {
        label = 'YESTERDAY';
      } else if (date.day == now.day && date.month == now.month) {
        label = 'TODAY';
      } else if (date.day == now.day + 1 && date.month == now.month) {
        label = 'TOMORROW';
      } else {
        label = DateFormat('EEEE').format(date).toUpperCase();
      }

      // Get sunrise/sunset for this day
      final sun = sunData[e.key];
      String? sunrise;
      String? sunset;
      if (sun != null) {
        try {
          sunrise = DateFormat('HH:mm').format(DateTime.parse(sun.sunrise));
          sunset = DateFormat('HH:mm').format(DateTime.parse(sun.sunset));
        } catch (_) {}
      }

      return _DayData(
        date: date,
        label: label,
        dateStr: DateFormat('d MMM').format(date),
        forecasts: e.value,
        moonPhase: TideService.calculateMoonPhase(date),
        sunrise: sunrise,
        sunset: sunset,
      );
    }).toList();
  }

  void _selectLocation(SavedLocation location) async {
    await _locationService.setSelectedLocation(location.id);
    setState(() => _selectedLocation = location);
    Navigator.pop(context); // Close picker
    
    // OPTIMISTIC UI: Try to load cache immediately
    setState(() => _loading = true); // Brief spinner if no cache, or just to signal change
    try {
      final cached = await _marineService.getCachedForecasts(
        Location(id: location.id, name: location.name, lat: location.lat, lon: location.lon)
      );
      
      if (cached != null && mounted) {
        // We have cache! Show it immediately
        final processed = _processForecastData(cached.forecasts, cached.sunData, null); // No fresh tides yet
        
        setState(() {
           _forecasts = processed.forecasts;
           _tides = []; // Clear old tides until fresh ones arrive? Or use cached if available? 
           // cached.forecasts has tides if they were saved!
           // processed.forecasts will have tides if cached.forecasts had them.
           // _processForecastData preserves existing tides if tideResult is null.
           // So if cached data has tides, we are good!
           
           // We might want to extract tides from cached forecasts to populate `_tides`?
           // `_tides` is used for the curve graphic.
           // If we don't populate `_tides`, the curve might be empty.
           // We can reconstruct `_tides` from `processed.forecasts`?
           // Each `HourlyForecast` has `tide`.
           // `_tides` needs to be `List<TideData>`.
           final cachedTides = processed.forecasts
               .where((f) => f.tide != null)
               .map((f) => f.tide!)
               .toList();
           
           if (cachedTides.isNotEmpty) {
             _tides = cachedTides;
           }

           _days = processed.days;
           _sunData = cached.sunData;
           _selectedDayIndex = processed.todayIndex;
           _lastUpdated = cached.lastUpdated;
           
           _loading = false;
           // Don't set _error to null yet? Or yes?
           _error = null;
        });
      }
    } catch (e) {
      print('Optimistic load failed: $e');
    }
    
    // Trigger background refresh (fetches fresh data and updates UI again)
    // We pass forceRefresh: true so it fetches from network.
    // _loadData handles setting _refreshing=true if we already have data.
    _loadData(forceRefresh: true);
  }

  void _deleteLocation(SavedLocation location, Function(List<SavedLocation>) onUpdate) async {
    await _locationService.removeLocation(location.id);
    final locations = await _locationService.getSavedLocations();
    
    // Update the modal's list
    onUpdate(locations);
    
    // Update the parent's list
    setState(() {
      _locations = locations;
      if (_selectedLocation?.id == location.id && locations.isNotEmpty) {
        // If we deleted the current location, switch to the first one
        _selectedLocation = locations.first;
        _locationService.setSelectedLocation(locations.first.id);
        _loadData(); 
      }
    });
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true, // Allow full height if needed
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.6, // Fixed height for scrolling
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Location',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFF3B82F6)),
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddLocation();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _locations.length,
                    itemBuilder: (context, index) {
                      final loc = _locations[index];
                      String subtitle = '';
                      if (loc.isCurrentLocation) {
                        subtitle = 'Current Location';
                      } else {
                        subtitle = '${loc.lat.toStringAsFixed(2)}, ${loc.lon.toStringAsFixed(2)}';
                      }

                      return ListTile(
                        leading: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                        title: Text(loc.name),
                        subtitle: Text(subtitle, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedLocation?.id == loc.id)
                              const Icon(Icons.check, color: Color(0xFF22C55E)),
                            if (_locations.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                                onPressed: () {
                                  _deleteLocation(loc, (newLocations) {
                                    setModalState(() {
                                      // _locations is updated in _deleteLocation but we need to verify
                                      // Actually _locations is a reference, but we need to trigger rebuild
                                    });
                                  });
                                },
                              ),
                          ],
                        ),
                        onTap: () => _selectLocation(loc),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showAddLocation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddLocationModal(
        onLocationAdded: (loc) async {
          final locations = await _locationService.getSavedLocations();
          setState(() {
            _locations = locations;
            _selectedLocation = loc;
          });
          _loadData();
        },
      ),
    );
  }

  void _showHourDetail(HourlyForecast forecast) async {
    final matchingTide = forecast.tide;
    final List<double> tideLevels = [];
    
    for (final tide in _tides) {
      if (tide.time.day == forecast.time.day && 
          tide.time.month == forecast.time.month &&
          tide.time.year == forecast.time.year) {
        tideLevels.add(tide.level);
      }
    }

    final moonPhase = TideService.calculateMoonPhase(forecast.time);
    final currentDay = _days[_selectedDayIndex];

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => HourDetailSheet(
        forecast: forecast,
        tide: matchingTide,
        moonPhase: moonPhase,
        allHours: currentDay.forecasts,
        tideLevels: tideLevels.isNotEmpty ? tideLevels : null,
        locationName: _selectedLocation?.name ?? 'Shared Location',
        savedLocation: _selectedLocation,
      ),
    );

    // If the detail sheet returned 'share', open the share modal
    if (result == 'share' && mounted && _selectedLocation != null) {
      _openShareModal(forecast);
    }
  }

  void _openShareModal(HourlyForecast forecast) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareModal(
        location: _selectedLocation!,
        forecast: forecast,
      ),
    );
  }

  void _scrollToRelevantTime() {
    if (!mounted || _days.isEmpty) return;
    if (!_scrollController.hasClients) return;

    final currentDay = _days[_selectedDayIndex];
    int targetHour = 8; // Default to 8am if nothing else matches

    if (_deepLinkTime != null) {
      try {
         final target = DateTime.parse(_deepLinkTime!);
         if (currentDay.date.year == target.year && 
             currentDay.date.month == target.month && 
             currentDay.date.day == target.day) {
           targetHour = target.hour;
         } else if (currentDay.label == 'TODAY') {
            targetHour = DateTime.now().hour;
         }
      } catch (_) {
         if (currentDay.label == 'TODAY') targetHour = DateTime.now().hour;
      }
      // Reset deep link hour after first scroll so user can navigate elsewhere
      // Actually we keep it until they change day manually? 
      // Let's clear it once used for scrolling.
      _deepLinkTime = null; 
    } else if (currentDay.label == 'TODAY') {
      targetHour = DateTime.now().hour;
    } else if (currentDay.sunrise != null) {
      // Parse "HH:mm"
      try {
        final parts = currentDay.sunrise!.split(':');
        if (parts.length >= 1) {
          targetHour = int.parse(parts[0]);
        }
      } catch (_) {}
    }

    // Find index of this hour
    int index = currentDay.forecasts.indexWhere((f) => f.time.toLocal().hour == targetHour);
    
    // If not found, try finding the first hour after the target
    if (index == -1) {
      index = currentDay.forecasts.indexWhere((f) => f.time.toLocal().hour > targetHour);
    }
    
    if (index == -1) index = 0;

    // Scroll precisely (itemExtent is 95.0)
    final offset = index * 95.0;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _prevDay() {
    if (_selectedDayIndex > 0) {
      setState(() => _selectedDayIndex--);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevantTime());
    }
  }

  void _nextDay() {
    if (_selectedDayIndex < _days.length - 1) {
      setState(() => _selectedDayIndex++);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevantTime());
    }
  }

  void _jumpToToday() {
    final today = DateTime.now();
    int todayIndex = _days.indexWhere((d) => 
        d.date.day == today.day && d.date.month == today.month);
    
    if (todayIndex != -1 && _selectedDayIndex != todayIndex) {
      setState(() => _selectedDayIndex = todayIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevantTime());
    }
  }

  void _shareCurrentState() {
    if (_selectedLocation == null || _forecasts.isEmpty) return;

    final currentDay = _days[_selectedDayIndex];
    int hourIndex = (_scrollController.offset / 95.0).round();
    if (hourIndex < 0) hourIndex = 0;
    if (hourIndex >= currentDay.forecasts.length) hourIndex = currentDay.forecasts.length - 1;
    
    final forecast = currentDay.forecasts[hourIndex];
    _openShareModal(forecast);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _showLocationPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.waves, color: Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Text(_selectedLocation?.name ?? 'Select Location'),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => WebcamScreen(
                userLat: _selectedLocation?.lat,
                userLon: _selectedLocation?.lon,
              )),
            ),
          ),
          RotationTransition(
            turns: _refreshController,
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadData(forceRefresh: true),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share Dip Report',
            onPressed: _shareCurrentState,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    forecasts: _forecasts,
                    locationName: _selectedLocation?.name ?? 'Unknown',
                  ),
                ),
              );
              setState(() {
                _showNext2Hours = SettingsService.showNext2Hours;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) 
            const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent),
          Expanded(child: _buildBody()),
        ],
      ),
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
            Text('Error: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadData(forceRefresh: true), 
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_days.isEmpty) {
      return const Center(child: Text('No forecast data available'));
    }

    // Safety clamp to prevent RangeError
    if (_selectedDayIndex >= _days.length) {
      _selectedDayIndex = _days.length - 1;
    }
    if (_selectedDayIndex < 0) {
      _selectedDayIndex = 0;
    }

    final currentDay = _days[_selectedDayIndex];

    return RefreshIndicator(
      onRefresh: () async {
        await _marineService.clearAllCaches();
        await _loadData(forceRefresh: true);
      },
      child: Column(
        children: [
          if (_sharedForecast != null && _selectedDayIndex == _days.indexWhere((d) => d.date.day == _sharedForecast!.time.day))
             ForecastSummaryCard(
               title: 'SHARED FORECAST • ${DateFormat('EEE d MMM @ HH:mm').format(_sharedForecast!.time)}',
               forecasts: [_sharedForecast!],
               message: _deepLinkMessage,
             ),
          // Day navigation header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.chevron_left,
                    color: _selectedDayIndex > 0 
                        ? Theme.of(context).colorScheme.onSurface 
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  onPressed: _selectedDayIndex > 0 ? _prevDay : null,
                ),
                Expanded(
                  child: InkWell(
                    onTap: _jumpToToday,
                    child: Column(
                      children: [
                        Text(
                          currentDay.label,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: currentDay.label == 'TODAY' 
                                ? Theme.of(context).colorScheme.onSurface 
                                : Theme.of(context).colorScheme.primary, // Blue if interactive
                          ),
                        ),
                        Text(
                          currentDay.dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Sun times + Moon phase
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentDay.sunrise != null || currentDay.sunset != null) ...[
                      const Text('☀️', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (currentDay.sunrise != null)
                            Text(
                              '↑ ${currentDay.sunrise!}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFFBBF24)),
                            ),
                          if (currentDay.sunset != null)
                            Text(
                              '↓ ${currentDay.sunset!}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFF97316)),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      currentDay.moonPhase.icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    color: _selectedDayIndex < _days.length - 1 
                        ? Theme.of(context).colorScheme.onSurface 
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  onPressed: _selectedDayIndex < _days.length - 1 ? _nextDay : null,
                ),
              ],
            ),
          ),

          // Last updated
          if (_lastUpdated != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.access_time, size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    'Updated ${DateFormat('d MMM HH:mm').format(_lastUpdated!)}',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

          // 3×2 Summary Widget — next 2 hours average
          if (_showNext2Hours && currentDay.label == 'TODAY') 
            _buildSummaryCard(currentDay),

          // Hourly forecasts
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemExtent: 95.0,
              padding: const EdgeInsets.all(16),
              itemCount: currentDay.forecasts.length,
              itemBuilder: (context, i) {
                final f = currentDay.forecasts[i];
                return _HourlyRow(
                  forecast: f,
                  isCurrentHour: currentDay.label == 'TODAY' && 
                      f.time.hour == DateTime.now().hour,
                  onTap: () => _showHourDetail(f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayData {
  final DateTime date;
  final String label;
  final String dateStr;
  final List<HourlyForecast> forecasts;
  final MoonPhase moonPhase;
  final String? sunrise;
  final String? sunset;

  _DayData({
    required this.date,
    required this.label,
    required this.dateStr,
    required this.forecasts,
    required this.moonPhase,
    this.sunrise,
    this.sunset,
  });
}

class _HourlyRow extends StatelessWidget {
  final HourlyForecast forecast;
  final bool isCurrentHour;
  final VoidCallback onTap;

  const _HourlyRow({
    required this.forecast,
    required this.isCurrentHour,
    required this.onTap,
  });

  Color get _statusColor {
    switch (forecast.swimCondition.status) {
      case SwimCondition.unsafe: return const Color(0xFFEF4444);
      case SwimCondition.rough: return const Color(0xFFF97316);
      case SwimCondition.medium: return const Color(0xFF3B82F6);
      case SwimCondition.calm: return const Color(0xFF22C55E);
    }
  }

  String get _statusLabel {
    switch (forecast.swimCondition.status) {
      case SwimCondition.calm: return 'GLASSY';
      case SwimCondition.medium: return 'MODERATE';
      case SwimCondition.rough: return 'CHOPPY';
      case SwimCondition.unsafe: return 'INTENSE';
    }
  }

  String get _weatherIcon {
    final code = forecast.weather.wmoCode;
    if (code == 0) return '☀️'; // Clear
    if (code <= 3) return '⛅'; // Partly cloudy
    if (code <= 48) return '🌫️'; // Fog
    if (code <= 67) return '🌧️'; // Rain
    if (code <= 77) return '🌨️'; // Snow
    if (code <= 82) return '🌧️'; // Showers
    if (code <= 86) return '🌨️'; // Snow showers
    return '⛈️'; // Thunderstorm
  }


  String _getTideArrow(bool isRising) {
    return isRising ? '↑' : '↓';
  }

  int _getWaveCount() {
    switch (forecast.swimCondition.status) {
      case SwimCondition.calm: return 1;
      case SwimCondition.medium: return 2;
      case SwimCondition.rough: return 3;
      case SwimCondition.unsafe: return 3;
    }
  }

  double _getWaveSpeed() {
    switch (forecast.swimCondition.status) {
      case SwimCondition.calm: return 0.5; // Was 0.8
      case SwimCondition.medium: return 1.0; // Was 1.5
      case SwimCondition.rough: return 1.8; // Was 2.5
      case SwimCondition.unsafe: return 2.5; // Was 3.5
    }
  }

  String _getSwellArrow(int deg) {
    const arrows = ['↓', '↙', '←', '↖', '↑', '↗', '→', '↘'];
    return arrows[(deg / 45).round() % 8];
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = '${forecast.time.hour.toString().padLeft(2, '0')}:00';
    final tideColor = forecast.tide != null ? Color(UnitConverter.getTideColor(forecast.tide!.status)) : const Color(0xFF94A3B8);
    final tideArrow = forecast.tide != null ? _getTideArrow(forecast.tide!.isRising) : '-';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isCurrentHour 
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2) 
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: isCurrentHour 
              ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4))
              : null,
        ),
        child: Row(
          children: [
            // Time (Flex 2)
            Expanded(
              flex: 2,
              child: Text(
                '${timeStr}${forecast.isMetEireann ? "" : "*"}',
                style: TextStyle(
                  color: isCurrentHour ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isCurrentHour ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),

            // Weather (Flex 3)
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_weatherIcon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Text(
                        UnitConverter.formatTemp(forecast.weather.temperature),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ],
                  ),
                  Text(
                    UnitConverter.formatWind(forecast.weather.windSpeed.toDouble()),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                    Text(
                      '💧${forecast.weather.precipitationProbability}%',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF38BDF8)),
                    ),
                ],
              ),
            ),

            // Tide (Flex 3)
            Expanded(
              flex: 3,
              child: forecast.tide != null ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TideGraphic(
                    percentage: forecast.tide!.percentage,
                    color: tideColor,
                    width: 32,
                    height: 18,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        UnitConverter.formatHeight(forecast.tide!.level),
                        style: TextStyle(color: tideColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        tideArrow,
                        style: TextStyle(color: tideColor, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ) : const Text('N/A', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            ),

            // Swell (Flex 3) - Stacked Height + Temp
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Height + Arrow
                  Row(
                    children: [
                      Text(
                        '${forecast.swell.height.toStringAsFixed(1)}m',
                        style: const TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _getSwellArrow(forecast.swell.direction),
                        style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12),
                      ),
                    ],
                  ),
                  // Row 2: Water Temp
                  Text(
                    '${forecast.swell.seaTemperature.round()}°',
                    style: const TextStyle(color: Color(0xFF4CC9F0), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Condition badge (Waves + Score) (Flex 2)
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedWaveWidget(
                    count: _getWaveCount(),
                    color: _statusColor,
                    size: 20,
                    speed: _getWaveSpeed(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${forecast.swimCondition.roughnessIndex}%',
                    style: TextStyle(
                      color: _statusColor, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 10
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
