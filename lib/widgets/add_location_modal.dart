import 'package:flutter/material.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';

/// Add location modal with geocoding search
class AddLocationModal extends StatefulWidget {
  final Function(SavedLocation) onLocationAdded;

  const AddLocationModal({super.key, required this.onLocationAdded});

  @override
  State<AddLocationModal> createState() => _AddLocationModalState();
}

class _AddLocationModalState extends State<AddLocationModal> {
  final _geocoding = GeocodingService();
  final _locationService = LocationService();
  final _controller = TextEditingController();
  
  List<GeocodingResult> _results = [];
  bool _searching = false;
  bool _saving = false;
  String? _error;

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }

    setState(() { _searching = true; _error = null; });

    try {
      final results = await _geocoding.searchLocations(query);
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty && query.length >= 3) {
          _error = 'No locations found';
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        _error = 'Search failed';
      });
    }
  }

  Future<void> _selectLocation(GeocodingResult result) async {
    setState(() => _saving = true);

    try {
      final newLocation = SavedLocation(
        id: '${result.lat}-${result.lon}-${DateTime.now().millisecondsSinceEpoch}',
        name: result.name,
        lat: result.lat,
        lon: result.lon,
      );

      await _locationService.addLocation(newLocation);
      widget.onLocationAdded(newLocation);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Failed to save location';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(color: Color(0xFFF8FAFC)),
                  decoration: InputDecoration(
                    hintText: 'Search for a location...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                    ),
                    suffixIcon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _search,
                ),
              ),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFF87171)),
                  ),
                ),

              // Results
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _controller.text.length < 2
                              ? 'Enter at least 2 characters'
                              : 'Type to search locations...',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final result = _results[i];
                          return GestureDetector(
                            onTap: () => _selectLocation(result),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result.name,
                                    style: const TextStyle(
                                      color: Color(0xFFF8FAFC),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (result.admin1 != null)
                                    Text(
                                      '${result.admin1}, ${result.country}',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 14,
                                      ),
                                    ),
                                  Text(
                                    '${result.lat.toStringAsFixed(2)}°, ${result.lon.toStringAsFixed(2)}°',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // Saving overlay
          if (_saving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Saving...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
