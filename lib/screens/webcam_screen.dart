import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'webcam_web_stub.dart' if (dart.library.html) 'webcam_web_impl.dart' as webcam_web;

// Only import webview_flutter on non-web
import 'webcam_native_stub.dart' if (dart.library.io) 'webcam_native_impl.dart' as webcam_native;

/// Camera configuration
class CamConfig {
  final String id;
  final String name;
  final String url;
  final String description;
  final String county;
  final double lat;
  final double lng;
  final bool isMjpeg;

  const CamConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
    required this.county,
    required this.lat,
    required this.lng,
    this.isMjpeg = false,
  });
}

// County ordering: clockwise around the Irish coast
const _countyOrder = [
  'Dublin', 'Wexford', 'Waterford', 'Cork',
  'Kerry', 'Clare', 'Galway', 'Mayo', 'Sligo', 'Donegal',
];

// Cameras covering the Irish coast — clean, direct embeds only
final cameras = [
  // ─── Dublin ───
  CamConfig(
    id: 'fortyfoot',
    name: 'Forty Foot',
    url: kIsWeb
        ? 'https://g0.ipcamlive.com/player/player.php?alias=6008744a58a63&autoplay=1'
        : 'https://dipreport.com/webcams/fortyfoot',
    description: 'Sandycove bathing spot',
    county: 'Dublin',
    lat: 53.2889,
    lng: -6.1143,
  ),

  // ─── Waterford ───
  CamConfig(
    id: 'tramore',
    name: 'Tramore Beach',
    url: 'https://dipreport.com/webcams/tramore.mjpg',
    description: 'Main Beach',
    county: 'Waterford',
    lat: 52.1603,
    lng: -7.1431,
    isMjpeg: true,
  ),

  // ─── Cork ───
  CamConfig(
    id: 'inchydoney',
    name: 'Inchydoney Beach',
    url: 'https://www.youtube.com/embed/tJy8Mx9w2WE?autoplay=1&mute=1',
    description: 'Atlantic view from West Cork',
    county: 'Cork',
    lat: 51.5978,
    lng: -8.8631,
  ),

  // ─── Kerry ───
  CamConfig(
    id: 'brandon_bay',
    name: 'Brandon Bay',
    url: 'https://www.youtube.com/embed/C6-FyC5ZHqQ?autoplay=1&mute=1',
    description: 'Dingle Peninsula bay view',
    county: 'Kerry',
    lat: 52.2256,
    lng: -10.0478,
  ),
  CamConfig(
    id: 'inch_beach',
    name: 'Inch Beach',
    url: 'https://www.youtube.com/embed/EQMeLVN-QxA?autoplay=1&mute=1',
    description: 'Dingle Peninsula strand',
    county: 'Kerry',
    lat: 52.1333,
    lng: -9.9667,
  ),

  // ─── Clare ───
  CamConfig(
    id: 'lahinch',
    name: 'Lahinch Beach',
    url: 'https://rtsp.me/embed/fbEzsA5B/',
    description: 'Liscannor Bay surf beach',
    county: 'Clare',
    lat: 52.9333,
    lng: -9.3472,
  ),

  // ─── Kerry (Ballybunion) ───
  CamConfig(
    id: 'ballybunion',
    name: 'Ballybunion',
    url: kIsWeb
        ? 'https://g0.ipcamlive.com/player/player.php?alias=mcmunnsfront&autoplay=1&mute=1'
        : 'https://g0.ipcamlive.com/player/player.php?alias=mcmunnsfront&autoplay=1&mute=1',
    description: 'North Kerry surf beach',
    county: 'Kerry',
    lat: 52.5111,
    lng: -9.6722,
  ),

  // ─── Sligo ───
  CamConfig(
    id: 'strandhill',
    name: 'Strandhill',
    url: kIsWeb
        ? 'https://ipcamlive.com/player/player.php?alias=strandhillsurfsch&autoplay=1&mute=1'
        : 'https://ipcamlive.com/player/player.php?alias=strandhillsurfsch&autoplay=1&mute=1',
    description: 'Main surf beach',
    county: 'Sligo',
    lat: 54.2719,
    lng: -8.6097,
  ),

  // ─── Donegal ───
  CamConfig(
    id: 'rossnowlagh',
    name: 'Rossnowlagh Beach',
    url: kIsWeb
        ? 'https://g0.ipcamlive.com/player/player.php?alias=641c1c9267f16&autoplay=1&mute=1'
        : 'https://g0.ipcamlive.com/player/player.php?alias=641c1c9267f16&autoplay=1&mute=1',
    description: 'Donegal Bay surf beach',
    county: 'Donegal',
    lat: 54.5406,
    lng: -8.2417,
  ),
];

