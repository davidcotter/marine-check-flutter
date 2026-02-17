import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

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
    final times = document.findAllElements('time').toList();
    print('Total time tags: ${times.length}');

    // Print first few instantaneous tags to see element names
    print('\nChecking first instantaneous data tags:');
    int count = 0;
    for (final t in times) {
      final from = t.getAttribute('from');
      final to = t.getAttribute('to');
      if (from == to) {
        print('From: $from');
        final location = t.getElement('location');
        if (location != null) {
           for (final node in location.children) {
             if (node is XmlElement) {
               print('  Element: ${node.name.local} attributes: ${node.attributes.map((a) => "${a.name.local}=${a.value}").join(", ")}');
             }
           }
        }
        count++;
        if (count > 2) break;
      }
    }

    final mergedData = <String, Map<String, dynamic>>{};

    for (final t in times) {
      final from = t.getAttribute('from');
      final to = t.getAttribute('to');
      if (from == null || to == null) continue;

      final timeKey = from.substring(0, 13) + ':00';
      final entry = mergedData.putIfAbsent(timeKey, () => {'time': timeKey});
      
      final location = t.getElement('location');
      if (location == null) continue;

      if (from == to) {
        final temp = location.getElement('temperature')?.getAttribute('value');
        final windSpeed = location.getElement('windSpeed')?.getAttribute('mps');
        final windDir = location.getElement('windDirection')?.getAttribute('deg');

        if (temp != null) entry['temp'] = double.parse(temp);
        if (windSpeed != null) entry['windSpeed'] = double.parse(windSpeed);
        if (windDir != null) entry['windDir'] = double.parse(windDir);
      } else {
        final symbol = location.getElement('symbol')?.getAttribute('number');
        if (symbol != null) entry['symbol'] = int.parse(symbol);
      }
    }

    print('\nSample data for tomorrow (2026-02-09):');
    final sortedKeys = mergedData.keys.toList()..sort();
    for (final key in sortedKeys) {
      if (key.startsWith('2026-02-09')) {
        print('$key: ${mergedData[key]}');
      }
    }

  } catch (e) {
    print('Error: $e');
  }
}
