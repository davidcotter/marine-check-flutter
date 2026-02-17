import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'dart:convert';

Future<void> main() async {
  final lat = 53.2891; // Forty Foot
  final lon = -6.1158;
  final url = 'http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast?lat=$lat;long=$lon';

  try {
    print('Fetching from $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      print('Failed: ${response.statusCode}');
      return;
    }

    final document = XmlDocument.parse(response.body);
    final times = document.findAllElements('time');

    final mergedData = <int, Map<String, dynamic>>{};

    for (final t in times) {
      final fromStr = t.getAttribute('from');
      final toStr = t.getAttribute('to');
      if (fromStr == null || toStr == null) continue;

      final from = DateTime.parse(fromStr).toUtc();
      final to = DateTime.parse(toStr).toUtc();
      final location = t.getElement('location');
      if (location == null) continue;

      if (fromStr == toStr) {
        final msKey = DateTime.utc(from.year, from.month, from.day, from.hour).millisecondsSinceEpoch;
        final entry = mergedData.putIfAbsent(msKey, () => {'ms': msKey});
        final temp = location.getElement('temperature')?.getAttribute('value');
        if (temp != null) entry['temp'] = double.parse(temp);
      } else {
        final durationHours = to.difference(from).inHours;
        for (int h = 0; h < durationHours; h++) {
          final hourTime = from.add(Duration(hours: h));
          final msKey = DateTime.utc(hourTime.year, hourTime.month, hourTime.day, hourTime.hour).millisecondsSinceEpoch;
          final entry = mergedData.putIfAbsent(msKey, () => {'ms': msKey});
          entry['hasSymbol'] = true;
        }
      }
    }

    final sortedKeys = mergedData.keys.toList()..sort();
    Map<String, dynamic>? lastPoint;
    for (final ms in sortedKeys) {
      final entry = mergedData[ms]!;
      if (entry['temp'] != null) {
        lastPoint = entry;
      } else if (lastPoint != null) {
        final diffHours = (ms - (lastPoint['ms'] as int)) / (1000 * 60 * 60);
        if (diffHours <= 6) {
          entry['temp'] = lastPoint['temp'];
          entry['filled'] = true;
        }
      }
    }

    print('Total keys count: ${mergedData.length}');
    final validEntries = mergedData.entries.where((e) => e.value['temp'] != null).toList();
    print('Entries with temp (inc filled): ${validEntries.length}');
    final filledEntries = mergedData.entries.where((e) => e.value['filled'] == true).toList();
    print('Filled (interpolated) entries: ${filledEntries.length}');

    if (validEntries.isNotEmpty) {
      final firstKey = validEntries.first.key;
      print('First valid key (ms): $firstKey');
      print('Equivalent DateTime: ${DateTime.fromMillisecondsSinceEpoch(firstKey, isUtc: true)}');
    }

    // Simulate MarineService matching
    print('\nSimulating MarineService matching:');
    final testTimeStr = "2026-02-09T10:00"; // Typical Open-Meteo format
    final time = DateTime.parse(testTimeStr + 'Z');
    final msKeyMatch = time.millisecondsSinceEpoch;
    print('Searching for $testTimeStr -> $msKeyMatch');
    
    final match = mergedData[msKeyMatch];
    print('Match found: ${match != null}');
    if (match != null) {
      print('Match details: $match');
    }

  } catch (e) {
    print('Error: $e');
  }
}
