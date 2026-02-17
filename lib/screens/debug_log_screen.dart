import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';
import '../services/marine_service.dart';
import '../services/met_eireann_service.dart';
import '../models/marine_data.dart';
import '../utils/unit_converter.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_ApiLogTabState> _apiLogKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  void _jumpToLog(String logId, String? keyPath) {
    _tabController.animateTo(0); // Go to API Logs
    // Delay slightly to allow tab switch
    Future.delayed(const Duration(milliseconds: 100), () {
      _apiLogKey.currentState?.scrollToLog(logId, keyPath: keyPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final debugData = MarineService.lastRoughnessCalculation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'API Logs'),
            Tab(icon: Icon(Icons.calculate), text: 'Roughness'),
            Tab(icon: Icon(Icons.data_exploration), text: 'Inspector'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ApiLogTab(key: _apiLogKey),
          _RoughnessTab(debugData: debugData),
          _DataInspectorTab(onJumpToLog: _jumpToLog),
        ],
      ),
    );
  }
}

class _ApiLogTab extends StatefulWidget {
  const _ApiLogTab({super.key});

  @override
  State<_ApiLogTab> createState() => _ApiLogTabState();
}

class _ApiLogTabState extends State<_ApiLogTab> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  final Map<String, ExpansionTileController> _controllers = {};
  
  // Highlighting State
  String? _highlightLogId;
  String? _highlightKey; // e.g. "temperature_2m"
  int? _highlightIndex;  // e.g. 4

  void scrollToLog(String logId, {String? keyPath}) {
    final logs = MarineService.apiLogs;
    final index = logs.indexWhere((l) => l.id == logId);

    setState(() {
      _highlightLogId = logId;
      _highlightKey = null;
      _highlightIndex = null;

      if (keyPath != null) {
        // Parse keyPath: "hourly.temperature_2m[4]" or "hourly.temperature[4]"
        final match = RegExp(r'hourly\.(\w+)\[(\d+)\]').firstMatch(keyPath);
        if (match != null) {
          _highlightKey = match.group(1);
          _highlightIndex = int.parse(match.group(2)!);
        }
      }
    });

    if (index != -1) {
      // 1. Rough scroll to bring item into view (so ListView builds it)
      // We estimate 80px per collapsed item.
      _scrollController.animateTo(
        index * 80.0, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeOut
      ).then((_) {
        // 2. Wait for build, then precise scroll & expand
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final key = _itemKeys[logId];
          final controller = _controllers[logId];
          
          controller?.expand();

          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!, 
              duration: const Duration(milliseconds: 400), 
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
          }
        });
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log entry not found in current log list.')));
    }
  }

  /// Parses Met Eireann XML into a TAI-compatible map (hourly arrays)
  Map<String, dynamic> _xmlToTai(String xmlBody) {
    if (xmlBody.isEmpty) return {};
    try {
      final doc = XmlDocument.parse(xmlBody);
      final times = doc.findAllElements('time');
      
      final Map<DateTime, Map<String, dynamic>> hourlyMap = {};
      
      for (var t in times) {
        final fromStr = t.getAttribute('from');
        final toStr = t.getAttribute('to');
        if (fromStr == null || toStr == null) continue;
        
        final from = DateTime.parse(fromStr);
        final loc = t.getElement('location');
        if (loc == null) continue;

        if (fromStr == toStr) {
          // Point data (Temp, Wind, etc.)
          final entry = hourlyMap.putIfAbsent(from, () => {});
          
          loc.attributes.forEach((attr) {
             // Skip obvious non-data tags if any, usually data is in child elements
          });
          
          for (var child in loc.childElements) {
             final val = child.getAttribute('value') ?? child.getAttribute('mps') ?? child.getAttribute('deg');
             if (val != null) {
               entry[child.name.local] = double.tryParse(val) ?? val;
             }
          }
        } else {
          // Interval data (Symbol, Precip)
          // We need to apply this to the hour at 'from' (and potentially subsequent hours if range > 1h)
          // For display simplicity, we'll just map it to the 'from' hour
          final entry = hourlyMap.putIfAbsent(from, () => {});
          
          for (var child in loc.childElements) {
             final val = child.getAttribute('id') ?? child.getAttribute('number') ?? child.getAttribute('value')  ?? child.getAttribute('probability');
             if (val != null) {
               entry[child.name.local] = double.tryParse(val) ?? val;
             }
          }
        }
      }
      
      // Convert map to separate arrays
      final sortedTimes = hourlyMap.keys.toList()..sort();
      if (sortedTimes.isEmpty) return {};

      final timeStrings = sortedTimes.map((t) => t.toIso8601String()).toList();
      final result = <String, List<dynamic>>{'time': timeStrings};

      // Collect all possible keys
      final allKeys = <String>{};
      for(var m in hourlyMap.values) allKeys.addAll(m.keys);
      
      for(var k in allKeys) {
        final list = [];
        for(var t in sortedTimes) {
          list.add(hourlyMap[t]?[k]);
        }
        result[k] = list;
      }
      
      return result;

    } catch (e) {
      return {'error': 'Failed to parse XML: $e'};
    }
  }

  Widget _formatBody(String logId, String body) {
    // 1. JSON
    if (body.startsWith('{') || body.startsWith('[')) {
      try {
        final jsonObject = json.decode(body);
        if (jsonObject is Map && jsonObject.containsKey('hourly')) {
          return _buildTaiTable(logId, jsonObject['hourly']);
        }
        return SelectableText(
          _toTaiFormat(jsonObject),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF4CAF50)),
        );
      } catch (_) {
        return SelectableText(body, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF4CAF50)));
      }
    } 
    // 2. XML (Met Eireann)
    else if (body.contains('<weatherdata') || body.contains('<time from=')) {
        final taiMap = _xmlToTai(body);
        if (taiMap.containsKey('time')) {
           return _buildTaiTable(logId, taiMap);
        }
        return SelectableText(
          body.replaceAll('><', '>\n<'), 
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF4CAF50))
        );
    }
    
    return SelectableText(body, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF4CAF50)));
  }

  Widget _buildTaiTable(String logId, Map<String, dynamic> hourly) {
    final keys = hourly.keys.toList();
    if (keys.isEmpty) return const Text('Empty hourly data');
    
    // Check if we have arrays of the same length
    final firstKey = keys.first;
    final firstVal = hourly[firstKey];
    if (firstVal is! List) return SelectableText(_toTaiFormat(hourly));
    
    final rowCount = firstVal.length;
    
    // Sort keys to put 'time' first
    keys.sort((a, b) {
      if (a == 'time') return -1;
      if (b == 'time') return 1;
      return a.compareTo(b);
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        headingRowHeight: 40,
        dataRowMinHeight: 25,
        columns: keys.map((k) => DataColumn(label: Text(k, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)))).toList(),
        rows: List.generate(rowCount, (index) {
          return DataRow(
            cells: keys.map((k) {
              final list = hourly[k] as List;
              final val = index < list.length ? list[index] : '-';
              String display = val?.toString() ?? '-';
              if (k == 'time') display = display.split('T').last.replaceAll('.000Z', ''); // Just show time
              
              // Highlight Logic
              final isHighlighted = 
                  _highlightLogId == logId && 
                  _highlightKey == k && 
                  _highlightIndex == index;

              return DataCell(
                Container(
                  padding: isHighlighted ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
                  decoration: isHighlighted ? BoxDecoration(
                    color: Colors.yellow,
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: Colors.yellow.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
                    ]
                  ) : null,
                  child: Text(
                    display, 
                    style: TextStyle(
                      fontSize: 10, 
                      color: isHighlighted ? Colors.black : Colors.greenAccent,
                      fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal
                    )
                  ),
                )
              );
            }).toList(),
          );
        }),
      ),
    );
  }

  String _toTaiFormat(dynamic object, [String indent = '']) {
    if (object is Map) {
      if (object.isEmpty) return '{}';
      final buffer = StringBuffer();
      object.forEach((key, value) {
        buffer.writeln('$indent$key: ${_toTaiFormat(value, indent + "  ").trimLeft()}');
      });
      return buffer.toString().trimRight();
    } else if (object is List) {
      if (object.isEmpty) return '[]';
      final buffer = StringBuffer();
      for (var item in object) {
        buffer.writeln('$indent- ${_toTaiFormat(item, indent + "  ").trimLeft()}');
      }
      return buffer.toString().trimRight();
    }
    return object.toString();
  }

  @override
  Widget build(BuildContext context) {
    final logs = MarineService.apiLogs;

    if (logs.isEmpty) {
      return const Center(child: Text('No API calls logged yet.'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: logs.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final log = logs[index];
        final isError = log.status != 200;
        
        // Register key for deep linking
        if (!_itemKeys.containsKey(log.id)) {
          _itemKeys[log.id] = GlobalKey();
        }
        if (!_controllers.containsKey(log.id)) {
          _controllers[log.id] = ExpansionTileController();
        }

        final isExpanded = _highlightLogId == log.id;

        return Card(
          key: _itemKeys[log.id],
          color: isError ? Colors.red.withOpacity(0.1) : (log.isMetEireann ? Colors.green.withOpacity(0.05) : (isExpanded ? Colors.blue.withOpacity(0.05) : null)),
          child: ExpansionTile(
            controller: _controllers[log.id],
            initiallyExpanded: isExpanded,
            leading: Icon(
              isError ? Icons.error_outline : (log.isMetEireann ? Icons.grass : Icons.cloud),
              color: isError ? Colors.red : (log.isMetEireann ? Colors.green : Colors.blue),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.locationName ?? 'Unknown Location',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        log.requestLabel ?? log.url.split('?').first.split('/').last,
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: isError ? Colors.red : Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: log.isMetEireann ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.isMetEireann ? 'MET ÉIREANN' : 'OPEN-METEO',
                    style: TextStyle(
                      fontSize: 9, 
                      fontWeight: FontWeight.bold, 
                      color: log.isMetEireann ? Colors.green : Colors.blue
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${log.timestamp.hour}:${log.timestamp.minute}:${log.timestamp.second} • ${log.status} ${log.isFallback ? "(Fallback)" : ""}',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('URL: ${log.url}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                    const SizedBox(height: 8),
                    const Text('Response Body (TAI):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 400),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E), // Dark terminal bg
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: SingleChildScrollView(
                        child: _formatBody(log.id, log.body),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DataInspectorTab extends StatefulWidget {
  final Function(String, String?) onJumpToLog;
  const _DataInspectorTab({required this.onJumpToLog});

  @override
  State<_DataInspectorTab> createState() => _DataInspectorTabState();
}

class _DataInspectorTabState extends State<_DataInspectorTab> {
  int _selectedHourIndex = 0;

  @override
  Widget build(BuildContext context) {
    final forecasts = MarineService.lastForecasts;
    if (forecasts == null || forecasts.isEmpty) {
      return const Center(child: Text('No forecast data available (or not yet loaded).\nTry searching for a location first.'));
    }

    _selectedHourIndex = _selectedHourIndex.clamp(0, forecasts.length - 1);
    final forecast = forecasts[_selectedHourIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Inspector Metadata Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Inspecting: ${MarineService.apiLogs.firstWhere((l) => true, orElse: () => ApiLog(id: '', timestamp: DateTime.now(), url: '', status: 0, body: '')).locationName ?? "Unknown"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${forecasts.length} Hours Available',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
        
        // Hour Selector
        Container(
          height: 60,
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: forecasts.length,
            itemBuilder: (context, index) {
              final f = forecasts[index];
              final isSelected = index == _selectedHourIndex;
              return GestureDetector(
                onTap: () => setState(() => _selectedHourIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                  child: Center(
                    child: Text(
                      '${f.time.hour}:00',
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Forecast for ${DateFormat('EEEE, MMM d @ HH:00').format(forecast.time.toLocal())}', 
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)
                ),
                const SizedBox(height: 16),
                if (forecast.provenance != null)
                  ...forecast.provenance!.entries.map((e) => _buildProvenanceCard(e.key, e.value))
                else
                  const Text('No provenance data available for this hour.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProvenanceCard(String label, FieldProvenance prov) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text(prov.sourceName, style: const TextStyle(fontSize: 10, color: Colors.white)),
                  backgroundColor: prov.sourceName.contains('Met Éireann') ? Colors.green : Colors.blue,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(4)),
              child: SelectableText(
                prov.snippet, 
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent)
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => widget.onJumpToLog(prov.logId, prov.keyPath),
                icon: const Icon(Icons.code, size: 16),
                label: const Text('Jump to Source'),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoughnessTab extends StatelessWidget {
  final Map<String, dynamic>? debugData;
  const _RoughnessTab({this.debugData});

  @override
  Widget build(BuildContext context) {
    final data = debugData ?? MarineService.lastRoughnessCalculation;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (data.isEmpty) {
      return Center(child: Text('No roughness calculation data.', style: TextStyle(color: colorScheme.onSurface)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(context, 'Inputs', data['inputs']),
          const SizedBox(height: 16),
          _buildSection(context, 'Formula Breakdown', data['formula']),
          const SizedBox(height: 16),
          _buildSection(context, 'Result', data['result']),
          const SizedBox(height: 24),
          Text(
            'Score Key:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.primary),
          ),
          const SizedBox(height: 8),
          _buildKeyRow(context, const Color(0xFF22C55E), '0-20', 'Perfect / Glassy'),
          _buildKeyRow(context, const Color(0xFF3B82F6), '21-40', 'Standard West Coast'),
          _buildKeyRow(context, const Color(0xFFF97316), '41-60', 'Rough / Advanced'),
          _buildKeyRow(context, const Color(0xFFEF4444), '60+', 'Unswimmable'),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, Map<String, dynamic>? items) {
    if (items == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title, 
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.bold, 
              color: isDark ? const Color(0xFF81C784) : colorScheme.primary 
            )
          ),
          Divider(color: theme.dividerColor),
          ...items.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  e.key, 
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace'
                  )
                ),
                Text(
                  e.value.toString(), 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontFamily: 'monospace',
                    color: isDark ? const Color(0xFF4CAF50) : const Color(0xFF15803D) 
                  )
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildKeyRow(BuildContext context, Color color, String range, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Text(
            '$range: $label',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontFamily: 'monospace'
            ),
          ),
        ],
      ),
    );
  }
}