class WebcamScreen extends StatefulWidget {
  final double? userLat;
  final double? userLon;

  const WebcamScreen({super.key, this.userLat, this.userLon});

  @override
  State<WebcamScreen> createState() => _WebcamScreenState();
}

class _WebcamScreenState extends State<WebcamScreen> {
  int _selectedIndex = 0;
  bool _pickerOpen = false;
  late List<CamConfig> _sortedCameras;

  @override
  void initState() {
    super.initState();
    _sortedCameras = _sortByProximity(cameras, widget.userLat, widget.userLon);
  }

  static List<CamConfig> _sortByProximity(List<CamConfig> cams, double? lat, double? lon) {
    if (lat == null || lon == null) return List.of(cams);
    final sorted = List.of(cams);
    sorted.sort((a, b) {
      final da = _distSq(a.lat, a.lng, lat, lon);
      final db = _distSq(b.lat, b.lng, lat, lon);
      return da.compareTo(db);
    });
    return sorted;
  }

  // Squared approximate distance — fine for sorting, no need for haversine
  static double _distSq(double lat1, double lon1, double lat2, double lon2) {
    final dLat = lat1 - lat2;
    final dLon = (lon1 - lon2) * 0.6; // rough cos(53°) correction for Ireland
    return dLat * dLat + dLon * dLon;
  }

  CamConfig get _activeCam => _sortedCameras[_selectedIndex];

  void _selectCamera(int index) {
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_activeCam.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showCameraPicker() {
    setState(() => _pickerOpen = true);

    final grouped = <String, List<MapEntry<int, CamConfig>>>{};
    for (var i = 0; i < _sortedCameras.length; i++) {
      grouped.putIfAbsent(_sortedCameras[i].county, () => []).add(MapEntry(i, _sortedCameras[i]));
    }
    // Order counties by their nearest camera to the user
    final countyOrder = grouped.keys.toList();
    if (widget.userLat != null && widget.userLon != null) {
      countyOrder.sort((a, b) {
        final nearestA = grouped[a]!.map((e) => _distSq(e.value.lat, e.value.lng, widget.userLat!, widget.userLon!)).reduce((a, b) => a < b ? a : b);
        final nearestB = grouped[b]!.map((e) => _distSq(e.value.lat, e.value.lng, widget.userLat!, widget.userLon!)).reduce((a, b) => a < b ? a : b);
        return nearestA.compareTo(nearestB);
      });
    } else {
      // Fallback to coastal order
      countyOrder.sort((a, b) {
        final ia = _countyOrder.indexOf(a);
        final ib = _countyOrder.indexOf(b);
        return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      });
    }
    final orderedCounties = countyOrder;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Select Camera',
                style: TextStyle(
                  color: Color(0xFFE0F2FE),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: orderedCounties.expand((county) {
                  final cams = grouped[county]!;
                  return [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        county.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...cams.map((entry) {
                      final isSelected = entry.key == _selectedIndex;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.videocam : Icons.videocam_outlined,
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFF64748B),
                        ),
                        title: Text(
                          entry.value.name,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFE0F2FE),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          entry.value.description,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Color(0xFF3B82F6))
                            : null,
                        onTap: () {
                          _selectCamera(entry.key);
                          Navigator.pop(ctx);
                        },
                      );
                    }),
                  ];
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _pickerOpen = false);
    });
  }

  String _formatCoord(double lat, double lng) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}\u00B0$latDir, ${lng.abs().toStringAsFixed(4)}\u00B0$lngDir';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Live Cams'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Camera selector
          GestureDetector(
            onTap: _showCameraPicker,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: Color(0xFF3B82F6), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activeCam.name,
                          style: const TextStyle(
                            color: Color(0xFFE0F2FE),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_activeCam.county} \u00B7 ${_activeCam.description}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
          // GPS coordinates
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xFF64748B), size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatCoord(_activeCam.lat, _activeCam.lng),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Video player
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _pickerOpen
                  ? const Center(
                      child: Icon(Icons.videocam, color: Color(0xFF334155), size: 48),
                    )
                  : kIsWeb
                      ? webcam_web.buildWebcamWidget(
                          key: ValueKey(_activeCam.id),
                          url: _activeCam.url,
                          isMjpeg: _activeCam.isMjpeg,
                        )
                      : webcam_native.buildNativeWebcamWidget(
                          cam: _activeCam,
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in Browser'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
