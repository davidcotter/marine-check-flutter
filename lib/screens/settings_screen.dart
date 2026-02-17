import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/marine_data.dart';
import '../models/notification_schedule.dart';
import '../services/settings_service.dart';
import '../widgets/widget_preview_screen.dart';
import '../main.dart';
import '../services/background_service.dart';
import 'package:flutter/foundation.dart';
import '../utils/js_bridge_stub.dart'
    if (dart.library.js_util) '../utils/js_bridge_web.dart' as js_bridge;
import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final List<HourlyForecast> forecasts;
  final String locationName;

  const SettingsScreen({
    super.key,
    required this.forecasts,
    required this.locationName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showNext2Hours = SettingsService.showNext2Hours;
  bool _notificationsEnabled = SettingsService.notificationsEnabled;
  List<NotificationSchedule> _schedules = SettingsService.notificationSchedules;
  bool _isInstallable = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _checkInstallable();
    }
  }

  void _checkInstallable() {
    try {
      // Check if already installable
      if (js_bridge.isPWAInstallable()) {
        setState(() => _isInstallable = true);
      }

      // Register callbacks for when it becomes installable/installed
      js_bridge.onPWAInstallable(() {
        if (mounted) setState(() => _isInstallable = true);
      });
      js_bridge.onPWAInstalled(() {
        if (mounted) setState(() => _isInstallable = false);
      });
    } catch (e) {
      debugPrint('PWA: Error checking installability: $e');
    }
  }

  bool get _isIOS => 
    defaultTargetPlatform == TargetPlatform.iOS || 
    (defaultTargetPlatform == TargetPlatform.macOS && kIsWeb); // iPadOS reports as macOS

  Future<void> _installPWA() async {
    try {
      final String result = await js_bridge.installPWA();
      if (result == 'accepted') {
        setState(() => _isInstallable = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Installation started! 🚀')),
          );
        }
      }
    } catch (e) {
      debugPrint('PWA: Error triggering install: $e');
    }
  }
  // bool _notifyGoodOnly removed (now per schedule)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _buildSectionHeader('ACCOUNT'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: AuthService().isAuthenticated
              ? Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary),
                      title: Text(
                        AuthService().user?['email'] ?? 'User',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Signed in via ${AuthService().user?['email'] != null ? 'Email/Social' : 'Token'}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    _buildDivider(),
                    ListTile(
                      onTap: () {
                        AuthService().logout();
                        if (mounted) setState(() {});
                      },
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              : ListTile(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                    if (mounted) setState(() {});
                  },
                  leading: Icon(Icons.login, color: Theme.of(context).colorScheme.primary),
                  title: Text('Sign In', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Sync settings and notifications across devices',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                ),
          ),
          const SizedBox(height: 12),
          _buildSectionHeader('APPEARANCE'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: _buildDropdownRow(
              'Theme',
              SettingsService.themeMode.name.toUpperCase(),
              AppThemeMode.values.map((e) => e.name.toUpperCase()).toList(),
              (val) async {
                final mode = AppThemeMode.values.firstWhere((e) => e.name.toUpperCase() == val);
                await SettingsService.setThemeMode(mode);
                if (mounted) {
                  MarineCheckApp.of(context)?.updateTheme();
                  setState(() {});
                }
              },
            ),
          ),

          Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('NOTIFICATIONS'),
                      IconButton(
                        icon: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Notification Options'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoItem(context, 'Good Conditions Only', 'Notifies you only when the surf status is "Calm" or "Medium". "Rough" or "Unsafe" conditions will be skipped.'),
                                  const SizedBox(height: 16),
                                  _buildInfoItem(context, 'High Tide Only', 'Notifies you only when the tide is near its peak (High). Useful if you prefer swimming at high tide.'),
                                  const SizedBox(height: 16),
                                  _buildInfoItem(context, 'Low Rain Only', 'Notifies you only if the chance of rain is less than 10%. Perfect for dry weather checks.'),
                                  const SizedBox(height: 16),
                                  _buildInfoItem(context, 'Forecast Time', 'Choose when to check conditions relative to the notification time. For example, get notified at 9 AM about the conditions at 1 PM (+4 hours).'),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Note: All checks are based on the average forecast for the 2-hour window at the selected time.',
                                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Got it'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    'Daily Surf Check',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                  ),
                  subtitle: Text(
                    'Get a daily report of conditions',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  value: _notificationsEnabled,
                  activeColor: const Color(0xFF3B82F6),
                  onChanged: (bool value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                    SettingsService.setNotificationsEnabled(value);
                    if (value) {
                      BackgroundService.registerPeriodicTask();
                    } else {
                      BackgroundService.cancelTasks();
                    }
                  },
                ),
                if (_notificationsEnabled) ...[
                  _buildDivider(),
                  // List of schedules
                  ..._schedules.asMap().entries.map((entry) {
                    final index = entry.key;
                    final schedule = entry.value;
                    return Column(
                      children: [
                        if (index > 0) 
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                          ),
                        Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Time & Close
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? time = await showTimePicker(
                                      context: context,
                                      initialTime: schedule.time,
                                    );
                                    if (time != null) {
                                      setState(() {
                                        _schedules[index] = schedule.copyWith(time: time);
                                      });
                                      await SettingsService.setNotificationSchedules(_schedules);
                                      await BackgroundService.registerPeriodicTask();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.access_time, size: 16, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Text(
                                          schedule.timeString,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_schedules.length > 1)
                                  IconButton(
                                    icon: Icon(Icons.close, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    onPressed: () async {
                                      setState(() {
                                        _schedules.removeAt(index);
                                      });
                                      await SettingsService.setNotificationSchedules(_schedules);
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Good Conditions & High Tide Toggles
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Good Conditions Only',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                  ),
                                ),
                                Switch(
                                  value: schedule.goodConditionsOnly,
                                  onChanged: (val) async {
                                    setState(() {
                                      _schedules[index] = schedule.copyWith(goodConditionsOnly: val);
                                    });
                                    await SettingsService.setNotificationSchedules(_schedules);
                                  },
                                  activeColor: const Color(0xFF3B82F6),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'High Tide Only',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                  ),
                                ),
                                Switch(
                                  value: schedule.highTideOnly,
                                  onChanged: (val) async {
                                    setState(() {
                                      _schedules[index] = schedule.copyWith(highTideOnly: val);
                                    });
                                    await SettingsService.setNotificationSchedules(_schedules);
                                  },
                                  activeColor: const Color(0xFF3B82F6),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Low Rain Only (<10%)',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                  ),
                                ),
                                Switch(
                                  value: schedule.lowRainOnly,
                                  onChanged: (val) async {
                                    setState(() {
                                      _schedules[index] = schedule.copyWith(lowRainOnly: val);
                                    });
                                    await SettingsService.setNotificationSchedules(_schedules);
                                  },
                                  activeColor: const Color(0xFF3B82F6),
                                ),
                              ],
                            ),
                            // Forecast Offset Selector
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Check Forecast For:',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                  ),
                                ),
                                DropdownButton<int>(
                                  value: schedule.forecastOffset,
                                  items: const [
                                    DropdownMenuItem(value: 0, child: Text("At Notification Time")),
                                    DropdownMenuItem(value: 2, child: Text("2 Hours Later")),
                                    DropdownMenuItem(value: 4, child: Text("4 Hours Later")),
                                    DropdownMenuItem(value: 6, child: Text("6 Hours Later")),
                                    DropdownMenuItem(value: 8, child: Text("8 Hours Later")),
                                  ],
                                  onChanged: (val) async {
                                    if (val != null) {
                                      setState(() {
                                        _schedules[index] = schedule.copyWith(forecastOffset: val);
                                      });
                                      await SettingsService.setNotificationSchedules(_schedules);
                                    }
                                  },
                                  underline: Container(), // Remove underline
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF3B82F6)),
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            
                            // Days Selector
                            SizedBox(
                              height: 36,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].asMap().entries.map((dayEntry) {
                                  final dayIndex = dayEntry.key + 1; // 1-7
                                  final label = dayEntry.value;
                                  final isSelected = schedule.days.contains(dayIndex);
                                  return GestureDetector(
                                    onTap: () async {
                                      final newDays = List<int>.from(schedule.days);
                                      if (isSelected) {
                                        if (newDays.length > 1) newDays.remove(dayIndex);
                                      } else {
                                        newDays.add(dayIndex);
                                      }
                                      setState(() {
                                        _schedules[index] = schedule.copyWith(days: newDays);
                                      });
                                      await SettingsService.setNotificationSchedules(_schedules);
                                    },
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isSelected 
                                            ? Theme.of(context).colorScheme.primary 
                                            : Theme.of(context).dividerColor.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: isSelected 
                                              ? Theme.of(context).colorScheme.onPrimary 
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),

                  // Add Time Button
                  if (_schedules.length < 3) 
                     ListTile(
                       leading: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                       title: Text('Add Another Time', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                       onTap: () async {
                          final TimeOfDay? time = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (time != null) {
                            // Check for duplicate times
                            final exists = _schedules.any((s) => s.time.hour == time.hour && s.time.minute == time.minute);
                            if (!exists) {
                              setState(() {
                                _schedules.add(NotificationSchedule(time: time));
                                // Sort by time? Maybe not needed for custom order
                              });
                              await SettingsService.setNotificationSchedules(_schedules);
                              await BackgroundService.registerPeriodicTask();
                            }
                          }
                       },
                     ),

                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionHeader('DISPLAY'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    'Show "Next 2 Hours"',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                  ),
                  subtitle: Text(
                    'Display summary card for now',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  value: _showNext2Hours,
                  activeColor: const Color(0xFF3B82F6),
                  onChanged: (bool value) async {
                    await SettingsService.setShowNext2Hours(value);
                    setState(() {
                      _showNext2Hours = value;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionHeader('UNITS'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                _buildDropdownRow(
                  'Wind Speed', 
                  SettingsService.windUnit.name.toUpperCase(),
                  WindUnit.values.map((e) => e.name.toUpperCase()).toList(),
                  (val) async {
                     await SettingsService.setWindUnit(WindUnit.values.firstWhere((e) => e.name.toUpperCase() == val));
                     setState(() {});
                  }
                ),
                _buildDivider(),
                _buildDropdownRow(
                  'Temperature', 
                  SettingsService.tempUnit.name.toUpperCase(),
                  TempUnit.values.map((e) => e.name.toUpperCase()).toList(),
                  (val) async {
                     await SettingsService.setTempUnit(TempUnit.values.firstWhere((e) => e.name.toUpperCase() == val));
                     setState(() {});
                  }
                ),
                _buildDivider(),
                _buildDropdownRow(
                  'Height (Tide/Waves)', 
                  SettingsService.heightUnit.name.toUpperCase(),
                  HeightUnit.values.map((e) => e.name.toUpperCase()).toList(),
                  (val) async {
                     await SettingsService.setHeightUnit(HeightUnit.values.firstWhere((e) => e.name.toUpperCase() == val));
                     setState(() {});
                  }
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _buildSectionHeader('WIDGET'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WidgetPreviewScreen(
                    forecasts: widget.forecasts,
                    locationName: widget.locationName,
                  ),
                ),
              ),
              leading: Icon(Icons.widgets_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text(
                'Preview Home Widget',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('APP INSTALLATION'),
            if (_isInstallable)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                ),
                child: ListTile(
                  onTap: _installPWA,
                  leading: Icon(Icons.install_mobile, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Install DipGuide',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Add to your home screen for easy access',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  trailing: Icon(Icons.download_for_offline, color: Theme.of(context).colorScheme.primary),
                ),
              )
            else if (_isIOS)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.apple, color: Theme.of(context).colorScheme.onSurface, size: 20),
                        const SizedBox(width: 8),
                        Text('Install on iOS / iPhone', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Tap the "Share" button at the bottom of Safari.\n2. Scroll down and tap "Add to Home Screen".',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'App is already installed or your browser doesn\'t support automatic prompts. Use the browser menu to "Install App" or "Add to Home Screen".',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
          const SizedBox(height: 12),
          _buildSectionHeader('ABOUT'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: ListTile(
              onTap: () => launchUrl(
                Uri.parse('https://dipreport.com/about'),
                mode: LaunchMode.externalApplication,
              ),
              leading: Icon(Icons.waves_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text('About Dip Report', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              subtitle: Text('Features, data sources & how it works',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              trailing: const Icon(Icons.open_in_new, color: Color(0xFF64748B), size: 18),
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionHeader('LEGAL'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsScreen()),
              ),
              leading: Icon(Icons.gavel_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text(
                'Terms & Conditions',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'DipReport v1.0.0',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDropdownRow(String title, String currentValue, List<String> items, Function(String?) onChanged, {VoidCallback? onInfoPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
              ),
              if (onInfoPressed != null)
                GestureDetector(
                  onTap: onInfoPressed,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.info_outline, color: const Color(0xFF94A3B8).withOpacity(0.7), size: 18),
                  ),
                ),
            ],
          ),
          DropdownButton<String>(
            value: currentValue,
            dropdownColor: Theme.of(context).colorScheme.surface,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
            items: items.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value.replaceAll('_', ' ')),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
          ),
        ],
      ),
    );
  }





  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13))),
          Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildColorRow(String range, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(range, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))),
          Container(
            width: 8, height: 8, 
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 1,
      color: Theme.of(context).dividerColor.withOpacity(0.1),
    );
  }

  Widget _buildInfoItem(BuildContext context, String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 4),
        Text(description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = TextStyle(color: cs.onSurface, fontSize: 14, height: 1.6);
    final heading = TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold, height: 2.2);
    final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.5);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text('Last updated: February 2026', style: muted),
          const SizedBox(height: 16),
          Text(
            'Welcome to DipReport ("the App"). By using the App you agree to these terms. Please read them carefully.',
            style: body,
          ),

          Text('1. About the App', style: heading),
          Text(
            'DipReport provides sea swimming condition forecasts based on publicly available weather and marine data. '
            'The App is intended as a general guide only and does not replace professional maritime or safety advice.',
            style: body,
          ),

          Text('2. Accuracy of Forecasts', style: heading),
          Text(
            'Forecasts are generated from third-party data sources and are provided on a best-effort basis. '
            'Conditions at sea can change rapidly and without warning. '
            'Always exercise your own judgement before entering the water and never swim alone in open water.',
            style: body,
          ),

          Text('3. No Liability', style: heading),
          Text(
            'DipReport and its developers accept no responsibility or liability for any injury, loss, or damage '
            'arising from reliance on information provided by the App. Use of the App is entirely at your own risk.',
            style: body,
          ),

          Text('4. User-Generated Content', style: heading),
          Text(
            'Registered users may post photos and comments ("Posts"). By submitting a Post you confirm that:\n'
            '  • You own or have the right to share the content.\n'
            '  • The content does not contain anything unlawful, offensive, or misleading.\n'
            '  • You grant DipReport a non-exclusive licence to display the content within the App.\n\n'
            'We reserve the right to remove any Post at our discretion.',
            style: body,
          ),

          Text('5. Account & Authentication', style: heading),
          Text(
            'Accounts are authenticated via Google OAuth or email. '
            'You are responsible for keeping your account secure. '
            'We do not store passwords.',
            style: body,
          ),

          Text('6. Privacy', style: heading),
          Text(
            'We collect only the data necessary to provide the service: your email address (for authentication), '
            'location data you choose to save, and any Posts you submit. '
            'We do not sell your data to third parties. '
            'Location data is stored locally on your device unless you explicitly share a forecast or post.',
            style: body,
          ),

          Text('7. Notifications', style: heading),
          Text(
            'If you enable notifications, the App will send you daily condition reports at times you configure. '
            'You can disable notifications at any time in Settings.',
            style: body,
          ),

          Text('8. Changes to These Terms', style: heading),
          Text(
            'We may update these terms from time to time. Continued use of the App after changes are posted '
            'constitutes acceptance of the updated terms.',
            style: body,
          ),

          Text('9. Contact', style: heading),
          Text(
            'If you have any questions about these terms, please contact us at hello@dipreport.com.',
            style: body,
          ),

          const SizedBox(height: 24),
          Text(
            '© 2026 DipReport. All rights reserved.',
            style: muted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
